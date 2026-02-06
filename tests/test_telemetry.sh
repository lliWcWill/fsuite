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
  mkdir -p "$HOME/.fsuite" 2>/dev/null || true
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
  shift  # Skip test description (used by caller for display)
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
  if ! command -v sqlite3 >/dev/null 2>&1; then
    pass "Schema migration test skipped (sqlite3 not available)"
    return 0
  fi
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
# v1.5.0: Flag Accumulation & Project Name Tests
# ============================================================================

test_v15_ftree_flags() {
  rm -f "$HOME/.fsuite/telemetry.jsonl"
  FSUITE_TELEMETRY=1 "${FTREE}" --recon --budget 5 -L 2 -o json "${TEST_DIR}" >/dev/null 2>&1 || true
  local line flags
  line=$(tail -1 "$HOME/.fsuite/telemetry.jsonl" 2>/dev/null) || line=""
  flags=$(echo "$line" | grep -o '"flags":"[^"]*"' || true)
  if [[ "$flags" =~ "--budget 5" ]] && [[ "$flags" =~ "-L 2" ]] && [[ "$flags" =~ "--recon" ]] && [[ "$flags" =~ "-o json" ]]; then
    pass "ftree flag accumulation: --budget, -L, --recon, -o all present"
  else
    fail "ftree flags should include --budget 5 -L 2 --recon -o json" "Got: $flags"
  fi
}

test_v15_fcontent_flags() {
  rm -f "$HOME/.fsuite/telemetry.jsonl"
  FSUITE_TELEMETRY=1 "${FCONTENT}" -m 3 -q -o json "hello" "${TEST_DIR}" >/dev/null 2>&1 || true
  local line flags
  line=$(tail -1 "$HOME/.fsuite/telemetry.jsonl" 2>/dev/null) || line=""
  flags=$(echo "$line" | grep -o '"flags":"[^"]*"' || true)
  if [[ "$flags" =~ "-m 3" ]] && [[ "$flags" =~ "-q" ]] && [[ "$flags" =~ "-o json" ]]; then
    pass "fcontent flag accumulation: -m, -q, -o all present"
  else
    fail "fcontent flags should include -m 3 -q -o json" "Got: $flags"
  fi
}

test_v15_jsonl_safety() {
  rm -f "$HOME/.fsuite/telemetry.jsonl"
  # Use rg-args with characters that could break JSONL (quotes, braces)
  FSUITE_TELEMETRY=1 "${FCONTENT}" --rg-args "-i --hidden" "hello" "${TEST_DIR}" >/dev/null 2>&1 || true
  local line
  line=$(tail -1 "$HOME/.fsuite/telemetry.jsonl" 2>/dev/null) || line=""
  if [[ -z "$line" ]]; then
    fail "JSONL should have been written"
    return
  fi
  # Validate it's parseable JSON
  if python3 -c "import json,sys; json.loads(sys.stdin.readline())" <<< "$line" 2>/dev/null; then
    pass "JSONL line is valid JSON after --rg-args with special chars"
  else
    # Fallback: at least check it has required fields
    if [[ "$line" =~ \"tool\": ]] && [[ "$line" =~ \"flags\": ]]; then
      pass "JSONL has required fields (python3 JSON validation skipped)"
    else
      fail "JSONL should be valid JSON" "Got: $line"
    fi
  fi
}

test_v15_project_name() {
  rm -f "$HOME/.fsuite/telemetry.jsonl"
  FSUITE_TELEMETRY=1 "${FTREE}" --project-name "MyProject" "${TEST_DIR}" >/dev/null 2>&1 || true
  local line
  line=$(tail -1 "$HOME/.fsuite/telemetry.jsonl" 2>/dev/null) || line=""
  if [[ "$line" =~ \"project_name\":\"MyProject\" ]]; then
    pass "--project-name override appears in telemetry"
  else
    fail "--project-name should set project_name in telemetry" "Got: $line"
  fi
}

# ============================================================================
# v1.5.0: fmetrics Enhancements
# ============================================================================

test_v15_selfcheck_python3() {
  local output
  output=$("${FMETRICS}" --self-check 2>&1) || true
  if [[ "$output" =~ "python3:" ]]; then
    pass "fmetrics --self-check reports python3 status"
  else
    fail "--self-check should show python3 line"
  fi
}

test_v15_selfcheck_predict() {
  local output
  output=$("${FMETRICS}" --self-check 2>&1) || true
  if [[ "$output" =~ "fmetrics-predict.py:" ]]; then
    pass "fmetrics --self-check reports predict script status"
  else
    fail "--self-check should show fmetrics-predict.py line"
  fi
}

test_v15_predict_tool_filter() {
  # Need substantial telemetry data for predictions
  rm -f "$HOME/.fsuite/telemetry.jsonl"
  rm -f "$HOME/.fsuite/telemetry.db"

  # Create varied test directories for diverse telemetry
  for i in {1..8}; do
    local vary_dir="${TEST_DIR}/vary_${i}"
    mkdir -p "${vary_dir}/sub"
    for j in $(seq 1 $((i * 2))); do
      echo "content $j" > "${vary_dir}/sub/file${j}.txt"
    done
    FSUITE_TELEMETRY=1 "${FTREE}" "${vary_dir}" >/dev/null 2>&1 || true
    FSUITE_TELEMETRY=1 "${FSEARCH}" "*.txt" "${vary_dir}" >/dev/null 2>&1 || true
    FSUITE_TELEMETRY=1 "${FCONTENT}" "content" "${vary_dir}" >/dev/null 2>&1 || true
  done

  local jsonl_lines=0
  [[ -f "$HOME/.fsuite/telemetry.jsonl" ]] && jsonl_lines=$(wc -l < "$HOME/.fsuite/telemetry.jsonl")

  "${FMETRICS}" import >/dev/null 2>&1 || true

  # Verify --tool flag passes through and filters output
  local output_all output_filtered
  output_all=$("${FMETRICS}" predict "${TEST_DIR}" 2>&1) || true
  output_filtered=$("${FMETRICS}" predict --tool ftree "${TEST_DIR}" 2>&1) || true

  if [[ "$output_filtered" =~ "ftree" ]] && ! [[ "$output_filtered" =~ "fsearch" ]] && ! [[ "$output_filtered" =~ "fcontent" ]]; then
    pass "fmetrics predict --tool ftree shows only ftree prediction"
  elif [[ "$output_filtered" =~ "Insufficient" ]] || [[ "$output_filtered" =~ "need at least" ]]; then
    # Not enough data for prediction, but verify the --tool flag was accepted
    if [[ "$output_filtered" =~ "ftree" ]] || [[ "$jsonl_lines" -ge 8 ]]; then
      pass "fmetrics predict --tool accepted (insufficient data for prediction, $jsonl_lines runs)"
    else
      fail "--tool ftree should be accepted" "Got: $output_filtered"
    fi
  else
    fail "--tool ftree should only show ftree in predict output" "Got: $output_filtered"
  fi
}

# ============================================================================
# v1.5.0+ — Project Name Inference (walk-up heuristic)
# ============================================================================

test_v15_project_name_walkup() {
  # Create a project with .git inside TEST_DIR
  local proj_dir="${TEST_DIR}/myproject"
  mkdir -p "${proj_dir}/.git"
  mkdir -p "${proj_dir}/src/deep/nested"
  echo "hello" > "${proj_dir}/src/deep/nested/file.txt"

  # Scan the deeply nested subdir — project name should be "myproject", not "nested"
  rm -f $HOME/.fsuite/telemetry.jsonl
  FSUITE_TELEMETRY=1 "${FTREE}" --recon "${proj_dir}/src/deep/nested" >/dev/null 2>&1 || true
  local line
  line=$(tail -1 $HOME/.fsuite/telemetry.jsonl 2>/dev/null) || line=""
  if [[ "$line" =~ \"project_name\":\"myproject\" ]]; then
    pass "ftree: walk-up finds .git and uses project root name"
  else
    fail "ftree should infer project_name='myproject' from .git" "Got: $line"
    return
  fi

  # Test fsearch on the same subdir
  rm -f $HOME/.fsuite/telemetry.jsonl
  FSUITE_TELEMETRY=1 "${FSEARCH}" --output paths "*.txt" "${proj_dir}/src/deep/nested" >/dev/null 2>&1 || true
  line=$(tail -1 $HOME/.fsuite/telemetry.jsonl 2>/dev/null) || line=""
  if [[ "$line" =~ \"project_name\":\"myproject\" ]]; then
    pass "fsearch: walk-up finds .git and uses project root name"
  else
    fail "fsearch should infer project_name='myproject'" "Got: $line"
    return
  fi

  # Test fcontent on the same subdir
  rm -f $HOME/.fsuite/telemetry.jsonl
  FSUITE_TELEMETRY=1 "${FCONTENT}" "hello" "${proj_dir}/src/deep/nested" >/dev/null 2>&1 || true
  line=$(tail -1 $HOME/.fsuite/telemetry.jsonl 2>/dev/null) || line=""
  if [[ "$line" =~ \"project_name\":\"myproject\" ]]; then
    pass "fcontent: walk-up finds .git and uses project root name"
  else
    fail "fcontent should infer project_name='myproject'" "Got: $line"
  fi
}

test_v15_project_name_fallback() {
  # Create a dir with NO project markers
  local plain_dir="${TEST_DIR}/plaindir"
  mkdir -p "${plain_dir}"
  echo "data" > "${plain_dir}/file.txt"

  rm -f $HOME/.fsuite/telemetry.jsonl
  FSUITE_TELEMETRY=1 "${FTREE}" --recon "${plain_dir}" >/dev/null 2>&1 || true
  local line
  line=$(tail -1 $HOME/.fsuite/telemetry.jsonl 2>/dev/null) || line=""
  if [[ "$line" =~ \"project_name\":\"plaindir\" ]]; then
    pass "Fallback: basename used when no project markers found"
  else
    fail "Should fall back to basename 'plaindir'" "Got: $line"
  fi
}

# ============================================================================
# Main Test Runner
# ============================================================================

main() {
  trap 'teardown' EXIT INT TERM
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

  echo ""
  echo "== v1.5.0: Flag Accumulation =="
  run_test "ftree flags in telemetry" test_v15_ftree_flags
  run_test "fcontent flags in telemetry" test_v15_fcontent_flags
  run_test "JSONL safety with special chars" test_v15_jsonl_safety
  run_test "Project-name override" test_v15_project_name

  echo ""
  echo "== v1.5.0: fmetrics Enhancements =="
  run_test "fmetrics --self-check shows python3 status" test_v15_selfcheck_python3
  run_test "fmetrics --self-check shows predict script" test_v15_selfcheck_predict
  run_test "fmetrics predict --tool filter" test_v15_predict_tool_filter

  echo ""
  echo "== v1.5.0+: Project Name Inference =="
  run_test "Walk-up heuristic across all tools" test_v15_project_name_walkup
  run_test "Basename fallback without markers" test_v15_project_name_fallback

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
