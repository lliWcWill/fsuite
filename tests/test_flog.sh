#!/usr/bin/env bash
# test_flog.sh — tests for flog bug fixes (1.3.0)
# Run with: bash test_flog.sh
#
# Each bug gets its own small, focused fixture. No shared mega-fixture.
# Sr dev review: "do not narrow scope. rewrite as small per-bug fixtures."
#
# Bug list:
#   1. Binary-unsafe grep: all grep paths missing -a/--text flag
#   2. json_escape() missing \r and control chars, breaks JSON
#   3. Numeric search patterns impossible (positional parser eats numbers)
#   4. errors leaks excluded warnings (config_handler filter order)
#   5. search false positives on substrings (FAIL matches failure_alert)
#   6. snapshot under-returns on sparse logs (fixed lookback window)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLOG="${SCRIPT_DIR}/../flog"
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() {
  TESTS_PASSED=$((TESTS_PASSED + 1))
  echo -e "${GREEN}✓${NC} $1"
}

fail() {
  TESTS_FAILED=$((TESTS_FAILED + 1))
  echo -e "${RED}✗${NC} $1"
  if [[ -n "${2:-}" ]]; then
    echo "  Details: $2"
  fi
}

run_test() {
  TESTS_RUN=$((TESTS_RUN + 1))
  shift
  "$@" || true
}

# Helper: create a temp file, caller must rm it
mkfixture() { mktemp /tmp/flog_test_XXXXXX; }

wait_for_output_match() {
  local file="$1"
  local pattern="$2"
  local attempts="${3:-20}"
  local i=0

  while (( i < attempts )); do
    if grep -q -- "$pattern" "$file" 2>/dev/null; then
      return 0
    fi
    sleep 0.1
    i=$((i + 1))
  done

  return 1
}

# ============================================================================
# Sanity (should always pass)
# ============================================================================

test_version() {
  local output
  output=$("$FLOG" --version 2>&1)
  if [[ "$output" =~ ^flog\ [0-9]+\.[0-9]+\.[0-9]+ ]]; then
    pass "Version output format correct: $output"
  else
    fail "Version output incorrect" "Got: $output"
  fi
}

test_help() {
  local output
  output=$("$FLOG" --help 2>&1)
  if [[ "$output" =~ USAGE ]] && [[ "$output" =~ flog ]]; then
    pass "Help output displays correctly"
  else
    fail "Help output missing or incorrect"
  fi
}

test_info() {
  local f; f=$(mkfixture)
  echo '2026-03-24 10:00:01,123    INFO: test_framework.mic.MicTest.async Thread-50:MainProcess ->   _analyze   515 - Mic 0: True' > "$f"
  local output
  output=$("$FLOG" info -f "$f" 2>&1) || true
  rm -f "$f"
  if echo "$output" | grep -q "Lines:"; then
    pass "Info command works"
  else
    fail "Info command failed" "Got: ${output:0:200}"
  fi
}

# ============================================================================
# Bug 1: Binary-unsafe grep
# A leading NUL byte makes grep treat file as binary.
# search should still return matches, tower should still find status.
# ============================================================================

test_bug1_search_with_nul() {
  local f; f=$(mkfixture)
  # NUL byte first, then a real matchable line
  printf '\x00\n' > "$f"
  echo '2026-03-24 10:00:01,123    FAIL: test_framework.mic.MicTest Thread-50:MainProcess ->   _run_test   200 - Test failed: mic_front' >> "$f"
  local output
  output=$("$FLOG" search "FAIL" -f "$f" 2>&1) || true
  rm -f "$f"
  if echo "$output" | grep -q "Binary file"; then
    fail "Bug1: search prints 'Binary file matches' with NUL byte"
  elif echo "$output" | grep -q "Test failed"; then
    pass "Bug1: search finds matches despite NUL byte"
  else
    fail "Bug1: search returned no matches with NUL byte" "Got: ${output:0:200}"
  fi
}

test_bug1_tower_with_nul() {
  local f; f=$(mkfixture)
  printf '\x00\n' > "$f"
  echo "2026-03-24 10:00:01,123    DEBUG: test_framework.radi_status_plugin Thread-55:MainProcess ->   _monitor_thread   200 - Light status: {'light_tower': 'yellow', 'sequencer_state': <LightState.YELLOW: 2>}" >> "$f"
  local output
  output=$("$FLOG" tower -f "$f" 2>&1) || true
  rm -f "$f"
  if echo "$output" | grep -q "Binary file"; then
    fail "Bug1: tower leaks 'Binary file matches'" "Got: $output"
  elif echo "$output" | grep -qi "yellow"; then
    pass "Bug1: tower finds status despite NUL byte"
  else
    fail "Bug1: tower degraded to NO_DATA with NUL byte" "Got: $output"
  fi
}

test_bug1_snapshot_with_nul() {
  local f; f=$(mkfixture)
  printf '\x00\n' > "$f"
  echo '2026-03-24 10:00:01,123    INFO: test_framework.mic.MicTest.async Thread-50:MainProcess ->   _analyze   515 - Mic 0: True' >> "$f"
  local output
  output=$("$FLOG" snapshot 5 -f "$f" 2>&1) || true
  rm -f "$f"
  if echo "$output" | grep -q "Binary file"; then
    fail "Bug1: snapshot prints 'Binary file matches' with NUL byte"
  elif echo "$output" | grep -q "Mic 0"; then
    pass "Bug1: snapshot works despite NUL byte"
  else
    fail "Bug1: snapshot returned empty with NUL byte" "Got: ${output:0:200}"
  fi
}

test_bug1_errors_with_nul() {
  local f; f=$(mkfixture)
  printf '\x00\n' > "$f"
  echo '2026-03-24 10:00:01,123    ERROR: test_framework.grading Thread-52:MainProcess ->   postprocess   300 - Could not grade' >> "$f"
  local output
  output=$("$FLOG" errors 5 -f "$f" 2>&1) || true
  rm -f "$f"
  if echo "$output" | grep -q "Binary file"; then
    fail "Bug1: errors prints 'Binary file matches' with NUL byte"
  elif echo "$output" | grep -q "Could not grade"; then
    pass "Bug1: errors works despite NUL byte"
  else
    fail "Bug1: errors returned empty with NUL byte" "Got: ${output:0:200}"
  fi
}

# ============================================================================
# Bug 2: json_escape() missing \r and control chars
# A log line with \r or 0x01 breaks strict JSON parsers.
# Fixture must put the bad line where snapshot will reach it (at the end).
# ============================================================================

test_bug2_json_with_cr() {
  local f; f=$(mkfixture)
  # The CR-containing line IS the only matchable line, so snapshot will hit it
  printf '2026-03-24 10:00:01,123    ERROR: test_framework.display Thread-54:MainProcess ->   _check   400 - Display failed\r\n' > "$f"
  local output
  output=$("$FLOG" snapshot 5 -f "$f" -o json 2>&1) || true
  rm -f "$f"
  if [[ -z "$output" ]]; then
    fail "Bug2: JSON snapshot returned empty (script died)"
    return
  fi
  if echo "$output" | python3 -c "import sys,json; json.loads(sys.stdin.read())" 2>/dev/null; then
    pass "Bug2: JSON with CR-containing line is valid"
  else
    fail "Bug2: JSON with CR-containing line breaks json.loads()"
  fi
}

test_bug2_json_with_control_char() {
  local f; f=$(mkfixture)
  # 0x01 (SOH) control character in the message
  printf '2026-03-24 10:00:01,123    ERROR: test_framework.display Thread-54:MainProcess ->   _check   400 - Display \x01 broken\n' > "$f"
  local output
  output=$("$FLOG" snapshot 5 -f "$f" -o json 2>&1) || true
  rm -f "$f"
  if [[ -z "$output" ]]; then
    fail "Bug2: JSON snapshot returned empty (script died)"
    return
  fi
  if echo "$output" | python3 -c "import sys,json; json.loads(sys.stdin.read())" 2>/dev/null; then
    pass "Bug2: JSON with 0x01 control char is valid"
  else
    fail "Bug2: JSON with 0x01 control char breaks json.loads()"
  fi
}

# ============================================================================
# Bug 3: Numeric search patterns impossible
# flog search "404" treats 404 as LINES, not as search pattern.
# ============================================================================

test_bug3_numeric_search_pattern() {
  local f; f=$(mkfixture)
  echo '2026-03-24 10:00:01,123    ERROR: test_framework.http Thread-60:MainProcess ->   _request   500 - HTTP 404 Not Found' > "$f"
  local output rc=0
  output=$("$FLOG" search "404" -f "$f" 2>&1) || rc=$?
  rm -f "$f"
  if [[ $rc -ne 0 ]] && echo "$output" | grep -q "requires a pattern"; then
    fail "Bug3: 'flog search 404' says pattern required (numeric eaten as LINES)"
  elif echo "$output" | grep -q "404"; then
    pass "Bug3: numeric search pattern '404' works"
  else
    fail "Bug3: 'flog search 404' unexpected result" "rc=$rc output: ${output:0:200}"
  fi
}

test_bug3_numeric_search_zero() {
  local f; f=$(mkfixture)
  echo '2026-03-24 10:00:01,123    ERROR: test_framework.exit Thread-60:MainProcess ->   _exit   100 - Exit code 0' > "$f"
  local output rc=0
  output=$("$FLOG" search "0" -f "$f" 2>&1) || rc=$?
  rm -f "$f"
  if [[ $rc -ne 0 ]] && echo "$output" | grep -q "requires a pattern"; then
    fail "Bug3: 'flog search 0' says pattern required"
  elif echo "$output" | grep -q "Exit code"; then
    pass "Bug3: single digit search pattern '0' works"
  else
    fail "Bug3: 'flog search 0' unexpected result" "rc=$rc output: ${output:0:200}"
  fi
}

# ============================================================================
# Bug 4: errors leaks excluded warnings (config_handler)
# The WARNING: keyword in INCLUDE catches config_handler lines before
# EXCLUDE strips them. The leaked line also arrives uncleaned.
# ============================================================================

test_bug4_errors_excludes_config_handler() {
  local f; f=$(mkfixture)
  # Real error first, then config_handler noise
  cat > "$f" << 'EOF'
2026-03-24 10:00:01,123    ERROR: test_framework.grading Thread-52:MainProcess ->   postprocess   300 - Could not grade
2026-03-24 10:00:02,456 WARNING:       config_handler Thread-62:MainProcess ->          read_config    69 - No configuration found, returning empty dict
EOF
  local output
  output=$("$FLOG" errors 10 -f "$f" 2>&1) || true
  rm -f "$f"
  if echo "$output" | grep -q "config_handler"; then
    fail "Bug4: errors shows config_handler lines (should be excluded)"
  else
    pass "Bug4: errors correctly excludes config_handler"
  fi
}

test_bug4_errors_lines_cleaned() {
  local f; f=$(mkfixture)
  cat > "$f" << 'EOF'
2026-03-24 10:00:01,123    ERROR: test_framework.grading Thread-52:MainProcess ->   postprocess   300 - Could not grade
2026-03-24 10:00:02,456 WARNING:       config_handler Thread-62:MainProcess ->          read_config    69 - No configuration found, returning empty dict
EOF
  local output
  output=$("$FLOG" errors 10 -f "$f" 2>&1) || true
  rm -f "$f"
  # Check for uncleaned raw format leaking through
  if echo "$output" | grep -v "^===" | grep -q "MainProcess ->"; then
    fail "Bug4: errors has uncleaned raw lines" "Found 'MainProcess ->' in output"
  else
    pass "Bug4: all error lines are cleaned"
  fi
}

# ============================================================================
# Bug 5: search false positives (FAIL matches failure_alert)
# search uses unrestricted regex, so FAIL matches inside field names.
# ============================================================================

test_bug5_search_no_tower_noise() {
  local f; f=$(mkfixture)
  cat > "$f" << 'EOF'
2026-03-24 10:00:01,123    FAIL: test_framework.mic.MicTest Thread-50:MainProcess ->   _run_test   200 - Test failed: mic_front volume too low
2026-03-24 10:00:02,456    DEBUG: test_framework.radi_status_plugin Thread-55:MainProcess ->   _monitor_thread   200 - Light status: {'sequencer_state': <LightState.YELLOW: 2>, 'failure_alert': <LightState.GREEN: 3>}
EOF
  local output
  output=$("$FLOG" search "FAIL" -f "$f" -n 20 2>&1) || true
  rm -f "$f"
  if echo "$output" | grep -q "failure_alert"; then
    fail "Bug5: search 'FAIL' returns failure_alert tower noise"
  else
    pass "Bug5: search 'FAIL' excludes tower debug noise"
  fi
}

test_bug5_search_finds_real_failures() {
  local f; f=$(mkfixture)
  cat > "$f" << 'EOF'
2026-03-24 10:00:01,123    FAIL: test_framework.mic.MicTest Thread-50:MainProcess ->   _run_test   200 - Test failed: mic_front volume too low
2026-03-24 10:00:02,456    DEBUG: test_framework.radi_status_plugin Thread-55:MainProcess ->   _monitor_thread   200 - Light status: {'sequencer_state': <LightState.YELLOW: 2>, 'failure_alert': <LightState.GREEN: 3>}
EOF
  local output
  output=$("$FLOG" search "FAIL" -f "$f" -n 20 2>&1) || true
  rm -f "$f"
  if echo "$output" | grep -q "Test failed"; then
    pass "Bug5: search 'FAIL' finds real test failures"
  else
    fail "Bug5: search 'FAIL' missed real failure lines"
  fi
}

# ============================================================================
# Bug 6: snapshot under-returns on sparse logs
# Relevant lines BEFORE 2000 excluded noise lines. snapshot only scans
# max(1000, LINES*10) raw lines back, so it misses the real content.
# ============================================================================

test_bug6_snapshot_sparse_log() {
  local f; f=$(mkfixture)
  # 50 real test lines FIRST
  for i in $(seq 1 50); do
    echo "2026-03-24 10:00:${i},000    INFO: test_framework.mic.MicTest.async Thread-50:MainProcess ->   _analyze   515 - Sparse line $i" >> "$f"
  done
  # Then 2000 excluded noise lines AFTER (this is what snapshot's tail will see)
  for i in $(seq 1 2000); do
    echo "2026-03-24 10:01:${i},000    DEBUG: cherrypy.access CP Server Thread-10:MainProcess ->   run   300 - 127.0.0.1 GET /api/heartbeat" >> "$f"
  done
  local output count
  output=$("$FLOG" snapshot 50 -f "$f" -o slim 2>&1) || true
  rm -f "$f"
  # Count actual content lines (not headers or empty lines)
  count=$(echo "$output" | grep -c "Sparse line" 2>/dev/null) || count=0
  if (( count >= 40 )); then
    pass "Bug6: snapshot 50 returned $count lines from sparse log"
  else
    fail "Bug6: snapshot 50 only returned $count lines (under-return)" "Expected ~50, got $count"
  fi
}

# ============================================================================
# Gap 1: tail binary-unsafe (sr dev review round 2)
# cmd_tail's grep --line-buffered calls missing -a flag. NUL bytes in
# socket_logger cause "Binary file matches" in the live tail stream.
# ============================================================================

test_gap1_tail_binary_unsafe() {
  # tail -f blocks forever, making behavioral testing unreliable with timeout.
  # Hybrid approach: prove grep -a --line-buffered works on NUL pipes (behavioral)
  # + verify all cmd_tail greps are patched (code inspection).
  local f; f=$(mkfixture)
  printf '\x00\n' > "$f"
  echo "2026-03-24 10:00:01,123    DEBUG: test_framework.plugin Thread-1:MainProcess ->   func   10 - Tail test line" >> "$f"
  local pipe_output
  pipe_output=$(cat "$f" | grep -a --line-buffered -E "test_framework" 2>&1) || true
  rm -f "$f"

  # Code verification: every grep --line-buffered in cmd_tail must have -a
  # If cmd_tail is renamed or split up, update this range probe with the new seam.
  local missing
  missing=$(sed -n '/^cmd_tail/,/^}/p' "$FLOG" | grep "grep.*--line-buffered" | grep -cv "\-a" 2>/dev/null) || missing=0

  if echo "$pipe_output" | grep -q "Tail test line" && (( missing == 0 )); then
    pass "Gap1: tail safe (grep -a handles NUL, all 8 calls patched)"
  elif (( missing > 0 )); then
    fail "Gap1: $missing tail grep calls missing -a flag"
  else
    fail "Gap1: grep -a --line-buffered failed on NUL input" "Got: ${pipe_output:0:200}"
  fi
}

# ============================================================================
# Gap 2: light_tower_plugin tower path broken (sr dev review round 2)
# INCLUDE targets light_tower_plugin.*LightState, but cmd_tower extraction
# requires sequencer_state in the line. NPI RADis emit LightState.X directly.
# ============================================================================

test_gap2_tower_light_tower_plugin() {
  local f; f=$(mkfixture)
  # NPI format: light_tower_plugin with LightState.X but NO sequencer_state
  echo "2026-03-24 10:00:01,123    DEBUG: test_framework.light_tower_plugin Thread-56:MainProcess ->   _update   100 - LightState.YELLOW" > "$f"
  local output
  output=$("$FLOG" tower -f "$f" 2>&1) || true
  rm -f "$f"
  if echo "$output" | grep -qi "yellow"; then
    pass "Gap2: tower extracts from light_tower_plugin LightState.X format"
  else
    fail "Gap2: tower NO_DATA for light_tower_plugin LightState.X" "Got: $output"
  fi
}

# ============================================================================
# Gap 3: search word-boundary (sr dev review round 2)
# search uses plain grep -ai, so FAIL matches failure_alert substring.
# _monitor_thread EXCLUDE only blocks one emitter. Need structural fix.
# Test uses _check_status (NOT in EXCLUDE) to verify word-boundary behavior.
# ============================================================================

test_gap3_search_word_boundary() {
  local f; f=$(mkfixture)
  cat > "$f" << 'EOF'
2026-03-24 10:00:01,123    FAIL: test_framework.mic.MicTest Thread-50:MainProcess ->   _run_test   200 - Test failed: mic_front volume too low
2026-03-24 10:00:02,456    DEBUG: test_framework.radi_status_plugin Thread-55:MainProcess ->   _check_status   200 - {'light_tower': 'green', 'failure_alert': False}
EOF
  local output
  output=$("$FLOG" search "FAIL" -f "$f" -n 20 2>&1) || true
  rm -f "$f"
  if echo "$output" | grep -q "failure_alert"; then
    fail "Gap3: search 'FAIL' matches substring in 'failure_alert'" "Got: ${output:0:300}"
  elif echo "$output" | grep -q "Test failed"; then
    pass "Gap3: search 'FAIL' word-boundary skips 'failure_alert'"
  else
    fail "Gap3: search 'FAIL' found nothing" "Got: ${output:0:300}"
  fi
}

test_gap3_search_real_matches_preserved() {
  local f; f=$(mkfixture)
  cat > "$f" << 'EOF'
2026-03-24 10:00:01,123    FAIL: test_framework.display.BlemishTest Thread-50:MainProcess ->   _run_test   200 - FAIL: display blemish detected
2026-03-24 10:00:02,456    ERROR: test_framework.camera.CameraTest Thread-51:MainProcess ->   _capture   300 - ERROR: camera capture timeout
EOF
  local output
  output=$("$FLOG" search "FAIL" -f "$f" -n 20 2>&1) || true
  rm -f "$f"
  if echo "$output" | grep -q "blemish"; then
    pass "Gap3: search 'FAIL' still finds real FAIL: lines"
  else
    fail "Gap3: word-boundary broke real FAIL: match" "Got: ${output:0:300}"
  fi
}

# ============================================================================
# Gap 4: errors sparse-log blind spot (sr dev review round 2)
# cmd_errors uses max(LINES*20, 2000) lookback, same bug snapshot had.
# 50 errors + 3000 noise = errors 50 returns 0 with old window.
# ============================================================================

test_gap4_errors_sparse_lookback() {
  local f; f=$(mkfixture)
  # 50 real error lines first
  for i in $(seq 1 50); do
    echo "2026-03-24 10:00:$(printf '%02d' $((i%60))),000    ERROR: test_framework.mic.MicTest Thread-50:MainProcess ->   _run_test   200 - Sparse error $i" >> "$f"
  done
  # 3000 noise lines after (pushes errors out of old 2000-line window)
  yes "2026-03-24 10:05:00,123    DEBUG: test_framework.plugin Thread-50:MainProcess ->   func   10 - Noise" | head -n 3000 >> "$f"
  local output count
  output=$("$FLOG" errors 50 -f "$f" -o slim 2>&1) || true
  rm -f "$f"
  count=$(echo "$output" | grep -c "Sparse error" 2>/dev/null) || count=0
  if (( count >= 40 )); then
    pass "Gap4: errors found $count/50 sparse errors through 3000 noise"
  else
    fail "Gap4: errors only found $count/50 (lookback too small)" "Expected >=40, got $count"
  fi
}

# ============================================================================
# Bug 7: info zero-count corruption
# grep -c exits 1 and outputs "0" when no matches. The || echo "0" fallback
# runs INSIDE the command substitution, capturing "0\n0". This corrupts
# pretty output with stray lines and produces invalid JSON.
# ============================================================================

test_bug7_info_zero_pretty() {
  local f; f=$(mkfixture)
  # File with NO errors or fails - both counts should be 0
  echo "2026-03-24 10:00:01,123    DEBUG: test_framework.plugin Thread-1:MainProcess ->   func   10 - Clean line" > "$f"
  local output
  output=$("$FLOG" info -f "$f" 2>&1) || true
  rm -f "$f"
  # Check for stray standalone "0" lines (the symptom of "0\n0" capture)
  local stray_zeros
  stray_zeros=$(echo "$output" | grep -c "^0$" 2>/dev/null) || stray_zeros=0
  if (( stray_zeros > 0 )); then
    fail "Bug7: info pretty has $stray_zeros stray '0' lines" "Got: $output"
  elif echo "$output" | grep -q "Errors:"; then
    pass "Bug7: info pretty clean when counts are zero"
  else
    fail "Bug7: info pretty missing expected fields" "Got: $output"
  fi
}

test_bug7_info_zero_json() {
  local f; f=$(mkfixture)
  echo "2026-03-24 10:00:01,123    DEBUG: test_framework.plugin Thread-1:MainProcess ->   func   10 - Clean line" > "$f"
  local output
  output=$("$FLOG" info -f "$f" -o json 2>&1) || true
  rm -f "$f"
  if [[ -z "$output" ]]; then
    fail "Bug7: info JSON returned empty"
    return
  fi
  if echo "$output" | python3 -c "import sys,json; json.loads(sys.stdin.read())" 2>/dev/null; then
    pass "Bug7: info JSON valid when counts are zero"
  else
    fail "Bug7: info JSON invalid when counts are zero" "Got: $output"
  fi
}

# ============================================================================
# Bug 8: tail cleaned modes stall (sed buffering)
# tail -f | grep -a --line-buffered | sed pipes stall because sed buffers
# output by default. Raw mode (-r) works because it skips the sed cleaners.
# Tests use background flog + delayed append to verify real streaming.
# ============================================================================

test_bug8_tail_pretty_streams() {
  local f; f=$(mkfixture)
  local out; out=$(mktemp)

  # Start flog tail in background, capturing output
  "$FLOG" tail -f "$f" > "$out" 2>&1 &
  local tailpid=$!

  # Append a matching line while tail is watching
  echo "2026-03-24 14:44:01,123    DEBUG: test_framework.radi_status_plugin Thread-6:MainProcess ->   send_request   71 - Pretty stream line" >> "$f"

  local captured
  wait_for_output_match "$out" "Pretty stream line" 20 || true

  kill "$tailpid" 2>/dev/null
  wait "$tailpid" 2>/dev/null || true

  captured=$(cat "$out")
  rm -f "$f" "$out"

  if echo "$captured" | grep -q "Pretty stream line"; then
    pass "Bug8: tail pretty mode streams cleaned lines"
  else
    fail "Bug8: tail pretty mode stalls (sed buffering)" "Got: ${captured:0:300}"
  fi
}

test_bug8_tail_slim_streams() {
  local f; f=$(mkfixture)
  local out; out=$(mktemp)

  "$FLOG" tail -o slim -f "$f" > "$out" 2>&1 &
  local tailpid=$!

  echo "2026-03-24 14:44:01,123    DEBUG: test_framework.radi_status_plugin Thread-6:MainProcess ->   send_request   71 - Slim stream line" >> "$f"

  local captured
  wait_for_output_match "$out" "Slim stream line" 20 || true

  kill "$tailpid" 2>/dev/null
  wait "$tailpid" 2>/dev/null || true

  captured=$(cat "$out")
  rm -f "$f" "$out"

  if echo "$captured" | grep -q "Slim stream line"; then
    pass "Bug8: tail slim mode streams cleaned lines"
  else
    fail "Bug8: tail slim mode stalls (sed buffering)" "Got: ${captured:0:300}"
  fi
}

test_bug8_tail_npi_streams() {
  local f; f=$(mkfixture)
  local out; out=$(mktemp)

  "$FLOG" tail -o npi -f "$f" > "$out" 2>&1 &
  local tailpid=$!

  echo "2026-03-24 14:44:01,123    DEBUG: test_framework.radi_status_plugin Thread-6:MainProcess ->   send_request   71 - NPI stream line" >> "$f"

  local captured
  wait_for_output_match "$out" "NPI stream line" 20 || true

  kill "$tailpid" 2>/dev/null
  wait "$tailpid" 2>/dev/null || true

  captured=$(cat "$out")
  rm -f "$f" "$out"

  if echo "$captured" | grep -q "NPI stream line"; then
    pass "Bug8: tail npi mode streams cleaned lines"
  else
    fail "Bug8: tail npi mode stalls (sed buffering)" "Got: ${captured:0:300}"
  fi
}

# ============================================================================
# Bug 9: missing argument validation for -f/-o/-n
# CodeRabbit: shift 2 on a missing value fails cryptically. These should die with
# a direct message before touching positional parsing.
# ============================================================================

test_bug9_missing_file_argument() {
  local output rc=0
  output=$("$FLOG" -f 2>&1) || rc=$?
  if [[ $rc -ne 0 ]] && echo "$output" | grep -q "Missing argument for -f"; then
    pass "Bug9: -f without a value gives a helpful error"
  else
    fail "Bug9: -f without a value not handled cleanly" "rc=$rc output: ${output:0:200}"
  fi
}

test_bug9_missing_output_argument() {
  local output rc=0
  output=$("$FLOG" -o 2>&1) || rc=$?
  if [[ $rc -ne 0 ]] && echo "$output" | grep -q "Missing argument for -o"; then
    pass "Bug9: -o without a value gives a helpful error"
  else
    fail "Bug9: -o without a value not handled cleanly" "rc=$rc output: ${output:0:200}"
  fi
}

test_bug9_missing_lines_argument() {
  local output rc=0
  output=$("$FLOG" -n 2>&1) || rc=$?
  if [[ $rc -ne 0 ]] && echo "$output" | grep -q "Missing argument for -n"; then
    pass "Bug9: -n without a value gives a helpful error"
  else
    fail "Bug9: -n without a value not handled cleanly" "rc=$rc output: ${output:0:200}"
  fi
}

# ============================================================================
# Run all tests
# ============================================================================

main() {
  echo "=== flog test suite ==="
  echo "Testing: $FLOG"
  echo ""

  echo "--- Sanity ---"
  run_test "version" test_version
  run_test "help" test_help
  run_test "info" test_info

  echo ""
  echo "--- Bug 1: Binary-unsafe grep ---"
  run_test "search_nul" test_bug1_search_with_nul
  run_test "tower_nul" test_bug1_tower_with_nul
  run_test "snapshot_nul" test_bug1_snapshot_with_nul
  run_test "errors_nul" test_bug1_errors_with_nul

  echo ""
  echo "--- Bug 2: JSON control chars ---"
  run_test "json_cr" test_bug2_json_with_cr
  run_test "json_ctrl" test_bug2_json_with_control_char

  echo ""
  echo "--- Bug 3: Numeric search pattern ---"
  run_test "search_404" test_bug3_numeric_search_pattern
  run_test "search_0" test_bug3_numeric_search_zero

  echo ""
  echo "--- Bug 4: Errors leaking excluded warnings ---"
  run_test "errors_config" test_bug4_errors_excludes_config_handler
  run_test "errors_clean" test_bug4_errors_lines_cleaned

  echo ""
  echo "--- Bug 5: Search false positives ---"
  run_test "no_tower" test_bug5_search_no_tower_noise
  run_test "real_fail" test_bug5_search_finds_real_failures

  echo ""
  echo "--- Bug 6: Snapshot under-return ---"
  run_test "sparse" test_bug6_snapshot_sparse_log

  echo ""
  echo "--- Gap 1: tail binary-unsafe ---"
  run_test "tail_nul" test_gap1_tail_binary_unsafe

  echo ""
  echo "--- Gap 2: tower light_tower_plugin ---"
  run_test "tower_ltp" test_gap2_tower_light_tower_plugin

  echo ""
  echo "--- Gap 3: search word-boundary ---"
  run_test "word_bound" test_gap3_search_word_boundary
  run_test "word_real" test_gap3_search_real_matches_preserved

  echo ""
  echo "--- Gap 4: errors sparse lookback ---"
  run_test "err_sparse" test_gap4_errors_sparse_lookback

  echo ""
  echo "--- Bug 7: info zero-count ---"
  run_test "info_zero_pretty" test_bug7_info_zero_pretty
  run_test "info_zero_json" test_bug7_info_zero_json

  echo ""
  echo "--- Bug 8: tail cleaned streaming ---"
  run_test "tail_pretty" test_bug8_tail_pretty_streams
  run_test "tail_slim" test_bug8_tail_slim_streams
  run_test "tail_npi" test_bug8_tail_npi_streams

  echo ""
  echo "--- Bug 9: missing flag arguments ---"
  run_test "missing_f" test_bug9_missing_file_argument
  run_test "missing_o" test_bug9_missing_output_argument
  run_test "missing_n" test_bug9_missing_lines_argument

  echo ""
  echo "=== Results: $TESTS_PASSED/$TESTS_RUN passed, $TESTS_FAILED failed ==="
  if (( TESTS_FAILED > 0 )); then
    exit 1
  fi
}

main
