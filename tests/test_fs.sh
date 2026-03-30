#!/usr/bin/env bash
# test_fs.sh — TDD tests for fs-engine.py (intent classification + orchestration engine)
# Run with: bash tests/test_fs.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENGINE="${REPO_DIR}/fs-engine.py"

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# ── Helpers ──────────────────────────────────────────────────────────────────

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  TESTS_RUN=$((TESTS_RUN + 1))
  if [[ "$expected" == "$actual" ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}✓${NC} ${label}"
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}✗${NC} ${label}"
    echo "  expected: ${expected}"
    echo "  actual:   ${actual}"
  fi
}

assert_json_field() {
  local label="$1" json="$2" field="$3" expected="$4"
  local actual
  actual=$(echo "$json" | python3 -c '
import sys, json
data = json.load(sys.stdin)
keys = sys.argv[1].split(".")
val = data
for k in keys:
    if isinstance(val, dict):
        val = val.get(k, "")
    else:
        val = ""
        break
print(val)
' "$field" 2>/dev/null || echo "__PARSE_ERROR__")
  assert_eq "$label" "$expected" "$actual"
}

run_engine() {
  echo "$1" | python3 "$ENGINE" 2>/dev/null
}

run_engine_with_stubbed_fsearch() {
  local request_json="$1"
  local stub_stdout="${2-}"
  local stub_stderr="${3-}"
  local stub_rc="${4-0}"

  python3 - "$ENGINE" "$request_json" "$stub_stdout" "$stub_stderr" "$stub_rc" <<'PY'
import importlib.util
import json
import sys

engine_path, request_json, stub_stdout, stub_stderr, stub_rc = sys.argv[1:6]
stub_rc = int(stub_rc)
spec = importlib.util.spec_from_file_location("fs_engine_test", engine_path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
request = json.loads(request_json)

def fake_run_tool(name, args, stdin_data=None, timeout=module.TIMEOUT_SECONDS):
    if name != "fsearch":
        raise AssertionError(f"unexpected tool call: {name}")
    return stub_stdout, stub_stderr, stub_rc, False

module.run_tool = fake_run_tool

try:
    result = module.orchestrate(request)
except Exception as exc:
    result = {"error": f"engine error: {exc}", "query": request.get("query", "")}

print(json.dumps(result))
PY
}

# ── Preflight check ─────────────────────────────────────────────────────────

if [[ ! -f "$ENGINE" ]]; then
  echo -e "${RED}ERROR${NC}: fs-engine.py not found at ${ENGINE}"
  exit 1
fi

echo "═══════════════════════════════════════════"
echo " fs-engine test suite"
echo "═══════════════════════════════════════════"
echo ""

# ============================================================================
# Section 1: Intent Classification
# ============================================================================

echo "── Section 1: Intent Classification ──"

# 1. Glob pattern → file intent, high confidence
result=$(run_engine '{"query": "*.py", "path": "/tmp"}')
assert_json_field "*.py → file intent" "$result" "resolved_intent" "file"
assert_json_field "*.py → high confidence" "$result" "route_confidence" "high"

# 2. Bare extension → file intent, high confidence
result=$(run_engine '{"query": ".rs", "path": "/tmp"}')
assert_json_field ".rs → file intent" "$result" "resolved_intent" "file"
assert_json_field ".rs → high confidence" "$result" "route_confidence" "high"

# 3. Known filename (package.json) → file intent, high confidence
result=$(run_engine '{"query": "package.json", "path": "/tmp"}')
assert_json_field "package.json → file intent" "$result" "resolved_intent" "file"
assert_json_field "package.json → high confidence" "$result" "route_confidence" "high"

# 4. camelCase → symbol intent, high confidence
result=$(run_engine '{"query": "renderTool", "path": "/tmp"}')
assert_json_field "renderTool (camelCase) → symbol intent" "$result" "resolved_intent" "symbol"
assert_json_field "renderTool → high confidence" "$result" "route_confidence" "high"

# 5. PascalCase → symbol intent, high confidence
result=$(run_engine '{"query": "McpServer", "path": "/tmp"}')
assert_json_field "McpServer (PascalCase) → symbol intent" "$result" "resolved_intent" "symbol"
assert_json_field "McpServer → high confidence" "$result" "route_confidence" "high"

# 6. snake_case → symbol intent, high confidence
result=$(run_engine '{"query": "verify_token", "path": "/tmp"}')
assert_json_field "verify_token (snake_case) → symbol intent" "$result" "resolved_intent" "symbol"
assert_json_field "verify_token → high confidence" "$result" "route_confidence" "high"

# 7. SCREAMING_CASE → symbol intent, medium confidence
result=$(run_engine '{"query": "DIFF_COLORS", "path": "/tmp"}')
assert_json_field "DIFF_COLORS (SCREAMING_CASE) → symbol intent" "$result" "resolved_intent" "symbol"
assert_json_field "DIFF_COLORS → medium confidence" "$result" "route_confidence" "medium"

# 8. Multi-word (spaces) → content intent, high confidence
result=$(run_engine '{"query": "error loading config", "path": "/tmp"}')
assert_json_field "multi-word → content intent" "$result" "resolved_intent" "content"
assert_json_field "multi-word → high confidence" "$result" "route_confidence" "high"

# 9. Single lowercase word → content intent, LOW confidence
result=$(run_engine '{"query": "authenticate", "path": "/tmp"}')
assert_json_field "single lowercase → content intent" "$result" "resolved_intent" "content"
assert_json_field "single lowercase → low confidence" "$result" "route_confidence" "low"

# 10. Explicit intent override → symbol, high confidence
result=$(run_engine '{"query": "authenticate", "path": "/tmp", "intent": "symbol"}')
assert_json_field "explicit intent override → symbol" "$result" "resolved_intent" "symbol"
assert_json_field "explicit override → high confidence" "$result" "route_confidence" "high"

# ============================================================================
# Section 2: Chain Building
# ============================================================================

echo ""
echo "── Section 2: Chain Building ──"

# file intent, no scope → ["fsearch"]
result=$(run_engine '{"query": "*.py", "path": "/tmp"}')
chain=$(echo "$result" | python3 -c "import sys,json; print(','.join(json.load(sys.stdin)['selected_chain']))")
assert_eq "file (no scope) → [fsearch]" "fsearch" "$chain"

# content intent, no scope → ["fcontent"]
result=$(run_engine '{"query": "error loading config", "path": "/tmp"}')
chain=$(echo "$result" | python3 -c "import sys,json; print(','.join(json.load(sys.stdin)['selected_chain']))")
assert_eq "content (no scope) → [fcontent]" "fcontent" "$chain"

# symbol intent, no scope → ["fcontent", "fmap"]
result=$(run_engine '{"query": "renderTool", "path": "/tmp"}')
chain=$(echo "$result" | python3 -c "import sys,json; print(','.join(json.load(sys.stdin)['selected_chain']))")
assert_eq "symbol (no scope) → [fcontent,fmap]" "fcontent,fmap" "$chain"

# file intent with scope → ["fsearch"] (file intent always uses fsearch)
result=$(run_engine '{"query": "*.py", "path": "/tmp", "intent": "file", "scope": "*.py"}')
chain=$(echo "$result" | python3 -c "import sys,json; print(','.join(json.load(sys.stdin)['selected_chain']))")
assert_eq "file (with scope) → [fsearch]" "fsearch" "$chain"

# content intent with scope → ["fsearch", "fcontent"]
result=$(run_engine '{"query": "authenticate", "path": "/tmp", "intent": "content", "scope": "*.py"}')
chain=$(echo "$result" | python3 -c "import sys,json; print(','.join(json.load(sys.stdin)['selected_chain']))")
assert_eq "content (with scope) → [fsearch,fcontent]" "fsearch,fcontent" "$chain"

# symbol intent with scope → ["fsearch", "fcontent", "fmap"]
result=$(run_engine '{"query": "McpServer", "path": "/tmp", "scope": "*.ts"}')
chain=$(echo "$result" | python3 -c "import sys,json; print(','.join(json.load(sys.stdin)['selected_chain']))")
assert_eq "symbol (with scope) → [fsearch,fcontent,fmap]" "fsearch,fcontent,fmap" "$chain"

# explicit nav intent override → ["fsearch"]
result=$(run_engine '{"query": "docs", "path": "/tmp", "intent": "nav"}')
assert_json_field "explicit nav override → nav" "$result" "resolved_intent" "nav"
assert_json_field "explicit nav override → high confidence" "$result" "route_confidence" "high"
chain=$(echo "$result" | python3 -c "import sys,json; print(','.join(json.load(sys.stdin)['selected_chain']))")
assert_eq "nav override → [fsearch]" "fsearch" "$chain"

# ambiguous bare word still does NOT auto-nav
result=$(run_engine '{"query": "docs", "path": "/tmp"}')
assert_json_field "bare docs remains content" "$result" "resolved_intent" "content"
assert_json_field "bare docs remains low confidence" "$result" "route_confidence" "low"

# ============================================================================
# Section 3: Output Structure
# ============================================================================

echo ""
echo "── Section 3: Output Structure ──"

result=$(run_engine '{"query": "*.py", "path": "/tmp"}')

# Verify all required top-level keys exist
for key in query path intent resolved_intent route_reason route_confidence selected_chain hits truncated budget next_hint; do
  has_key=$(echo "$result" | python3 -c "
import sys, json
data = json.load(sys.stdin)
print('yes' if sys.argv[1] in data else 'no')
" "$key" 2>/dev/null || echo "no")
  TESTS_RUN=$((TESTS_RUN + 1))
  if [[ "$has_key" == "yes" ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}✓${NC} output has '${key}' field"
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}✗${NC} output missing '${key}' field"
  fi
done

# Budget sub-fields
for key in candidate_files enriched_files time_ms; do
  has_key=$(echo "$result" | python3 -c "
import sys, json
data = json.load(sys.stdin)
print('yes' if sys.argv[1] in data.get('budget', {}) else 'no')
" "$key" 2>/dev/null || echo "no")
  TESTS_RUN=$((TESTS_RUN + 1))
  if [[ "$has_key" == "yes" ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}✓${NC} budget has '${key}' sub-field"
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}✗${NC} budget missing '${key}' sub-field"
  fi
done

# ============================================================================
# Section 4: Budget Caps
# ============================================================================

echo ""
echo "── Section 4: Budget Caps ──"

result=$(run_engine '{"query": "*.py", "path": "/tmp"}')
candidate_cap=$(echo "$result" | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(data['budget']['candidate_files'])
" 2>/dev/null || echo "-1")

TESTS_RUN=$((TESTS_RUN + 1))
cap_ok=$(python3 -c "print('yes' if int('${candidate_cap}') <= 50 else 'no')" 2>/dev/null || echo "no")
if [[ "$cap_ok" == "yes" ]]; then
  TESTS_PASSED=$((TESTS_PASSED + 1))
  echo -e "${GREEN}✓${NC} candidate_files <= 50 (MAX_CANDIDATE_FILES)"
else
  TESTS_FAILED=$((TESTS_FAILED + 1))
  echo -e "${RED}✗${NC} candidate_files exceeds MAX_CANDIDATE_FILES cap (got ${candidate_cap})"
fi

# ============================================================================
# Section 5: Edge Cases
# ============================================================================

echo ""
echo "── Section 5: Edge Cases ──"

# Empty query
result=$(run_engine '{"query": "", "path": "/tmp"}')
has_error=$(echo "$result" | python3 -c "
import sys, json
data = json.load(sys.stdin)
print('yes' if 'error' in data else 'no')
" 2>/dev/null || echo "no")
TESTS_RUN=$((TESTS_RUN + 1))
if [[ "$has_error" == "yes" ]]; then
  TESTS_PASSED=$((TESTS_PASSED + 1))
  echo -e "${GREEN}✓${NC} empty query returns error"
else
  TESTS_FAILED=$((TESTS_FAILED + 1))
  echo -e "${RED}✗${NC} empty query should return error"
fi

# Missing path defaults to "."
result=$(run_engine '{"query": "test"}')
has_error=$(echo "$result" | python3 -c "
import sys, json
data = json.load(sys.stdin)
print('yes' if 'error' in data else 'no')
" 2>/dev/null || echo "no")
TESTS_RUN=$((TESTS_RUN + 1))
if [[ "$has_error" == "no" ]]; then
  TESTS_PASSED=$((TESTS_PASSED + 1))
  echo -e "${GREEN}✓${NC} missing path defaults to '.' (no error)"
else
  TESTS_FAILED=$((TESTS_FAILED + 1))
  echo -e "${RED}✗${NC} missing path should default to '.', not error"
fi
assert_json_field "missing path → path is '.'" "$result" "path" "."

# Filename-shaped query (word.ext) → file
result=$(run_engine '{"query": "config.yaml", "path": "/tmp"}')
assert_json_field "config.yaml → file intent" "$result" "resolved_intent" "file"
assert_json_field "config.yaml → high confidence" "$result" "route_confidence" "high"

# Scope field present when scope is provided
result=$(run_engine '{"query": "test", "path": "/tmp", "scope": "*.py"}')
has_scope=$(echo "$result" | python3 -c "
import sys, json
data = json.load(sys.stdin)
print('yes' if 'scope' in data else 'no')
" 2>/dev/null || echo "no")
TESTS_RUN=$((TESTS_RUN + 1))
if [[ "$has_scope" == "yes" ]]; then
  TESTS_PASSED=$((TESTS_PASSED + 1))
  echo -e "${GREEN}✓${NC} scope field present when scope provided"
else
  TESTS_FAILED=$((TESTS_FAILED + 1))
  echo -e "${RED}✗${NC} scope field should be present when scope provided"
fi

# Scope field absent when scope is not provided
result=$(run_engine '{"query": "test", "path": "/tmp"}')
has_scope=$(echo "$result" | python3 -c "
import sys, json
data = json.load(sys.stdin)
print('yes' if 'scope' in data else 'no')
" 2>/dev/null || echo "no")
TESTS_RUN=$((TESTS_RUN + 1))
if [[ "$has_scope" == "no" ]]; then
  TESTS_PASSED=$((TESTS_PASSED + 1))
  echo -e "${GREEN}✓${NC} scope field absent when scope not provided"
else
  TESTS_FAILED=$((TESTS_FAILED + 1))
  echo -e "${RED}✗${NC} scope field should be absent when scope not provided"
fi

# ============================================================================
# Section 6: CLI Entrypoint
# ============================================================================

echo ""
echo "── Section 6: CLI Entrypoint ──"

FS="$REPO_DIR/fs"

# CLI produces JSON
result=$("$FS" -o json "*.py" /tmp 2>/dev/null || true)
assert_json_field "CLI *.py → file" "$result" "resolved_intent" "file"

# CLI --scope flag
result=$("$FS" -o json "renderTool" --scope "*.js" --path /tmp 2>/dev/null || true)
assert_json_field "CLI --scope passes through" "$result" "resolved_intent" "symbol"

# CLI --intent override
result=$("$FS" -o json "authenticate" --intent symbol --path /tmp 2>/dev/null || true)
assert_json_field "CLI --intent symbol" "$result" "resolved_intent" "symbol"

# CLI --help exits 0
"$FS" --help >/dev/null 2>&1; help_rc=$?
assert_eq "CLI --help exits 0" "0" "$help_rc"

# CLI --version
version_out=$("$FS" --version 2>/dev/null)
assert_eq "CLI --version contains 2.3.0" "true" "$([[ "$version_out" == *"2.3.0"* ]] && echo true || echo false)"

# CLI pretty output should not show orphan preview ellipsis without visible children
STUB_FS_DIR=$(mktemp -d)
cp "$FS" "$STUB_FS_DIR/fs"
chmod +x "$STUB_FS_DIR/fs"
cat > "$STUB_FS_DIR/fs-engine.py" <<'PYEOF'
#!/usr/bin/env python3
import json
import sys

sys.stdin.read()
json.dump({
    "query": "docs",
    "path": "/tmp",
    "intent": "nav",
    "resolved_intent": "nav",
    "route_reason": "explicit override",
    "route_confidence": "high",
    "selected_chain": ["fsearch"],
    "hits": [
        {
            "path": "/tmp/docs",
            "kind": "dir",
            "preview": [],
            "preview_truncated": True,
        }
    ],
    "truncated": False,
    "budget": {
        "candidate_files": 1,
        "enriched_files": 0,
        "time_ms": 1,
    },
    "next_hint": {
        "tool": "ftree",
        "args": {
            "path": "/tmp/docs",
            "depth": 2,
        }
    },
}, sys.stdout)
PYEOF
chmod +x "$STUB_FS_DIR/fs-engine.py"
PRETTY_STDERR=$(mktemp)
if pretty_out=$("$STUB_FS_DIR/fs" -o pretty docs /tmp 2>"$PRETTY_STDERR"); then
  pretty_rc=0
else
  pretty_rc=$?
fi
pretty_err=$(cat "$PRETTY_STDERR")
rm -f "$PRETTY_STDERR"
rm -rf "$STUB_FS_DIR"
pretty_check=$(printf '%s' "$pretty_out" | python3 -c '
import re
import sys
text = re.sub(r"\x1b\[[0-9;]*m", "", sys.stdin.read())
has_path = "/tmp/docs/" in text
has_orphan_ellipsis = any(line == "  ..." for line in text.splitlines())
print("yes" if has_path and not has_orphan_ellipsis else "no")
' 2>/dev/null || echo "no")
assert_eq "CLI pretty output regression exits 0" "0" "$pretty_rc"
TESTS_RUN=$((TESTS_RUN + 1))
if [[ "$pretty_check" == "yes" ]]; then
  TESTS_PASSED=$((TESTS_PASSED + 1))
  echo -e "${GREEN}✓${NC} CLI pretty output suppresses orphan preview ellipsis"
else
  TESTS_FAILED=$((TESTS_FAILED + 1))
  echo -e "${RED}✗${NC} CLI pretty output should suppress orphan preview ellipsis"
  echo "  exit: ${pretty_rc}"
  echo "  stderr: ${pretty_err}"
  echo "  output: ${pretty_out}"
fi

# ============================================================================
# Section 7: Chain Execution Integration Tests
# ============================================================================

echo ""
echo "── Section 7: Chain Execution Integration Tests ──"

TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

mkdir -p "$TEST_DIR/src"
mkdir -p "$TEST_DIR/docs/handoffs"

cat > "$TEST_DIR/src/auth.py" << 'PYEOF'
def authenticate(token, secret):
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

cat > "$TEST_DIR/docs/handoffs/note.md" << 'MDEOF'
# note
MDEOF

# 7.1 — file intent: *.py finds 2 python files
result=$("$FS" -o json "*.py" "$TEST_DIR" 2>/dev/null || true)
hit_count=$(echo "$result" | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(len(data.get('hits', [])))
" 2>/dev/null || echo "0")
assert_json_field "7.1 file intent" "$result" "resolved_intent" "file"
assert_eq "7.1 *.py finds 2 python files" "2" "$hit_count"

# 7.2 — content intent: "authenticate" finds at least 1 file
result=$("$FS" -o json "authenticate" "$TEST_DIR" --intent content 2>/dev/null || true)
hit_count=$(echo "$result" | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(len(data.get('hits', [])))
" 2>/dev/null || echo "0")
assert_json_field "7.2 content intent override" "$result" "resolved_intent" "content"
TESTS_RUN=$((TESTS_RUN + 1))
if [[ "$hit_count" -ge 1 ]]; then
  TESTS_PASSED=$((TESTS_PASSED + 1))
  echo -e "${GREEN}✓${NC} 7.2 content hits >= 1 (got ${hit_count})"
else
  TESTS_FAILED=$((TESTS_FAILED + 1))
  echo -e "${RED}✗${NC} 7.2 content hits >= 1 (got ${hit_count})"
fi

# 7.3 — symbol intent: "AuthError" (PascalCase), chain includes fmap
result=$("$FS" -o json "AuthError" "$TEST_DIR" 2>/dev/null || true)
assert_json_field "7.3 AuthError → symbol intent" "$result" "resolved_intent" "symbol"
chain=$(echo "$result" | python3 -c "import sys,json; print(','.join(json.load(sys.stdin)['selected_chain']))" 2>/dev/null || echo "")
TESTS_RUN=$((TESTS_RUN + 1))
if [[ "$chain" == *"fmap"* ]]; then
  TESTS_PASSED=$((TESTS_PASSED + 1))
  echo -e "${GREEN}✓${NC} 7.3 symbol chain includes fmap (${chain})"
else
  TESTS_FAILED=$((TESTS_FAILED + 1))
  echo -e "${RED}✗${NC} 7.3 symbol chain should include fmap (got ${chain})"
fi

# 7.4 — scoped search: chain includes fsearch
result=$("$FS" -o json "authenticate" "$TEST_DIR" --scope "*.py" 2>/dev/null || true)
chain=$(echo "$result" | python3 -c "import sys,json; print(','.join(json.load(sys.stdin)['selected_chain']))" 2>/dev/null || echo "")
TESTS_RUN=$((TESTS_RUN + 1))
if [[ "$chain" == *"fsearch"* ]]; then
  TESTS_PASSED=$((TESTS_PASSED + 1))
  echo -e "${GREEN}✓${NC} 7.4 scoped chain includes fsearch (${chain})"
else
  TESTS_FAILED=$((TESTS_FAILED + 1))
  echo -e "${RED}✗${NC} 7.4 scoped chain should include fsearch (got ${chain})"
fi

# 7.5 — next_hint is present (not null) for results with hits
result=$("$FS" -o json "authenticate" "$TEST_DIR" --intent content 2>/dev/null || true)
next_hint_present=$(echo "$result" | python3 -c "
import sys, json
data = json.load(sys.stdin)
hits = data.get('hits', [])
nh = data.get('next_hint')
print('yes' if len(hits) > 0 and nh is not None else 'no')
" 2>/dev/null || echo "no")
TESTS_RUN=$((TESTS_RUN + 1))
if [[ "$next_hint_present" == "yes" ]]; then
  TESTS_PASSED=$((TESTS_PASSED + 1))
  echo -e "${GREEN}✓${NC} 7.5 next_hint is present when hits exist"
else
  TESTS_FAILED=$((TESTS_FAILED + 1))
  echo -e "${RED}✗${NC} 7.5 next_hint should be present when hits exist"
fi

# 7.6 — budget.time_ms >= 0
result=$("$FS" -o json "*.py" "$TEST_DIR" 2>/dev/null || true)
time_ok=$(echo "$result" | python3 -c "
import sys, json
data = json.load(sys.stdin)
t = data.get('budget', {}).get('time_ms', -1)
print('yes' if t >= 0 else 'no')
" 2>/dev/null || echo "no")
TESTS_RUN=$((TESTS_RUN + 1))
if [[ "$time_ok" == "yes" ]]; then
  TESTS_PASSED=$((TESTS_PASSED + 1))
  echo -e "${GREEN}✓${NC} 7.6 budget.time_ms >= 0"
else
  TESTS_FAILED=$((TESTS_FAILED + 1))
  echo -e "${RED}✗${NC} 7.6 budget.time_ms should be >= 0"
fi

# 7.7 — explicit nav override returns nav hits
result=$("$FS" -o json "docs" "$TEST_DIR" --intent nav 2>/dev/null || true)
assert_json_field "7.7 docs with nav override" "$result" "resolved_intent" "nav"
chain=$(echo "$result" | python3 -c "import sys,json; print(','.join(json.load(sys.stdin)['selected_chain']))" 2>/dev/null || echo "")
assert_eq "7.7 nav chain → [fsearch]" "fsearch" "$chain"

# 7.8 — bare docs still does not auto-nav
result=$("$FS" -o json "docs" "$TEST_DIR" 2>/dev/null || true)
assert_json_field "7.8 bare docs remains content" "$result" "resolved_intent" "content"
assert_json_field "7.8 bare docs remains low confidence" "$result" "route_confidence" "low"

# 7.9 — nav dir hits recommend ftree
result=$("$FS" -o json "docs" "$TEST_DIR" --intent nav 2>/dev/null || true)
next_tool=$(echo "$result" | python3 -c "import sys,json; print((json.load(sys.stdin).get('next_hint') or {}).get('tool', ''))" 2>/dev/null || echo "")
assert_eq "7.9 nav dir hit suggests ftree" "ftree" "$next_tool"

# 7.10 — malformed nav JSON from fsearch surfaces as an error
result=$(run_engine_with_stubbed_fsearch '{"query":"docs","path":"/tmp","intent":"nav"}' '{not json')
assert_json_field "7.10 malformed nav JSON keeps query context" "$result" "query" "docs"
engine_error=$(echo "$result" | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(data.get('error', ''))
" 2>/dev/null || echo "")
TESTS_RUN=$((TESTS_RUN + 1))
if [[ "$engine_error" == *"fsearch returned invalid JSON"* ]]; then
  TESTS_PASSED=$((TESTS_PASSED + 1))
  echo -e "${GREEN}✓${NC} 7.10 malformed nav JSON returns an engine error"
else
  TESTS_FAILED=$((TESTS_FAILED + 1))
  echo -e "${RED}✗${NC} 7.10 malformed nav JSON should return an engine error"
  echo "  actual error: ${engine_error}"
fi

# 7.11 — nav fsearch exit failures surface as engine errors
result=$(run_engine_with_stubbed_fsearch '{"query":"docs","path":"/tmp","intent":"nav"}' '' 'permission denied' 17)
assert_json_field "7.11 fsearch exit failure keeps query context" "$result" "query" "docs"
engine_error=$(echo "$result" | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(data.get('error', ''))
" 2>/dev/null || echo "")
TESTS_RUN=$((TESTS_RUN + 1))
if [[ "$engine_error" == *"fsearch failed with exit 17: permission denied"* ]]; then
  TESTS_PASSED=$((TESTS_PASSED + 1))
  echo -e "${GREEN}✓${NC} 7.11 fsearch exit failures return an engine error"
else
  TESTS_FAILED=$((TESTS_FAILED + 1))
  echo -e "${RED}✗${NC} 7.11 fsearch exit failures should return an engine error"
  echo "  actual error: ${engine_error}"
fi

# 7.12 — empty nav JSON output surfaces as engine errors
result=$(run_engine_with_stubbed_fsearch '{"query":"docs","path":"/tmp","intent":"nav"}')
assert_json_field "7.12 empty nav JSON keeps query context" "$result" "query" "docs"
engine_error=$(echo "$result" | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(data.get('error', ''))
" 2>/dev/null || echo "")
TESTS_RUN=$((TESTS_RUN + 1))
if [[ "$engine_error" == *"fsearch returned empty JSON output"* ]]; then
  TESTS_PASSED=$((TESTS_PASSED + 1))
  echo -e "${GREEN}✓${NC} 7.12 empty nav JSON returns an engine error"
else
  TESTS_FAILED=$((TESTS_FAILED + 1))
  echo -e "${RED}✗${NC} 7.12 empty nav JSON should return an engine error"
  echo "  actual error: ${engine_error}"
fi

# ============================================================================
# Results
# ============================================================================

echo ""
echo "═══════════════════════════════════════════"
echo " Results: ${TESTS_PASSED}/${TESTS_RUN} passed, ${TESTS_FAILED} failed"
echo "═══════════════════════════════════════════"

[[ $TESTS_FAILED -eq 0 ]] || exit 1
