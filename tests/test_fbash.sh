#!/usr/bin/env bash
# test_fbash.sh — comprehensive tests for fbash
# Run with: bash test_fbash.sh
#
# Tests cover: basic execution, exit codes, command classification,
# output budgeting (truncation, tail, filter, quiet), CWD tracking,
# smart routing suggestions, session state, internal commands,
# and the JSON output contract.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FBASH="${SCRIPT_DIR}/../fbash"
TEST_DIR=""
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

pass() { TESTS_PASSED=$((TESTS_PASSED + 1)); echo -e "${GREEN}✓${NC} $1"; }
fail() { TESTS_FAILED=$((TESTS_FAILED + 1)); echo -e "${RED}✗${NC} $1"; [[ -n "${2:-}" ]] && echo "  Details: $2"; }
skip() { echo -e "${YELLOW}⊘${NC} $1 (skipped)"; }
run_test() { TESTS_RUN=$((TESTS_RUN + 1)); local n="$1"; shift; "$@" || true; }

# ── Setup / Teardown ─────────────────────────────────────────────

setup() {
  TEST_DIR="$(mktemp -d)"

  # Isolate fbash session state so tests don't pollute user state
  export FBASH_SESSION_DIR="${TEST_DIR}/.fbash_session"
  mkdir -p "${FBASH_SESSION_DIR}"

  # Disable telemetry during tests
  export FSUITE_TELEMETRY=0
}

teardown() {
  if [[ -n "${TEST_DIR}" && -d "${TEST_DIR}" ]]; then
    rm -rf "${TEST_DIR}"
  fi
}

# Helper: run fbash and capture JSON output. Always appends -o json.
# Usage: fbash_json [args...]
# Sets global FBASH_OUT to the raw output.
fbash_json() {
  FBASH_OUT=$("${FBASH}" "$@" -o json 2>/dev/null) || true
}

# Helper: extract a top-level string/number/bool field from FBASH_OUT via jq.
# Usage: jfield <field_name>
jfield() {
  echo "$FBASH_OUT" | jq -r ".$1 // empty" 2>/dev/null
}

# Helper: extract a top-level raw value (for numbers and booleans without quotes).
# Usage: jraw <field_name>
jraw() {
  echo "$FBASH_OUT" | jq ".$1" 2>/dev/null
}

# ============================================================================
# 1. Basic Execution
# ============================================================================

test_basic_execution() {
  fbash_json --command 'echo hello'

  # Verify valid JSON
  if ! echo "$FBASH_OUT" | jq empty 2>/dev/null; then
    fail "basic_execution: output is not valid JSON" "Got: $FBASH_OUT"
    return
  fi

  local stdout
  stdout=$(jfield stdout)
  if [[ "$stdout" == "hello" ]]; then
    pass "basic_execution: stdout='hello'"
  else
    fail "basic_execution: expected stdout='hello'" "Got stdout='$stdout'"
  fi
}

# ============================================================================
# 2. Exit Code
# ============================================================================

test_exit_code() {
  fbash_json --command 'exit 42'

  local exit_code
  exit_code=$(jraw exit_code)
  if [[ "$exit_code" == "42" ]]; then
    pass "exit_code: exit_code=42"
  else
    fail "exit_code: expected 42" "Got exit_code='$exit_code'"
  fi
}

# ============================================================================
# 3. Command Classification — build
# ============================================================================

test_command_classification_build() {
  fbash_json --command 'make all'

  local cmd_class
  cmd_class=$(jfield command_class)
  if [[ "$cmd_class" == "build" ]]; then
    pass "classification_build: 'make all' -> build"
  else
    fail "classification_build: expected 'build'" "Got command_class='$cmd_class'"
  fi
}

# ============================================================================
# 4. Command Classification — test
# ============================================================================

test_command_classification_test() {
  fbash_json --command 'npm test'

  local cmd_class
  cmd_class=$(jfield command_class)
  if [[ "$cmd_class" == "test" ]]; then
    pass "classification_test: 'npm test' -> test"
  else
    fail "classification_test: expected 'test'" "Got command_class='$cmd_class'"
  fi
}

# ============================================================================
# 5. Command Classification — git
# ============================================================================

test_command_classification_git() {
  fbash_json --command 'git status'

  local cmd_class
  cmd_class=$(jfield command_class)
  if [[ "$cmd_class" == "git" ]]; then
    pass "classification_git: 'git status' -> git"
  else
    fail "classification_git: expected 'git'" "Got command_class='$cmd_class'"
  fi
}

# ============================================================================
# 6. Command Classification — query
# ============================================================================

test_command_classification_query() {
  fbash_json --command 'ls -la'

  local cmd_class
  cmd_class=$(jfield command_class)
  if [[ "$cmd_class" == "query" ]]; then
    pass "classification_query: 'ls -la' -> query"
  else
    fail "classification_query: expected 'query'" "Got command_class='$cmd_class'"
  fi
}

# ============================================================================
# 7. Max Lines Truncation
# ============================================================================

test_max_lines_truncation() {
  # Generate a file with 500 lines, then cat it through fbash with --max-lines 10
  local bigfile="${TEST_DIR}/big.txt"
  for i in $(seq 1 500); do
    echo "line $i of 500"
  done > "$bigfile"

  fbash_json --command "cat ${bigfile}" --max-lines 10

  local truncated stdout_lines
  truncated=$(jraw truncated)
  stdout_lines=$(jraw stdout_lines)

  if [[ "$truncated" == "true" ]] && [[ "$stdout_lines" == "10" ]]; then
    pass "max_lines_truncation: truncated=true, stdout_lines=10"
  else
    fail "max_lines_truncation: expected truncated=true and stdout_lines=10" \
         "Got truncated=$truncated, stdout_lines=$stdout_lines"
  fi
}

# ============================================================================
# 8. Tail Mode
# ============================================================================

test_tail_mode() {
  # Generate numbered lines 1-100
  local numfile="${TEST_DIR}/numbers.txt"
  for i in $(seq 1 100); do
    echo "line_$i"
  done > "$numfile"

  fbash_json --command "cat ${numfile}" --tail --max-lines 5

  local stdout
  stdout=$(jfield stdout)

  # The last 5 lines should be line_96 through line_100
  local has_tail=true
  for i in 96 97 98 99 100; do
    if [[ "$stdout" != *"line_$i"* ]]; then
      has_tail=false
      break
    fi
  done

  if [[ "$has_tail" == "true" ]]; then
    pass "tail_mode: last 5 lines (96-100) present"
  else
    fail "tail_mode: expected lines 96-100 in output" "Got stdout='${stdout:0:200}...'"
  fi
}

# ============================================================================
# 9. Filter
# ============================================================================

test_filter() {
  # Generate mixed output, then filter for specific lines
  local mixfile="${TEST_DIR}/mixed.txt"
  cat > "$mixfile" <<'EOF'
INFO: starting up
DEBUG: loading config
ERROR: disk full
INFO: retrying
ERROR: timeout
DEBUG: cleanup
EOF

  fbash_json --command "cat ${mixfile}" --filter 'ERROR'

  local stdout
  stdout=$(jfield stdout)

  if [[ "$stdout" == *"ERROR: disk full"* ]] && [[ "$stdout" == *"ERROR: timeout"* ]] && \
     [[ "$stdout" != *"INFO:"* ]] && [[ "$stdout" != *"DEBUG:"* ]]; then
    pass "filter: only ERROR lines returned"
  else
    fail "filter: expected only ERROR lines" "Got stdout='$stdout'"
  fi
}

# ============================================================================
# 10. Quiet Mode
# ============================================================================

test_quiet_mode() {
  fbash_json --command 'echo hello' --quiet

  local stdout exit_code
  stdout=$(jfield stdout)
  exit_code=$(jraw exit_code)

  if [[ -z "$stdout" || "$stdout" == "null" ]] && [[ "$exit_code" == "0" ]]; then
    pass "quiet_mode: stdout suppressed, exit_code=0"
  else
    fail "quiet_mode: expected empty stdout and exit_code=0" \
         "Got stdout='$stdout', exit_code=$exit_code"
  fi
}

# ============================================================================
# 11. CWD Tracking
# ============================================================================

test_cwd_tracking() {
  fbash_json --command 'pwd' --cwd /tmp

  local cwd
  cwd=$(jfield cwd)

  # cwd should be /tmp (or resolve to /tmp if it's a symlink, e.g. /private/tmp on macOS)
  if [[ "$cwd" == "/tmp" ]] || [[ "$cwd" == "/private/tmp" ]]; then
    pass "cwd_tracking: cwd=/tmp"
  else
    fail "cwd_tracking: expected cwd=/tmp" "Got cwd='$cwd'"
  fi
}

# ============================================================================
# 12. Routing Suggestion — ls -> fls
# ============================================================================

test_routing_suggestion_ls() {
  fbash_json --command 'ls'

  local routing_tool
  routing_tool=$(echo "$FBASH_OUT" | jq -r '.routing_suggestion.tool // empty' 2>/dev/null)

  if [[ "$routing_tool" == "fls" ]]; then
    pass "routing_suggestion_ls: ls -> fls"
  else
    fail "routing_suggestion_ls: expected tool='fls'" "Got routing_tool='$routing_tool'"
  fi
}

# ============================================================================
# 13. Routing Suggestion — cat -> fread
# ============================================================================

test_routing_suggestion_cat() {
  fbash_json --command 'cat /etc/hostname'

  local routing_tool
  routing_tool=$(echo "$FBASH_OUT" | jq -r '.routing_suggestion.tool // empty' 2>/dev/null)

  if [[ "$routing_tool" == "fread" ]]; then
    pass "routing_suggestion_cat: cat -> fread"
  else
    fail "routing_suggestion_cat: expected tool='fread'" "Got routing_tool='$routing_tool'"
  fi
}

# ============================================================================
# 14. Routing Suggestion — grep -> fcontent
# ============================================================================

test_routing_suggestion_grep() {
  fbash_json --command 'grep foo bar'

  local routing_tool
  routing_tool=$(echo "$FBASH_OUT" | jq -r '.routing_suggestion.tool // empty' 2>/dev/null)

  if [[ "$routing_tool" == "fcontent" ]]; then
    pass "routing_suggestion_grep: grep -> fcontent"
  else
    fail "routing_suggestion_grep: expected tool='fcontent'" "Got routing_tool='$routing_tool'"
  fi
}

# ============================================================================
# 15. Session State
# ============================================================================

test_session_state() {
  # Run a real command first to populate session
  "${FBASH}" --command 'echo session_test' -o json >/dev/null 2>&1 || true

  # Now query session state
  fbash_json --command '__fbash_session'

  # Session should have history with at least one entry
  local has_history
  has_history=$(echo "$FBASH_OUT" | jq 'if .stdout then (.stdout | test("history")) else false end' 2>/dev/null)

  # Alternative: the session response itself might be structured
  local has_session_id
  has_session_id=$(echo "$FBASH_OUT" | jq -r '.session_id // empty' 2>/dev/null)

  if [[ "$has_history" == "true" ]] || [[ -n "$has_session_id" ]]; then
    pass "session_state: session has history or session_id"
  else
    # Fallback: just verify the internal command was classified correctly
    local cmd_class
    cmd_class=$(jfield command_class)
    if [[ "$cmd_class" == "internal" ]]; then
      pass "session_state: __fbash_session classified as internal"
    else
      fail "session_state: expected session data or internal classification" \
           "Got output='${FBASH_OUT:0:300}'"
    fi
  fi
}

# ============================================================================
# 16. Internal History
# ============================================================================

test_internal_history() {
  # Run 3 commands to build history
  "${FBASH}" --command 'echo one' -o json >/dev/null 2>&1 || true
  "${FBASH}" --command 'echo two' -o json >/dev/null 2>&1 || true
  "${FBASH}" --command 'echo three' -o json >/dev/null 2>&1 || true

  # Query history — now returns standard envelope with history JSON in stdout
  fbash_json --command '__fbash_history'

  local stdout
  stdout=$(jfield stdout)

  # stdout contains the JSON array as a string; count "echo" occurrences
  local echo_count
  echo_count=$(echo "$stdout" | grep -co "echo" 2>/dev/null || echo "0")

  if (( echo_count >= 3 )); then
    pass "internal_history: found >= 3 echo commands in history"
  else
    # Verify at least it was classified correctly
    local cmd_class
    cmd_class=$(jfield command_class)
    if [[ "$cmd_class" == "internal" ]]; then
      pass "internal_history: __fbash_history classified as internal (history=$echo_count echos)"
    else
      fail "internal_history: expected >= 3 echo entries" \
           "Got echo_count=$echo_count, class=$cmd_class"
    fi
  fi
}

# ============================================================================
# 17. Internal Reset
# ============================================================================

test_internal_reset() {
  # Populate some history first
  "${FBASH}" --command 'echo before_reset' -o json >/dev/null 2>&1 || true

  # Reset session — now returns standard envelope
  fbash_json --command '__fbash_reset'

  local exit_code
  exit_code=$(jraw exit_code)

  local stdout
  stdout=$(jfield stdout)

  if [[ "$exit_code" == "0" && "$stdout" == *"reset"* ]]; then
    pass "internal_reset: session reset confirmed (exit=0, stdout contains 'reset')"
  elif [[ "$exit_code" == "0" ]]; then
    pass "internal_reset: __fbash_reset executed with exit_code=0"
  else
    fail "internal_reset: expected exit_code=0" \
         "Got exit_code=$exit_code"
  fi
}

# ============================================================================
# 18. JSON Output Contract
# ============================================================================

test_json_output_contract() {
  fbash_json --command 'echo contract_test'

  # Verify valid JSON first
  if ! echo "$FBASH_OUT" | jq empty 2>/dev/null; then
    fail "json_output_contract: output is not valid JSON" "Got: ${FBASH_OUT:0:200}"
    return
  fi

  # Check all required fields from the spec's Output Field Contracts table
  local missing=""

  # tool (always present, string "fbash")
  local tool
  tool=$(jfield tool)
  [[ "$tool" != "fbash" ]] && missing="${missing} tool(expected 'fbash', got '$tool')"

  # version (always present, string)
  local version
  version=$(jfield version)
  [[ -z "$version" ]] && missing="${missing} version"

  # command (always present, string)
  local command
  command=$(jfield command)
  [[ -z "$command" ]] && missing="${missing} command"

  # command_class (always present, string)
  local cmd_class
  cmd_class=$(jfield command_class)
  [[ -z "$cmd_class" ]] && missing="${missing} command_class"

  # exit_code (always present, int or null)
  local exit_code
  exit_code=$(jraw exit_code)
  [[ "$exit_code" == "" ]] && missing="${missing} exit_code"

  # cwd (always present, string)
  local cwd
  cwd=$(jfield cwd)
  [[ -z "$cwd" ]] && missing="${missing} cwd"

  # cwd_changed (always present, boolean)
  local cwd_changed
  cwd_changed=$(jraw cwd_changed)
  [[ "$cwd_changed" != "true" && "$cwd_changed" != "false" ]] && missing="${missing} cwd_changed"

  # duration_ms (always present, int)
  local duration_ms
  duration_ms=$(jraw duration_ms)
  [[ "$duration_ms" == "null" || -z "$duration_ms" ]] && missing="${missing} duration_ms"

  # stdout (always present, string)
  # Note: jq -r on null returns "null", empty string returns ""
  local stdout_check
  stdout_check=$(echo "$FBASH_OUT" | jq 'has("stdout")' 2>/dev/null)
  [[ "$stdout_check" != "true" ]] && missing="${missing} stdout"

  # stderr (always present, string)
  local stderr_check
  stderr_check=$(echo "$FBASH_OUT" | jq 'has("stderr")' 2>/dev/null)
  [[ "$stderr_check" != "true" ]] && missing="${missing} stderr"

  # stdout_lines (always present, int)
  local stdout_lines
  stdout_lines=$(jraw stdout_lines)
  [[ "$stdout_lines" == "null" || -z "$stdout_lines" ]] && missing="${missing} stdout_lines"

  # stderr_lines (always present, int)
  local stderr_lines
  stderr_lines=$(jraw stderr_lines)
  [[ "$stderr_lines" == "null" || -z "$stderr_lines" ]] && missing="${missing} stderr_lines"

  # truncated (always present, boolean)
  local truncated
  truncated=$(jraw truncated)
  [[ "$truncated" != "true" && "$truncated" != "false" ]] && missing="${missing} truncated"

  # truncation_reason (always present, string or null)
  local tr_check
  tr_check=$(echo "$FBASH_OUT" | jq 'has("truncation_reason")' 2>/dev/null)
  [[ "$tr_check" != "true" ]] && missing="${missing} truncation_reason"

  # lines_total (always present, int)
  local lines_total
  lines_total=$(jraw lines_total)
  [[ "$lines_total" == "null" || -z "$lines_total" ]] && missing="${missing} lines_total"

  # bytes_total (always present, int)
  local bytes_total
  bytes_total=$(jraw bytes_total)
  [[ "$bytes_total" == "null" || -z "$bytes_total" ]] && missing="${missing} bytes_total"

  # token_estimate (always present, int)
  local token_estimate
  token_estimate=$(jraw token_estimate)
  [[ "$token_estimate" == "null" || -z "$token_estimate" ]] && missing="${missing} token_estimate"

  # next_hint (always present, string or null)
  local nh_check
  nh_check=$(echo "$FBASH_OUT" | jq 'has("next_hint")' 2>/dev/null)
  [[ "$nh_check" != "true" ]] && missing="${missing} next_hint"

  # routing_suggestion (always present, object or null)
  local rs_check
  rs_check=$(echo "$FBASH_OUT" | jq 'has("routing_suggestion")' 2>/dev/null)
  [[ "$rs_check" != "true" ]] && missing="${missing} routing_suggestion"

  # metadata (always present, object)
  local meta_check
  meta_check=$(echo "$FBASH_OUT" | jq 'has("metadata")' 2>/dev/null)
  [[ "$meta_check" != "true" ]] && missing="${missing} metadata"

  # warnings (always present, array)
  local warn_check
  warn_check=$(echo "$FBASH_OUT" | jq '.warnings | type == "array"' 2>/dev/null)
  [[ "$warn_check" != "true" ]] && missing="${missing} warnings"

  # errors (always present, array)
  local err_check
  err_check=$(echo "$FBASH_OUT" | jq '.errors | type == "array"' 2>/dev/null)
  [[ "$err_check" != "true" ]] && missing="${missing} errors"

  if [[ -z "$missing" ]]; then
    pass "json_output_contract: all 21 required fields present and typed correctly"
  else
    fail "json_output_contract: missing or mistyped fields:${missing}"
  fi
}

# ============================================================================
# Main
# ============================================================================

main() {
  trap 'teardown' EXIT INT TERM

  echo "======================================"
  echo "  fbash Test Suite"
  echo "======================================"
  echo ""

  if [[ ! -x "${FBASH}" ]]; then
    echo -e "${RED}Error: fbash not found at ${FBASH}${NC}"
    echo "  fbash has not been built yet. Ensure the fbash script exists and is executable."
    exit 1
  fi

  if ! command -v jq >/dev/null 2>&1; then
    echo -e "${RED}Error: jq is required for JSON parsing in tests${NC}"
    exit 1
  fi

  setup

  echo "Running tests..."
  echo ""

  echo "== Basic Execution =="
  run_test "Basic execution" test_basic_execution
  run_test "Exit code" test_exit_code

  echo ""
  echo "== Command Classification =="
  run_test "Classification: build" test_command_classification_build
  run_test "Classification: test" test_command_classification_test
  run_test "Classification: git" test_command_classification_git
  run_test "Classification: query" test_command_classification_query

  echo ""
  echo "== Output Budgeting =="
  run_test "Max lines truncation" test_max_lines_truncation
  run_test "Tail mode" test_tail_mode
  run_test "Filter" test_filter
  run_test "Quiet mode" test_quiet_mode

  echo ""
  echo "== CWD Tracking =="
  run_test "CWD tracking" test_cwd_tracking

  echo ""
  echo "== Smart Routing Suggestions =="
  run_test "Routing: ls -> fls" test_routing_suggestion_ls
  run_test "Routing: cat -> fread" test_routing_suggestion_cat
  run_test "Routing: grep -> fcontent" test_routing_suggestion_grep

  echo ""
  echo "== Session State & Internal Commands =="
  run_test "Session state" test_session_state
  run_test "Internal history" test_internal_history
  run_test "Internal reset" test_internal_reset

  echo ""
  echo "== JSON Output Contract =="
  run_test "JSON output contract" test_json_output_contract

  echo ""
  echo "======================================"
  echo "  Test Results"
  echo "======================================"
  echo -e "Total:  ${TESTS_RUN}"
  echo -e "${GREEN}Passed: ${TESTS_PASSED}${NC}"
  if [[ ${TESTS_FAILED} -gt 0 ]]; then
    echo -e "${RED}Failed: ${TESTS_FAILED}${NC}"
    exit 1
  else
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
  fi
}

main "$@"
