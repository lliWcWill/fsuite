#!/usr/bin/env python3
"""fs-engine.py — deterministic intent classification and tool-chain orchestration engine.

Core brain of the `fs` meta-search tool. Reads JSON from stdin, classifies
query intent using heuristics, builds tool chains, executes them via
subprocess calls to fsearch/fcontent/fmap, shapes results, generates
next_hint recommendations, and enforces budget caps.

All output is JSON to stdout. Pretty formatting is the bash layer's job.
"""

import sys
import json
import os
import re
import subprocess
import time
import shutil
from datetime import datetime, timezone

# ── Budget Constants ─────────────────────────────────────────────────────────

MAX_CANDIDATE_FILES = 50
MAX_ENRICH_FILES = 15
TIMEOUT_SECONDS = 10

# ── Known filenames that signal "file" intent ────────────────────────────────

KNOWN_FILENAMES = frozenset({
    "Makefile", "Dockerfile", "Vagrantfile", "Procfile", "Gemfile",
    "Rakefile", "Justfile", "Taskfile",
    "package.json", "package-lock.json", "tsconfig.json", "jsconfig.json",
    "pyproject.toml", "setup.py", "setup.cfg", "requirements.txt",
    "Cargo.toml", "Cargo.lock", "go.mod", "go.sum",
    "CMakeLists.txt", "Makefile.am", "configure.ac",
    "docker-compose.yml", "docker-compose.yaml",
    ".gitignore", ".gitattributes", ".editorconfig",
    ".eslintrc", ".prettierrc", ".babelrc",
    "README.md", "LICENSE", "CHANGELOG.md",
    "renovate.json", "netlify.toml", "vercel.json",
    "flake.nix", "flake.lock", "shell.nix", "default.nix",
})

# ── Known bare extensions ────────────────────────────────────────────────────

KNOWN_EXTENSIONS = frozenset({
    ".py", ".rs", ".go", ".js", ".ts", ".tsx", ".jsx",
    ".c", ".h", ".cpp", ".hpp", ".cc", ".cxx",
    ".java", ".kt", ".scala", ".clj",
    ".rb", ".php", ".lua", ".zig", ".nim", ".ex", ".exs",
    ".sh", ".bash", ".zsh", ".fish",
    ".json", ".yaml", ".yml", ".toml", ".xml", ".ini", ".cfg",
    ".md", ".rst", ".txt", ".csv",
    ".html", ".css", ".scss", ".less", ".svelte", ".vue",
    ".sql", ".graphql", ".proto",
    ".log", ".lock", ".conf", ".env",
})


# ── Intent Classification ────────────────────────────────────────────────────

def classify_intent(query, explicit_intent=None):
    """Classify query into intent (file/symbol/content) with confidence.

    Returns (intent, confidence, reason) tuple.

    Priority order:
    1. Explicit override → skip classification
    2. Glob chars → file
    3. Bare extension → file
    4. Known filenames → file
    5. Filename-shaped (word.ext) → file
    6. camelCase → symbol
    7. PascalCase → symbol
    8. snake_case → symbol
    9. SCREAMING_CASE → symbol
    10. Multi-word (spaces) → content
    11. Single lowercase word → content (low confidence)
    """

    # 1. Explicit override bypasses all heuristics
    if explicit_intent:
        return (explicit_intent, "high", f"explicit intent={explicit_intent}")

    q = query.strip()

    # 2. Glob characters (* ?)
    if '*' in q or '?' in q:
        return ("file", "high", "glob characters detected")

    # 3. Bare extension (.py, .rs, etc.)
    if re.match(r'^\.\w+$', q) and q.lower() in KNOWN_EXTENSIONS:
        return ("file", "high", f"bare extension: {q}")

    # 4. Known filenames
    if q in KNOWN_FILENAMES:
        return ("file", "high", f"known filename: {q}")

    # 5. Filename-shaped: word.ext (e.g. config.yaml, utils.py)
    if re.match(r'^[\w.-]+\.\w{1,10}$', q) and not re.match(r'^\.\w+$', q):
        return ("file", "high", f"filename-shaped: {q}")

    # 6. camelCase: starts lowercase, has at least one uppercase letter
    if re.match(r'^[a-z][a-zA-Z0-9]*$', q) and re.search(r'[A-Z]', q):
        return ("symbol", "high", "camelCase identifier")

    # 7. PascalCase: starts uppercase, has lowercase, single word
    if re.match(r'^[A-Z][a-zA-Z0-9]*$', q) and re.search(r'[a-z]', q):
        return ("symbol", "high", "PascalCase identifier")

    # 8. snake_case: lowercase with underscores
    if re.match(r'^[a-z][a-z0-9]*(_[a-z0-9]+)+$', q):
        return ("symbol", "high", "snake_case identifier")

    # 9. SCREAMING_CASE: uppercase with underscores (constants)
    if re.match(r'^[A-Z][A-Z0-9]*(_[A-Z0-9]+)+$', q):
        return ("symbol", "medium", "SCREAMING_CASE constant")

    # 10. Multi-word (contains spaces) → content search
    if ' ' in q:
        return ("content", "high", "multi-word query")

    # 11. Fallback: single lowercase word → content, low confidence
    return ("content", "low", "ambiguous single word, defaulting to content")


# ── Chain Building ───────────────────────────────────────────────────────────

def build_chain(intent, scope=None):
    """Build ordered tool chain based on intent and optional scope.

    scope is a glob pattern (e.g. "*.py") that narrows the file set first.
    When scope is provided, fsearch is prepended to narrow candidates.
    """
    if intent == "file":
        # File search doesn't benefit from prepending fsearch for scope—
        # the query IS the glob
        return ["fsearch"]
    elif intent == "content":
        if scope:
            return ["fsearch", "fcontent"]
        return ["fcontent"]
    elif intent == "symbol":
        if scope:
            return ["fsearch", "fcontent", "fmap"]
        return ["fcontent", "fmap"]
    else:
        # Unknown intent, fall back to content
        if scope:
            return ["fsearch", "fcontent"]
        return ["fcontent"]


# ── Tool Resolution ──────────────────────────────────────────────────────────

def resolve_tool(name):
    """Find tool executable: prefer sibling of engine, fall back to PATH."""
    engine_dir = os.path.dirname(os.path.abspath(__file__))
    sibling = os.path.join(engine_dir, name)
    if os.path.isfile(sibling) and os.access(sibling, os.X_OK):
        return sibling
    path_tool = shutil.which(name)
    if path_tool:
        return path_tool
    return None


def run_tool(name, args, stdin_data=None, timeout=TIMEOUT_SECONDS):
    """Execute a tool via subprocess with capture and timeout.

    Returns (stdout_str, stderr_str, return_code, timed_out).
    """
    tool_path = resolve_tool(name)
    if not tool_path:
        return ("", f"tool not found: {name}", 127, False)

    cmd = [tool_path] + args
    try:
        proc = subprocess.run(
            cmd,
            input=stdin_data,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        return (proc.stdout, proc.stderr, proc.returncode, False)
    except subprocess.TimeoutExpired:
        return ("", f"timeout after {timeout}s", -1, True)
    except Exception as e:
        return ("", str(e), -1, False)


# ── Tool Runners ─────────────────────────────────────────────────────────────

def run_fsearch(query, path, timeout=TIMEOUT_SECONDS):
    """Run fsearch -o paths, return list of file paths."""
    args = ["-o", "paths"]
    args.append(query)
    args.append(path)

    stdout, stderr, rc, timed_out = run_tool("fsearch", args, timeout=timeout)
    if timed_out:
        return [], True
    paths = [p.strip() for p in stdout.strip().splitlines() if p.strip()]
    return paths, False


def run_fcontent(query, path, file_list=None, timeout=TIMEOUT_SECONDS):
    """Run fcontent -o json. If file_list given, pipe paths via stdin."""
    args = ["-o", "json", query]
    stdin_data = None

    if file_list:
        stdin_data = "\n".join(file_list) + "\n"
    else:
        args.append(path)

    stdout, stderr, rc, timed_out = run_tool(
        "fcontent", args, stdin_data=stdin_data, timeout=timeout
    )
    if timed_out:
        return None, True

    try:
        result = json.loads(stdout) if stdout.strip() else []
    except json.JSONDecodeError:
        result = []
    return result, False


def run_fmap(file_list, timeout=TIMEOUT_SECONDS):
    """Run fmap -o json on a list of files."""
    if not file_list:
        return [], False

    stdin_data = "\n".join(file_list) + "\n"
    args = ["-o", "json"]

    stdout, stderr, rc, timed_out = run_tool(
        "fmap", args, stdin_data=stdin_data, timeout=timeout
    )
    if timed_out:
        return None, True

    try:
        result = json.loads(stdout) if stdout.strip() else []
    except json.JSONDecodeError:
        result = []
    return result, False


# ── Hit Shaping ──────────────────────────────────────────────────────────────

def shape_file_hits(paths):
    """Shape file search results: path + size_bytes + modified."""
    hits = []
    for p in paths:
        hit = {"file": p, "size_bytes": -1}
        try:
            stat = os.stat(p)
            hit["size_bytes"] = stat.st_size
            hit["modified"] = datetime.fromtimestamp(stat.st_mtime, tz=timezone.utc).isoformat()
        except OSError:
            pass
        hits.append(hit)
    return hits


def shape_content_hits(fcontent_result):
    """Shape fcontent JSON into normalized hit list.

    fcontent -o json returns:
      {"tool":"fcontent", ..., "matches": ["file:line:text", ...]}
    OR a list of such strings, or a list of dicts.

    Output: [{file, matches: [{line, text}], match_count}]
    """
    if not fcontent_result:
        return []

    # Extract the matches array from fcontent's top-level dict
    raw_matches = fcontent_result
    if isinstance(fcontent_result, dict):
        raw_matches = fcontent_result.get("matches", [])

    if not isinstance(raw_matches, list):
        return []

    # Parse "file:line:text" strings into structured data, group by file
    by_file = {}
    for item in raw_matches:
        if isinstance(item, str):
            # Format: "filepath:linenum:text"
            # Use regex to handle colons in file paths (e.g. C:\... or paths with colons)
            m = re.match(r'^(.+?):(\d+):(.*)$', item)
            if m:
                f, line, text = m.group(1), int(m.group(2)), m.group(3)
            else:
                # fallback: treat entire string as filename
                f = item
                line = 0
                text = ""
            if f not in by_file:
                by_file[f] = []
            by_file[f].append({"line": line, "text": text})
        elif isinstance(item, dict):
            f = item.get("file", item.get("path", ""))
            if f not in by_file:
                by_file[f] = []
            by_file[f].append({
                "line": item.get("line", item.get("line_number", 0)),
                "text": item.get("text", item.get("match", "")),
            })

    return [
        {"file": f, "matches": m, "match_count": len(m)}
        for f, m in by_file.items()
    ]


_DEFINITION_PREFIXES = (
    "def ", "function ", "class ", "const ", "let ", "var ",
    "export ", "pub fn ", "fn ",
)


def _is_definition(text, symbol_names):
    """Heuristic: text looks like a definition if it starts with a def keyword
    and contains one of the known symbol names."""
    stripped = text.strip()
    if not any(stripped.startswith(pfx) for pfx in _DEFINITION_PREFIXES):
        return False
    for name in symbol_names:
        if name in stripped:
            return True
    return False


def shape_symbol_hits(content_hits, fmap_result, query=""):
    """Merge content hits with fmap symbol data, rank by relevance."""
    if not content_hits:
        return []

    # Build lookup from fmap results
    # fmap -o json returns: {"files": [{"path": "...", "symbols": [...]}]}
    symbol_map = {}
    if isinstance(fmap_result, dict):
        files_list = fmap_result.get("files", [])
        for item in files_list:
            f = item.get("path", item.get("file", ""))
            symbols = item.get("symbols", [])
            symbol_map[f] = symbols
    elif isinstance(fmap_result, list):
        for item in fmap_result:
            f = item.get("path", item.get("file", ""))
            symbols = item.get("symbols", item.get("entries", []))
            symbol_map[f] = symbols

    q_lower = query.lower()

    merged = []
    for hit in content_hits:
        entry = dict(hit)
        file_symbols = symbol_map.get(hit["file"], [])

        # Filter symbols to only those relevant to the query
        if q_lower:
            relevant_symbols = []
            for sym in file_symbols:
                name = sym.get("name", "") if isinstance(sym, dict) else str(sym)
                if q_lower in name.lower():
                    relevant_symbols.append(sym)
            entry["symbols"] = relevant_symbols
        else:
            entry["symbols"] = file_symbols

        # Collect symbol names for definition heuristic
        sym_names = []
        for sym in entry["symbols"]:
            if isinstance(sym, dict):
                sym_names.append(sym.get("name", ""))
            else:
                sym_names.append(str(sym))

        # Annotate matches with type if they look like definitions
        has_definition = False
        if "matches" in entry:
            for match in entry["matches"]:
                text = match.get("text", "")
                if _is_definition(text, sym_names):
                    match["type"] = "definition"
                    has_definition = True

        # Compute ranking score
        has_symbol_match = any(q_lower in n.lower() for n in sym_names) if q_lower else False
        entry["_has_symbol_match"] = has_symbol_match
        entry["_has_definition"] = has_definition
        entry["_match_count"] = entry.get("match_count", 0)

        merged.append(entry)

    # Rank: symbol name match first, definitions within those, then by match count
    merged.sort(key=lambda e: (
        not e["_has_symbol_match"],   # True first (False < True, so negate)
        not e["_has_definition"],     # Definitions first
        -e["_match_count"],           # More matches first
    ))

    # Strip internal ranking keys
    for entry in merged:
        del entry["_has_symbol_match"]
        del entry["_has_definition"]
        del entry["_match_count"]

    return merged


# ── next_hint Generation ─────────────────────────────────────────────────────

def generate_next_hint(intent, hits, query, scope=None):
    """Generate a recommendation for the next tool call."""
    if not hits:
        return None

    top_hit = hits[0]
    top_file = top_hit.get("file", "")

    if intent == "file":
        if scope:
            return {"tool": "fread", "args": {"path": top_file}}
        else:
            return {"tool": "fcontent", "args": {"query": query, "path": top_file}}

    elif intent == "content":
        return {"tool": "fread", "args": {"path": top_file, "around": query}}

    elif intent == "symbol":
        # Only suggest fread --symbol if the top hit has a matching symbol
        symbols = top_hit.get("symbols", [])
        best_match = None
        if symbols:
            for sym in symbols:
                name = sym.get("name", "") if isinstance(sym, dict) else str(sym)
                if query.lower() in name.lower():
                    best_match = name
                    break
        if best_match:
            return {"tool": "fread", "args": {"path": top_file, "symbol": best_match}}
        # No symbol match — fall back to fread --around
        return {"tool": "fread", "args": {"path": top_file, "around": query}}

    return None


# ── Orchestrator ─────────────────────────────────────────────────────────────

def orchestrate(request):
    """Main orchestration: classify → chain → execute → shape → hint."""
    start_time = time.time()

    query = request.get("query", "").strip()
    path = request.get("path") or "."
    scope = request.get("scope", None)
    explicit_intent = request.get("intent", None)

    # ── Budget overrides ────────────────────────────────────────────────
    def safe_int(val, default):
        try:
            return int(val)
        except (TypeError, ValueError):
            return default

    max_candidates = safe_int(request.get("max_candidates"), MAX_CANDIDATE_FILES)
    max_enrich = safe_int(request.get("max_enrich"), MAX_ENRICH_FILES)
    timeout = safe_int(request.get("timeout"), TIMEOUT_SECONDS)

    # ── Validation ───────────────────────────────────────────────────────
    if not query:
        return {"error": "query is required", "query": query}

    # ── Classify ─────────────────────────────────────────────────────────
    resolved_intent, confidence, reason = classify_intent(query, explicit_intent)

    # ── Build chain ──────────────────────────────────────────────────────
    chain = build_chain(resolved_intent, scope)

    # ── Execute chain ────────────────────────────────────────────────────
    hits = []
    truncated = False
    candidate_count = 0
    enriched_count = 0
    file_list = None

    elapsed = lambda: int((time.time() - start_time) * 1000)

    for tool_name in chain:
        # Budget: check total elapsed time
        if elapsed() > timeout * 1000:
            truncated = True
            break

        if tool_name == "fsearch":
            search_query = scope if scope else query
            file_list, timed_out = run_fsearch(search_query, path, timeout=timeout)
            file_list = file_list[:max_candidates]
            candidate_count = len(file_list)
            if timed_out:
                truncated = True
                break
            if resolved_intent == "file":
                # When scope is present, filter candidates by query match
                if scope and query:
                    q_lower = query.lower()
                    file_list = [f for f in file_list if q_lower in f.lower()]
                    candidate_count = len(file_list)
                hits = shape_file_hits(file_list)

        elif tool_name == "fcontent":
            result, timed_out = run_fcontent(query, path, file_list, timeout=timeout)
            if timed_out:
                truncated = True
                break
            hits = shape_content_hits(result)
            candidate_count = max(candidate_count, len(hits))

        elif tool_name == "fmap":
            # Only enrich files that have content hits
            enrich_files = [h["file"] for h in hits[:max_enrich]]
            enriched_count = len(enrich_files)
            if enrich_files:
                fmap_result, timed_out = run_fmap(enrich_files, timeout=timeout)
                if timed_out:
                    truncated = True
                    # Return search-only results
                    break
                if fmap_result:
                    hits = shape_symbol_hits(hits, fmap_result, query=query)

    # ── next_hint ────────────────────────────────────────────────────────
    next_hint = generate_next_hint(resolved_intent, hits, query, scope)

    # ── Build output ─────────────────────────────────────────────────────
    output = {
        "query": query,
        "path": path,
        "intent": explicit_intent or "auto",
        "resolved_intent": resolved_intent,
        "route_reason": reason,
        "route_confidence": confidence,
        "selected_chain": chain,
        "hits": hits,
        "truncated": truncated,
        "budget": {
            "candidate_files": candidate_count,
            "enriched_files": enriched_count,
            "time_ms": elapsed(),
        },
        "next_hint": next_hint,
    }

    if scope:
        output["scope"] = scope

    return output


# ── Entry Point ──────────────────────────────────────────────────────────────

def main():
    try:
        raw = sys.stdin.read()
        request = json.loads(raw)
    except json.JSONDecodeError as e:
        json.dump({"error": f"invalid JSON input: {e}"}, sys.stdout)
        sys.exit(1)

    try:
        result = orchestrate(request)
    except Exception as e:
        json.dump({"error": f"engine error: {e}", "query": request.get("query", "")}, sys.stdout)
        sys.exit(1)

    json.dump(result, sys.stdout, indent=2)


if __name__ == "__main__":
    main()
