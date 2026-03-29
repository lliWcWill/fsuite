# fs — Unified Search Orchestrator Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `fs`, an agent-first search orchestrator that classifies query intent, chains fsuite primitives (fsearch/fcontent/fmap), and returns enriched results with next-step hints — all within hard budget caps.

**Architecture:** Python engine (`fs-engine.py`) does all routing/chaining/budgeting. Bash entrypoint (`fs`) handles CLI parsing and formatting. MCP handler in `mcp/index.js` calls `fs -o json` and returns both text `content` and `structuredContent` with `outputSchema`.

**Tech Stack:** Python 3.8+ (engine), Bash (CLI shim), Node.js/Zod (MCP registration), fsearch/fcontent/fmap (called as subprocesses)

**Spec:** `docs/specs/2026-03-29-fs-unified-search-design.md`

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `fs-engine.py` | Create | Intent classification, chain execution, budget enforcement, JSON output |
| `fs` | Create | Bash entrypoint — arg parsing, engine invocation, pretty/json output |
| `mcp/index.js` | Modify | Register `fs` tool with inputSchema, outputSchema, structuredContent |
| `install.sh` | Modify | Add `fs` to TOOLS array, `fs-engine.py` to SHARE_FILES |
| `freplay` | Modify | Add `[fs]="read_only"` to TOOL_MODE_DEFAULT, add to is_fsuite_tool |
| `fsuite` | Modify | Add fs to tool list and help text |
| `tests/test_fs.sh` | Create | TDD tests for intent classification, chain execution, budgets |
| `tests/run_all_tests.sh` | Modify | Add fs test suite block |

---

### Task 1: Intent Classification Engine (TDD)

**Files:**
- Create: `fs-engine.py`
- Create: `tests/test_fs.sh`

This is the core brain — deterministic heuristic classification of query strings into `file`, `content`, or `symbol` intents, plus `route_reason` and `route_confidence`.

- [ ] **Step 1: Write the test harness and first intent classification tests**

```bash
#!/usr/bin/env bash
# tests/test_fs.sh — TDD tests for fs unified search orchestrator
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ENGINE="$REPO_DIR/fs-engine.py"

PASS=0; FAIL=0; TOTAL=0

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  TOTAL=$((TOTAL + 1))
  if [[ "$expected" == "$actual" ]]; then
    PASS=$((PASS + 1))
    echo "  ✓ $label"
  else
    FAIL=$((FAIL + 1))
    echo "  ✗ $label"
    echo "    expected: $expected"
    echo "    actual:   $actual"
  fi
}

assert_json_field() {
  local label="$1" json="$2" field="$3" expected="$4"
  local actual
  actual=$(echo "$json" | python3 -c "import sys,json; print(json.load(sys.stdin).get('$field',''))")
  assert_eq "$label" "$expected" "$actual"
}

# ── Section 1: Intent Classification ──────────────────────────────
echo ""
echo "=== Intent Classification ==="

# File intent: glob chars
result=$(echo '{"query":"*.py","path":"/tmp"}' | python3 "$ENGINE")
assert_json_field "glob *.py → file" "$result" "resolved_intent" "file"
assert_json_field "glob *.py → high confidence" "$result" "route_confidence" "high"

# File intent: bare extension
result=$(echo '{"query":".rs","path":"/tmp"}' | python3 "$ENGINE")
assert_json_field "bare .rs → file" "$result" "resolved_intent" "file"

# File intent: filename-shaped
result=$(echo '{"query":"package.json","path":"/tmp"}' | python3 "$ENGINE")
assert_json_field "package.json → file" "$result" "resolved_intent" "file"

# Symbol intent: camelCase
result=$(echo '{"query":"renderTool","path":"/tmp"}' | python3 "$ENGINE")
assert_json_field "camelCase → symbol" "$result" "resolved_intent" "symbol"

# Symbol intent: PascalCase
result=$(echo '{"query":"McpServer","path":"/tmp"}' | python3 "$ENGINE")
assert_json_field "PascalCase → symbol" "$result" "resolved_intent" "symbol"

# Symbol intent: snake_case
result=$(echo '{"query":"verify_token","path":"/tmp"}' | python3 "$ENGINE")
assert_json_field "snake_case → symbol" "$result" "resolved_intent" "symbol"

# Symbol intent: SCREAMING_CASE
result=$(echo '{"query":"DIFF_COLORS","path":"/tmp"}' | python3 "$ENGINE")
assert_json_field "SCREAMING_CASE → symbol" "$result" "resolved_intent" "symbol"

# Content intent: multi-word phrase
result=$(echo '{"query":"error loading config","path":"/tmp"}' | python3 "$ENGINE")
assert_json_field "multi-word → content" "$result" "resolved_intent" "content"

# Content intent: single lowercase word (ambiguous → content, low confidence)
result=$(echo '{"query":"authenticate","path":"/tmp"}' | python3 "$ENGINE")
assert_json_field "single lowercase → content" "$result" "resolved_intent" "content"
assert_json_field "single lowercase → low confidence" "$result" "route_confidence" "low"

# Explicit intent override
result=$(echo '{"query":"authenticate","path":"/tmp","intent":"symbol"}' | python3 "$ENGINE")
assert_json_field "explicit intent=symbol" "$result" "resolved_intent" "symbol"
assert_json_field "explicit intent → high confidence" "$result" "route_confidence" "high"

echo ""
echo "=== Results: $PASS passed, $FAIL failed, $TOTAL total ==="
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_fs.sh`
Expected: FAIL — `fs-engine.py` does not exist yet

- [ ] **Step 3: Write the intent classification engine**

```python
#!/usr/bin/env python3
"""fs-engine.py — routing, chaining, budgeting engine for fs.

Reads JSON from stdin. Outputs JSON to stdout.
All chain execution calls fsuite CLI tools as subprocesses.
"""

import sys
import json
import re
import subprocess
import time
import os

# ── Budget defaults ──────────────────────────────────────────────
MAX_CANDIDATE_FILES = 50
MAX_ENRICH_FILES = 15
TIMEOUT_SECONDS = 10

# ── Intent classification ────────────────────────────────────────

def classify_intent(query, scope=None, explicit_intent=None):
    """Classify a query string into (intent, confidence, reason)."""
    if explicit_intent and explicit_intent != "auto":
        return explicit_intent, "high", f"explicit intent={explicit_intent}"

    q = query.strip()

    # File intent: glob chars
    if "*" in q or "?" in q:
        return "file", "high", "query contains glob characters (* or ?)"

    # File intent: bare extension (.py, .rs, log)
    if re.match(r'^\.[a-zA-Z0-9]+$', q):
        return "file", "high", f"bare extension pattern ({q})"

    # File intent: looks like a filename (has dot + extension, or known names)
    known_filenames = {"Makefile", "Dockerfile", "Vagrantfile", "Rakefile",
                       "Gemfile", "Procfile", "CMakeLists.txt", ".gitignore",
                       ".env", "LICENSE", "README", "CHANGELOG"}
    if q in known_filenames:
        return "file", "high", f"known filename ({q})"
    if re.match(r'^[\w.-]+\.[a-zA-Z0-9]{1,10}$', q) and not re.search(r'[A-Z].*[a-z].*[A-Z]', q):
        # Has extension and doesn't look like camelCase/PascalCase
        if not "_" in q or q.count(".") > 0:
            return "file", "high", f"filename-shaped query with extension ({q})"

    # Symbol intent: camelCase (lowercase followed by uppercase)
    if re.search(r'[a-z][A-Z]', q) and " " not in q:
        return "symbol", "high", f"camelCase identifier ({q})"

    # Symbol intent: PascalCase (starts uppercase, has another uppercase after lowercase)
    if re.match(r'^[A-Z][a-z]', q) and re.search(r'[a-z][A-Z]', q) and " " not in q:
        return "symbol", "high", f"PascalCase identifier ({q})"

    # Symbol intent: PascalCase simple (starts uppercase, no spaces, not all caps)
    if re.match(r'^[A-Z][a-zA-Z0-9]+$', q) and not q.isupper() and " " not in q:
        return "symbol", "high", f"PascalCase identifier ({q})"

    # Symbol intent: snake_case (has underscore, no spaces)
    if "_" in q and " " not in q and not q.isupper():
        return "symbol", "high", f"snake_case identifier ({q})"

    # Symbol intent: SCREAMING_CASE
    if re.match(r'^[A-Z][A-Z0-9_]+$', q) and "_" in q:
        return "symbol", "medium", f"SCREAMING_CASE identifier ({q})"

    # Content intent: has spaces → multi-word phrase
    if " " in q:
        return "content", "high", "multi-word phrase"

    # Content intent: single lowercase word (ambiguous)
    if q.islower() and q.isalpha():
        return "content", "low", f"single lowercase word, ambiguous ({q})"

    # Default: content
    return "content", "medium", f"no strong pattern detected ({q})"


# ── Chain building ───────────────────────────────────────────────

def build_chain(intent, scope=None):
    """Build the tool chain for a given intent and scope."""
    chain = []
    if scope:
        chain.append("fsearch")
    if intent == "file":
        if not scope:
            chain.append("fsearch")
    elif intent == "content":
        chain.append("fcontent")
    elif intent == "symbol":
        chain.append("fcontent")
        chain.append("fmap")
    return chain


# ── Tool execution ───────────────────────────────────────────────

def resolve_tool(name):
    """Resolve tool path — prefer source tree, fall back to PATH."""
    engine_dir = os.path.dirname(os.path.abspath(__file__))
    source_path = os.path.join(engine_dir, name)
    if os.path.isfile(source_path) and os.access(source_path, os.X_OK):
        return source_path
    return name  # fall back to PATH


def run_tool(name, args, timeout=None):
    """Run an fsuite tool and return (stdout, stderr, returncode)."""
    cmd = [resolve_tool(name)] + args
    try:
        result = subprocess.run(
            cmd, capture_output=True, text=True,
            timeout=timeout or TIMEOUT_SECONDS
        )
        return result.stdout, result.stderr, result.returncode
    except subprocess.TimeoutExpired:
        return "", f"timeout after {timeout or TIMEOUT_SECONDS}s", -1


def run_fsearch(query, path, scope=None):
    """Run fsearch and return list of file paths."""
    pattern = scope if scope else query
    args = ["-o", "paths", pattern, path]
    stdout, stderr, rc = run_tool("fsearch", args)
    if rc != 0:
        return []
    paths = [p.strip() for p in stdout.strip().split("\n") if p.strip()]
    return paths[:MAX_CANDIDATE_FILES]


def run_fcontent(query, path, file_list=None):
    """Run fcontent and return parsed JSON results."""
    args = ["-o", "json", query]
    stdin_data = None
    if file_list:
        stdin_data = "\n".join(file_list)
    else:
        args.append(path)
    cmd = [resolve_tool("fcontent")] + args
    try:
        result = subprocess.run(
            cmd, capture_output=True, text=True,
            input=stdin_data, timeout=TIMEOUT_SECONDS
        )
        if result.returncode != 0:
            return {"files": [], "total_matches": 0}
        return json.loads(result.stdout)
    except (subprocess.TimeoutExpired, json.JSONDecodeError):
        return {"files": [], "total_matches": 0}


def run_fmap(file_list):
    """Run fmap on a list of files and return parsed JSON."""
    if not file_list:
        return []
    stdin_data = "\n".join(file_list[:MAX_ENRICH_FILES])
    cmd = [resolve_tool("fmap"), "-o", "json"]
    try:
        result = subprocess.run(
            cmd, capture_output=True, text=True,
            input=stdin_data, timeout=TIMEOUT_SECONDS
        )
        if result.returncode != 0:
            return []
        return json.loads(result.stdout)
    except (subprocess.TimeoutExpired, json.JSONDecodeError):
        return []


# ── Hit shaping ──────────────────────────────────────────────────

def shape_file_hits(paths):
    """Shape file search results into hit objects."""
    hits = []
    for p in paths:
        hit = {"file": p}
        try:
            stat = os.stat(p)
            hit["size_bytes"] = stat.st_size
        except OSError:
            pass
        hits.append(hit)
    return hits


def shape_content_hits(fcontent_result):
    """Shape fcontent JSON output into hit objects."""
    hits = []
    for f in fcontent_result.get("files", []):
        hit = {
            "file": f.get("path", f.get("file", "")),
            "matches": [],
            "match_count": 0,
        }
        for m in f.get("matches", []):
            hit["matches"].append({
                "line": m.get("line", 0),
                "text": m.get("text", ""),
            })
        hit["match_count"] = len(hit["matches"])
        hits.append(hit)
    return hits


def shape_symbol_hits(content_hits, fmap_result):
    """Merge fcontent hits with fmap symbol data."""
    # Index fmap results by file path
    symbol_index = {}
    if isinstance(fmap_result, dict):
        for f in fmap_result.get("files", []):
            symbol_index[f.get("path", "")] = [
                s.get("name", "") for s in f.get("symbols", [])
            ]
    elif isinstance(fmap_result, list):
        for f in fmap_result:
            if isinstance(f, dict):
                symbol_index[f.get("path", "")] = [
                    s.get("name", "") for s in f.get("symbols", [])
                ]

    hits = []
    for ch in content_hits:
        hit = dict(ch)
        hit["symbols"] = symbol_index.get(ch["file"], [])
        hits.append(hit)
    return hits


# ── Next hint generation ─────────────────────────────────────────

def generate_next_hint(resolved_intent, hits, query, scope=None):
    """Generate the next_hint recommendation."""
    if not hits:
        return None

    top = hits[0]
    top_file = top.get("file", "")

    if resolved_intent == "file":
        if scope:
            return {"tool": "fread", "args": {"path": top_file}}
        else:
            return {"tool": "fcontent", "args": {"query": query, "path": top_file}}

    elif resolved_intent == "content":
        return {"tool": "fread", "args": {"path": top_file, "around": query}}

    elif resolved_intent == "symbol":
        # Find best symbol match
        symbols = top.get("symbols", [])
        best_symbol = None
        for s in symbols:
            if query.lower() in s.lower():
                best_symbol = s
                break
        if best_symbol:
            return {"tool": "fread", "args": {"path": top_file, "symbol": best_symbol}}
        else:
            return {"tool": "fread", "args": {"path": top_file, "around": query}}

    return None


# ── Main orchestrator ────────────────────────────────────────────

def orchestrate(request):
    """Main orchestration: classify → chain → execute → shape → respond."""
    query = request.get("query", "")
    path = request.get("path", ".")
    scope = request.get("scope")
    intent = request.get("intent", "auto")
    max_candidates = request.get("max_candidates", MAX_CANDIDATE_FILES)
    max_enrich = request.get("max_enrich", MAX_ENRICH_FILES)
    timeout = request.get("timeout", TIMEOUT_SECONDS)

    start_time = time.time()

    # Classify
    resolved_intent, confidence, reason = classify_intent(query, scope, intent)

    # Build chain
    chain = build_chain(resolved_intent, scope)

    # Execute chain
    hits = []
    truncated = False
    candidate_files = 0
    enriched_files = 0
    file_list = None

    # Stage 1: fsearch (if in chain)
    if "fsearch" in chain:
        file_list = run_fsearch(query if resolved_intent == "file" and not scope else scope or query, path, scope)
        candidate_files = len(file_list)
        if candidate_files >= max_candidates:
            truncated = True
            file_list = file_list[:max_candidates]

        if resolved_intent == "file":
            hits = shape_file_hits(file_list)

    # Stage 2: fcontent (if in chain and not file-only)
    content_result = None
    content_hits = []
    if "fcontent" in chain:
        elapsed = time.time() - start_time
        if elapsed < timeout:
            content_result = run_fcontent(query, path, file_list)
            content_hits = shape_content_hits(content_result)
            if not hits:  # Only set hits if fsearch didn't already set them
                hits = content_hits
            candidate_files = candidate_files or len(content_hits)

    # Stage 3: fmap enrichment (if in chain)
    if "fmap" in chain and content_hits:
        elapsed = time.time() - start_time
        if elapsed < timeout:
            enrich_paths = [h["file"] for h in content_hits[:max_enrich]]
            enriched_files = len(enrich_paths)
            fmap_result = run_fmap(enrich_paths)
            hits = shape_symbol_hits(content_hits, fmap_result)
        else:
            truncated = True
            hits = content_hits  # Graceful degradation

    elapsed_ms = int((time.time() - start_time) * 1000)

    # Generate next_hint
    next_hint = generate_next_hint(resolved_intent, hits, query, scope)

    # Build response
    response = {
        "query": query,
        "path": os.path.abspath(path),
        "intent": intent,
        "resolved_intent": resolved_intent,
        "route_reason": reason,
        "route_confidence": confidence,
        "selected_chain": chain,
        "hits": hits,
        "truncated": truncated,
        "budget": {
            "candidate_files": candidate_files,
            "enriched_files": enriched_files,
            "time_ms": elapsed_ms,
        },
        "next_hint": next_hint,
    }
    if scope:
        response["scope"] = scope

    return response


# ── Entry point ──────────────────────────────────────────────────

def main():
    try:
        raw = sys.stdin.read()
        request = json.loads(raw)
    except json.JSONDecodeError as e:
        json.dump({"error": f"invalid JSON input: {e}"}, sys.stdout)
        sys.exit(1)

    result = orchestrate(request)
    json.dump(result, sys.stdout, indent=2)


if __name__ == "__main__":
    main()
```

- [ ] **Step 4: Run intent classification tests to verify they pass**

Run: `bash tests/test_fs.sh`
Expected: All 12 assertions PASS (intent classification only — no chain execution yet)

- [ ] **Step 5: Commit**

```bash
git add fs-engine.py tests/test_fs.sh
git commit -m "feat(fs): intent classification engine + TDD tests

Deterministic heuristic routing: glob/extension → file, camelCase/
snake_case/PascalCase → symbol, multi-word → content, ambiguous → low
confidence content. Explicit intent override bypasses classification."
```

---

### Task 2: Bash CLI Entrypoint

**Files:**
- Create: `fs`

Bash shim that parses CLI args, pipes JSON to the engine, and formats output (pretty or json).

- [ ] **Step 1: Add CLI tests to test_fs.sh**

Add this section after the intent classification tests in `tests/test_fs.sh`:

```bash
# ── Section 2: CLI Entrypoint ─────────────────────────────────────
echo ""
echo "=== CLI Entrypoint ==="

FS="$REPO_DIR/fs"

# CLI produces JSON
result=$("$FS" -o json "*.py" /tmp 2>/dev/null || true)
assert_json_field "CLI *.py → file" "$result" "resolved_intent" "file"

# CLI --scope flag
result=$("$FS" -o json "renderTool" --scope "*.js" --path /tmp 2>/dev/null || true)
assert_json_field "CLI --scope → fsearch in chain" "$result" "resolved_intent" "symbol"

# CLI --intent override
result=$("$FS" -o json "authenticate" --intent symbol --path /tmp 2>/dev/null || true)
assert_json_field "CLI --intent symbol" "$result" "resolved_intent" "symbol"

# CLI --help exits 0
"$FS" --help >/dev/null 2>&1
assert_eq "CLI --help exits 0" "0" "$?"

# CLI --version outputs version
version_out=$("$FS" --version 2>/dev/null)
assert_eq "CLI --version contains 2.3.0" "true" "$([[ "$version_out" == *"2.3.0"* ]] && echo true || echo false)"
```

- [ ] **Step 2: Run tests to verify CLI tests fail**

Run: `bash tests/test_fs.sh`
Expected: Intent tests PASS, CLI tests FAIL (fs script doesn't exist yet)

- [ ] **Step 3: Write the fs bash entrypoint**

```bash
#!/usr/bin/env bash
# fs — unified search orchestrator for fsuite.
# Routes queries to fsearch, fcontent, fmap based on heuristic intent classification.
#
# Architecture: Bash entrypoint + Python engine (fs-engine.py)
# The engine does routing, chaining, budgeting; this layer handles CLI UX.

set -euo pipefail

VERSION="2.3.0"

# ── Locate engine ────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$(realpath "$0" 2>/dev/null || readlink -f "$0" 2>/dev/null || echo "$0")")" && pwd)"
ENGINE="${SCRIPT_DIR}/fs-engine.py"

if [[ ! -f "$ENGINE" ]]; then
  for candidate in \
    "${FSUITE_SHARE_DIR:-/nonexistent}/fs-engine.py" \
    "${SCRIPT_DIR}/../share/fsuite/fs-engine.py" \
    "/usr/local/share/fsuite/fs-engine.py" \
    "/usr/share/fsuite/fs-engine.py"; do
    if [[ -f "$candidate" ]]; then
      ENGINE="$candidate"
      break
    fi
  done
fi

if [[ ! -f "$ENGINE" ]]; then
  echo "fs: error: fs-engine.py not found" >&2
  exit 1
fi

# ── Helpers ──────────────────────────────────────────────────────
die() { echo "fs: $*" >&2; exit 1; }

usage() {
cat <<'EOF'
fs — unified search orchestrator

USAGE
  fs [OPTIONS] <query> [path]

OPTIONS
  -s, --scope GLOB     Glob filter for file narrowing (e.g. "*.py")
  -i, --intent MODE    Override: auto|file|content|symbol (default: auto)
  -o, --output MODE    pretty|json (default: pretty for tty, json for pipe)
  -p, --path PATH      Search root (default: .)
  --max-candidates N   Override candidate file cap (default: 50)
  --max-enrich N       Override enrichment file cap (default: 15)
  --timeout N          Override wall time cap in seconds (default: 10)
  -h, --help           Show help
  --version            Show version

EXAMPLES
  fs "authenticate"                    # auto-route, search cwd
  fs "*.py" /repo                      # file intent (glob detected)
  fs "renderTool" --scope "*.js"       # symbol in JS files
  fs "error loading" --intent content  # explicit content search
EOF
}

# ── Parse args ───────────────────────────────────────────────────
QUERY=""
SEARCH_PATH="."
SCOPE=""
INTENT="auto"
OUTPUT=""
MAX_CANDIDATES=""
MAX_ENRICH=""
TIMEOUT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)    usage; exit 0 ;;
    --version)    echo "fs $VERSION"; exit 0 ;;
    -s|--scope)   SCOPE="$2"; shift 2 ;;
    -i|--intent)  INTENT="$2"; shift 2 ;;
    -o|--output)  OUTPUT="$2"; shift 2 ;;
    -p|--path)    SEARCH_PATH="$2"; shift 2 ;;
    --max-candidates) MAX_CANDIDATES="$2"; shift 2 ;;
    --max-enrich) MAX_ENRICH="$2"; shift 2 ;;
    --timeout)    TIMEOUT="$2"; shift 2 ;;
    -*)           die "unknown option: $1" ;;
    *)
      if [[ -z "$QUERY" ]]; then
        QUERY="$1"
      elif [[ "$SEARCH_PATH" == "." ]]; then
        SEARCH_PATH="$1"
      else
        die "unexpected argument: $1"
      fi
      shift
      ;;
  esac
done

[[ -n "$QUERY" ]] || { usage; exit 1; }

# Default output mode: json if piped, pretty if tty
if [[ -z "$OUTPUT" ]]; then
  if [[ -t 1 ]]; then OUTPUT="pretty"; else OUTPUT="json"; fi
fi

# ── Build JSON request ───────────────────────────────────────────
json_request=$(python3 -c "
import json, sys
req = {'query': sys.argv[1], 'path': sys.argv[2], 'intent': sys.argv[3]}
if sys.argv[4]: req['scope'] = sys.argv[4]
if sys.argv[5]: req['max_candidates'] = int(sys.argv[5])
if sys.argv[6]: req['max_enrich'] = int(sys.argv[6])
if sys.argv[7]: req['timeout'] = int(sys.argv[7])
print(json.dumps(req))
" "$QUERY" "$SEARCH_PATH" "$INTENT" "$SCOPE" "$MAX_CANDIDATES" "$MAX_ENRICH" "$TIMEOUT")

# ── Run engine ───────────────────────────────────────────────────
STDERR_TMP=$(mktemp)
trap 'rm -f "$STDERR_TMP"' EXIT

json_output=$(echo "$json_request" | python3 "$ENGINE" 2>"$STDERR_TMP") || {
  cat "$STDERR_TMP" >&2
  die "engine failed"
}

# ── Output ───────────────────────────────────────────────────────
if [[ "$OUTPUT" == "json" ]]; then
  echo "$json_output"
else
  # Pretty output: summary header + hits
  python3 -c "
import json, sys

data = json.loads(sys.stdin.read())
intent = data.get('resolved_intent', '?')
conf = data.get('route_confidence', '?')
reason = data.get('route_reason', '')
chain = ' → '.join(data.get('selected_chain', []))
hits = data.get('hits', [])
budget = data.get('budget', {})
hint = data.get('next_hint')
trunc = data.get('truncated', False)

print(f'\\033[1;36m{intent}\\033[0m ({conf}) via {chain}')
print(f'  {reason}')
print(f'  {budget.get(\"candidate_files\",0)} candidates, {budget.get(\"enriched_files\",0)} enriched, {budget.get(\"time_ms\",0)}ms')
if trunc:
    print(f'  \\033[1;33m⚠ truncated\\033[0m')
print()

for h in hits[:20]:
    f = h.get('file', '?')
    mc = h.get('match_count', 0)
    syms = h.get('symbols', [])
    print(f'  \\033[0;32m{f}\\033[0m', end='')
    if mc: print(f'  ({mc} matches)', end='')
    if syms: print(f'  [{\" \".join(syms[:5])}]', end='')
    print()

if hint:
    tool = hint.get('tool', '?')
    args = ' '.join(f'--{k} {v}' for k,v in hint.get('args',{}).items())
    print(f'\\n  \\033[1;35mnext →\\033[0m {tool} {args}')
" <<< "$json_output"
fi
```

- [ ] **Step 4: Make fs executable and run tests**

Run: `chmod +x fs && bash tests/test_fs.sh`
Expected: All intent + CLI tests PASS

- [ ] **Step 5: Commit**

```bash
git add fs tests/test_fs.sh
git commit -m "feat(fs): bash CLI entrypoint with pretty/json output

Parses args, builds JSON request, pipes to fs-engine.py. Auto-detects
tty for pretty vs json output. Pretty mode shows colored summary."
```

---

### Task 3: Chain Execution Integration Tests

**Files:**
- Modify: `tests/test_fs.sh`

Test that fs actually calls fsearch/fcontent/fmap correctly against a real file tree.

- [ ] **Step 1: Add integration tests to test_fs.sh**

Add this section after CLI tests:

```bash
# ── Section 3: Chain Execution (Integration) ──────────────────────
echo ""
echo "=== Chain Execution ==="

# Create a temp project with known files
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR" "$STDERR_TMP" 2>/dev/null' EXIT

mkdir -p "$TEST_DIR/src"
cat > "$TEST_DIR/src/auth.py" << 'PYEOF'
def authenticate(token, secret):
    """Authenticate a user with token and secret."""
    if not token:
        raise AuthError("missing token")
    return verify_token(token, secret)

class AuthError(Exception):
    pass

def verify_token(token, secret):
    return token == secret
PYEOF

cat > "$TEST_DIR/src/main.py" << 'PYEOF'
from auth import authenticate

def main():
    result = authenticate("abc", "abc")
    print(result)
PYEOF

cat > "$TEST_DIR/src/config.json" << 'JSONEOF'
{"api_key": "test123", "debug": true}
JSONEOF

# File intent: find *.py files
result=$("$FS" -o json "*.py" "$TEST_DIR" 2>/dev/null)
hit_count=$(echo "$result" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('hits',[])))")
assert_eq "*.py finds 2 python files" "2" "$hit_count"

# Content intent: find "authenticate"
result=$("$FS" -o json "authenticate" "$TEST_DIR" --intent content 2>/dev/null)
hit_count=$(echo "$result" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('hits',[])))")
assert_eq "content 'authenticate' finds files" "true" "$([[ "$hit_count" -ge 1 ]] && echo true || echo false)"

# Symbol intent: find "AuthError" (PascalCase → symbol chain)
result=$("$FS" -o json "AuthError" "$TEST_DIR" 2>/dev/null)
resolved=$(echo "$result" | python3 -c "import sys,json; print(json.load(sys.stdin).get('resolved_intent',''))")
assert_eq "AuthError → symbol intent" "symbol" "$resolved"
chain=$(echo "$result" | python3 -c "import sys,json; print(','.join(json.load(sys.stdin).get('selected_chain',[])))")
assert_eq "symbol chain includes fmap" "true" "$([[ "$chain" == *"fmap"* ]] && echo true || echo false)"

# Scoped search: "authenticate" in *.py files
result=$("$FS" -o json "authenticate" "$TEST_DIR" --scope "*.py" 2>/dev/null)
chain=$(echo "$result" | python3 -c "import sys,json; print(','.join(json.load(sys.stdin).get('selected_chain',[])))")
assert_eq "scoped has fsearch in chain" "true" "$([[ "$chain" == *"fsearch"* ]] && echo true || echo false)"

# next_hint is present
hint=$(echo "$result" | python3 -c "import sys,json; h=json.load(sys.stdin).get('next_hint'); print(h.get('tool','') if h else 'null')")
assert_eq "next_hint present" "true" "$([[ "$hint" != "null" ]] && echo true || echo false)"

# Budget fields present
time_ms=$(echo "$result" | python3 -c "import sys,json; print(json.load(sys.stdin).get('budget',{}).get('time_ms',-1))")
assert_eq "budget.time_ms >= 0" "true" "$([[ "$time_ms" -ge 0 ]] && echo true || echo false)"
```

- [ ] **Step 2: Run integration tests**

Run: `bash tests/test_fs.sh`
Expected: All tests PASS (engine chains to real fsearch/fcontent/fmap)

- [ ] **Step 3: Commit**

```bash
git add tests/test_fs.sh
git commit -m "test(fs): integration tests for chain execution

Tests file/content/symbol chains against a real temp project with
known Python files. Verifies hit counts, chain composition, next_hint,
and budget fields."
```

---

### Task 4: MCP Registration

**Files:**
- Modify: `mcp/index.js`

Register `fs` as an MCP tool with inputSchema, outputSchema, and structuredContent.

- [ ] **Step 1: Add fs MCP registration to mcp/index.js**

Add this block before the `// ─── Start` comment (before the server.connect line), after the fprobe registration:

```javascript
// ─── fs (unified search orchestrator) ───────────────────────────
server.registerTool(
  "fs",
  {
    title: "fs",
    description:
      "Unified search orchestrator. One call to find files, content, or symbols. " +
      "Auto-classifies query intent and chains the right fsuite tools (fsearch, fcontent, fmap). " +
      "Returns ranked hits with enrichment and a recommended next step (next_hint). " +
      "Use scope to narrow by file glob. Use intent to override auto-classification.",
    inputSchema: z.object({
      query: z.string().describe("Search intent: glob pattern, literal string, or code identifier"),
      path: z.string().optional().describe("Search root directory (default: cwd)"),
      scope: z.string().optional().describe("Glob filter to narrow file set first, e.g. '*.py'"),
      intent: z.enum(["auto", "file", "content", "symbol"]).optional()
        .describe("Override auto-classification. Default: auto"),
    }),
    outputSchema: z.object({
      query: z.string(),
      path: z.string(),
      scope: z.string().optional(),
      intent: z.enum(["auto", "file", "content", "symbol"]),
      resolved_intent: z.enum(["file", "content", "symbol"]),
      route_reason: z.string(),
      route_confidence: z.enum(["high", "medium", "low"]),
      selected_chain: z.array(z.string()),
      hits: z.array(z.object({}).passthrough()),
      truncated: z.boolean(),
      budget: z.object({
        candidate_files: z.number(),
        enriched_files: z.number(),
        time_ms: z.number(),
      }),
      next_hint: z.object({
        tool: z.string(),
        args: z.object({}).passthrough(),
      }).nullable(),
    }),
  },
  async ({ query, path, scope, intent }) => {
    // fs bypasses cli() — cli() wraps in { content }, but we need raw JSON
    // for structuredContent. Use run() + resolveTool() directly.
    const args = ["-o", "json", query];
    if (path) args.push("--path", path);
    if (scope) args.push("--scope", scope);
    if (intent) args.push("--intent", intent);
    const { stdout } = await run(resolveTool("fs"), args, EXEC_OPTS);
    try {
      const parsed = JSON.parse(stdout);
      // Build human-readable summary
      const chain = parsed.selected_chain?.join(" → ") || "?";
      const hitCount = parsed.hits?.length || 0;
      const summary = [
        `${parsed.resolved_intent} (${parsed.route_confidence}) via ${chain}`,
        `  ${parsed.route_reason}`,
        `  ${parsed.budget?.candidate_files || 0} candidates, ${parsed.budget?.enriched_files || 0} enriched, ${parsed.budget?.time_ms || 0}ms`,
        `  ${hitCount} hits${parsed.truncated ? " (truncated)" : ""}`,
      ];
      if (parsed.hits) {
        for (const h of parsed.hits.slice(0, 15)) {
          const syms = h.symbols ? ` [${h.symbols.slice(0, 5).join(", ")}]` : "";
          const mc = h.match_count ? ` (${h.match_count} matches)` : "";
          summary.push(`    ${h.file}${mc}${syms}`);
        }
      }
      if (parsed.next_hint) {
        const nh = parsed.next_hint;
        const argStr = Object.entries(nh.args || {}).map(([k, v]) => `${k}: ${v}`).join(", ");
        summary.push(`\n  next → ${nh.tool}(${argStr})`);
      }
      return {
        content: [{ type: "text", text: summary.join("\n") }],
        structuredContent: parsed,
      };
    } catch {
      return { content: [{ type: "text", text: raw }] };
    }
  }
);
```

- [ ] **Step 2: Add `fs` to the RENDERERS map**

No custom renderer needed — the handler above already builds the text summary inline. But add `fs` to the renderAs map if using the generic runTool helper. Since we're using a custom handler, skip this step.

- [ ] **Step 3: Verify MCP server starts without errors**

Run: `cd mcp && node -e "import('./index.js').then(() => console.log('OK')).catch(e => { console.error(e); process.exit(1) })"`
Expected: `OK` (no import/syntax errors)

- [ ] **Step 4: Commit**

```bash
git add mcp/index.js
git commit -m "feat(fs): MCP registration with structuredContent + outputSchema

Registers fs as MCP tool alongside existing primitives. Returns both
human-readable content summary and machine-readable structuredContent.
outputSchema enables Claude Code client-side validation."
```

---

### Task 5: Suite Integration (install, freplay, fsuite, tests)

**Files:**
- Modify: `install.sh`
- Modify: `freplay`
- Modify: `fsuite`
- Modify: `tests/run_all_tests.sh`

Wire fs into every integration point so it's a first-class citizen.

- [ ] **Step 1: Add fs to install.sh**

In `install.sh`, change:
```bash
TOOLS=(fsuite ftree fsearch fcontent fmap fread fcase fedit fmetrics freplay fprobe)
SHARE_FILES=(_fsuite_common.sh _fsuite_db.sh fmetrics-predict.py fprobe-engine.py)
```
to:
```bash
TOOLS=(fsuite ftree fsearch fcontent fmap fread fcase fedit fmetrics freplay fprobe fs)
SHARE_FILES=(_fsuite_common.sh _fsuite_db.sh fmetrics-predict.py fprobe-engine.py fs-engine.py)
```

- [ ] **Step 2: Add fs to freplay**

In `freplay`, change the TOOL_MODE_DEFAULT to include fs:
```bash
declare -A TOOL_MODE_DEFAULT=(
  [ftree]="read_only"
  [fsearch]="read_only"
  [fcontent]="read_only"
  [fmap]="read_only"
  [fread]="read_only"
  [fedit]="read_only"
  [fprobe]="read_only"
  [fs]="read_only"
)
```

In `is_fsuite_tool()`, change:
```bash
ftree|fsearch|fcontent|fmap|fread|fcase|fedit|fsuite|fmetrics|freplay|fprobe) return 0 ;;
```
to:
```bash
ftree|fsearch|fcontent|fmap|fread|fcase|fedit|fsuite|fmetrics|freplay|fprobe|fs) return 0 ;;
```

- [ ] **Step 3: Add fs to fsuite help text**

In `fsuite`, update the tool list in `print_help()`:
- Change `"Ten operational tools. One composable sensor suite."` to `"Eleven operational tools. One composable sensor suite."`
- Change `"fsuite is the suite-level guide for the ten operational tools:"` to `"fsuite is the suite-level guide for the eleven operational tools:"`
- Add `fs` to the tool listing:
```
fs        One-call search: routes queries to fsearch/fcontent/fmap automatically
```
- Add to the tool listing line: `ftree, fsearch, fcontent, fmap, fread, fcase, fedit, fmetrics, freplay, fprobe, fs`

- [ ] **Step 4: Add fs test suite to run_all_tests.sh**

Add after the fprobe test block:

```bash
# ── fs ─────────────────────────────────────────────────────────
run_test_suite "${SCRIPT_DIR}/test_fs.sh" "fs (unified search)"
```

- [ ] **Step 5: Update mcp/package.json version**

Change version from `"2.2.0"` to `"2.3.0"`.

- [ ] **Step 6: Run full test suite**

Run: `bash tests/run_all_tests.sh`
Expected: All test suites pass including the new fs tests

- [ ] **Step 7: Commit**

```bash
git add install.sh freplay fsuite tests/run_all_tests.sh mcp/package.json
git commit -m "chore(fs): suite integration — install, freplay, fsuite, tests

Add fs to TOOLS array, SHARE_FILES, TOOL_MODE_DEFAULT, is_fsuite_tool,
suite help text (eleven tools), and master test runner. Bump MCP
version to 2.3.0."
```

---

### Task 6: End-to-End Validation

**Files:** (no new files — validation only)

- [ ] **Step 1: Run the full test suite**

Run: `cd <project-root> && bash tests/run_all_tests.sh`
Expected: All suites green

- [ ] **Step 2: Test fs CLI manually**

```bash
# File search
fs "*.py" <project-root>

# Content search
fs "highlightLine" <project-root>

# Symbol search
fs "McpServer" <project-root>

# Scoped search
fs "registerTool" --scope "*.js" <project-root>

# JSON output
fs -o json "DIFF_COLORS" <project-root>
```

Expected: Each returns structured results with correct intent classification, hits, and next_hint.

- [ ] **Step 3: Restart MCP server and test via Claude Code**

Restart Claude Code to reload MCP. Then call `fs(query: "highlightLine")` via MCP.
Expected: Returns structuredContent with resolved_intent=symbol, hits with file paths, next_hint pointing to fread.

- [ ] **Step 4: Import metrics**

Run: `fmetrics import` to capture any new telemetry from the test runs.

- [ ] **Step 5: Final commit if any fixes needed**

```bash
git add -A
git commit -m "fix(fs): address e2e validation findings"
```
