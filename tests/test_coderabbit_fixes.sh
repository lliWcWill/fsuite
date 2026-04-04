#!/usr/bin/env bash
# test_coderabbit_fixes.sh — Regression tests for CodeRabbit-identified bugs
# Each test is designed to FAIL on pre-fix code, PASS on fixed code.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FSUITE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
FBASH="$FSUITE_DIR/fbash"
FREAD="$FSUITE_DIR/fread"

export FSUITE_TELEMETRY=0

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0
TMPDIR_BASE=""

pass() { echo -e "\033[0;32m✓\033[0m $1"; (( PASS_COUNT++ )) || true; }
fail() { echo -e "\033[0;31m✗\033[0m $1"; [[ -n "${2:-}" ]] && echo "  Details: $2"; (( FAIL_COUNT++ )) || true; }
skip() { echo -e "\033[0;33m⊘\033[0m $1 (skipped)"; (( SKIP_COUNT++ )) || true; }

poll_background_job() {
  local job_id="$1"
  local __outvar="$2"
  local __rcvar="$3"
  local response=""
  local response_rc=""
  local status=""
  local attempt

  printf -v "$__outvar" '%s' ""
  printf -v "$__rcvar" '%s' ""

  for attempt in {1..40}; do
    response=""
    response_rc=0
    response=$("$FBASH" --command "__fbash_poll $job_id" -o json 2>/dev/null) || response_rc=$?
    if [[ -z "$response" ]]; then
      sleep 0.1
      continue
    fi
    status=$(echo "$response" | jq -r '.metadata.background_status // empty')
    if [[ "$status" == "running" || -z "$status" ]]; then
      sleep 0.1
      continue
    fi
    printf -v "$__outvar" '%s' "$response"
    printf -v "$__rcvar" '%s' "$response_rc"
    return 0
  done
  return 1
}

setup() {
  TMPDIR_BASE=$(mktemp -d)
  export FBASH_SESSION_DIR="$TMPDIR_BASE/session"
  mkdir -p "$FBASH_SESSION_DIR"
}

teardown() {
  rm -rf "$TMPDIR_BASE" 2>/dev/null || true
}
trap teardown EXIT

setup

echo "======================================"
echo "  CodeRabbit Fix Regression Tests"
echo "======================================"
echo ""

# ============================================================================
# Bug 1: Process exit code propagation
# OLD: fbash always exited 0 regardless of command failure
# FIX: exit "$EXEC_EXIT_CODE" at end of script
# ============================================================================
echo "== Bug 1: Exit Code Propagation =="

# Test 1a: Non-zero exit code propagates to process
"$FBASH" --command 'exit 42' -o json >/dev/null 2>&1 || rc=$?
rc=${rc:-0}
if [[ "$rc" == "42" ]]; then
  pass "bug1_process_exit: exit 42 propagates (got $rc)"
else
  fail "bug1_process_exit: expected process exit 42" "Got $rc"
fi

# Test 1b: Zero exit code still works
rc=0
"$FBASH" --command 'true' -o json >/dev/null 2>&1 || rc=$?
if [[ "$rc" == "0" ]]; then
  pass "bug1_zero_exit: successful command exits 0"
else
  fail "bug1_zero_exit: expected exit 0" "Got $rc"
fi

# Test 1c: JSON exit_code matches process exit
# Capture full JSON first, then extract — piping from a non-zero exit breaks under set -e
json_raw=""
json_raw=$("$FBASH" --command 'exit 7' -o json 2>/dev/null) || true
json_ec=$(echo "$json_raw" | jq -r '.exit_code' 2>/dev/null || echo "null")
proc_ec=0
"$FBASH" --command 'exit 7' -o json >/dev/null 2>&1 || proc_ec=$?
if [[ "$json_ec" == "7" && "$proc_ec" == "7" ]]; then
  pass "bug1_json_matches_process: JSON exit_code=$json_ec, process=$proc_ec"
else
  fail "bug1_json_matches_process: mismatch" "JSON=$json_ec, process=$proc_ec"
fi

echo ""

# ============================================================================
# Bug 2: cd commands don't double-execute
# OLD: CWD tracking re-ran the entire command to capture pwd
# FIX: Parse cd target from command string, don't re-execute
# ============================================================================
echo "== Bug 2: No Double Execution =="

# Test 2a: Side-effect command with cd runs exactly once
COUNTER_FILE="$TMPDIR_BASE/exec_counter"
echo "0" > "$COUNTER_FILE"
"$FBASH" --command "cd /tmp && expr \$(cat $COUNTER_FILE) + 1 > $COUNTER_FILE" -o json >/dev/null 2>&1 || true
count=$(cat "$COUNTER_FILE" 2>/dev/null || echo "?")
if [[ "$count" == "1" ]]; then
  pass "bug2_single_exec: cd + side-effect ran once (count=$count)"
else
  fail "bug2_single_exec: expected count=1" "Got count=$count (command ran $count times)"
fi

# Test 2b: CWD is tracked after cd
cwd_out=$("$FBASH" --command 'cd /tmp' -o json 2>/dev/null | jq -r '.cwd')
if [[ "$cwd_out" == "/tmp" ]]; then
  pass "bug2_cwd_tracked: cd /tmp tracked correctly"
else
  fail "bug2_cwd_tracked: CWD tracking should update to /tmp" "got: $cwd_out"
fi

# Test 2c: Quoted paths with spaces are tracked after cd
SPACE_DIR="$TMPDIR_BASE/dir with spaces"
mkdir -p "$SPACE_DIR"
cwd_out=$("$FBASH" --command "cd \"$SPACE_DIR\"" -o json 2>/dev/null | jq -r '.cwd')
if [[ "$cwd_out" == "$SPACE_DIR" ]]; then
  pass "bug2_cwd_tracked_spaces: quoted cd path tracked correctly"
else
  fail "bug2_cwd_tracked_spaces: CWD tracking should preserve quoted paths with spaces" "expected: $SPACE_DIR got: $cwd_out"
fi

echo ""

# ============================================================================
# Bug 3: --json flag warns instead of being silent no-op
# OLD: JSON_MODE set but never read
# FIX: Runtime warning added to WARNINGS array
# ============================================================================
echo "== Bug 3: --json Flag Warning =="

json_warnings=$("$FBASH" --command 'echo test' --json -o json 2>/dev/null | jq -r '.warnings[]' 2>/dev/null || echo "")
if echo "$json_warnings" | grep -q "reserved"; then
  pass "bug3_json_warns: --json flag produces 'reserved' warning"
else
  fail "bug3_json_warns: expected warning about --json being reserved" "Got warnings: $json_warnings"
fi

echo ""

# ============================================================================
# Bug 4: Background mode respects --env and --timeout
# OLD: start_background_job() ignored ENV_OVERRIDES and TIMEOUT
# FIX: Build env_prefix and timeout_cmd in background path
# ============================================================================
echo "== Bug 4: Background Respects --env =="

# Test 4a: --env is applied in background mode
bg_out=""
if ! bg_out=$("$FBASH" --command 'echo $FBASH_TEST_VAR' --env 'FBASH_TEST_VAR=rabbit_fix_4' --background -o json 2>/dev/null); then
  fail "bug4_bg_env: background job start command failed"
  bg_out=""
fi
job_id=$(echo "$bg_out" | jq -r '.metadata.background_job_id // empty')

if [[ -n "$job_id" ]]; then
  poll_out=""
  poll_shell_rc=""
  if poll_background_job "$job_id" poll_out poll_shell_rc; then
    bg_stdout=$(echo "$poll_out" | jq -r '.stdout // empty')
    if echo "$bg_stdout" | grep -q "rabbit_fix_4"; then
      pass "bug4_bg_env: background job received FBASH_TEST_VAR=rabbit_fix_4"
    else
      fail "bug4_bg_env: env var not propagated to background" "stdout=$bg_stdout"
    fi
  else
    fail "bug4_bg_env: polling timed out" "job_id=$job_id"
  fi
else
  fail "bug4_bg_env: background job didn't start" "response=$bg_out"
fi

# Test 4b: __fbash_poll preserves the polled job exit code at top level
bg_out=""
if ! bg_out=$("$FBASH" --command 'exit 9' --background -o json 2>/dev/null); then
  fail "bug4_poll_exit_code: background job start command failed"
  bg_out=""
fi
job_id=$(echo "$bg_out" | jq -r '.metadata.background_job_id // empty')

if [[ -n "$job_id" ]]; then
  poll_out=""
  poll_shell_rc=""
  if poll_background_job "$job_id" poll_out poll_shell_rc; then
    poll_exit_code=$(echo "$poll_out" | jq -r '.exit_code')
    poll_stdout=$(echo "$poll_out" | jq -r '.stdout // empty')
    if [[ "$poll_shell_rc" == "9" ]] && [[ "$poll_exit_code" == "9" ]] && [[ "$poll_stdout" != *'"exit_code":9'* ]]; then
      pass "bug4_poll_exit_code: polled exit_code surfaced at top level"
    else
      fail "bug4_poll_exit_code: expected shell rc and top-level exit_code=9 from __fbash_poll" "shell_rc=$poll_shell_rc exit_code=$poll_exit_code stdout=$poll_stdout response=$poll_out"
    fi
  else
    fail "bug4_poll_exit_code: polling timed out" "job_id=$job_id"
  fi
else
  fail "bug4_poll_exit_code: background job didn't start" "response=$bg_out"
fi

echo ""

# ============================================================================
# Bug 5: fread --paths skips directories, finds files
# OLD: Used -e (exists) which matched directories
# FIX: Use -f (regular file) for non-symbol mode
# ============================================================================
echo "== Bug 5: --paths Skips Directories =="

# Test 5a: Directory is skipped, file after it is found
resolved=$("$FREAD" --paths "/tmp,/etc/hostname" -o json 2>/dev/null | jq -r '.resolved_path // empty')
if [[ "$resolved" == "/etc/hostname" ]]; then
  pass "bug5_skip_dir: /tmp (dir) skipped, /etc/hostname (file) resolved"
else
  fail "bug5_skip_dir: expected /etc/hostname" "Got resolved=$resolved"
fi

# Test 5b: First regular file wins
resolved2=$("$FREAD" --paths "/etc/hostname,/etc/hosts" -o json 2>/dev/null | jq -r '.resolved_path // empty')
if [[ "$resolved2" == "/etc/hostname" ]]; then
  pass "bug5_first_file_wins: first regular file /etc/hostname selected"
else
  fail "bug5_first_file_wins: expected /etc/hostname" "Got resolved=$resolved2"
fi

# Test 5c: All directories = error
err_out=""
err_rc=0
err_out=$("$FREAD" --paths "/tmp,/var,/usr" -o json 2>&1) || err_rc=$?
err_errors=$(printf '%s' "$err_out" | jq -r '.errors | length' 2>/dev/null || echo 0)
err_code=$(printf '%s' "$err_out" | jq -r '.errors[0].error_code // empty' 2>/dev/null)
if (( err_rc != 0 )) && [[ "$err_errors" =~ ^[0-9]+$ ]] && (( err_errors > 0 )) && [[ -n "$err_code" ]]; then
  pass "bug5_all_dirs_error: all directories correctly returns structured errors"
else
  fail "bug5_all_dirs_error: expected structured error for all-directory paths" "rc=$err_rc errors=$err_errors error_code=$err_code out=$err_out"
fi

# Test 5d: Symbol mode accepts file candidates in --paths
symbol_tmp=$(mktemp -d)
cat > "$symbol_tmp/symbol.ts" <<'EOF'
function foo() {
  return 42;
}
EOF
symbol_out=$("$FREAD" --paths "$symbol_tmp/symbol.ts" --symbol foo -o json 2>/dev/null || true)
symbol_name=$(printf '%s' "$symbol_out" | jq -r '.symbol_resolution.symbol // empty')
symbol_path=$(printf '%s' "$symbol_out" | jq -r '.symbol_resolution.path // empty')
if [[ "$symbol_name" == "foo" ]] && [[ "$symbol_path" == "$symbol_tmp/symbol.ts" ]]; then
  pass "bug5_symbol_file_paths: symbol mode resolves file candidates from --paths"
else
  fail "bug5_symbol_file_paths: expected file candidate to resolve symbol" "out=$symbol_out"
fi
rm -rf "$symbol_tmp"

# Test 5e: No-match short-circuits without extra dispatch errors
no_match_out=""
no_match_rc=0
no_match_out=$("$FREAD" --paths "/definitely/missing-one,/definitely/missing-two" --symbol whatever -o json 2>&1) || no_match_rc=$?
no_match_errors=$(printf '%s' "$no_match_out" | jq -r '.errors | length' 2>/dev/null || echo 0)
no_match_code=$(printf '%s' "$no_match_out" | jq -r '.errors[0].error_code // empty' 2>/dev/null)
second_code=$(printf '%s' "$no_match_out" | jq -r '.errors[1].error_code // empty' 2>/dev/null)
if (( no_match_rc != 0 )) && [[ "$no_match_errors" == "1" ]] && [[ "$no_match_code" == "no_match" ]] && [[ -z "$second_code" ]]; then
  pass "bug5_no_match_short_circuit: unresolved --paths stops before symbol dispatch"
else
  fail "bug5_no_match_short_circuit: expected only no_match error" "rc=$no_match_rc out=$no_match_out"
fi

echo ""

# ============================================================================
# Summary
# ============================================================================
echo "======================================"
echo "  Results"
echo "======================================"
echo "Total:  $(( PASS_COUNT + FAIL_COUNT + SKIP_COUNT ))"
echo -e "\033[0;32mPassed: $PASS_COUNT\033[0m"
[[ $FAIL_COUNT -gt 0 ]] && echo -e "\033[0;31mFailed: $FAIL_COUNT\033[0m"
[[ $SKIP_COUNT -gt 0 ]] && echo -e "\033[0;33mSkipped: $SKIP_COUNT\033[0m"
[[ $FAIL_COUNT -eq 0 ]] && echo -e "\033[0;32mAll tests passed!\033[0m"
exit $FAIL_COUNT
