#!/usr/bin/env bash
# test_telemetry.sh — tests for fsuite telemetry system
# Run with: bash test_telemetry.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FSUITE_DIR="${SCRIPT_DIR}/.."
FCONTENT="${FSUITE_DIR}/fcontent"
FSEARCH="${FSUITE_DIR}/fsearch"
FTREE="${FSUITE_DIR}/ftree"
FMETRICS="${FSUITE_DIR}/fmetrics"

TEST_DIR=""
BACKUP_TELEMETRY=""
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

setup() {
  TEST_DIR="$(mktemp -d)"
  mkdir -p "${TEST_DIR}/src"
  echo "hello world" > "${TEST_DIR}/src/test.txt"
  echo "function foo() { return 1; }" > "${TEST_DIR}/src/code.js"
  dd if=/dev/zero of="${TEST_DIR}/large_file.bin" bs=1024 count=50 2>/dev/null

  # Backup existing telemetry
  if [[ -f "$HOME/.fsuite/telemetry.jsonl" ]]; then
    BACKUP_TELEMETRY="$(mktemp)"
    cp "$HOME/.fsuite/telemetry.jsonl" "$BACKUP_TELEMETRY"
  fi

  # Clear telemetry for clean tests
  rm -f "$HOME/.fsuite/telemetry.jsonl"
  rm -f "$HOME/.fsuite/telemetry.db"
  rm -f "$HOME/.fsuite/machine_profile.json"
}

teardown() {
  if [[ -n "${TEST_DIR}" && -d "${TEST_DIR}" ]]; then
    rm -rf "${TEST_DIR}"
  fi

  # Restore telemetry backup
  if [[ -n "$BACKUP_TELEMETRY" && -f "$BACKUP_TELEMETRY" ]]; then
    mv "$BACKUP_TELEMETRY" "$HOME/.fsuite/telemetry.jsonl"
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
  local test_name="$1"
  shift
  "$@" || true
}

# ============================================================================
# bytes_scanned Tests (Phase 1)
# ============================================================================

test_fcontent_bytes_scanned() {
  rm -f "$HOME/.fsuite/telemetry.jsonl"
  FSUITE_TELEMETRY=1 "${FCONTENT}" "hello" "${TEST_DIR}" >/dev/null 2>&1 || true
  local bytes
  bytes=$(tail -1 "$HOME/.fsuite/telemetry.jsonl" 2>/dev/null | grep -o '"bytes_scanned":[0-9]*' | cut -d: -f2)
  if [[ "$bytes" =~ ^[0-9]+$ ]] && (( bytes > 0 )); then
    pass "fcontent records bytes_scanned > 0"
  else
    fail "fcontent bytes_scanned should be > 0" "Got: $bytes"
  fi
}

test_fsearch_bytes_scanned() {
  rm -f "$HOME/.fsuite/telemetry.jsonl"
  FSUITE_TELEMETRY=1 "${FSEARCH}" "*.txt" "${TEST_DIR}" >/dev/null 2>&1 || true
  local bytes
  bytes=$(tail -1 "$HOME/.fsuite/telemetry.jsonl" 2>/dev/null | grep -o '"bytes_scanned":[0-9]*' | cut -d: -f2)
  if [[ "$bytes" =~ ^[0-9]+$ ]] && (( bytes > 0 )); then
    pass "fsearch records bytes_scanned > 0"
  else
    fail "fsearch bytes_scanned should be > 0" "Got: $bytes"
  fi
}

test_ftree_bytes_scanned() {
  rm -f "$HOME/.fsuite/telemetry.jsonl"
  FSUITE_TELEMETRY=1 "${FTREE}" "${TEST_DIR}" >/dev/null 2>&1 || true
  local bytes
  bytes=$(tail -1 "$HOME/.fsuite/telemetry.jsonl" 2>/dev/null | grep -o '"bytes_scanned":[0-9]*' | cut -d: -f2)
  if [[ "$bytes" =~ ^[0-9]+$ ]] && (( bytes > 0 )); then
    pass "ftree records bytes_scanned > 0"
  else
    fail "ftree bytes_scanned should be > 0" "Got: $bytes"
  fi
}

test_fcontent_stdin_mode_bytes_minus1() {
  rm -f "$HOME/.fsuite/telemetry.jsonl"
  echo "${TEST_DIR}/src/test.txt" | FSUITE_TELEMETRY=1 "${FCONTENT}" "hello" >/dev/null 2>&1 || true
  local bytes
  bytes=$(tail -1 "$HOME/.fsuite/telemetry.jsonl" 2>/dev/null | grep -o '"bytes_scanned":-*[0-9]*' | cut -d: -f2)
  if [[ "$bytes" == "-1" ]]; then
    pass "fcontent stdin mode keeps bytes_scanned = -1"
  else
    fail "fcontent stdin mode should have bytes_scanned = -1" "Got: $bytes"
  fi
}

# ============================================================================
# Tier 0 Tests (Disabled Telemetry)
# ============================================================================

test_tier0_no_telemetry() {
  rm -f "$HOME/.fsuite/telemetry.jsonl"
  local before=0
  [[ -f "$HOME/.fsuite/telemetry.jsonl" ]] && before=$(wc -l < "$HOME/.fsuite/telemetry.jsonl")

  FSUITE_TELEMETRY=0 "${FTREE}" "${TEST_DIR}" >/dev/null 2>&1 || true
  FSUITE_TELEMETRY=0 "${FSEARCH}" "*.txt" "${TEST_DIR}" >/dev/null 2>&1 || true
  FSUITE_TELEMETRY=0 "${FCONTENT}" "hello" "${TEST_DIR}" >/dev/null 2>&1 || true

  local after=0
  [[ -f "$HOME/.fsuite/telemetry.jsonl" ]] && after=$(wc -l < "$HOME/.fsuite/telemetry.jsonl")

  if (( after == before )); then
    pass "Tier 0 produces no telemetry"
  else
    fail "Tier 0 should not produce telemetry" "Lines before=$before, after=$after"
  fi
}

# ============================================================================
# Tier 2 Tests (Hardware Telemetry)
# ============================================================================

test_tier2_hardware_fields() {
  rm -f "$HOME/.fsuite/telemetry.jsonl"
  FSUITE_TELEMETRY=2 "${FTREE}" "${TEST_DIR}" >/dev/null 2>&1 || true
  local line
  line=$(tail -1 "$HOME/.fsuite/telemetry.jsonl" 2>/dev/null)

  local has_cpu has_ram has_load
  has_cpu=$(echo "$line" | grep -o '"cpu_temp_mc"' || true)
  has_ram=$(echo "$line" | grep -o '"ram_total_kb"' || true)
  has_load=$(echo "$line" | grep -o '"load_avg_1m"' || true)

  if [[ -n "$has_cpu" ]] && [[ -n "$has_ram" ]] && [[ -n "$has_load" ]]; then
    pass "Tier 2 includes hardware telemetry fields"
  else
    fail "Tier 2 should include cpu_temp_mc, ram_total_kb, load_avg_1m"
  fi
}

test_tier1_no_hardware_fields() {
  rm -f "$HOME/.fsuite/telemetry.jsonl"
  FSUITE_TELEMETRY=1 "${FTREE}" "${TEST_DIR}" >/dev/null 2>&1 || true
  local line
  line=$(tail -1 "$HOME/.fsuite/telemetry.jsonl" 2>/dev/null)

  local has_cpu
  has_cpu=$(echo "$line" | grep -o '"cpu_temp_mc"' || true)

  if [[ -z "$has_cpu" ]]; then
    pass "Tier 1 does not include hardware fields"
  else
    fail "Tier 1 should not include cpu_temp_mc"
  fi
}

test_tier2_filesystem_storage_fields() {
  rm -f "$HOME/.fsuite/telemetry.jsonl"
  FSUITE_TELEMETRY=2 "${FTREE}" "${TEST_DIR}" >/dev/null 2>&1 || true
  local line
  line=$(tail -1 "$HOME/.fsuite/telemetry.jsonl" 2>/dev/null)

  local has_fs has_st
  has_fs=$(echo "$line" | grep -o '"filesystem_type"' || true)
  has_st=$(echo "$line" | grep -o '"storage_type"' || true)

  if [[ -n "$has_fs" ]] && [[ -n "$has_st" ]]; then
    pass "Tier 2 includes filesystem_type and storage_type fields"
  else
    fail "Tier 2 should include filesystem_type and storage_type"
  fi
}

test_filesystem_type_not_unknown() {
  rm -f "$HOME/.fsuite/telemetry.jsonl"
  FSUITE_TELEMETRY=2 "${FTREE}" "${TEST_DIR}" >/dev/null 2>&1 || true
  local line fs_type
  line=$(tail -1 "$HOME/.fsuite/telemetry.jsonl" 2>/dev/null)
  fs_type=$(echo "$line" | grep -oE '"filesystem_type":"[^"]+"' | cut -d'"' -f4)

  if [[ -n "$fs_type" ]] && [[ "$fs_type" != "unknown" ]]; then
    pass "Filesystem type detected: $fs_type"
  else
    fail "Filesystem type should not be unknown for valid path"
  fi
}

test_storage_type_not_unknown() {
  rm -f "$HOME/.fsuite/telemetry.jsonl"
  FSUITE_TELEMETRY=2 "${FTREE}" "${TEST_DIR}" >/dev/null 2>&1 || true
  local line st_type
  line=$(tail -1 "$HOME/.fsuite/telemetry.jsonl" 2>/dev/null)
  st_type=$(echo "$line" | grep -oE '"storage_type":"[^"]+"' | cut -d'"' -f4)

  if [[ -n "$st_type" ]] && [[ "$st_type" != "unknown" ]]; then
    pass "Storage type detected: $st_type"
  else
    fail "Storage type should not be unknown for valid path"
  fi
}

# ============================================================================
# Tier 3 Tests (Machine Profile)
# ============================================================================

test_tier3_machine_profile() {
  rm -f "$HOME/.fsuite/machine_profile.json"
  FSUITE_TELEMETRY=3 "${FSEARCH}" "*.txt" "${TEST_DIR}" >/dev/null 2>&1 || true

  if [[ -f "$HOME/.fsuite/machine_profile.json" ]]; then
    local has_os has_cpu_model
    has_os=$(grep -o '"os"' "$HOME/.fsuite/machine_profile.json" || true)
    has_cpu_model=$(grep -o '"cpu_model"' "$HOME/.fsuite/machine_profile.json" || true)
    if [[ -n "$has_os" ]] && [[ -n "$has_cpu_model" ]]; then
      pass "Tier 3 generates machine profile with expected fields"
    else
      fail "Machine profile missing os or cpu_model"
    fi
  else
    fail "Tier 3 should generate machine_profile.json"
  fi
}

# ============================================================================
# Schema Migration Tests
# ============================================================================

test_schema_migration_idempotent() {
  rm -f "$HOME/.fsuite/telemetry.db"
  # Run fmetrics import twice (which runs ensure_db twice)
  FSUITE_TELEMETRY=1 "${FTREE}" "${TEST_DIR}" >/dev/null 2>&1 || true
  "${FMETRICS}" import >/dev/null 2>&1 || true
  "${FMETRICS}" import >/dev/null 2>&1 || true

  # Check that db exists and has the new columns
  local cols
  cols=$(sqlite3 "$HOME/.fsuite/telemetry.db" "SELECT sql FROM sqlite_master WHERE name='telemetry';" 2>/dev/null || true)

  if [[ "$cols" == *"cpu_temp_mc"* ]] && [[ "$cols" == *"load_avg_1m"* ]]; then
    pass "Schema migration is idempotent"
  else
    fail "Schema should have hardware columns after migration" "Got: $cols"
  fi
}

# ============================================================================
# Metacharacter Warning Tests (Phase 3)
# ============================================================================

test_metachar_warning_parens() {
  local output
  output=$("${FCONTENT}" "foo(bar)" "${TEST_DIR}" 2>&1)
  if [[ "$output" == *"regex metacharacters"* ]]; then
    pass "Metacharacter warning fires on ()"
  else
    fail "Should warn about metacharacters in foo(bar)"
  fi
}

test_metachar_warning_brackets() {
  local output
  output=$("${FCONTENT}" "test[0]" "${TEST_DIR}" 2>&1)
  if [[ "$output" == *"regex metacharacters"* ]]; then
    pass "Metacharacter warning fires on []"
  else
    fail "Should warn about metacharacters in test[0]"
  fi
}

test_metachar_warning_suppressed_with_F() {
  local output
  output=$("${FCONTENT}" "foo(bar)" "${TEST_DIR}" --rg-args "-F" 2>&1)
  if [[ "$output" != *"regex metacharacters"* ]]; then
    pass "Metacharacter warning suppressed with -F"
  else
    fail "Warning should be suppressed when -F is used"
  fi
}

test_metachar_warning_json_field() {
  local output
  output=$("${FCONTENT}" "foo(bar)" "${TEST_DIR}" -o json 2>&1)
  if [[ "$output" == *'"warning":'* ]]; then
    pass "JSON output includes warning field"
  else
    fail "JSON should have warning field for metacharacter query"
  fi
}

test_no_metachar_no_warning() {
  local output
  output=$("${FCONTENT}" "hello" "${TEST_DIR}" 2>&1)
  if [[ "$output" != *"regex metacharacters"* ]]; then
    pass "No warning for plain text query"
  else
    fail "Plain text query should not trigger warning"
  fi
}

# ============================================================================
# Graceful Degradation Tests
# ============================================================================

test_graceful_without_common_lib() {
  # Temporarily rename the common lib
  local lib="${FSUITE_DIR}/_fsuite_common.sh"
  if [[ -f "$lib" ]]; then
    mv "$lib" "${lib}.bak"
    # Trap to restore lib on any exit (including abort)
    trap 'mv "${lib}.bak" "$lib" 2>/dev/null || true' RETURN

    rm -f "$HOME/.fsuite/telemetry.jsonl"

    FSUITE_TELEMETRY=1 "${FTREE}" "${TEST_DIR}" >/dev/null 2>&1 || true

    mv "${lib}.bak" "$lib"
    trap - RETURN  # Clear trap after successful restore

    if [[ -f "$HOME/.fsuite/telemetry.jsonl" ]]; then
      local bytes
      bytes=$(tail -1 "$HOME/.fsuite/telemetry.jsonl" 2>/dev/null | grep -o '"bytes_scanned"' || true)
      if [[ -n "$bytes" ]]; then
        pass "Tools work without _fsuite_common.sh (graceful degradation)"
      else
        fail "Tier 1 telemetry should still work without common lib"
      fi
    else
      fail "Telemetry should still be recorded without common lib"
    fi
  else
    pass "Common lib test skipped (lib not found)"
  fi
}

test_non_numeric_telemetry_env() {
  rm -f "$HOME/.fsuite/telemetry.jsonl"
  FSUITE_TELEMETRY=invalid "${FTREE}" "${TEST_DIR}" >/dev/null 2>&1 || true

  if [[ -f "$HOME/.fsuite/telemetry.jsonl" ]]; then
    pass "Non-numeric FSUITE_TELEMETRY defaults to tier 1"
  else
    fail "Should default to tier 1 for non-numeric env value"
  fi
}

# ============================================================================
# Main Test Runner
# ============================================================================

main() {
  echo "======================================"
  echo "  fsuite Telemetry Test Suite"
  echo "======================================"
  echo ""

  # Check dependencies
  if [[ ! -x "${FTREE}" ]]; then
    echo -e "${RED}Error: ftree not found at ${FTREE}${NC}"
    exit 1
  fi

  setup

  echo "Running tests..."
  echo ""

  # bytes_scanned tests
  echo "== Phase 1: bytes_scanned =="
  run_test "fcontent bytes_scanned > 0" test_fcontent_bytes_scanned
  run_test "fsearch bytes_scanned > 0" test_fsearch_bytes_scanned
  run_test "ftree bytes_scanned > 0" test_ftree_bytes_scanned
  run_test "fcontent stdin mode bytes = -1" test_fcontent_stdin_mode_bytes_minus1

  # Tier tests
  echo ""
  echo "== Tier 0 (Disabled) =="
  run_test "Tier 0 produces no telemetry" test_tier0_no_telemetry

  echo ""
  echo "== Tier 2 (Hardware) =="
  run_test "Tier 2 includes hardware fields" test_tier2_hardware_fields
  run_test "Tier 1 excludes hardware fields" test_tier1_no_hardware_fields

  echo ""
  echo "== Filesystem & Storage Detection =="
  run_test "Tier 2 includes fs/storage fields" test_tier2_filesystem_storage_fields
  run_test "Filesystem type detected" test_filesystem_type_not_unknown
  run_test "Storage type detected" test_storage_type_not_unknown

  echo ""
  echo "== Tier 3 (Machine Profile) =="
  run_test "Tier 3 generates machine profile" test_tier3_machine_profile

  echo ""
  echo "== Schema Migration =="
  run_test "Schema migration is idempotent" test_schema_migration_idempotent

  echo ""
  echo "== Metacharacter Warning =="
  run_test "Warning on parentheses" test_metachar_warning_parens
  run_test "Warning on brackets" test_metachar_warning_brackets
  run_test "Warning suppressed with -F" test_metachar_warning_suppressed_with_F
  run_test "JSON includes warning field" test_metachar_warning_json_field
  run_test "No warning for plain text" test_no_metachar_no_warning

  echo ""
  echo "== Graceful Degradation =="
  run_test "Works without _fsuite_common.sh" test_graceful_without_common_lib
  run_test "Non-numeric FSUITE_TELEMETRY handled" test_non_numeric_telemetry_env

  teardown

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
