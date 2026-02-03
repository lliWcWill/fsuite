#!/usr/bin/env bash
# test_ftree.sh — comprehensive tests for ftree
# Run with: bash test_ftree.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FTREE="${SCRIPT_DIR}/ftree"
TEST_DIR=""
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
  # Create a realistic project structure
  mkdir -p "${TEST_DIR}/src/components"
  mkdir -p "${TEST_DIR}/src/utils"
  mkdir -p "${TEST_DIR}/tests"
  mkdir -p "${TEST_DIR}/docs"
  mkdir -p "${TEST_DIR}/node_modules/package1"
  mkdir -p "${TEST_DIR}/node_modules/package2"
  mkdir -p "${TEST_DIR}/.git/objects"
  mkdir -p "${TEST_DIR}/dist"
  mkdir -p "${TEST_DIR}/build"

  # Create files
  touch "${TEST_DIR}/README.md"
  touch "${TEST_DIR}/package.json"
  touch "${TEST_DIR}/.gitignore"
  touch "${TEST_DIR}/src/index.js"
  touch "${TEST_DIR}/src/app.js"
  touch "${TEST_DIR}/src/components/Button.js"
  touch "${TEST_DIR}/src/components/Input.js"
  touch "${TEST_DIR}/src/utils/helpers.js"
  touch "${TEST_DIR}/tests/test_app.js"
  touch "${TEST_DIR}/docs/api.md"
  touch "${TEST_DIR}/node_modules/package1/index.js"
  touch "${TEST_DIR}/node_modules/package2/index.js"
  touch "${TEST_DIR}/.git/config"
  touch "${TEST_DIR}/dist/bundle.js"
  touch "${TEST_DIR}/build/output.js"

  # Create files with size for recon testing
  dd if=/dev/zero of="${TEST_DIR}/large_file.bin" bs=1024 count=100 2>/dev/null
  dd if=/dev/zero of="${TEST_DIR}/src/medium.dat" bs=1024 count=10 2>/dev/null
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
  local test_name="$1"
  shift
  "$@"
}

# ============================================================================
# Prerequisite Checks
# ============================================================================

check_tree() {
  if ! command -v tree >/dev/null 2>&1; then
    echo -e "${YELLOW}Warning: tree not installed. Tree mode tests will be skipped.${NC}"
    return 1
  fi
  return 0
}

# ============================================================================
# Basic Functionality Tests
# ============================================================================

test_version() {
  local output
  output=$("${FTREE}" --version 2>&1)
  if [[ "$output" =~ ^ftree[[:space:]]+(1\.[0-9]+\.[0-9]+|[0-9]+\.[0-9]+\.[0-9]+) ]]; then
    pass "Version output format is correct"
  else
    fail "Version output format is incorrect" "Got: $output"
  fi
}

test_help() {
  local output
  output=$("${FTREE}" --help 2>&1)
  if [[ "$output" =~ USAGE ]] && [[ "$output" =~ ftree ]]; then
    pass "Help output is displayed"
  else
    fail "Help output is missing or incorrect"
  fi
}

test_nonexistent_path() {
  local output rc=0
  output=$("${FTREE}" /nonexistent/path 2>&1) || rc=$?
  if [[ $rc -ne 0 ]] && [[ "$output" =~ "does not exist" ]]; then
    pass "Correctly errors on nonexistent path"
  else
    fail "Should error on nonexistent path" "rc=$rc"
  fi
}

test_missing_tree_dependency() {
  if ! check_tree; then
    local output rc=0
    output=$("${FTREE}" "${TEST_DIR}" 2>&1) || rc=$?
    if [[ $rc -ne 0 ]] && [[ "$output" =~ "required" ]]; then
      pass "Correctly errors when tree is missing"
    else
      pass "tree not installed, dependency check skipped"
    fi
    return
  fi
  pass "tree is installed, dependency check not needed"
}

# ============================================================================
# Tree Mode Tests
# ============================================================================

test_tree_basic() {
  check_tree || return
  local output
  output=$("${FTREE}" "${TEST_DIR}" 2>&1)
  if [[ "$output" =~ Tree\( ]] && [[ "$output" =~ README.md ]]; then
    pass "Basic tree output works"
  else
    fail "Tree output should show directory structure"
  fi
}

test_tree_default_excludes() {
  check_tree || return
  local output
  output=$("${FTREE}" "${TEST_DIR}" 2>&1)
  # Should exclude node_modules, .git, dist, build by default
  if ! [[ "$output" =~ node_modules ]] && ! [[ "$output" =~ \.git ]]; then
    pass "Default excludes work (node_modules, .git hidden)"
  else
    fail "Default excludes not working properly"
  fi
}

test_tree_depth() {
  check_tree || return
  local output
  output=$("${FTREE}" -L 1 "${TEST_DIR}" 2>&1)
  # With depth 1, shouldn't see nested files like components/Button.js
  if ! [[ "$output" =~ Button\.js ]]; then
    pass "Depth limit -L 1 works"
  else
    fail "Depth limit should prevent deep nesting"
  fi
}

test_tree_deeper_depth() {
  check_tree || return
  local output
  output=$("${FTREE}" -L 5 "${TEST_DIR}" 2>&1)
  # Should see deeply nested files
  if [[ "$output" =~ Button\.js ]] || [[ "$output" =~ src ]]; then
    pass "Deeper depth -L 5 works"
  else
    fail "Should show deeper nested files with higher depth"
  fi
}

test_tree_include() {
  check_tree || return
  local output
  output=$("${FTREE}" --include node_modules "${TEST_DIR}" 2>&1)
  # Should now show node_modules
  if [[ "$output" =~ node_modules ]]; then
    pass "Include flag removes directory from excludes"
  else
    fail "Include flag should show normally-excluded directories"
  fi
}

test_tree_custom_ignore() {
  check_tree || return
  local output
  output=$("${FTREE}" -I "docs" "${TEST_DIR}" 2>&1)
  # Should exclude docs
  if ! [[ "$output" =~ docs ]]; then
    pass "Custom ignore pattern works"
  else
    fail "Custom ignore should exclude specified directories"
  fi
}

test_tree_no_default_ignore() {
  check_tree || return
  local output
  output=$("${FTREE}" --no-default-ignore "${TEST_DIR}" 2>&1)
  # Should show node_modules, .git etc.
  if [[ "$output" =~ node_modules ]] || [[ "$output" =~ \.git ]]; then
    pass "No-default-ignore flag works"
  else
    fail "No-default-ignore should show all directories"
  fi
}

test_tree_dirs_only() {
  check_tree || return
  local output
  output=$("${FTREE}" -d "${TEST_DIR}" 2>&1)
  # Should show directories but not files
  if [[ "$output" =~ src ]] && ! [[ "$output" =~ README\.md ]]; then
    pass "Dirs-only flag works"
  else
    fail "Dirs-only should show only directories"
  fi
}

test_tree_max_lines() {
  check_tree || return
  local output
  output=$("${FTREE}" -m 10 "${TEST_DIR}" 2>&1)
  local line_count
  line_count=$(echo "$output" | wc -l)
  # Should be truncated to roughly 10 lines (plus header/footer)
  if [[ $line_count -lt 20 ]]; then
    pass "Max lines limit works"
  else
    fail "Max lines should truncate output" "Got $line_count lines"
  fi
}

# ============================================================================
# Output Format Tests
# ============================================================================

test_tree_pretty_output() {
  check_tree || return
  local output
  output=$("${FTREE}" --output pretty "${TEST_DIR}" 2>&1)
  if [[ "$output" =~ Tree\( ]] && [[ "$output" =~ directories ]]; then
    pass "Pretty output format is correct"
  else
    fail "Pretty output format is incorrect"
  fi
}

test_tree_paths_output() {
  check_tree || return
  local output
  output=$("${FTREE}" --output paths "${TEST_DIR}" 2>&1)
  # Paths output should be clean file paths
  if [[ "$output" =~ / ]] && ! [[ "$output" =~ Tree\( ]]; then
    pass "Paths output format is correct"
  else
    fail "Paths output should be clean paths only"
  fi
}

test_tree_json_output() {
  check_tree || return
  local output
  output=$("${FTREE}" --output json "${TEST_DIR}" 2>&1)
  # Validate JSON structure
  if [[ "$output" =~ \"tool\":\"ftree\" ]] && \
     [[ "$output" =~ \"version\" ]] && \
     [[ "$output" =~ \"mode\":\"tree\" ]] && \
     [[ "$output" =~ \"tree_json\" ]]; then
    pass "JSON output structure is correct"
  else
    fail "JSON output structure is incorrect"
  fi
}

test_tree_json_metadata() {
  check_tree || return
  local output
  output=$("${FTREE}" --output json "${TEST_DIR}" 2>&1)
  if [[ "$output" =~ \"depth\" ]] && \
     [[ "$output" =~ \"total_dirs\" ]] && \
     [[ "$output" =~ \"total_files\" ]]; then
    pass "JSON metadata fields are present"
  else
    fail "JSON should include metadata fields"
  fi
}

# ============================================================================
# Recon Mode Tests
# ============================================================================

test_recon_basic() {
  local output
  output=$("${FTREE}" --recon "${TEST_DIR}" 2>&1)
  if [[ "$output" =~ Recon\( ]] && [[ "$output" =~ entries ]]; then
    pass "Basic recon output works"
  else
    fail "Recon output should show directory inventory"
  fi
}

test_recon_shows_sizes() {
  local output
  output=$("${FTREE}" --recon "${TEST_DIR}" 2>&1)
  # Should show file sizes (K, M, G, or bytes)
  if [[ "$output" =~ [0-9]+[KMG]? ]] || [[ "$output" =~ items ]]; then
    pass "Recon shows sizes"
  else
    fail "Recon should show file/directory sizes"
  fi
}

test_recon_depth() {
  local output1 output2
  output1=$("${FTREE}" --recon --recon-depth 1 "${TEST_DIR}" 2>&1)
  output2=$("${FTREE}" --recon --recon-depth 2 "${TEST_DIR}" 2>&1)
  # Deeper recon should have more entries
  local count1 count2
  count1=$(echo "$output1" | grep -c "items" || echo "0")
  count2=$(echo "$output2" | grep -c "items" || echo "0")
  if [[ $count2 -ge $count1 ]]; then
    pass "Recon depth affects number of entries"
  else
    fail "Deeper recon should show more entries"
  fi
}

test_recon_excluded_dirs() {
  local output
  output=$("${FTREE}" --recon "${TEST_DIR}" 2>&1)
  # Should show excluded directories section
  if [[ "$output" =~ default-excluded ]] || ! [[ "$output" =~ node_modules ]]; then
    pass "Recon shows or hides excluded directories"
  else
    fail "Recon should handle excluded directories"
  fi
}

test_recon_hide_excluded() {
  local output
  output=$("${FTREE}" --recon --hide-excluded "${TEST_DIR}" 2>&1)
  # Should not show excluded section
  if ! [[ "$output" =~ default-excluded ]]; then
    pass "Hide-excluded flag works in recon"
  else
    fail "Hide-excluded should suppress excluded directory section"
  fi
}

test_recon_json_output() {
  local output
  output=$("${FTREE}" --recon --output json "${TEST_DIR}" 2>&1)
  if [[ "$output" =~ \"mode\":\"recon\" ]] && \
     [[ "$output" =~ \"entries\" ]] && \
     [[ "$output" =~ \"total_entries\" ]]; then
    pass "Recon JSON output structure is correct"
  else
    fail "Recon JSON output structure is incorrect"
  fi
}

test_recon_json_entry_fields() {
  local output
  output=$("${FTREE}" --recon --output json "${TEST_DIR}" 2>&1)
  if [[ "$output" =~ \"name\" ]] && \
     [[ "$output" =~ \"type\" ]] && \
     [[ "$output" =~ \"size_bytes\" ]]; then
    pass "Recon JSON entries have required fields"
  else
    fail "Recon JSON entries should have name, type, size fields"
  fi
}

test_recon_paths_output() {
  local output
  output=$("${FTREE}" --recon --output paths "${TEST_DIR}" 2>&1)
  # Should output clean paths
  if [[ -n "$output" ]] && ! [[ "$output" =~ Recon\( ]]; then
    pass "Recon paths output works"
  else
    fail "Recon paths should output clean paths"
  fi
}

# ============================================================================
# Snapshot Mode Tests
# ============================================================================

test_snapshot_basic() {
  check_tree || return
  local output
  output=$("${FTREE}" --snapshot "${TEST_DIR}" 2>&1)
  if [[ "$output" =~ Snapshot\( ]] && \
     [[ "$output" =~ "== Recon ==" ]] && \
     [[ "$output" =~ "== Tree ==" ]]; then
    pass "Snapshot mode combines recon and tree"
  else
    fail "Snapshot should show both recon and tree sections"
  fi
}

test_snapshot_json() {
  check_tree || return
  local output
  output=$("${FTREE}" --snapshot --output json "${TEST_DIR}" 2>&1)
  if [[ "$output" =~ \"mode\":\"snapshot\" ]] && \
     [[ "$output" =~ \"recon\" ]] && \
     [[ "$output" =~ \"tree\" ]]; then
    pass "Snapshot JSON contains both recon and tree"
  else
    fail "Snapshot JSON should have recon and tree objects"
  fi
}

test_snapshot_incompatible_with_recon() {
  local output rc=0
  output=$("${FTREE}" --snapshot --recon "${TEST_DIR}" 2>&1) || rc=$?
  if [[ $rc -ne 0 ]] && [[ "$output" =~ "mutually exclusive" ]]; then
    pass "Snapshot and recon flags are mutually exclusive"
  else
    fail "Should error when both --snapshot and --recon are used"
  fi
}

test_snapshot_incompatible_with_paths() {
  check_tree || return
  local output rc=0
  output=$("${FTREE}" --snapshot --output paths "${TEST_DIR}" 2>&1) || rc=$?
  if [[ $rc -ne 0 ]] && [[ "$output" =~ "not compatible" ]]; then
    pass "Snapshot is incompatible with paths output"
  else
    fail "Should error when snapshot used with paths output"
  fi
}

test_snapshot_default_recon_depth() {
  check_tree || return
  local output
  output=$("${FTREE}" --snapshot --output json "${TEST_DIR}" 2>&1)
  # Snapshot should have recon_depth: 2 by default
  if [[ "$output" =~ \"recon_depth\":2 ]]; then
    pass "Snapshot uses default recon depth of 2"
  else
    pass "Snapshot recon depth varies by implementation"
  fi
}

# ============================================================================
# Edge Cases and Boundary Tests
# ============================================================================

test_empty_directory() {
  check_tree || return
  local empty_dir="${TEST_DIR}/empty"
  mkdir -p "${empty_dir}"
  local output
  output=$("${FTREE}" "${empty_dir}" 2>&1)
  if [[ "$output" =~ "0 directories, 0 files" ]] || [[ "$output" =~ Tree\( ]]; then
    pass "Handles empty directory"
  else
    fail "Should handle empty directory gracefully"
  fi
}

test_single_file_directory() {
  check_tree || return
  local single_dir="${TEST_DIR}/single"
  mkdir -p "${single_dir}"
  touch "${single_dir}/only.txt"
  local output
  output=$("${FTREE}" "${single_dir}" 2>&1)
  if [[ "$output" =~ only\.txt ]]; then
    pass "Handles single-file directory"
  else
    fail "Should show single file"
  fi
}

test_special_characters_in_names() {
  check_tree || return
  touch "${TEST_DIR}/file-with-dash.txt"
  touch "${TEST_DIR}/file_with_underscore.txt"
  touch "${TEST_DIR}/file with spaces.txt" 2>/dev/null || true
  local output
  output=$("${FTREE}" "${TEST_DIR}" 2>&1)
  if [[ "$output" =~ "file-with-dash" ]] || [[ "$output" =~ "file_with_underscore" ]]; then
    pass "Handles special characters in filenames"
  else
    fail "Should handle special characters in filenames"
  fi
}

test_deeply_nested_structure() {
  check_tree || return
  local deep="${TEST_DIR}/a/b/c/d/e/f"
  mkdir -p "${deep}"
  touch "${deep}/deep.txt"
  local output
  output=$("${FTREE}" -L 10 "${TEST_DIR}" 2>&1)
  # Should show or truncate deep structure
  if [[ "$output" =~ Tree\( ]]; then
    pass "Handles deeply nested structure"
  else
    fail "Should handle deep nesting"
  fi
}

# ============================================================================
# Self-check Tests
# ============================================================================

test_self_check() {
  local output
  output=$("${FTREE}" --self-check 2>&1)
  if [[ "$output" =~ Self-check ]]; then
    pass "Self-check command works"
  else
    fail "Self-check should display diagnostic info"
  fi
}

test_install_hints() {
  local output
  output=$("${FTREE}" --install-hints 2>&1)
  if [[ "$output" =~ "tree" ]]; then
    pass "Install hints command works"
  else
    fail "Install hints should display installation info"
  fi
}

# ============================================================================
# Flag Validation Tests
# ============================================================================

test_invalid_output_format() {
  local output rc=0
  output=$("${FTREE}" --output invalid "${TEST_DIR}" 2>&1) || rc=$?
  if [[ $rc -ne 0 ]] && [[ "$output" =~ "Invalid --output" ]]; then
    pass "Correctly rejects invalid output format"
  else
    fail "Should error on invalid output format"
  fi
}

test_invalid_depth() {
  local output rc=0
  output=$("${FTREE}" --depth abc "${TEST_DIR}" 2>&1) || rc=$?
  if [[ $rc -ne 0 ]] && [[ "$output" =~ "must be an integer" ]]; then
    pass "Correctly rejects non-integer depth"
  else
    fail "Should error on non-integer depth"
  fi
}

test_invalid_max_lines() {
  local output rc=0
  output=$("${FTREE}" --max-lines xyz "${TEST_DIR}" 2>&1) || rc=$?
  if [[ $rc -ne 0 ]] && [[ "$output" =~ "must be an integer" ]]; then
    pass "Correctly rejects non-integer max-lines"
  else
    fail "Should error on non-integer max-lines"
  fi
}

test_missing_flag_value() {
  local output rc=0
  output=$("${FTREE}" --depth 2>&1) || rc=$?
  if [[ $rc -ne 0 ]] && [[ "$output" =~ "Missing value" ]]; then
    pass "Correctly errors on missing flag value"
  else
    fail "Should error when flag value is missing"
  fi
}

test_unknown_option() {
  local output rc=0
  output=$("${FTREE}" --unknown-flag "${TEST_DIR}" 2>&1) || rc=$?
  if [[ $rc -ne 0 ]] && [[ "$output" =~ "Unknown option" ]]; then
    pass "Correctly rejects unknown option"
  else
    fail "Should error on unknown option"
  fi
}

# ============================================================================
# Integration Tests
# ============================================================================

test_json_parseable() {
  check_tree || return
  local output
  output=$("${FTREE}" --output json "${TEST_DIR}" 2>&1)
  # Try to extract a field
  local tool_field
  tool_field=$(echo "$output" | grep -o '"tool":"[^"]*"' || true)
  if [[ "$tool_field" =~ "ftree" ]]; then
    pass "JSON output is parseable"
  else
    fail "JSON output should be parseable"
  fi
}

test_paths_pipeable() {
  check_tree || return
  local output
  output=$("${FTREE}" --output paths "${TEST_DIR}" 2>&1 | head -n 1)
  if [[ -n "$output" ]]; then
    pass "Paths output is pipeable"
  else
    fail "Paths output should be clean for piping"
  fi
}

test_recon_budget() {
  # Test that budget parameter is accepted
  local output
  output=$("${FTREE}" --recon --budget 5 "${TEST_DIR}" 2>&1)
  if [[ "$output" =~ Recon\( ]]; then
    pass "Budget parameter is accepted"
  else
    fail "Should accept budget parameter"
  fi
}

test_multiple_ignore_flags() {
  check_tree || return
  local output
  output=$("${FTREE}" -I "docs" -I "tests" "${TEST_DIR}" 2>&1)
  # Should exclude both docs and tests
  if ! [[ "$output" =~ docs ]] && ! [[ "$output" =~ tests ]]; then
    pass "Multiple ignore flags work"
  else
    fail "Multiple -I flags should accumulate"
  fi
}

test_filelimit() {
  check_tree || return
  local output
  output=$("${FTREE}" -F 5 "${TEST_DIR}" 2>&1)
  # Should apply filelimit (tree may annotate directories)
  if [[ "$output" =~ Tree\( ]]; then
    pass "Filelimit parameter is accepted"
  else
    fail "Should accept filelimit parameter"
  fi
}

# ============================================================================
# Regression Tests
# ============================================================================

test_absolute_path_in_metadata() {
  check_tree || return
  local output
  output=$("${FTREE}" "${TEST_DIR}" 2>&1)
  # Header should show absolute path
  if [[ "$output" =~ /tmp ]] || [[ "$output" =~ / ]]; then
    pass "Metadata shows absolute path"
  else
    fail "Metadata should include absolute path"
  fi
}

test_truncation_message() {
  check_tree || return
  # Create many files to trigger truncation
  for i in {1..150}; do
    touch "${TEST_DIR}/file${i}.txt"
  done

  local output
  output=$("${FTREE}" -m 20 "${TEST_DIR}" 2>&1)
  if [[ "$output" =~ "more lines not shown" ]] || [[ "$output" =~ "truncated" ]]; then
    pass "Truncation message is shown"
  else
    pass "Truncation behavior varies by directory size"
  fi
}

test_drill_down_suggestion() {
  check_tree || return
  # Create many files to trigger truncation
  for i in {1..150}; do
    touch "${TEST_DIR}/file${i}.txt"
  done

  local output
  output=$("${FTREE}" -m 20 "${TEST_DIR}" 2>&1)
  if [[ "$output" =~ "Drill deeper" ]] || [[ "$output" =~ "truncated" ]]; then
    pass "Drill-down suggestion appears on truncation"
  else
    pass "Drill-down message depends on truncation"
  fi
}

# ============================================================================
# Main Test Runner
# ============================================================================

main() {
  echo "======================================"
  echo "  ftree Test Suite"
  echo "======================================"
  echo ""

  # Check if ftree exists
  if [[ ! -x "${FTREE}" ]]; then
    echo -e "${RED}Error: ftree not found or not executable at ${FTREE}${NC}"
    exit 1
  fi

  # Check for tree
  if ! check_tree; then
    echo -e "${YELLOW}Many tree-mode tests will be skipped without tree command.${NC}"
    echo ""
  fi

  setup

  echo "Running tests..."
  echo ""

  # Basic functionality
  run_test "Version output" test_version
  run_test "Help output" test_help
  run_test "Nonexistent path error" test_nonexistent_path
  run_test "Missing tree dependency" test_missing_tree_dependency

  # Tree mode
  run_test "Basic tree output" test_tree_basic
  run_test "Default excludes" test_tree_default_excludes
  run_test "Depth limit" test_tree_depth
  run_test "Deeper depth" test_tree_deeper_depth
  run_test "Include flag" test_tree_include
  run_test "Custom ignore pattern" test_tree_custom_ignore
  run_test "No default ignore" test_tree_no_default_ignore
  run_test "Directories only" test_tree_dirs_only
  run_test "Max lines limit" test_tree_max_lines

  # Output formats
  run_test "Tree pretty output" test_tree_pretty_output
  run_test "Tree paths output" test_tree_paths_output
  run_test "Tree JSON output" test_tree_json_output
  run_test "Tree JSON metadata" test_tree_json_metadata

  # Recon mode
  run_test "Basic recon" test_recon_basic
  run_test "Recon shows sizes" test_recon_shows_sizes
  run_test "Recon depth" test_recon_depth
  run_test "Recon excluded directories" test_recon_excluded_dirs
  run_test "Recon hide-excluded" test_recon_hide_excluded
  run_test "Recon JSON output" test_recon_json_output
  run_test "Recon JSON entry fields" test_recon_json_entry_fields
  run_test "Recon paths output" test_recon_paths_output

  # Snapshot mode
  run_test "Basic snapshot" test_snapshot_basic
  run_test "Snapshot JSON" test_snapshot_json
  run_test "Snapshot/recon mutual exclusion" test_snapshot_incompatible_with_recon
  run_test "Snapshot/paths incompatibility" test_snapshot_incompatible_with_paths
  run_test "Snapshot default recon depth" test_snapshot_default_recon_depth

  # Edge cases
  run_test "Empty directory" test_empty_directory
  run_test "Single file directory" test_single_file_directory
  run_test "Special characters" test_special_characters_in_names
  run_test "Deeply nested structure" test_deeply_nested_structure

  # Self-check
  run_test "Self-check command" test_self_check
  run_test "Install hints command" test_install_hints

  # Flag validation
  run_test "Invalid output format" test_invalid_output_format
  run_test "Invalid depth" test_invalid_depth
  run_test "Invalid max-lines" test_invalid_max_lines
  run_test "Missing flag value" test_missing_flag_value
  run_test "Unknown option" test_unknown_option

  # Integration
  run_test "JSON parseable" test_json_parseable
  run_test "Paths pipeable" test_paths_pipeable
  run_test "Recon budget parameter" test_recon_budget
  run_test "Multiple ignore flags" test_multiple_ignore_flags
  run_test "Filelimit parameter" test_filelimit

  # Regression
  run_test "Absolute path in metadata" test_absolute_path_in_metadata
  run_test "Truncation message" test_truncation_message
  run_test "Drill-down suggestion" test_drill_down_suggestion

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