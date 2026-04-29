#!/usr/bin/env bash
# test_fread.sh — comprehensive tests for fread
# Run with: bash test_fread.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FREAD="${SCRIPT_DIR}/../fread"
FSEARCH="${SCRIPT_DIR}/../fsearch"
TEST_DIR=""
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

setup() {
  TEST_DIR="$(mktemp -d)"

  # Multi-line text file
  for i in $(seq 1 50); do
    echo "Line $i: this is content for testing fread line range functionality" >> "${TEST_DIR}/sample.txt"
  done

  # Larger line-count fixture for default uncapped reads
  for i in $(seq 1 260); do
    echo "Large line $i: no truncate regression fixture" >> "${TEST_DIR}/large.txt"
  done

  # Larger byte-count fixture that would exceed the old 50 KB default cap
  local huge_payload
  huge_payload=$(printf '%240s' '' | tr ' ' 'x')
  for i in $(seq 1 260); do
    echo "Huge line $i: ${huge_payload}" >> "${TEST_DIR}/huge.txt"
  done

  # Python file with functions
  cat > "${TEST_DIR}/auth.py" <<'PYEOF'
import os
import sys

def authenticate(user, password):
    """Verify credentials against the database."""
    if not user or not password:
        return False
    return check_db(user, password)

def check_db(user, password):
    """Database lookup."""
    return True

class AuthHandler:
    def __init__(self):
        self.sessions = {}

    def login(self, user, password):
        return authenticate(user, password)

# TODO: add logout method
PYEOF

  # Short file
  echo "only one line" > "${TEST_DIR}/short.txt"

  # Empty file
  touch "${TEST_DIR}/empty.txt"

# Non-media binary file (raw NUL bytes, no media magic header).
# Phase 2 added media dispatch ahead of binary-skip; this fixture deliberately
# uses NUL bytes with no PNG/PDF/JPEG magic so it still hits the skipped_binary
# path rather than the media engine.
printf '\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00' > "${TEST_DIR}/image.png"

  # File with special chars in name
  echo "special content" > "${TEST_DIR}/file with spaces.txt"

  # File with tabs and special content
  printf 'line1\ttabbed\nline2\t"quoted"\nline3\tback\\slash\n' > "${TEST_DIR}/special_chars.txt"

  # Nested structure for stdin tests
  mkdir -p "${TEST_DIR}/src"
  echo "def foo(): pass" > "${TEST_DIR}/src/foo.py"
  echo "def bar(): pass" > "${TEST_DIR}/src/bar.py"
  echo "class Baz: pass" > "${TEST_DIR}/src/baz.py"

  # Symbol-resolution fixtures
  mkdir -p "${TEST_DIR}/symbols"
  cat > "${TEST_DIR}/symbols/one.py" <<'PYEOF'
def duplicate():
    value = 1
    return value

def unique_dir_symbol():
    return duplicate()
PYEOF

  cat > "${TEST_DIR}/symbols/two.py" <<'PYEOF'
def duplicate():
    return 2
PYEOF

  cat > "${TEST_DIR}/symbols/server.go" <<'GOEOF'
package main

import "fmt"

type Server struct{}

func (s *Server) Start() {
    fmt.Println("started")
}
GOEOF

  # File for around-pattern tests
  cat > "${TEST_DIR}/search_target.txt" <<'EOF'
header line 1
header line 2
header line 3
MARKER_ALPHA content here
middle line 5
middle line 6
MARKER_BETA second marker
footer line 8
footer line 9
footer line 10
EOF

  # Git diff fixture
  cat > "${TEST_DIR}/sample.diff" <<'DIFFEOF'
diff --git a/src/auth.py b/src/auth.py
index abc1234..def5678 100644
--- a/src/auth.py
+++ b/src/auth.py
@@ -3,6 +3,8 @@ import sys
 def authenticate(user, password):
     """Verify credentials against the database."""
+    if not user:
+        raise ValueError("user required")
     if not user or not password:
         return False
     return check_db(user, password)
DIFFEOF

  # Diff with deleted file
  cat > "${TEST_DIR}/delete.diff" <<'DIFFEOF'
diff --git a/old_file.py b/old_file.py
deleted file mode 100644
--- a/old_file.py
+++ /dev/null
@@ -1,3 +0,0 @@
-def old():
-    pass
-
DIFFEOF

  # Diff with binary
  cat > "${TEST_DIR}/binary.diff" <<'DIFFEOF'
diff --git a/image.png b/image.png
Binary files a/image.png and b/image.png differ
DIFFEOF
}

teardown() {
  if [[ -n "${TEST_DIR}" && -d "${TEST_DIR}" ]]; then
    rm -rf "${TEST_DIR}"
  fi
}

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

# ============================================================================
# Basic Functionality Tests
# ============================================================================

test_version() {
  local output
  output=$("${FREAD}" --version 2>&1)
  if [[ "$output" =~ ^fread\ [0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    pass "Version output format is correct"
  else
    fail "Version output format incorrect" "Got: $output"
  fi
}

test_help() {
  local output
  output=$("${FREAD}" --help 2>&1)
  if [[ "$output" == *"fread"* ]] && [[ "$output" == *"--lines"* ]] && [[ "$output" == *"--around"* ]] && [[ "$output" == *"--symbol"* ]]; then
    pass "Help output documents fread and --symbol"
  else
    fail "Help output is missing key sections"
  fi
}

test_self_check() {
  local output
  output=$("${FREAD}" --self-check 2>&1)
  if [[ "$output" == *"sed:"* ]] && [[ "$output" == *"perl:"* ]]; then
    pass "Self-check command works"
  else
    fail "Self-check output missing dependency list" "Got: $output"
  fi
}

test_install_hints() {
  local output
  output=$("${FREAD}" --install-hints 2>&1)
  if [[ "$output" == *"apt"* ]] || [[ "$output" == *"brew"* ]]; then
    pass "Install hints command works"
  else
    fail "Install hints missing package manager guidance"
  fi
}

test_nonexistent_file() {
  local rc=0
  FSUITE_TELEMETRY=0 "${FREAD}" "/nonexistent/path/foo.txt" 2>/dev/null || rc=$?
  if (( rc != 0 )); then
    pass "Correctly errors on nonexistent file"
  else
    fail "Should error on nonexistent file"
  fi
}

test_missing_file_arg() {
  local rc=0
  FSUITE_TELEMETRY=0 "${FREAD}" 2>/dev/null || rc=$?
  if (( rc != 0 )); then
    pass "Correctly errors on missing file argument"
  else
    fail "Should error when no file argument given"
  fi
}

test_invalid_output() {
  local rc=0
  FSUITE_TELEMETRY=0 "${FREAD}" -o xml "${TEST_DIR}/sample.txt" 2>/dev/null || rc=$?
  if (( rc != 0 )); then
    pass "Correctly rejects invalid output format"
  else
    fail "Should reject --output xml"
  fi
}

test_unknown_option() {
  local rc=0
  FSUITE_TELEMETRY=0 "${FREAD}" --foobar "${TEST_DIR}/sample.txt" 2>/dev/null || rc=$?
  if (( rc != 0 )); then
    pass "Correctly rejects unknown option"
  else
    fail "Should reject --foobar"
  fi
}

# ============================================================================
# Single File Read Tests
# ============================================================================

test_read_whole_file() {
  local output
  output=$(FSUITE_TELEMETRY=0 "${FREAD}" "${TEST_DIR}/sample.txt" 2>/dev/null)
  local line_count
  line_count=$(echo "$output" | grep -c "^[0-9]" || true)
  if (( line_count == 50 )); then
    pass "Read whole file (50 lines)"
  else
    fail "Should read all 50 lines" "Got $line_count lines"
  fi
}

test_default_read_is_uncapped() {
  local output tmp_json
  output=$(FSUITE_TELEMETRY=0 "${FREAD}" "${TEST_DIR}/huge.txt" -o json 2>/dev/null)
  tmp_json="$(mktemp)"
  printf '%s\n' "$output" > "$tmp_json"

  if python3 - "$tmp_json" <<'PY' 2>/dev/null
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as fh:
    d = json.load(fh)

assert d["truncated"] is False
assert d["truncation_reason"] == "none"
assert d["max_lines"] == 0
assert d["max_bytes"] == 0
assert d["lines_emitted"] == 260
assert any("Huge line 260:" in line for chunk in d["chunks"] for line in chunk["content"])
PY
  then
    pass "Default read is uncapped for lines and bytes"
  else
    fail "Default fread should not truncate requested content" "Got: $output"
  fi
  rm -f "$tmp_json"
}

test_read_with_max_lines() {
  local output
  output=$(FSUITE_TELEMETRY=0 "${FREAD}" --max-lines 10 "${TEST_DIR}/sample.txt" 2>/dev/null)
  local line_count
  line_count=$(echo "$output" | grep -c "^[0-9]" || true)
  if (( line_count <= 10 )); then
    pass "Max lines limit works"
  else
    fail "Should cap at 10 lines" "Got $line_count"
  fi
}

test_line_numbers_present() {
  local output
  output=$(FSUITE_TELEMETRY=0 "${FREAD}" "${TEST_DIR}/sample.txt" --max-lines 5 2>/dev/null)
  if echo "$output" | grep -qE '^[0-9]+[[:space:]]'; then
    pass "Line numbers present in output"
  else
    fail "Line numbers should be present"
  fi
}

test_empty_file() {
  local rc=0
  local output
  output=$(FSUITE_TELEMETRY=0 "${FREAD}" "${TEST_DIR}/empty.txt" -o json 2>/dev/null) || rc=$?
  if [[ "$output" =~ \"lines_emitted\":0 ]]; then
    pass "Empty file handled gracefully"
  else
    fail "Empty file should produce 0 lines" "Got: $output"
  fi
}

test_short_file() {
  local output
  output=$(FSUITE_TELEMETRY=0 "${FREAD}" "${TEST_DIR}/short.txt" -o json 2>/dev/null)
  if [[ "$output" =~ \"lines_emitted\":1 ]]; then
    pass "Single-line file handled correctly"
  else
    fail "Single-line file should produce 1 line" "Got: $output"
  fi
}

test_binary_file_skipped() {
  local output
  output=$(FSUITE_TELEMETRY=0 "${FREAD}" "${TEST_DIR}/image.png" -o json 2>/dev/null)
  if [[ "$output" =~ \"status\":\"skipped_binary\" ]]; then
    pass "Binary file skipped with status"
  else
    fail "Binary file should be skipped" "Got: $output"
  fi
}

test_force_text_reads_binary() {
  local output
  output=$(FSUITE_TELEMETRY=0 "${FREAD}" "${TEST_DIR}/image.png" --force-text -o json 2>/dev/null)
# NUL-byte binary has no text lines, so --force-text yields read_empty; both
# read and read_empty confirm the media-skip was bypassed by --force-text.
if [[ "$output" =~ \"status\":\"read\" ]] || [[ "$output" =~ \"status\":\"read_empty\" ]]; then
    pass "--force-text reads binary file"
  else
    fail "--force-text should force read" "Got: $output"
  fi
}

# ============================================================================
# Line Range Tests
# ============================================================================

test_line_range_basic() {
  local output
  output=$(FSUITE_TELEMETRY=0 "${FREAD}" -r 5:10 "${TEST_DIR}/sample.txt" -o json 2>/dev/null)
  if [[ "$output" =~ \"start_line\":5 ]] && [[ "$output" =~ \"end_line\":10 ]]; then
    pass "Line range --lines 5:10 works"
  else
    fail "Range should be 5-10" "Got: $output"
  fi
}

test_line_range_past_eof() {
  local output
  output=$(FSUITE_TELEMETRY=0 "${FREAD}" -r 45:100 "${TEST_DIR}/sample.txt" -o json 2>/dev/null)
  # File has 50 lines — should clamp to 50
  if [[ "$output" =~ \"start_line\":45 ]]; then
    pass "Range past EOF is clamped"
  else
    fail "Should clamp to file end" "Got: $output"
  fi
}

test_line_range_single_line() {
  local output
  output=$(FSUITE_TELEMETRY=0 "${FREAD}" -r 5:5 "${TEST_DIR}/sample.txt" -o json 2>/dev/null)
  if [[ "$output" =~ \"start_line\":5 ]] && [[ "$output" =~ \"end_line\":5 ]]; then
    pass "Single line range works"
  else
    fail "Should read exactly line 5" "Got: $output"
  fi
}

test_line_range_invalid() {
  local rc=0
  FSUITE_TELEMETRY=0 "${FREAD}" -r "abc" "${TEST_DIR}/sample.txt" 2>/dev/null || rc=$?
  if (( rc != 0 )); then
    pass "Invalid range format rejected"
  else
    fail "Should reject invalid range"
  fi
}

test_head_mode() {
  local output
  output=$(FSUITE_TELEMETRY=0 "${FREAD}" --head 5 "${TEST_DIR}/sample.txt" -o json 2>/dev/null)
  if [[ "$output" =~ \"start_line\":1 ]] && [[ "$output" =~ \"end_line\":5 ]]; then
    pass "--head 5 reads first 5 lines"
  else
    fail "--head 5 should read lines 1-5" "Got: $output"
  fi
}

test_tail_mode() {
  local output
  output=$(FSUITE_TELEMETRY=0 "${FREAD}" --tail 5 "${TEST_DIR}/sample.txt" -o json 2>/dev/null)
  if [[ "$output" =~ \"start_line\":46 ]]; then
    pass "--tail 5 reads last 5 lines"
  else
    fail "--tail 5 should read lines 46-50" "Got: $output"
  fi
}

# ============================================================================
# Around Pattern Tests
# ============================================================================

test_around_finds_pattern() {
  local output
  output=$(FSUITE_TELEMETRY=0 "${FREAD}" --around "MARKER_ALPHA" -B 1 -A 2 "${TEST_DIR}/search_target.txt" -o json 2>/dev/null)
  if [[ "$output" =~ \"match_line\":4 ]]; then
    pass "--around finds pattern and reports match_line"
  else
    fail "Should find MARKER_ALPHA at line 4" "Got: $output"
  fi
}

test_around_before_after() {
  local output
  output=$(FSUITE_TELEMETRY=0 "${FREAD}" --around "MARKER_ALPHA" -B 2 -A 3 "${TEST_DIR}/search_target.txt" -o json 2>/dev/null)
  if [[ "$output" =~ \"start_line\":2 ]] && [[ "$output" =~ \"end_line\":7 ]]; then
    pass "--around with -B 2 -A 3 gives correct range"
  else
    fail "Expected range 2-7" "Got: $output"
  fi
}

test_around_pattern_not_found() {
  local rc=0
  local output
  output=$(FSUITE_TELEMETRY=0 "${FREAD}" --around "NONEXISTENT_XYZ" "${TEST_DIR}/search_target.txt" -o json 2>/dev/null) || rc=$?
  if [[ "$output" =~ \"error_code\":\"pattern_not_found\" ]]; then
    pass "Pattern not found reports error in JSON"
  else
    fail "Should report pattern_not_found error" "Got: $output, rc=$rc"
  fi
}

test_around_near_file_start() {
  local output
  output=$(FSUITE_TELEMETRY=0 "${FREAD}" --around "header line 1" -B 10 -A 1 "${TEST_DIR}/search_target.txt" -o json 2>/dev/null)
  if [[ "$output" =~ \"start_line\":1 ]]; then
    pass "--around near file start clamps to line 1"
  else
    fail "Should clamp start to line 1" "Got: $output"
  fi
}

test_around_all_matches() {
  local output
  output=$(FSUITE_TELEMETRY=0 "${FREAD}" --around "MARKER" --all-matches -B 0 -A 0 "${TEST_DIR}/search_target.txt" -o json 2>/dev/null)
  # Should find both MARKER_ALPHA (line 4) and MARKER_BETA (line 7)
  if [[ "$output" =~ \"match_line\":4 ]] && [[ "$output" =~ \"match_line\":7 ]]; then
    pass "--all-matches finds both markers"
  else
    fail "Should find markers at line 4 and 7" "Got: $output"
  fi
}

test_around_line_mode() {
  local output
  output=$(FSUITE_TELEMETRY=0 "${FREAD}" --around-line 25 -B 2 -A 2 "${TEST_DIR}/sample.txt" -o json 2>/dev/null)
  if [[ "$output" =~ \"start_line\":23 ]] && [[ "$output" =~ \"end_line\":27 ]]; then
    pass "--around-line 25 with -B 2 -A 2 gives 23-27"
  else
    fail "Expected range 23-27" "Got: $output"
  fi
}

# ============================================================================
# Pipeline / Stdin Tests
# ============================================================================

test_stdin_paths_mode() {
  local output
  output=$(printf '%s\n' "${TEST_DIR}/src/foo.py" "${TEST_DIR}/src/bar.py" | \
    FSUITE_TELEMETRY=0 "${FREAD}" --from-stdin --stdin-format=paths -o json 2>/dev/null)
  if [[ "$output" =~ \"mode\":\"stdin_paths\" ]] && [[ "$output" =~ foo.py ]] && [[ "$output" =~ bar.py ]]; then
    pass "--from-stdin --stdin-format=paths reads multiple files"
  else
    fail "Should read both files from stdin" "Got: $output"
  fi
}

test_stdin_max_files_cap() {
  local output
  output=$(printf '%s\n' "${TEST_DIR}/src/foo.py" "${TEST_DIR}/src/bar.py" "${TEST_DIR}/src/baz.py" | \
    FSUITE_TELEMETRY=0 "${FREAD}" --from-stdin --stdin-format=paths --max-files 2 -o json 2>/dev/null)
  # Should only read 2 files
  local file_count
  file_count=$(echo "$output" | grep -o '"status":"read"' | wc -l)
  file_count="${file_count//[[:space:]]/}"
  if (( file_count <= 2 )); then
    pass "--max-files 2 caps stdin file reading"
  else
    fail "Should cap at 2 files" "Got $file_count read"
  fi
}

test_stdin_format_required() {
  local rc=0
  echo "${TEST_DIR}/src/foo.py" | FSUITE_TELEMETRY=0 "${FREAD}" --from-stdin 2>/dev/null || rc=$?
  if (( rc != 0 )); then
    pass "--from-stdin without --stdin-format is rejected"
  else
    fail "Should require --stdin-format"
  fi
}

test_stdin_fsearch_pipe() {
  local output
  output=$(FSUITE_TELEMETRY=0 "${FSEARCH}" -o paths "*.py" "${TEST_DIR}/src" 2>/dev/null | \
    FSUITE_TELEMETRY=0 "${FREAD}" --from-stdin --stdin-format=paths --max-files 3 -o json 2>/dev/null)
  if [[ "$output" =~ \"tool\":\"fread\" ]] && [[ "$output" =~ \"mode\":\"stdin_paths\" ]]; then
    pass "fsearch | fread pipeline works"
  else
    fail "Pipeline should produce fread JSON" "Got: $output"
  fi
}

test_stdin_missing_files() {
  local output
  output=$(printf '%s\n' "/nonexistent/foo.py" "${TEST_DIR}/src/foo.py" | \
    FSUITE_TELEMETRY=0 "${FREAD}" --from-stdin --stdin-format=paths -o json 2>/dev/null)
  if [[ "$output" =~ \"error_code\":\"not_found\" ]] && [[ "$output" =~ \"status\":\"read\" ]]; then
    pass "Stdin with missing file reports error + reads others"
  else
    fail "Should handle mix of missing and valid files" "Got: $output"
  fi
}

# ============================================================================
# Unified Diff Tests
# ============================================================================

test_diff_basic() {
  # The diff references src/auth.py — create it at the expected relative path
  mkdir -p "${TEST_DIR}/src"
  cp "${TEST_DIR}/auth.py" "${TEST_DIR}/src/auth.py"
  local output
  output=$(cd "${TEST_DIR}" && FSUITE_TELEMETRY=0 "${FREAD}" --from-stdin --stdin-format=unified-diff -B 1 -A 1 -o json < "${TEST_DIR}/sample.diff" 2>/dev/null)
  if [[ "$output" =~ \"mode\":\"stdin_unified_diff\" ]]; then
    pass "--from-stdin --stdin-format=unified-diff parses diff"
  else
    fail "Should parse unified diff" "Got: $output"
  fi
}

test_diff_deleted_file() {
  local output
  output=$(cd "${TEST_DIR}" && FSUITE_TELEMETRY=0 "${FREAD}" --from-stdin --stdin-format=unified-diff -o json < "${TEST_DIR}/delete.diff" 2>/dev/null)
  if [[ "$output" =~ warning ]] || [[ "$output" =~ deleted ]] || [[ "$output" =~ "not_found" ]]; then
    pass "Deleted file in diff produces warning/error"
  else
    fail "Should warn about deleted file" "Got: $output"
  fi
}

test_diff_binary_patch() {
  local output
  output=$(cd "${TEST_DIR}" && FSUITE_TELEMETRY=0 "${FREAD}" --from-stdin --stdin-format=unified-diff -o json < "${TEST_DIR}/binary.diff" 2>/dev/null)
  if [[ "$output" =~ warning ]] || [[ "$output" =~ binary ]]; then
    pass "Binary patch in diff produces warning"
  else
    fail "Should warn about binary patch" "Got: $output"
  fi
}

# ============================================================================
# Output Format Tests
# ============================================================================

test_json_structure() {
  local output
  output=$(FSUITE_TELEMETRY=0 "${FREAD}" "${TEST_DIR}/sample.txt" --max-lines 5 -o json 2>/dev/null)
  if [[ "$output" =~ \"tool\":\"fread\" ]] && \
     [[ "$output" =~ \"version\":\"[0-9]+\.[0-9]+\.[0-9]+\" ]] && \
     [[ "$output" =~ \"truncated\" ]] && \
     [[ "$output" =~ \"token_estimate\" ]] && \
     [[ "$output" =~ \"chunks\" ]] && \
     [[ "$output" =~ \"files\" ]]; then
    pass "JSON output has all required fields"
  else
    fail "JSON missing required fields" "Got: $output"
  fi
}

test_json_parseable() {
  local output
  output=$(FSUITE_TELEMETRY=0 "${FREAD}" "${TEST_DIR}/sample.txt" --max-lines 10 -o json 2>/dev/null)
  if ! command -v python3 >/dev/null 2>&1; then
    pass "JSON output is valid (python3 validation skipped)"
    return 0
  fi
  if python3 -c "import json,sys; json.loads(sys.stdin.read())" <<< "$output" 2>/dev/null; then
    pass "JSON output is valid (python3 parsed)"
  else
    fail "JSON output is not valid JSON" "Got: $output"
  fi
}

test_json_special_chars() {
  local output
  output=$(FSUITE_TELEMETRY=0 "${FREAD}" "${TEST_DIR}/special_chars.txt" -o json 2>/dev/null)
  if python3 -c "import json,sys; json.loads(sys.stdin.read())" <<< "$output" 2>/dev/null; then
    pass "JSON with tabs/quotes/backslashes is valid"
  else
    fail "JSON with special chars should be valid" "Got: $output"
  fi
}

test_pretty_has_headers() {
  local output
  output=$(FSUITE_TELEMETRY=0 "${FREAD}" "${TEST_DIR}/sample.txt" --max-lines 5 2>/dev/null)
  if [[ "$output" == *"Read("* ]] || [[ "$output" == *"---"* ]] || [[ "$output" == *"lines"* ]]; then
    pass "Pretty output has headers"
  else
    fail "Pretty output should have headers" "Got first line: $(echo "$output" | head -1)"
  fi
}

test_quiet_suppresses_headers() {
  local output
  output=$(FSUITE_TELEMETRY=0 "${FREAD}" -q "${TEST_DIR}/sample.txt" --max-lines 3 2>/dev/null)
  # First line should be a numbered content line, not a header
  local first_line
  first_line=$(echo "$output" | head -1)
  if [[ "$first_line" =~ ^[0-9] ]]; then
    pass "Quiet mode suppresses headers"
  else
    fail "Quiet first line should be numbered content" "Got: $first_line"
  fi
}

test_paths_output() {
  local output
  output=$(FSUITE_TELEMETRY=0 "${FREAD}" "${TEST_DIR}/sample.txt" -o paths 2>/dev/null)
  if [[ "$output" == *"sample.txt" ]]; then
    pass "Paths output shows file path"
  else
    fail "Paths output should show file path" "Got: $output"
  fi
}

# ============================================================================
# Symbol Resolution Tests
# ============================================================================

test_symbol_exact_single_match() {
  local output tmp_json
  output=$(FSUITE_TELEMETRY=0 "${FREAD}" "${TEST_DIR}/auth.py" --symbol authenticate -o json 2>/dev/null)
  tmp_json="$(mktemp)"
  printf '%s\n' "$output" > "$tmp_json"

  if python3 - "$tmp_json" <<'PY' 2>/dev/null
import json, sys
with open(sys.argv[1], "r", encoding="utf-8") as fh:
    d = json.load(fh)
assert d["errors"] == []
assert len(d["chunks"]) == 1
chunk = d["chunks"][0]
assert chunk["path"].endswith("auth.py")
assert chunk["start_line"] == 4
assert chunk["end_line"] == 9
assert any("def authenticate" in line for line in chunk["content"])
resolution = d["symbol_resolution"]
assert resolution["query"] == "authenticate"
assert resolution["symbol"] == "authenticate"
assert resolution["symbol_type"] == "function"
assert resolution["path"].endswith("auth.py")
assert resolution["line_start"] == 4
assert resolution["line_end"] == 9
PY
  then
    pass "fread --symbol exact single match resolves and reads the correct chunk"
  else
    fail "fread --symbol exact single match JSON contract failed" "Got: $output"
  fi
  rm -f "$tmp_json"
}

test_symbol_directory_scope() {
  local output tmp_json
  output=$(FSUITE_TELEMETRY=0 "${FREAD}" "${TEST_DIR}/symbols" --symbol unique_dir_symbol -o json 2>/dev/null)
  tmp_json="$(mktemp)"
  printf '%s\n' "$output" > "$tmp_json"

  if python3 - "$tmp_json" <<'PY' 2>/dev/null
import json, sys
with open(sys.argv[1], "r", encoding="utf-8") as fh:
    d = json.load(fh)
assert d["errors"] == []
assert len(d["chunks"]) == 1
chunk = d["chunks"][0]
assert chunk["path"].endswith("one.py")
assert any("def unique_dir_symbol" in line for line in chunk["content"])
resolution = d["symbol_resolution"]
assert resolution["path"].endswith("one.py")
assert resolution["symbol"] == "unique_dir_symbol"
PY
  then
    pass "fread --symbol resolves within directory mapping scope"
  else
    fail "fread --symbol directory scope failed" "Got: $output"
  fi
  rm -f "$tmp_json"
}

test_symbol_file_scope_is_local() {
  local output tmp_json
  output=$(FSUITE_TELEMETRY=0 "${FREAD}" "${TEST_DIR}/symbols/one.py" --symbol duplicate -o json 2>/dev/null)
  tmp_json="$(mktemp)"
  printf '%s\n' "$output" > "$tmp_json"

  if python3 - "$tmp_json" <<'PY' 2>/dev/null
import json, sys
with open(sys.argv[1], "r", encoding="utf-8") as fh:
    d = json.load(fh)
assert d["errors"] == []
assert len(d["chunks"]) == 1
chunk = d["chunks"][0]
assert chunk["path"].endswith("one.py")
assert any("value = 1" in line for line in chunk["content"])
resolution = d["symbol_resolution"]
assert resolution["path"].endswith("one.py")
assert resolution["symbol"] == "duplicate"
PY
  then
    pass "fread file target keeps --symbol resolution file-local"
  else
    fail "fread file target should not resolve sibling symbols" "Got: $output"
  fi
  rm -f "$tmp_json"
}

test_symbol_go_receiver_method() {
  local output tmp_json
  output=$(FSUITE_TELEMETRY=0 "${FREAD}" "${TEST_DIR}/symbols/server.go" --symbol Start -o json 2>/dev/null)
  tmp_json="$(mktemp)"
  printf '%s\n' "$output" > "$tmp_json"

  if python3 - "$tmp_json" <<'PY' 2>/dev/null
import json, sys
with open(sys.argv[1], "r", encoding="utf-8") as fh:
    d = json.load(fh)
assert d["errors"] == []
assert len(d["chunks"]) == 1
chunk = d["chunks"][0]
assert chunk["path"].endswith("server.go")
assert chunk["start_line"] == 7
assert any("func (s *Server) Start()" in line for line in chunk["content"])
resolution = d["symbol_resolution"]
assert resolution["symbol"] == "Start"
assert resolution["symbol_type"] == "function"
assert resolution["path"].endswith("server.go")
assert resolution["line_start"] == 7
PY
  then
    pass "fread --symbol resolves Go receiver methods by method name"
  else
    fail "fread --symbol should resolve Go receiver methods by method name" "Got: $output"
  fi
  rm -f "$tmp_json"
}

test_symbol_ambiguous_failure() {
  local output rc tmp_json
  set +e
  output=$(FSUITE_TELEMETRY=0 "${FREAD}" "${TEST_DIR}/symbols" --symbol duplicate -o json 2>/dev/null)
  rc=$?
  set -e
  tmp_json="$(mktemp)"
  printf '%s\n' "$output" > "$tmp_json"

  if (( rc != 0 )) && python3 - "$tmp_json" <<'PY' 2>/dev/null
import json, sys
with open(sys.argv[1], "r", encoding="utf-8") as fh:
    d = json.load(fh)
assert d["chunks"] == []
assert len(d["errors"]) == 1
err = d["errors"][0]
assert err["error_code"] == "symbol_ambiguous"
candidates = d["candidates"]
assert len(candidates) == 2
assert [c["path"].rsplit("/", 1)[-1] for c in candidates] == ["one.py", "two.py"]
assert all(c["symbol"] == "duplicate" for c in candidates)
assert [c["line_start"] for c in candidates] == [1, 1]
PY
  then
    pass "fread --symbol ambiguous exact matches fail with deterministic candidates"
  else
    fail "fread --symbol ambiguity failure contract failed" "rc=$rc output=$output"
  fi
  rm -f "$tmp_json"
}

test_symbol_not_found_failure() {
  local output rc tmp_json
  set +e
  output=$(FSUITE_TELEMETRY=0 "${FREAD}" "${TEST_DIR}/symbols" --symbol duplic -o json 2>/dev/null)
  rc=$?
  set -e
  tmp_json="$(mktemp)"
  printf '%s\n' "$output" > "$tmp_json"

  if (( rc != 0 )) && python3 - "$tmp_json" <<'PY' 2>/dev/null
import json, sys
with open(sys.argv[1], "r", encoding="utf-8") as fh:
    d = json.load(fh)
assert d["chunks"] == []
assert len(d["errors"]) == 1
err = d["errors"][0]
assert err["error_code"] == "symbol_not_found"
assert d["candidates"] == []
assert d["symbol_resolution"] is None
PY
  then
    pass "fread --symbol missing exact match fails without substring fallback"
  else
    fail "fread --symbol missing exact match contract failed" "rc=$rc output=$output"
  fi
  rm -f "$tmp_json"
}

# ============================================================================
# Budget / Truncation Tests
# ============================================================================

test_max_lines_truncation() {
  local output
  output=$(FSUITE_TELEMETRY=0 "${FREAD}" --max-lines 10 "${TEST_DIR}/sample.txt" -o json 2>/dev/null)
  if [[ "$output" =~ \"truncated\":true ]] && [[ "$output" =~ \"truncation_reason\":\"max_lines\" ]]; then
    pass "--max-lines triggers truncation with correct reason"
  else
    fail "Should truncate with reason=max_lines" "Got: $output"
  fi
}

test_max_bytes_truncation() {
  local output
  output=$(FSUITE_TELEMETRY=0 "${FREAD}" --max-bytes 100 "${TEST_DIR}/sample.txt" -o json 2>/dev/null)
  if [[ "$output" =~ \"truncated\":true ]] && [[ "$output" =~ \"truncation_reason\":\"max_bytes\" ]]; then
    pass "--max-bytes triggers truncation with correct reason"
  else
    fail "Should truncate with reason=max_bytes" "Got: $output"
  fi
}

test_token_budget_truncation() {
  local output
  output=$(FSUITE_TELEMETRY=0 "${FREAD}" --token-budget 30 "${TEST_DIR}/sample.txt" -o json 2>/dev/null)
  if [[ "$output" =~ \"truncated\":true ]] && [[ "$output" =~ \"truncation_reason\":\"token_budget\" ]]; then
    pass "--token-budget triggers truncation with correct reason"
  else
    fail "Should truncate with reason=token_budget" "Got: $output"
  fi
}

test_next_hint_on_truncation() {
  local output
  output=$(FSUITE_TELEMETRY=0 "${FREAD}" --max-lines 10 "${TEST_DIR}/sample.txt" -o json 2>/dev/null)
  if [[ "$output" =~ \"next_hint\":\"fread ]]; then
    pass "next_hint present on truncation"
  else
    fail "Truncated output should include next_hint" "Got: $output"
  fi
}

test_token_estimate_present() {
  local output
  output=$(FSUITE_TELEMETRY=0 "${FREAD}" "${TEST_DIR}/sample.txt" --max-lines 5 -o json 2>/dev/null)
  if [[ "$output" =~ \"token_estimate\":[0-9]+ ]] && [[ "$output" =~ \"token_estimator\":\"bytes_div_3_conservative\" ]]; then
    pass "Token estimate and estimator method present in JSON"
  else
    fail "Should include token_estimate and token_estimator" "Got: $output"
  fi
}

test_no_truncate_overrides_all_budgets() {
  local output tmp_json
  output=$(FSUITE_TELEMETRY=0 "${FREAD}" "${TEST_DIR}/large.txt" --max-lines 10 --max-bytes 100 --token-budget 1 --no-truncate -o json 2>/dev/null)
  tmp_json="$(mktemp)"
  printf '%s\n' "$output" > "$tmp_json"

  if python3 - "$tmp_json" <<'PY' 2>/dev/null
import json, sys
with open(sys.argv[1], "r", encoding="utf-8") as fh:
    d = json.load(fh)
assert d["truncated"] is False
assert d["truncation_reason"] == "none"
assert d["lines_emitted"] == 260
assert any("Large line 260" in line for chunk in d["chunks"] for line in chunk["content"])
PY
  then
    pass "--no-truncate overrides line, byte, and token budgets"
  else
    fail "--no-truncate should emit the full requested file" "Got: $output"
  fi
  rm -f "$tmp_json"
}

# ============================================================================
# Mode Conflict Tests
# ============================================================================

test_conflicting_modes_rejected() {
  local rc=0
  FSUITE_TELEMETRY=0 "${FREAD}" --head 5 --tail 5 "${TEST_DIR}/sample.txt" 2>/dev/null || rc=$?
  if (( rc != 0 )); then
    pass "Conflicting modes (--head + --tail) rejected"
  else
    fail "Should reject conflicting mode selectors"
  fi
}

test_all_matches_without_around() {
  local rc=0
  FSUITE_TELEMETRY=0 "${FREAD}" --all-matches "${TEST_DIR}/sample.txt" 2>/dev/null || rc=$?
  if (( rc != 0 )); then
    pass "--all-matches without --around rejected"
  else
    fail "Should reject --all-matches without --around"
  fi
}

test_from_stdin_with_file_arg() {
  local rc=0
  echo "${TEST_DIR}/src/foo.py" | FSUITE_TELEMETRY=0 "${FREAD}" --from-stdin --stdin-format=paths "${TEST_DIR}/sample.txt" 2>/dev/null || rc=$?
  if (( rc != 0 )); then
    pass "--from-stdin with positional file argument rejected"
  else
    fail "Should reject --from-stdin + positional path"
  fi
}

# ============================================================================
# Telemetry Tests
# ============================================================================

test_telemetry_recorded() {
  rm -f "$HOME/.fsuite/telemetry.jsonl"
  FSUITE_TELEMETRY=1 "${FREAD}" "${TEST_DIR}/sample.txt" --max-lines 5 >/dev/null 2>&1 || true
  local line
  line=$(tail -1 "$HOME/.fsuite/telemetry.jsonl" 2>/dev/null) || line=""
  if python3 - "$line" <<'PY' 2>/dev/null; then
import json
import sys

payload = json.loads(sys.argv[1])
run_id = payload.get("run_id", "")
assert payload.get("tool") == "fread"
assert isinstance(run_id, str) and len(run_id) > 0
PY
    pass "Telemetry records fread with run_id"
  else
    fail "Telemetry should record tool=fread with run_id" "Got: $line"
  fi
}

test_telemetry_escapes_run_id() {
  rm -f "$HOME/.fsuite/telemetry.jsonl"
  local raw_run_id line
  raw_run_id=$'custom"run\\id\nnext'
  FSUITE_TELEMETRY=1 FSUITE_TELEMETRY_RUN_ID="$raw_run_id" "${FREAD}" "${TEST_DIR}/sample.txt" --max-lines 5 >/dev/null 2>&1 || true
  line=$(tail -1 "$HOME/.fsuite/telemetry.jsonl" 2>/dev/null) || line=""
  if python3 - "$line" "$raw_run_id" <<'PY' 2>/dev/null; then
import json
import sys

payload = json.loads(sys.argv[1])
assert payload.get("tool") == "fread"
assert payload.get("run_id") == sys.argv[2]
PY
    pass "Telemetry JSON escapes custom run_id"
  else
    fail "Telemetry should JSON-escape custom run_id" "Got: $line"
  fi
}

test_telemetry_project_name() {
  rm -f "$HOME/.fsuite/telemetry.jsonl"
  FSUITE_TELEMETRY=1 "${FREAD}" --project-name "TestProj" "${TEST_DIR}/sample.txt" --max-lines 5 >/dev/null 2>&1 || true
  local line
  line=$(tail -1 "$HOME/.fsuite/telemetry.jsonl" 2>/dev/null) || line=""
  if [[ "$line" =~ \"project_name\":\"TestProj\" ]]; then
    pass "--project-name override appears in telemetry"
  else
    fail "Telemetry should include project_name=TestProj" "Got: $line"
  fi
}

test_telemetry_flags() {
  rm -f "$HOME/.fsuite/telemetry.jsonl"
  FSUITE_TELEMETRY=1 "${FREAD}" --max-lines 5 -r 1:10 "${TEST_DIR}/sample.txt" >/dev/null 2>&1 || true
  local line flags
  line=$(tail -1 "$HOME/.fsuite/telemetry.jsonl" 2>/dev/null) || line=""
  flags=$(echo "$line" | grep -o '"flags":"[^"]*"' || true)
  if [[ "$flags" =~ "--max-lines 5" ]] && [[ "$flags" =~ "-r 1:10" ]]; then
    pass "Flag accumulation records --max-lines and -r in telemetry"
  else
    fail "Telemetry flags should include --max-lines 5 and -r 1:10" "Got: $flags"
  fi
}

test_telemetry_default_flags() {
  rm -f "$HOME/.fsuite/telemetry.jsonl"
  FSUITE_TELEMETRY=1 "${FREAD}" "${TEST_DIR}/sample.txt" --max-lines 3 >/dev/null 2>&1 || true
  local line flags
  line=$(tail -1 "$HOME/.fsuite/telemetry.jsonl" 2>/dev/null) || line=""
  flags=$(echo "$line" | grep -o '"flags":"[^"]*"' || true)
  if [[ "$flags" =~ "-o pretty" ]]; then
    pass "Default flag seeding records output format"
  else
    fail "Telemetry should include default -o pretty" "Got: $flags"
  fi
}

# ============================================================================
# File with Spaces Test
# ============================================================================

test_file_with_spaces() {
  local output
  output=$(FSUITE_TELEMETRY=0 "${FREAD}" "${TEST_DIR}/file with spaces.txt" -o json 2>/dev/null)
  if [[ "$output" =~ \"status\":\"read\" ]]; then
    pass "File with spaces in name reads correctly"
  else
    fail "Should handle filenames with spaces" "Got: $output"
  fi
}

# ============================================================================
# Language Detection Test
# ============================================================================

test_language_detection() {
  local output
  output=$(FSUITE_TELEMETRY=0 "${FREAD}" "${TEST_DIR}/auth.py" -o json 2>/dev/null)
  if [[ "$output" =~ \"language\":\"python\" ]]; then
    pass "Language detected as python for .py file"
  else
    fail "Should detect python language" "Got: $output"
  fi
}

# ── Media reading tests (Phase 5) ────────────────────────────────────────────
# These tests exercise the fread-media.py engine dispatch added in Phase 1-2.
# All use real fixture files from tests/fixtures/media/ which are checked in.
MEDIA_FIXTURES="${SCRIPT_DIR}/fixtures/media"

# A. Image pretty mode — no base64 in stdout
test_media_image_pretty_no_base64() {
local output rc=0
output=$(FSUITE_TELEMETRY=0 FSUITE_MEMORY_INGEST=0 "${FREAD}" "${MEDIA_FIXTURES}/sample.png" 2>/dev/null) || rc=$?
if (( rc != 0 )); then
fail "Image pretty mode should exit 0" "exit=$rc"
return
fi
if [[ "$output" != *"PNG"* ]]; then
fail "Image pretty output missing PNG" "Got: $output"
return
fi
if [[ "$output" != *"100"*"80"* ]]; then
fail "Image pretty output missing dimensions 100x80" "Got: $output"
return
fi
if [[ "$output" == *"iVBORw0KGgo"* ]]; then
fail "Image pretty mode must not contain base64 payload" "Got base64 in stdout"
return
fi
pass "Image pretty mode: no base64, shows PNG + dimensions"
}

# B. Image JSON has media_payload
test_media_image_json_has_media_payload() {
local output rc=0
output=$(FSUITE_TELEMETRY=0 FSUITE_MEMORY_INGEST=0 "${FREAD}" "${MEDIA_FIXTURES}/sample.png" -o json 2>/dev/null) || rc=$?
if (( rc != 0 )); then
fail "Image JSON should exit 0" "exit=$rc"
return
fi
local result
result=$(printf '%s' "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
mp = d.get('media_payload', {})
f  = mp.get('file', {})
ip = mp.get('ingest_payload', {})
ok = (
    'media_payload' in d and
    mp.get('type') == 'image' and
    isinstance(f.get('tokens_estimate'), int) and
    1 <= f.get('tokens_estimate', 0) <= 50 and
    f.get('format') == 'png' and
    'ingest_payload' in mp and
    ip.get('category') == 'custom' and
    any(t.startswith('hash:') for t in ip.get('tags', []))
)
print('OK' if ok else 'FAIL: type=%s fmt=%s tok=%s cat=%s tags=%s' % (
    mp.get('type'), f.get('format'), f.get('tokens_estimate'),
    ip.get('category'), ip.get('tags')))
" 2>/dev/null || echo "PARSE_ERROR")
if [[ "$result" == "OK" ]]; then
pass "Image JSON: media_payload structure correct"
else
fail "Image JSON: media_payload structure wrong" "$result"
fi
}

# C. Image meta-only
test_media_image_meta_only() {
local output rc=0
output=$(FSUITE_TELEMETRY=0 FSUITE_MEMORY_INGEST=0 "${FREAD}" "${MEDIA_FIXTURES}/sample.png" --meta-only -o json 2>/dev/null) || rc=$?
if (( rc != 0 )); then
fail "Image meta-only should exit 0" "exit=$rc"
return
fi
local result
result=$(printf '%s' "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
mp = d.get('media_payload', {})
f  = mp.get('file', {})
ok = (
    mp.get('type') == 'image-meta' and
    'data' not in f and
    'base64' not in str(f)
)
print('OK' if ok else 'FAIL: type=%s file_keys=%s' % (mp.get('type'), list(f.keys())))
" 2>/dev/null || echo "PARSE_ERROR")
if [[ "$result" == "OK" ]]; then
pass "Image meta-only: type=image-meta, no base64"
else
fail "Image meta-only: wrong output" "$result"
fi
}

# D. Image no-resize token refusal
test_media_image_no_resize_token_refusal() {
local rc=0 combined
combined=$(FSUITE_TELEMETRY=0 FSUITE_MEMORY_INGEST=0 "${FREAD}" "${MEDIA_FIXTURES}/sample.png" --no-resize --max-tokens 1 2>&1) || rc=$?
if (( rc == 0 )); then
fail "Image --no-resize --max-tokens 1 should exit non-zero"
return
fi
if [[ "$combined" != *"TOKEN_BUDGET_EXCEEDED"* ]]; then
fail "Image token refusal should mention TOKEN_BUDGET_EXCEEDED" "Got: $combined"
return
fi
pass "Image --no-resize --max-tokens 1 exits non-zero with TOKEN_BUDGET_EXCEEDED"
}

# E. PDF text default (pretty)
test_media_pdf_text_default() {
local output rc=0
output=$(FSUITE_TELEMETRY=0 FSUITE_MEMORY_INGEST=0 "${FREAD}" "${MEDIA_FIXTURES}/sample.pdf" 2>/dev/null) || rc=$?
if (( rc != 0 )); then
fail "PDF pretty mode should exit 0" "exit=$rc"
return
fi
if [[ "$output" != *"--- page 1 ---"* ]]; then
fail "PDF text missing '--- page 1 ---'" "Got: ${output:0:200}"
return
fi
local sep_count
sep_count=$(printf '%s' "$output" | grep -c "^--- page " || true)
if (( sep_count < 2 )); then
fail "PDF text should have at least 2 page separators" "Got count=$sep_count"
return
fi
pass "PDF text pretty: page separators present"
}

# F. PDF text JSON
test_media_pdf_text_json() {
local output rc=0
output=$(FSUITE_TELEMETRY=0 FSUITE_MEMORY_INGEST=0 "${FREAD}" "${MEDIA_FIXTURES}/sample.pdf" -o json 2>/dev/null) || rc=$?
if (( rc != 0 )); then
fail "PDF JSON should exit 0" "exit=$rc"
return
fi
local result
result=$(printf '%s' "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
mp = d.get('media_payload', {})
f  = mp.get('file', {})
ok = (
    mp.get('type') == 'pdf-text' and
    f.get('pages_returned') == [1, 2, 3, 4, 5] and
    f.get('truncated') == False and
    len(f.get('text', '')) > 100
)
print('OK' if ok else 'FAIL: type=%s pages=%s trunc=%s textlen=%d' % (
    mp.get('type'), f.get('pages_returned'), f.get('truncated'), len(f.get('text',''))))
" 2>/dev/null || echo "PARSE_ERROR")
if [[ "$result" == "OK" ]]; then
pass "PDF text JSON: correct type, pages, not truncated"
else
fail "PDF text JSON: wrong output" "$result"
fi
}

# G. PDF meta-only
test_media_pdf_meta_only() {
local output rc=0
output=$(FSUITE_TELEMETRY=0 FSUITE_MEMORY_INGEST=0 "${FREAD}" "${MEDIA_FIXTURES}/sample.pdf" --meta-only -o json 2>/dev/null) || rc=$?
if (( rc != 0 )); then
fail "PDF meta-only should exit 0" "exit=$rc"
return
fi
local result
result=$(printf '%s' "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
mp = d.get('media_payload', {})
f  = mp.get('file', {})
ok = mp.get('type') == 'pdf-meta' and f.get('page_count') == 5
print('OK' if ok else 'FAIL: type=%s page_count=%s' % (mp.get('type'), f.get('page_count')))
" 2>/dev/null || echo "PARSE_ERROR")
if [[ "$result" == "OK" ]]; then
pass "PDF meta-only: type=pdf-meta, page_count=5"
else
fail "PDF meta-only: wrong output" "$result"
fi
}

# H. PDF render pages
test_media_pdf_render_pages() {
local output rc=0
output=$(FSUITE_TELEMETRY=0 FSUITE_MEMORY_INGEST=0 "${FREAD}" "${MEDIA_FIXTURES}/sample.pdf" --render --pages 1:2 -o json 2>/dev/null) || rc=$?
if (( rc != 0 )); then
fail "PDF render pages should exit 0" "exit=$rc"
return
fi
local result
result=$(printf '%s' "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
mp = d.get('media_payload', {})
f  = mp.get('file', {})
pages = f.get('pages', [])
ok = (
    mp.get('type') == 'pdf-pages' and
    f.get('count') == 2 and
    len(pages) == 2 and
    all(p.get('mime_type') == 'image/jpeg' for p in pages)
)
print('OK' if ok else 'FAIL: type=%s count=%s mimes=%s' % (
    mp.get('type'), f.get('count'), [p.get('mime_type') for p in pages]))
" 2>/dev/null || echo "PARSE_ERROR")
if [[ "$result" == "OK" ]]; then
pass "PDF render pages: type=pdf-pages, count=2, mime_type=image/jpeg"
else
fail "PDF render pages: wrong output" "$result"
fi
}

# I. PDF render cap (>10 pages without --max-pages)
test_media_pdf_render_cap() {
local rc=0 combined
# Part 1: 12 pages without --max-pages should fail
combined=$(FSUITE_TELEMETRY=0 FSUITE_MEMORY_INGEST=0 "${FREAD}" "${MEDIA_FIXTURES}/big.pdf" --render --pages 1:12 2>&1) || rc=$?
if (( rc == 0 )); then
fail "PDF render 12 pages without --max-pages should exit non-zero"
return
fi
if [[ "$combined" != *"TOKEN_BUDGET_EXCEEDED"* ]]; then
fail "PDF render cap should mention TOKEN_BUDGET_EXCEEDED" "Got: $combined"
return
fi
# Part 2: with --max-pages 12 should succeed
local output2 rc2=0
output2=$(FSUITE_TELEMETRY=0 FSUITE_MEMORY_INGEST=0 "${FREAD}" "${MEDIA_FIXTURES}/big.pdf" --render --pages 1:12 --max-pages 12 -o json 2>/dev/null) || rc2=$?
if (( rc2 != 0 )); then
fail "PDF render --max-pages 12 should exit 0" "exit=$rc2"
return
fi
local count
count=$(printf '%s' "$output2" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('media_payload',{}).get('file',{}).get('count','?'))" 2>/dev/null || echo "?")
if [[ "$count" == "12" ]]; then
pass "PDF render cap: blocked >10 pages; --max-pages 12 allows 12 pages"
else
fail "PDF render --max-pages 12: expected count=12" "Got count=$count"
fi
}

# J. PDF invalid pages
test_media_pdf_invalid_pages() {
local rc1=0 out1 rc2=0 out2
# Non-numeric range
out1=$(FSUITE_TELEMETRY=0 FSUITE_MEMORY_INGEST=0 "${FREAD}" "${MEDIA_FIXTURES}/sample.pdf" --pages "abc:xyz" 2>&1) || rc1=$?
if (( rc1 == 0 )); then
fail "PDF --pages abc:xyz should exit non-zero"
return
fi
if [[ "$out1" != *"INVALID_PAGE_RANGE"* ]]; then
fail "PDF invalid range abc:xyz should mention INVALID_PAGE_RANGE" "Got: $out1"
return
fi
# Out-of-range
out2=$(FSUITE_TELEMETRY=0 FSUITE_MEMORY_INGEST=0 "${FREAD}" "${MEDIA_FIXTURES}/sample.pdf" --pages "10:20" 2>&1) || rc2=$?
if (( rc2 == 0 )); then
fail "PDF --pages 10:20 should exit non-zero (only 5 pages)"
return
fi
if [[ "$out2" != *"INVALID_PAGE_RANGE"* ]]; then
fail "PDF out-of-range pages should mention INVALID_PAGE_RANGE" "Got: $out2"
return
fi
pass "PDF invalid pages: abc:xyz and 10:20 both give INVALID_PAGE_RANGE"
}

# K. PDF encrypted
test_media_pdf_encrypted() {
local enc_pdf="${TEST_DIR}/encrypted.pdf"
# Create encrypted PDF
python3 -c "
import fitz
d = fitz.open('${MEDIA_FIXTURES}/sample.pdf')
d.save('${enc_pdf}', encryption=fitz.PDF_ENCRYPT_AES_256, owner_pw='x', user_pw='x')
d.close()
" 2>/dev/null
if [[ ! -f "$enc_pdf" ]]; then
fail "Could not create encrypted PDF fixture"
return
fi

local all_pass=1

# Mode 1: default text
local out1 rc1=0
out1=$(FSUITE_TELEMETRY=0 FSUITE_MEMORY_INGEST=0 "${FREAD}" "$enc_pdf" 2>&1) || rc1=$?
if (( rc1 == 0 )) || [[ "$out1" != *"PDF_ENCRYPTED"* ]]; then
fail "Encrypted PDF (default) should fail with PDF_ENCRYPTED" "rc=$rc1 out=$out1"
all_pass=0
fi

# Mode 2: --meta-only
local out2 rc2=0
out2=$(FSUITE_TELEMETRY=0 FSUITE_MEMORY_INGEST=0 "${FREAD}" "$enc_pdf" --meta-only 2>&1) || rc2=$?
if (( rc2 == 0 )) || [[ "$out2" != *"PDF_ENCRYPTED"* ]]; then
fail "Encrypted PDF (--meta-only) should fail with PDF_ENCRYPTED" "rc=$rc2"
all_pass=0
fi

# Mode 3: --render
local out3 rc3=0
out3=$(FSUITE_TELEMETRY=0 FSUITE_MEMORY_INGEST=0 "${FREAD}" "$enc_pdf" --render --pages 1:1 2>&1) || rc3=$?
if (( rc3 == 0 )) || [[ "$out3" != *"PDF_ENCRYPTED"* ]]; then
fail "Encrypted PDF (--render) should fail with PDF_ENCRYPTED" "rc=$rc3"
all_pass=0
fi

# Modes 4 & 5: poppler backend (skip if pdftotext absent)
if command -v pdftotext >/dev/null 2>&1; then
local out4 rc4=0
out4=$(FSUITE_TELEMETRY=0 FSUITE_MEMORY_INGEST=0 FREAD_MEDIA_FORCE_BACKEND=poppler "${FREAD}" "$enc_pdf" 2>&1) || rc4=$?
if (( rc4 == 0 )) || [[ "$out4" != *"PDF_ENCRYPTED"* ]]; then
fail "Encrypted PDF (poppler default) should fail with PDF_ENCRYPTED" "rc=$rc4"
all_pass=0
fi

local out5 rc5=0
out5=$(FSUITE_TELEMETRY=0 FSUITE_MEMORY_INGEST=0 FREAD_MEDIA_FORCE_BACKEND=poppler "${FREAD}" "$enc_pdf" --render --pages 1:1 2>&1) || rc5=$?
if (( rc5 == 0 )) || [[ "$out5" != *"PDF_ENCRYPTED"* ]]; then
fail "Encrypted PDF (poppler render) should fail with PDF_ENCRYPTED" "rc=$rc5"
all_pass=0
fi
fi

if (( all_pass )); then
pass "PDF encrypted: all modes emit PDF_ENCRYPTED and exit non-zero"
fi
}

# L. PDF backend fallback (poppler)
test_media_backend_fallback() {
if ! command -v pdftotext >/dev/null 2>&1; then
echo "  SKIP: test_media_backend_fallback — pdftotext not installed"
TESTS_PASSED=$((TESTS_PASSED + 1))
return
fi
local output rc=0
output=$(FSUITE_TELEMETRY=0 FSUITE_MEMORY_INGEST=0 FREAD_MEDIA_FORCE_BACKEND=poppler "${FREAD}" "${MEDIA_FIXTURES}/sample.pdf" -o json 2>/dev/null) || rc=$?
if (( rc != 0 )); then
fail "PDF poppler backend should exit 0" "exit=$rc"
return
fi
local result
result=$(printf '%s' "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
mp = d.get('media_payload', {})
f  = mp.get('file', {})
ok = (
    mp.get('backend') == 'poppler' and
    mp.get('type') == 'pdf-text' and
    len(f.get('text', '')) > 0
)
print('OK' if ok else 'FAIL: backend=%s type=%s textlen=%d' % (
    mp.get('backend'), mp.get('type'), len(f.get('text',''))))
" 2>/dev/null || echo "PARSE_ERROR")
if [[ "$result" == "OK" ]]; then
pass "PDF poppler backend: backend=poppler, type=pdf-text, text non-empty"
else
fail "PDF poppler backend: wrong output" "$result"
fi
}

# M. PDF invalid backend
test_media_backend_force_invalid() {
local rc=0 combined
combined=$(FSUITE_TELEMETRY=0 FSUITE_MEMORY_INGEST=0 FREAD_MEDIA_FORCE_BACKEND=banana "${FREAD}" "${MEDIA_FIXTURES}/sample.pdf" 2>&1) || rc=$?
if (( rc == 0 )); then
fail "Invalid backend should exit non-zero"
return
fi
if [[ "$combined" != *"BACKEND_MISSING"* ]]; then
fail "Invalid backend should mention BACKEND_MISSING" "Got: $combined"
return
fi
if [[ "$combined" != *"not recognized"* ]]; then
fail "Invalid backend should mention 'not recognized'" "Got: $combined"
return
fi
pass "Invalid backend 'banana' exits non-zero with BACKEND_MISSING + not recognized"
}

# N. --no-ingest flag suppresses memory-ingest log entry
test_media_no_ingest_flag() {
local log_file="${HOME}/.cache/fsuite/memory-ingest.log"
mkdir -p "${HOME}/.cache/fsuite" 2>/dev/null
rm -f "$log_file"
FSUITE_TELEMETRY=0 "${FREAD}" "${MEDIA_FIXTURES}/sample.png" --no-ingest >/dev/null 2>&1
sleep 2
if [[ ! -f "$log_file" ]] || [[ ! -s "$log_file" ]]; then
pass "--no-ingest suppresses memory-ingest log entry"
else
fail "--no-ingest should produce no log entries" "Log: $(cat "$log_file" 2>/dev/null | head -3)"
fi
}

# O. Missing ingest helper — exercised manually in Phase 7; skip here.
# The _media_maybe_ingest function locates the helper via a hard path
# (${_FSUITE_SCRIPT_DIR}/mcp/memory-ingest.js) with no env override,
# so the only clean test requires moving the file. Phase 7 covers this.

# P. PDF token budget truncation
test_media_pdf_token_budget_truncation() {
local output rc=0
output=$(FSUITE_TELEMETRY=0 FSUITE_MEMORY_INGEST=0 "${FREAD}" "${MEDIA_FIXTURES}/sample.pdf" --token-budget 50 -o json 2>/dev/null) || rc=$?
if (( rc != 0 )); then
fail "PDF token-budget truncation should exit 0" "exit=$rc"
return
fi
local result
result=$(printf '%s' "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
mp = d.get('media_payload', {})
f  = mp.get('file', {})
pr = f.get('pages_returned')
ok = f.get('truncated') == True and pr is not None and len(pr) < 5
print('OK' if ok else 'FAIL: truncated=%s pages_returned=%s' % (f.get('truncated'), pr))
" 2>/dev/null || echo "PARSE_ERROR")
if [[ "$result" == "OK" ]]; then
pass "PDF token-budget truncation: truncated=true, fewer than 5 pages"
else
fail "PDF token-budget truncation: wrong output" "$result"
fi
}

# Q. Python engine standalone probe
test_media_python_engine_standalone() {
local engine="${SCRIPT_DIR}/../fread-media.py"
if [[ ! -f "$engine" ]]; then
fail "fread-media.py not found at $engine"
return
fi

# Probe image
local r1
r1=$(python3 "$engine" probe "${MEDIA_FIXTURES}/sample.png" 2>/dev/null | python3 -c "
import json,sys; d=json.load(sys.stdin)
ok = d.get('type')=='probe' and d.get('detected')=='image'
print('OK' if ok else 'FAIL: '+str(d))
" 2>/dev/null || echo "PARSE_ERROR")
if [[ "$r1" != "OK" ]]; then
fail "Engine probe sample.png: wrong result" "$r1"
return
fi

# Probe PDF
local r2
r2=$(python3 "$engine" probe "${MEDIA_FIXTURES}/sample.pdf" 2>/dev/null | python3 -c "
import json,sys; d=json.load(sys.stdin)
ok = d.get('type')=='probe' and d.get('detected')=='pdf'
print('OK' if ok else 'FAIL: '+str(d))
" 2>/dev/null || echo "PARSE_ERROR")
if [[ "$r2" != "OK" ]]; then
fail "Engine probe sample.pdf: wrong result" "$r2"
return
fi

# Probe big.pdf
local r3
r3=$(python3 "$engine" probe "${MEDIA_FIXTURES}/big.pdf" 2>/dev/null | python3 -c "
import json,sys; d=json.load(sys.stdin)
ok = d.get('type')=='probe' and d.get('detected')=='pdf'
print('OK' if ok else 'FAIL: '+str(d))
" 2>/dev/null || echo "PARSE_ERROR")
if [[ "$r3" != "OK" ]]; then
fail "Engine probe big.pdf: wrong result" "$r3"
return
fi

# Probe missing file — capture output into variable to avoid pipefail on engine exit 1
local r4
r4=$(python3 "$engine" probe "/nonexistent/missing.png" 2>/dev/null || true) 
r4=$(printf '%s' "$r4" | python3 -c "
import json,sys
d=json.load(sys.stdin)
ok = d.get('type')=='error' and d.get('code')=='FILE_NOT_FOUND'
print('OK' if ok else 'FAIL: '+str(d))
" 2>/dev/null || echo "PARSE_ERROR")
if [[ "$r4" != "OK" ]]; then
fail "Engine probe missing file: expected FILE_NOT_FOUND error" "$r4"
return
fi

pass "Engine standalone probe: image/pdf/big.pdf/missing all correct"
}

# ============================================================================
# Main
# ============================================================================
main() {
  trap 'teardown' EXIT INT TERM
  echo "======================================"
  echo "  fread Test Suite"
  echo "======================================"
  echo ""

  if [[ ! -x "${FREAD}" ]]; then
    echo -e "${RED}Error: fread not found at ${FREAD}${NC}"
    exit 1
  fi

  setup

  echo "Running tests..."
  echo ""

  echo "== Basic =="
  run_test "Version output" test_version
  run_test "Help output" test_help
  run_test "Self-check" test_self_check
  run_test "Install hints" test_install_hints
  run_test "Nonexistent file" test_nonexistent_file
  run_test "Missing file argument" test_missing_file_arg
  run_test "Invalid output format" test_invalid_output
  run_test "Unknown option" test_unknown_option

  echo ""
  echo "== Single File Read =="
  run_test "Read whole file" test_read_whole_file
  run_test "Default read uncapped" test_default_read_is_uncapped
  run_test "Max lines limit" test_read_with_max_lines
  run_test "Line numbers present" test_line_numbers_present
  run_test "Empty file" test_empty_file
  run_test "Short file" test_short_file
  run_test "Binary file skipped" test_binary_file_skipped
  run_test "Force text on binary" test_force_text_reads_binary
  run_test "File with spaces" test_file_with_spaces
  run_test "Language detection" test_language_detection

  echo ""
  echo "== Line Range =="
  run_test "Basic range" test_line_range_basic
  run_test "Range past EOF" test_line_range_past_eof
  run_test "Single line range" test_line_range_single_line
  run_test "Invalid range format" test_line_range_invalid
  run_test "Head mode" test_head_mode
  run_test "Tail mode" test_tail_mode

  echo ""
  echo "== Around Pattern =="
  run_test "Around finds pattern" test_around_finds_pattern
  run_test "Around before/after" test_around_before_after
  run_test "Pattern not found" test_around_pattern_not_found
  run_test "Around near file start" test_around_near_file_start
  run_test "All matches" test_around_all_matches
  run_test "Around line mode" test_around_line_mode

  echo ""
  echo "== Pipeline / Stdin =="
  run_test "Stdin paths mode" test_stdin_paths_mode
  run_test "Stdin max files cap" test_stdin_max_files_cap
  run_test "Stdin format required" test_stdin_format_required
  run_test "fsearch | fread pipeline" test_stdin_fsearch_pipe
  run_test "Stdin missing files" test_stdin_missing_files

  echo ""
  echo "== Unified Diff =="
  run_test "Diff basic parse" test_diff_basic
  run_test "Diff deleted file" test_diff_deleted_file
  run_test "Diff binary patch" test_diff_binary_patch

  echo ""
  echo "== Output Formats =="
  run_test "JSON structure" test_json_structure
  run_test "JSON parseable" test_json_parseable
  run_test "JSON special chars" test_json_special_chars
  run_test "Pretty headers" test_pretty_has_headers
  run_test "Quiet mode" test_quiet_suppresses_headers
  run_test "Paths output" test_paths_output

  echo ""
  echo "== Symbol Resolution =="
  run_test "Symbol exact single match" test_symbol_exact_single_match
  run_test "Symbol directory scope" test_symbol_directory_scope
  run_test "Symbol file scope is local" test_symbol_file_scope_is_local
  run_test "Symbol Go receiver method" test_symbol_go_receiver_method
  run_test "Symbol ambiguous failure" test_symbol_ambiguous_failure
  run_test "Symbol not found failure" test_symbol_not_found_failure

  echo ""
  echo "== Budget / Truncation =="
  run_test "Max lines truncation" test_max_lines_truncation
  run_test "Max bytes truncation" test_max_bytes_truncation
  run_test "Token budget truncation" test_token_budget_truncation
  run_test "Next hint on truncation" test_next_hint_on_truncation
  run_test "Token estimate present" test_token_estimate_present
  run_test "No truncate override" test_no_truncate_overrides_all_budgets

  echo ""
  echo "== Mode Conflicts =="
  run_test "Conflicting modes rejected" test_conflicting_modes_rejected
  run_test "All-matches without around" test_all_matches_without_around
  run_test "From-stdin with file arg" test_from_stdin_with_file_arg

  echo ""
  echo "== Telemetry =="
  run_test "Telemetry recorded" test_telemetry_recorded
  run_test "Telemetry escapes run_id" test_telemetry_escapes_run_id
  run_test "Project name override" test_telemetry_project_name
  run_test "Flag accumulation" test_telemetry_flags
  run_test "Default flag seeding" test_telemetry_default_flags

echo ""
echo "== Media Reading (Phase 5) =="
run_test "Image pretty no base64" test_media_image_pretty_no_base64
run_test "Image JSON media_payload" test_media_image_json_has_media_payload
run_test "Image meta-only" test_media_image_meta_only
run_test "Image no-resize token refusal" test_media_image_no_resize_token_refusal
run_test "PDF text default" test_media_pdf_text_default
run_test "PDF text JSON" test_media_pdf_text_json
run_test "PDF meta-only" test_media_pdf_meta_only
run_test "PDF render pages" test_media_pdf_render_pages
run_test "PDF render cap" test_media_pdf_render_cap
run_test "PDF invalid pages" test_media_pdf_invalid_pages
run_test "PDF encrypted" test_media_pdf_encrypted
run_test "PDF backend fallback (poppler)" test_media_backend_fallback
run_test "PDF invalid backend" test_media_backend_force_invalid
run_test "No-ingest flag" test_media_no_ingest_flag
run_test "PDF token budget truncation" test_media_pdf_token_budget_truncation
run_test "Engine standalone probe" test_media_python_engine_standalone
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
