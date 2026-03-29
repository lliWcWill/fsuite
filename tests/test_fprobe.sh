#!/usr/bin/env bash
# test_fprobe.sh — TDD tests for fprobe (binary/opaque file reconnaissance)
# Run with: bash test_fprobe.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FPROBE="${SCRIPT_DIR}/../fprobe"
TEST_DIR=""
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

setup() {
  TEST_DIR="$(mktemp -d)"

  # ── Binary-ish test file: mixed printable + NUL bytes ──
  # Simulates a compiled JS bundle inside a SEA binary
  python3 - "${TEST_DIR}" <<'PYEOF'
import sys, os
out_dir = sys.argv[1]
buf = bytearray()
# Some binary junk (simulated ELF header area)
buf += b'\x7fELF' + b'\x00' * 50
# Embedded JS bundle starts here (offset ~54)
buf += b'function renderToolUseMessage(H,$){return Object.entries(H).map(([k,v])=>k+": "+v).join(", ")}'
buf += b'\x00' * 20
buf += b'function userFacingName(){return H.name+" - "+z+" (MCP)"}'
buf += b'\x00' * 20
buf += b'var diffAdded="rgb(105,219,124)",diffRemoved="rgb(255,168,180)"'
buf += b'\x00' * 30
# Another chunk deeper in
buf += b'\x00' * 100
buf += b'class tm8{constructor(H,$,q,K){this.hunk=H;this.filePath=q}render(H,$,q){return[]}}'
buf += b'\x00' * 50
# End padding
buf += b'\x00' * 200
with open(os.path.join(out_dir, 'test.bin'), 'wb') as f:
    f.write(buf)
PYEOF

  # ── Plain text file (fprobe should handle these too) ──
  cat > "${TEST_DIR}/config.json" <<'EOF'
{
  "name": "claude-code",
  "version": "2.1.87",
  "theme": {
    "diffAdded": "rgb(105,219,124)",
    "diffRemoved": "rgb(255,168,180)"
  }
}
EOF

  # ── Large-ish file with repeated patterns ──
  python3 - "${TEST_DIR}" <<'PYEOF'
import sys, os
with open(os.path.join(sys.argv[1], 'repeated.bin'), 'wb') as f:
    for i in range(50):
        f.write(f'function tool_{i}() {{ return {i}; }}\n'.encode())
        f.write(b'\x00' * 10)
PYEOF

  # ── Empty file ──
  touch "${TEST_DIR}/empty.bin"
}

cleanup() {
  [[ -n "${TEST_DIR}" ]] && rm -rf "${TEST_DIR}"
}
trap cleanup EXIT

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
# test_num=$1 reserved for future use
shift
"$@" || true
}

# ============================================================================
# Meta / CLI Tests
# ============================================================================

test_version() {
  local output
  output=$("${FPROBE}" --version 2>&1)
  if [[ "$output" =~ ^fprobe\ [0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    pass "Version output format is correct"
  else
    fail "Version output format incorrect" "Got: $output"
  fi
}

test_help() {
  local output
  output=$("${FPROBE}" --help 2>&1)
  if [[ "$output" == *"strings"* ]] && [[ "$output" == *"scan"* ]] && [[ "$output" == *"window"* ]]; then
    pass "Help documents all three subcommands"
  else
    fail "Help missing subcommand docs" "Got: $output"
  fi
}

test_no_args_shows_usage() {
  local output rc=0
  output=$("${FPROBE}" 2>&1) || rc=$?
  if [[ $rc -ne 0 ]] && [[ "$output" == *"USAGE"* || "$output" == *"usage"* ]]; then
    pass "No args exits non-zero with usage hint"
  else
    fail "No args should show usage and exit non-zero" "rc=$rc, output: $output"
  fi
}

# ============================================================================
# strings subcommand
# ============================================================================

test_strings_basic() {
  local output
  output=$("${FPROBE}" strings "${TEST_DIR}/test.bin" 2>&1)
  if [[ "$output" == *"renderToolUseMessage"* ]] && [[ "$output" == *"userFacingName"* ]]; then
    pass "strings extracts printable strings from binary"
  else
    fail "strings missed expected content" "Got: ${output:0:200}"
  fi
}

test_strings_filter() {
  local output
  output=$("${FPROBE}" strings "${TEST_DIR}/test.bin" --filter "diffAdded" 2>&1)
  if [[ "$output" == *"diffAdded"* ]] && [[ "$output" != *"renderToolUseMessage"* ]]; then
    pass "strings --filter narrows output to matching strings only"
  else
    fail "strings --filter didn't narrow correctly" "Got: ${output:0:200}"
  fi
}

test_strings_filter_no_match() {
  local output rc=0
  output=$("${FPROBE}" strings "${TEST_DIR}/test.bin" --filter "NONEXISTENT_MARKER" 2>&1) || rc=$?
  if [[ -z "$output" ]] || [[ "$output" == *"0 matches"* ]] || [[ "$output" == "[]" ]]; then
    pass "strings --filter with no match returns empty/zero"
  else
    fail "strings --filter should return empty for no match" "Got: $output"
  fi
}

test_strings_json_output() {
  local output
  output=$("${FPROBE}" strings "${TEST_DIR}/test.bin" --filter "diffAdded" -o json 2>&1)
  if [[ "$output" == "["* ]] || [[ "$output" == "{"* ]]; then
    pass "strings -o json returns valid JSON structure"
  else
    fail "strings -o json didn't return JSON" "Got: ${output:0:200}"
  fi
}

test_strings_empty_file() {
  local output rc=0
  output=$("${FPROBE}" strings "${TEST_DIR}/empty.bin" 2>&1) || rc=$?
  if [[ -z "$output" ]] || [[ "$output" == *"0"* ]] || [[ "$output" == "[]" ]]; then
    pass "strings on empty file returns empty cleanly"
  else
    fail "strings on empty file should be empty" "Got: $output"
  fi
}

test_strings_nonexistent_file() {
  local rc=0
  "${FPROBE}" strings "/nonexistent/path" 2>/dev/null || rc=$?
  if [[ $rc -ne 0 ]]; then
    pass "strings on missing file exits non-zero"
  else
    fail "strings should fail on missing file"
  fi
}

# ============================================================================
# scan subcommand
# ============================================================================

test_scan_basic() {
  local output
  output=$("${FPROBE}" scan "${TEST_DIR}/test.bin" --pattern "renderToolUseMessage" 2>&1)
  if [[ "$output" == *"renderToolUseMessage"* ]]; then
    pass "scan finds pattern in binary"
  else
    fail "scan missed pattern" "Got: ${output:0:200}"
  fi
}

test_scan_context() {
  local output
  output=$("${FPROBE}" scan "${TEST_DIR}/test.bin" --pattern "userFacingName" --context 100 2>&1)
  # Should show context around the match, including nearby content
  if [[ "$output" == *"userFacingName"* ]] && [[ "$output" == *"MCP"* ]]; then
    pass "scan --context shows surrounding bytes"
  else
    fail "scan --context didn't show enough context" "Got: ${output:0:300}"
  fi
}

test_scan_multiple_matches() {
  local output
  output=$("${FPROBE}" scan "${TEST_DIR}/repeated.bin" --pattern "function tool_" -o json 2>&1)
  # Count matches from JSON array length
  local count
  count=$(echo "$output" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo 0)
  if [[ $count -gt 5 ]]; then
    pass "scan finds multiple occurrences ($count matches)"
  else
    fail "scan should find many matches in repeated.bin" "Found only $count"
  fi
}

test_scan_ignore_case() {
  local output
  output=$("${FPROBE}" scan "${TEST_DIR}/test.bin" --pattern "RENDERTOOLUSEMESSAGE" --ignore-case 2>&1)
  if [[ "$output" == *"renderToolUseMessage"* ]] || [[ "$output" == *"RENDERTOOLUSEMESSAGE"* ]]; then
    pass "scan --ignore-case finds case-insensitive match"
  else
    fail "scan --ignore-case missed the match" "Got: ${output:0:200}"
  fi
}

test_scan_no_match() {
  local output rc=0
  output=$("${FPROBE}" scan "${TEST_DIR}/test.bin" --pattern "ZZZZZZZ_NEVER_EXISTS" 2>&1) || rc=$?
  if [[ -z "$output" ]] || [[ "$output" == *"0 matches"* ]] || [[ "$output" == "[]" ]]; then
    pass "scan with no match returns empty"
  else
    fail "scan should return empty on no match" "Got: $output"
  fi
}

test_scan_json_output() {
  local output
  output=$("${FPROBE}" scan "${TEST_DIR}/test.bin" --pattern "diffAdded" -o json 2>&1)
  if [[ "$output" == "["* ]] || [[ "$output" == "{"* ]]; then
    pass "scan -o json returns valid JSON"
  else
    fail "scan -o json didn't return JSON" "Got: ${output:0:200}"
  fi
}

test_scan_reports_offset() {
  local output
  output=$("${FPROBE}" scan "${TEST_DIR}/test.bin" --pattern "renderToolUseMessage" -o json 2>&1)
  if [[ "$output" == *"offset"* ]]; then
    pass "scan JSON includes byte offset"
  else
    fail "scan JSON should include offset field" "Got: ${output:0:200}"
  fi
}

# ============================================================================
# window subcommand
# ============================================================================

test_window_basic() {
  local output
  # Read from a known offset area (the ELF header starts at 0)
  output=$("${FPROBE}" window "${TEST_DIR}/test.bin" --offset 54 --after 80 2>&1)
  if [[ "$output" == *"renderToolUseMessage"* ]]; then
    pass "window reads bytes at given offset"
  else
    fail "window missed content at offset 54" "Got: ${output:0:200}"
  fi
}

test_window_before_and_after() {
  local output
  output=$("${FPROBE}" window "${TEST_DIR}/test.bin" --offset 54 --before 10 --after 80 2>&1)
  if [[ -n "$output" ]]; then
    pass "window --before --after returns content"
  else
    fail "window --before --after returned nothing"
  fi
}

test_window_hex_decode() {
  local output
  output=$("${FPROBE}" window "${TEST_DIR}/test.bin" --offset 0 --after 16 --decode hex 2>&1)
  # Hex output should contain hex characters
  if [[ "$output" =~ [0-9a-fA-F]{2} ]]; then
    pass "window --decode hex outputs hex bytes"
  else
    fail "window --decode hex didn't produce hex" "Got: $output"
  fi
}

test_window_printable_decode() {
  local output text
  output=$("${FPROBE}" window "${TEST_DIR}/test.bin" --offset 54 --after 80 --decode printable -o json 2>&1)
  text=$(echo "$output" | python3 -c "import sys,json; sys.stdout.write(json.load(sys.stdin).get('text',''))" 2>/dev/null || echo "")
  # Printable mode: should contain our marker, and no literal NUL bytes in the raw output
  local has_marker=0 has_nul=0
  echo "$text" | grep -q "renderToolUseMessage" && has_marker=1
  printf '%s' "$text" | od -An -tx1 | grep -q ' 00' && has_nul=1
  if [[ $has_marker -eq 1 ]] && [[ $has_nul -eq 0 ]]; then
    pass "window --decode printable replaces NUL with dots"
  else
    fail "window --decode printable still has NUL or missed text" "Got: ${text:0:200}"
  fi
}

test_window_json_output() {
  local output
  output=$("${FPROBE}" window "${TEST_DIR}/test.bin" --offset 54 --after 80 -o json 2>&1)
  if [[ "$output" == "{"* ]] && [[ "$output" == *"offset"* ]]; then
    pass "window -o json returns JSON with offset"
  else
    fail "window -o json didn't return expected JSON" "Got: ${output:0:200}"
  fi
}

test_window_out_of_bounds() {
  local output rc=0
  output=$("${FPROBE}" window "${TEST_DIR}/test.bin" --offset 999999 --after 10 2>&1) || rc=$?
  # Should handle gracefully — empty or error, not crash
  if [[ $rc -eq 0 ]] || [[ "$output" == *"beyond"* ]] || [[ "$output" == *"out of range"* ]]; then
    pass "window handles out-of-bounds offset gracefully"
  else
    fail "window should handle OOB offset" "rc=$rc, output: $output"
  fi
}

test_window_zero_length() {
  local output rc=0
  output=$("${FPROBE}" window "${TEST_DIR}/test.bin" --offset 0 --after 0 2>&1) || rc=$?
  # Should return empty or a minimal result, not crash
  if [[ $rc -eq 0 ]]; then
    pass "window with --after 0 doesn't crash"
  else
    fail "window with zero length shouldn't crash" "rc=$rc"
  fi
}

# ============================================================================
# Cross-cutting concerns
# ============================================================================

test_plain_text_file() {
  local output
  output=$("${FPROBE}" scan "${TEST_DIR}/config.json" --pattern "diffAdded" 2>&1)
  if [[ "$output" == *"diffAdded"* ]]; then
    pass "scan works on plain text files too"
  else
    fail "scan should work on any file, not just binaries"
  fi
}

test_strings_on_text_file() {
  local output
  output=$("${FPROBE}" strings "${TEST_DIR}/config.json" --filter "claude-code" 2>&1)
  if [[ "$output" == *"claude-code"* ]]; then
    pass "strings works on text files"
  else
    fail "strings should work on text files too"
  fi
}

# ============================================================================
# Runner
# ============================================================================

setup

echo "═══════════════════════════════════════════"
echo " fprobe test suite"
echo "═══════════════════════════════════════════"
echo ""

echo "── Meta ──"
run_test 1 test_version
run_test 2 test_help
run_test 3 test_no_args_shows_usage

echo ""
echo "── strings ──"
run_test 4 test_strings_basic
run_test 5 test_strings_filter
run_test 6 test_strings_filter_no_match
run_test 7 test_strings_json_output
run_test 8 test_strings_empty_file
run_test 9 test_strings_nonexistent_file

echo ""
echo "── scan ──"
run_test 10 test_scan_basic
run_test 11 test_scan_context
run_test 12 test_scan_multiple_matches
run_test 13 test_scan_ignore_case
run_test 14 test_scan_no_match
run_test 15 test_scan_json_output
run_test 16 test_scan_reports_offset

echo ""
echo "── window ──"
run_test 17 test_window_basic
run_test 18 test_window_before_and_after
run_test 19 test_window_hex_decode
run_test 20 test_window_printable_decode
run_test 21 test_window_json_output
run_test 22 test_window_out_of_bounds
run_test 23 test_window_zero_length

echo ""
echo "── Cross-cutting ──"
run_test 24 test_plain_text_file
run_test 25 test_strings_on_text_file

echo ""
echo "═══════════════════════════════════════════"
echo " Results: ${TESTS_PASSED}/${TESTS_RUN} passed, ${TESTS_FAILED} failed"
echo "═══════════════════════════════════════════"

[[ $TESTS_FAILED -eq 0 ]] || exit 1
