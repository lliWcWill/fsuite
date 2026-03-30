#!/usr/bin/env bash
# fs — unified search meta-tool for fsuite.
# Classifies query intent, builds tool chains, and orchestrates
# fsearch/fcontent/fmap to deliver ranked results.
#
# Architecture: Bash entrypoint + Python engine (fs-engine.py)
# The engine handles classification, chain execution, and shaping;
# this layer handles CLI UX and formatting.

set -euo pipefail

VERSION="2.3.0"

# ── Locate engine ────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$(realpath "$0" 2>/dev/null || readlink -f "$0" 2>/dev/null || echo "$0")")" && pwd)"
ENGINE="${SCRIPT_DIR}/fs-engine.py"

if [[ ! -f "$ENGINE" ]]; then
  # Try installed location
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
fs — unified search meta-tool

USAGE
  fs [OPTIONS] <query> [path]

OPTIONS
  -s, --scope GLOB     Glob filter for file narrowing (e.g. "*.py")
  -i, --intent MODE    Override: auto|file|content|symbol|nav (default: auto)
  -o, --output MODE    pretty|json (default: pretty for tty, json for pipe)
  -p, --path PATH      Search root (default: .). Overrides positional [path].
  --max-candidates N   Override candidate file cap (default: 50)
  --max-enrich N       Override enrichment file cap (default: 15)
  --timeout N          Override wall time cap in seconds (default: 10)
  -h, --help           Show help
  --version            Show version

DESCRIPTION
  Classifies your query as file / symbol / content intent, then builds
  and runs the optimal fsuite tool chain. Returns ranked hits with
  enrichment and a next_hint for follow-up refinement.

EXAMPLES
  fs "*.py"                         # file search — glob
  fs renderTool                     # symbol search — camelCase detected
  fs "error loading config" src/    # content search — multi-word
  fs -s "*.ts" McpServer            # symbol search, scoped to .ts files
  fs -i symbol authenticate         # force symbol intent
  fs -i nav docs                    # explicit path navigation
  fs -o json "*.rs" | jq '.hits'    # JSON output for piping
EOF
}

# ── Parse arguments ──────────────────────────────────────────────
QUERY=""
SEARCH_PATH=""
SCOPE=""
INTENT=""
OUTPUT=""
MAX_CANDIDATES=""
MAX_ENRICH=""
TIMEOUT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)    echo "fs ${VERSION}"; exit 0 ;;
    --help|-h)    usage; exit 0 ;;
    -s|--scope)   [[ $# -ge 2 ]] || die "missing value for $1"; SCOPE="$2"; shift 2 ;;
    -i|--intent)  [[ $# -ge 2 ]] || die "missing value for $1"; INTENT="$2"; shift 2 ;;
    -o|--output)  [[ $# -ge 2 ]] || die "missing value for $1"; OUTPUT="$2"; shift 2 ;;
    -p|--path)    [[ $# -ge 2 ]] || die "missing value for $1"; SEARCH_PATH="$2"; shift 2 ;;
    --max-candidates) [[ $# -ge 2 ]] || die "missing value for $1"; MAX_CANDIDATES="$2"; shift 2 ;;
    --max-enrich)     [[ $# -ge 2 ]] || die "missing value for $1"; MAX_ENRICH="$2"; shift 2 ;;
    --timeout)        [[ $# -ge 2 ]] || die "missing value for $1"; TIMEOUT="$2"; shift 2 ;;
    --)           shift; break ;;
    -*)           die "unknown option: $1" ;;
    *)
      # Positional args: first is query, second is path
      if [[ -z "$QUERY" ]]; then
        QUERY="$1"
      elif [[ -z "$SEARCH_PATH" ]]; then
        SEARCH_PATH="$1"
      else
        die "unexpected argument: $1"
      fi
      shift
      ;;
  esac
done

# Remaining args after -- are positional
while [[ $# -gt 0 ]]; do
  if [[ -z "$QUERY" ]]; then
    QUERY="$1"
  elif [[ -z "$SEARCH_PATH" ]]; then
    SEARCH_PATH="$1"
  else
    die "unexpected argument: $1"
  fi
  shift
done

[[ -n "$QUERY" ]] || { usage >&2; exit 1; }

# Default path
if [[ -z "$SEARCH_PATH" ]]; then
  SEARCH_PATH="."
fi

# ── Detect output mode ───────────────────────────────────────────
if [[ -z "$OUTPUT" ]]; then
  if [[ -t 1 ]]; then
    OUTPUT="pretty"
  else
    OUTPUT="json"
  fi
fi

case "$OUTPUT" in
  pretty|json) ;;
  *) die "invalid --output value: '$OUTPUT' (accepted: pretty, json)" ;;
esac

case "$INTENT" in
  ""|auto|file|content|symbol|nav) ;;
  *) die "invalid --intent value: '$INTENT' (accepted: auto, file, content, symbol, nav)" ;;
esac

# ── Build JSON request via python3 ───────────────────────────────
json_request=$(python3 -c "
import json, sys

req = {
    'query': sys.argv[1],
    'path': sys.argv[2],
}

scope = sys.argv[3]
intent = sys.argv[4]
max_candidates = sys.argv[5]
max_enrich = sys.argv[6]
timeout = sys.argv[7]

if scope:
    req['scope'] = scope
if intent:
    req['intent'] = intent
if max_candidates:
    req['max_candidates'] = int(max_candidates)
if max_enrich:
    req['max_enrich'] = int(max_enrich)
if timeout:
    req['timeout'] = int(timeout)

print(json.dumps(req))
" "$QUERY" "$SEARCH_PATH" "$SCOPE" "$INTENT" "$MAX_CANDIDATES" "$MAX_ENRICH" "$TIMEOUT") || die "failed to build JSON request"

# ── Run engine ───────────────────────────────────────────────────
STDERR_TMP=$(mktemp)
trap 'rm -f "$STDERR_TMP"' EXIT

json_output=$(echo "$json_request" | python3 "$ENGINE" 2>"$STDERR_TMP") || {
  rc=$?
  cat "$STDERR_TMP" >&2
  exit $rc
}

# ── Format output ────────────────────────────────────────────────
if [[ "$OUTPUT" == "json" ]]; then
  echo "$json_output"
else
  echo "$json_output" | python3 -c "
import sys, json

CYAN = '\033[36m'
GREEN = '\033[32m'
MAGENTA = '\033[35m'
DIM = '\033[2m'
BOLD = '\033[1m'
NC = '\033[0m'

data = json.load(sys.stdin)

if 'error' in data:
    print(f'fs: {data[\"error\"]}', file=sys.stderr)
    sys.exit(1)
intent = data.get('resolved_intent', '?')
confidence = data.get('route_confidence', '?')
reason = data.get('route_reason', '')
hits = data.get('hits', [])
budget = data.get('budget', {})
next_hint = data.get('next_hint', '')
truncated = data.get('truncated', False)
scope = data.get('scope', '')

# Header
print(f'{CYAN}{BOLD}{intent}{NC} {DIM}({confidence}, {reason}){NC}')
if scope:
    print(f'{DIM}scope: {scope}{NC}')
chain = data.get('selected_chain', [])
print(f'{DIM}chain: {\" → \".join(chain)}{NC}')
print(f'{DIM}{budget.get(\"candidate_files\", 0)} candidates, {budget.get(\"enriched_files\", 0)} enriched, {budget.get(\"time_ms\", 0)}ms{NC}')
if truncated:
    print(f'{DIM}(truncated){NC}')
print()

# Hits
if not hits:
    print(f'{DIM}no hits{NC}')
else:
    for i, h in enumerate(hits):
        item_path = h.get('file') or h.get('path', '')
        suffix = '/' if h.get('kind') == 'dir' else ''
        print(f'{GREEN}{item_path}{suffix}{NC}')
        if 'preview' in h:
            for child in h['preview'][:5]:
                child_name = child.get('name', '')
                child_suffix = '/' if child.get('kind') == 'dir' else ''
                print(f'  {DIM}{child_name}{child_suffix}{NC}')
            if h.get('preview_truncated'):
                print(f'  {DIM}...{NC}')
        # Show match lines if present
        if 'line' in h:
            print(f'  {DIM}line {h[\"line\"]}{NC}', end='')
            if 'snippet' in h:
                snippet = h['snippet']
                if len(snippet) > 100:
                    snippet = snippet[:97] + '...'
                print(f'  {snippet}', end='')
            print()
        # Show symbols if present
        if 'symbols' in h:
            for sym in h['symbols'][:5]:
                name = sym.get('name', '')
                kind = sym.get('kind', '')
                sline = sym.get('line', '')
                print(f'  {DIM}{kind} {name} L{sline}{NC}')
        if i >= 19:
            remaining = len(hits) - 20
            if remaining > 0:
                print(f'{DIM}... and {remaining} more{NC}')
            break

# Next hint
hint = next_hint
if hint:
    tool = hint.get('tool', '?')
    args_parts = []
    for k, v in hint.get('args', {}).items():
        args_parts.append(f'--{k} {v}')
    args_str = ' '.join(args_parts)
    print(f'\n  \033[1;35mnext →\033[0m {tool} {args_str}')
"
fi
