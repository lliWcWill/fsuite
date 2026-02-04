#!/usr/bin/env bash
# test_fsearch.sh — comprehensive tests for fsearch
# Run with: bash test_fsearch.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FSEARCH="${SCRIPT_DIR}/../fsearch"
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
  # Create test directory structure
  mkdir -p "${TEST_DIR}/subdir1"
  mkdir -p "${TEST_DIR}/subdir2/nested"
  touch "${TEST_DIR}/file1.log"
  touch "${TEST_DIR}/file2.txt"
  touch "${TEST_DIR}/subdir1/test.log"
  touch "${TEST_DIR}/subdir1/data.py"
  touch "${TEST_DIR}/subdir2/config.conf"
  touch "${TEST_DIR}/subdir2/nested/deep.log"
  touch "${TEST_DIR}/token_file.json"
  touch "${TEST_DIR}/another_token.txt"
  touch "${TEST_DIR}/upscale_image.png"
  touch "${TEST_DIR}/upscale_video.mp4"
  touch "${TEST_DIR}/progress_bar.js"
  touch "${TEST_DIR}/test_progress.py"
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
# Basic Functionality Tests
# ============================================================================

test_version() {
  local output
  output=$("${FSEARCH}" --version 2>&1)
  if [[ "$output" =~ ^fsearch[[:space:]]+(1\.[0-9]+\.[0-9]+|[0-9]+\.[0-9]+\.[0-9]+) ]]; then
    pass "Version output format is correct"
  else
    fail "Version output format is incorrect" "Got: $output"
  fi
}

test_help() {
  local output
  output=$("${FSEARCH}" --help 2>&1)
  if [[ "$output" =~ USAGE ]] && [[ "$output" =~ fsearch ]]; then
    pass "Help output is displayed"
  else
    fail "Help output is missing or incorrect"
  fi
}

test_missing_pattern() {
  local output rc=0
  output=$("${FSEARCH}" 2>&1) || rc=$?
  if [[ $rc -ne 0 ]] || [[ "$output" =~ "Interactive mode" ]]; then
    pass "Correctly handles missing pattern (interactive or error)"
  else
    fail "Should error or prompt on missing pattern" "rc=$rc, output=$output"
  fi
}

test_invalid_output_format() {
  local output rc=0
  output=$("${FSEARCH}" --output invalid "*.log" "${TEST_DIR}" 2>&1) || rc=$?
  if [[ $rc -ne 0 ]] && [[ "$output" =~ "Invalid --output" ]]; then
    pass "Correctly errors on invalid output format"
  else
    fail "Should error on invalid output format"
  fi
}

test_invalid_backend() {
  local output rc=0
  output=$("${FSEARCH}" --backend invalid "*.log" "${TEST_DIR}" 2>&1) || rc=$?
  if [[ $rc -ne 0 ]] && [[ "$output" =~ "Invalid --backend" ]]; then
    pass "Correctly errors on invalid backend"
  else
    fail "Should error on invalid backend"
  fi
}

# ============================================================================
# Pattern Matching Tests
# ============================================================================

test_glob_extension() {
  local output
  output=$("${FSEARCH}" --output paths "*.log" "${TEST_DIR}" 2>&1)
  local count
  count=$(echo "$output" | grep -c "\.log$" || true)
  if [[ $count -eq 3 ]]; then
    pass "Glob pattern *.log finds all .log files"
  else
    fail "Glob pattern *.log should find 3 files" "Found: $count"
  fi
}

test_bare_extension() {
  local output
  output=$("${FSEARCH}" --output paths "log" "${TEST_DIR}" 2>&1)
  local count
  count=$(echo "$output" | grep -c "\.log$" || true)
  if [[ $count -eq 3 ]]; then
    pass "Bare extension 'log' expands to *.log"
  else
    fail "Bare extension 'log' should find 3 files" "Found: $count"
  fi
}

test_dotted_extension() {
  local output
  output=$("${FSEARCH}" --output paths ".log" "${TEST_DIR}" 2>&1)
  local count
  count=$(echo "$output" | grep -c "\.log$" || true)
  if [[ $count -eq 3 ]]; then
    pass "Dotted extension '.log' expands to *.log"
  else
    fail "Dotted extension '.log' should find 3 files" "Found: $count"
  fi
}

test_starts_with_pattern() {
  local output
  output=$("${FSEARCH}" --output paths "upscale*" "${TEST_DIR}" 2>&1)
  local count
  count=$(echo "$output" | grep -c "upscale" || true)
  if [[ $count -eq 2 ]]; then
    pass "Pattern 'upscale*' finds files starting with upscale"
  else
    fail "Pattern 'upscale*' should find 2 files" "Found: $count"
  fi
}

test_contains_pattern() {
  local output
  output=$("${FSEARCH}" --output paths "*progress*" "${TEST_DIR}" 2>&1)
  local count
  count=$(echo "$output" | grep -c "progress" || true)
  if [[ $count -eq 2 ]]; then
    pass "Pattern '*progress*' finds files containing progress"
  else
    fail "Pattern '*progress*' should find 2 files" "Found: $count"
  fi
}

test_ends_with_pattern() {
  local output
  output=$("${FSEARCH}" --output paths "*token*" "${TEST_DIR}" 2>&1)
  local count
  count=$(echo "$output" | grep -c "token" || true)
  if [[ $count -eq 2 ]]; then
    pass "Pattern '*token*' finds files containing token"
  else
    fail "Pattern '*token*' should find 2 files" "Found: $count"
  fi
}

test_question_mark_wildcard() {
  local output
  output=$("${FSEARCH}" --output paths "*.p?" "${TEST_DIR}" 2>&1)
  local count
  count=$(echo "$output" | wc -l)
  if [[ $count -ge 1 ]]; then
    pass "Question mark wildcard *.p? works"
  else
    fail "Question mark wildcard should find at least 1 file"
  fi
}

# ============================================================================
# Output Format Tests
# ============================================================================

test_pretty_output() {
  local output
  output=$("${FSEARCH}" --output pretty "*.log" "${TEST_DIR}" 2>&1)
  if [[ "$output" =~ Search\(pattern: ]] && [[ "$output" =~ Found ]]; then
    pass "Pretty output format is correct"
  else
    fail "Pretty output format is incorrect"
  fi
}

test_paths_output() {
  local output
  output=$("${FSEARCH}" --output paths "*.log" "${TEST_DIR}" 2>&1)
  # Paths output should be one path per line, no headers
  if [[ "$output" =~ \.log$ ]] && ! [[ "$output" =~ Search\( ]]; then
    pass "Paths output format is correct"
  else
    fail "Paths output should be clean paths only"
  fi
}

test_json_output() {
  local output
  output=$("${FSEARCH}" --output json "*.log" "${TEST_DIR}" 2>&1)
  # Validate JSON structure
  if [[ "$output" =~ \"tool\":\"fsearch\" ]] && \
     [[ "$output" =~ \"version\" ]] && \
     [[ "$output" =~ \"pattern\" ]] && \
     [[ "$output" =~ \"results\" ]] && \
     [[ "$output" =~ \"total_found\" ]]; then
    pass "JSON output structure is correct"
  else
    fail "JSON output structure is incorrect"
  fi
}

test_json_total_found() {
  local output
  output=$("${FSEARCH}" --output json "*.log" "${TEST_DIR}" 2>&1)
  if [[ "$output" =~ \"total_found\":3 ]]; then
    pass "JSON total_found field is accurate"
  else
    fail "JSON total_found should be 3"
  fi
}

test_json_backend_field() {
  local output
  output=$("${FSEARCH}" --output json "*.log" "${TEST_DIR}" 2>&1)
  if [[ "$output" =~ \"backend\":\"(find|fd|fdfind)\" ]]; then
    pass "JSON backend field is present"
  else
    fail "JSON backend field is missing"
  fi
}

# ============================================================================
# Max Limit Tests
# ============================================================================

test_max_limit() {
  local output
  output=$("${FSEARCH}" --output pretty --max 1 "*.log" "${TEST_DIR}" 2>&1)
  local count
  count=$(echo "$output" | grep -c "\.log$" || true)
  if [[ $count -eq 1 ]]; then
    pass "Max limit --max 1 works correctly"
  else
    fail "Max limit should show only 1 result" "Found: $count"
  fi
}

test_max_limit_in_json() {
  local output
  output=$("${FSEARCH}" --output json --max 2 "*.log" "${TEST_DIR}" 2>&1)
  if [[ "$output" =~ \"total_found\":3 ]] && [[ "$output" =~ \"shown\":2 ]]; then
    pass "JSON shows correct total_found vs shown with max limit"
  else
    fail "JSON max limit handling is incorrect"
  fi
}

# ============================================================================
# Backend Tests
# ============================================================================

test_backend_find() {
  local output rc=0
  output=$("${FSEARCH}" --backend find --output paths "*.log" "${TEST_DIR}" 2>&1) || rc=$?
  if [[ $rc -eq 0 ]]; then
    pass "Backend 'find' works"
  else
    fail "Backend 'find' should work" "rc=$rc"
  fi
}

test_backend_auto() {
  local output rc=0
  output=$("${FSEARCH}" --backend auto --output paths "*.log" "${TEST_DIR}" 2>&1) || rc=$?
  if [[ $rc -eq 0 ]]; then
    pass "Backend 'auto' works"
  else
    fail "Backend 'auto' should work"
  fi
}

# ============================================================================
# Edge Cases and Boundary Tests
# ============================================================================

test_no_results() {
  local output
  output=$("${FSEARCH}" --output pretty "*.nonexistent" "${TEST_DIR}" 2>&1)
  if [[ "$output" =~ Found[[:space:]]+0 ]]; then
    pass "Handles no results gracefully"
  else
    fail "Should show 'Found 0' for no results"
  fi
}

test_empty_directory() {
  local empty_dir="${TEST_DIR}/empty"
  mkdir -p "${empty_dir}"
  local output
  output=$("${FSEARCH}" --output pretty "*.log" "${empty_dir}" 2>&1)
  if [[ "$output" =~ Found[[:space:]]+0 ]]; then
    pass "Handles empty directory gracefully"
  else
    fail "Should handle empty directory"
  fi
}

test_nonexistent_path() {
  local output rc=0
  output=$("${FSEARCH}" "*.log" "/nonexistent/path/here" 2>&1) || rc=$?
  # find will just return no results, which is fine
  if [[ $rc -eq 0 ]] && [[ "$output" =~ Found[[:space:]]+0 ]]; then
    pass "Handles nonexistent path gracefully"
  else
    fail "Should handle nonexistent path" "rc=$rc"
  fi
}

test_special_characters_in_pattern() {
  touch "${TEST_DIR}/file-with-dash.txt"
  touch "${TEST_DIR}/file_with_underscore.txt"
  local output
  output=$("${FSEARCH}" --output paths "*with*" "${TEST_DIR}" 2>&1)
  local count
  count=$(echo "$output" | wc -l)
  if [[ $count -ge 2 ]]; then
    pass "Handles special characters in filenames"
  else
    fail "Should find files with special characters"
  fi
}

test_recursive_search() {
  local output
  output=$("${FSEARCH}" --output paths "*.log" "${TEST_DIR}" 2>&1)
  # Should find logs in subdirectories
  if [[ "$output" =~ subdir1 ]] && [[ "$output" =~ nested ]]; then
    pass "Recursive search works"
  else
    fail "Should find files in subdirectories recursively"
  fi
}

# ============================================================================
# Self-check Tests
# ============================================================================

test_self_check() {
  local output
  output=$("${FSEARCH}" --self-check 2>&1)
  if [[ "$output" =~ Self-check ]]; then
    pass "Self-check command works"
  else
    fail "Self-check should display diagnostic info"
  fi
}

test_install_hints() {
  local output
  output=$("${FSEARCH}" --install-hints 2>&1)
  if [[ "$output" =~ "Optional tools" ]] || [[ "$output" =~ "fd" ]]; then
    pass "Install hints command works"
  else
    fail "Install hints should display installation info"
  fi
}

# ============================================================================
# Path Handling Tests
# ============================================================================

test_default_path() {
  # Test searching from current directory (default)
  (
    cd "${TEST_DIR}"
    local output
    output=$("${FSEARCH}" --output paths "*.log" 2>&1)
    if [[ -n "$output" ]] && [[ "$output" =~ \.log$ ]]; then
      pass "Default path (current directory) works"
    else
      fail "Should search current directory by default"
    fi
  )
}

test_absolute_path() {
  local output
  output=$("${FSEARCH}" --output paths "*.log" "${TEST_DIR}" 2>&1)
  if [[ -n "$output" ]]; then
    pass "Absolute path works"
  else
    fail "Should work with absolute paths"
  fi
}

test_relative_path() {
  (
    cd "$(dirname "${TEST_DIR}")"
    local basename
    basename=$(basename "${TEST_DIR}")
    local output
    output=$("${FSEARCH}" --output paths "*.log" "./${basename}" 2>&1)
    if [[ -n "$output" ]]; then
      pass "Relative path works"
    else
      fail "Should work with relative paths"
    fi
  )
}

# ============================================================================
# Integration Tests
# ============================================================================

test_json_parseable() {
  local output
  output=$("${FSEARCH}" --output json "*.log" "${TEST_DIR}" 2>&1)
  # Try to extract a field using basic tools
  local tool_field
  tool_field=$(echo "$output" | grep -o '"tool":"[^"]*"' || true)
  if [[ "$tool_field" =~ "fsearch" ]]; then
    pass "JSON output is parseable"
  else
    fail "JSON output should be parseable"
  fi
}

test_paths_pipeable() {
  local output
  output=$("${FSEARCH}" --output paths "*.log" "${TEST_DIR}" 2>&1 | head -n 1)
  if [[ "$output" =~ \.log$ ]]; then
    pass "Paths output is pipeable"
  else
    fail "Paths output should be clean for piping"
  fi
}

# ============================================================================
# Negative Tests
# ============================================================================

test_invalid_max_value() {
  local output rc=0
  output=$("${FSEARCH}" --max abc "*.log" "${TEST_DIR}" 2>&1) || rc=$?
  if [[ $rc -ne 0 ]] && [[ "$output" =~ "must be an integer" ]]; then
    pass "Correctly rejects non-integer max value"
  else
    fail "Should error on non-integer max value"
  fi
}

test_unknown_option() {
  local output rc=0
  output=$("${FSEARCH}" --unknown-flag "*.log" "${TEST_DIR}" 2>&1) || rc=$?
  if [[ $rc -ne 0 ]] && [[ "$output" =~ "Unknown option" ]]; then
    pass "Correctly rejects unknown option"
  else
    fail "Should error on unknown option"
  fi
}

# ============================================================================
# Main Test Runner
# ============================================================================

main() {
  echo "======================================"
  echo "  fsearch Test Suite"
  echo "======================================"
  echo ""

  # Check if fsearch exists
  if [[ ! -x "${FSEARCH}" ]]; then
    echo -e "${RED}Error: fsearch not found or not executable at ${FSEARCH}${NC}"
    exit 1
  fi

  setup

  echo "Running tests..."
  echo ""

  # Basic functionality
  run_test "Version output" test_version
  run_test "Help output" test_help
  run_test "Missing pattern error" test_missing_pattern
  run_test "Invalid output format error" test_invalid_output_format
  run_test "Invalid backend error" test_invalid_backend

  # Pattern matching
  run_test "Glob extension pattern" test_glob_extension
  run_test "Bare extension" test_bare_extension
  run_test "Dotted extension" test_dotted_extension
  run_test "Starts-with pattern" test_starts_with_pattern
  run_test "Contains pattern" test_contains_pattern
  run_test "Ends-with pattern" test_ends_with_pattern
  run_test "Question mark wildcard" test_question_mark_wildcard

  # Output formats
  run_test "Pretty output format" test_pretty_output
  run_test "Paths output format" test_paths_output
  run_test "JSON output structure" test_json_output
  run_test "JSON total_found field" test_json_total_found
  run_test "JSON backend field" test_json_backend_field

  # Max limit
  run_test "Max limit pretty output" test_max_limit
  run_test "Max limit JSON output" test_max_limit_in_json

  # Backends
  run_test "Backend find" test_backend_find
  run_test "Backend auto" test_backend_auto

  # Edge cases
  run_test "No results" test_no_results
  run_test "Empty directory" test_empty_directory
  run_test "Nonexistent path" test_nonexistent_path
  run_test "Special characters" test_special_characters_in_pattern
  run_test "Recursive search" test_recursive_search

  # Self-check
  run_test "Self-check command" test_self_check
  run_test "Install hints command" test_install_hints

  # Path handling
  run_test "Default path" test_default_path
  run_test "Absolute path" test_absolute_path
  run_test "Relative path" test_relative_path

  # Integration
  run_test "JSON parseable" test_json_parseable
  run_test "Paths pipeable" test_paths_pipeable

  # Negative tests
  run_test "Invalid max value" test_invalid_max_value
  run_test "Unknown option" test_unknown_option

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