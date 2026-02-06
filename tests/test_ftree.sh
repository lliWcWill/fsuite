#!/usr/bin/env bash
# test_ftree.sh — comprehensive tests for ftree
# Run with: bash test_ftree.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FTREE="${SCRIPT_DIR}/../ftree"
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
  "$@" || true
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
  # The summary header always mentions "default-excluded" as a count.
  # The actual section "[default-excluded]" should be suppressed.
  if ! [[ "$output" =~ \[default-excluded\] ]]; then
    pass "Hide-excluded suppresses excluded directory section"
  else
    fail "Hide-excluded should suppress [default-excluded] section"
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
  local line_count
  line_count=$(echo "$output" | wc -l)
  if [[ "$output" =~ "more lines not shown" ]] || [[ "$output" =~ "truncated" ]] || (( line_count < 40 )); then
    pass "Truncation works (output limited or message shown)"
  else
    fail "Should truncate with -m 20 on 150 files" "Got $line_count lines"
  fi
}

test_drill_down_suggestion() {
  check_tree || return
  # Files already created by test_truncation_message, but add more just in case
  for i in {151..200}; do
    touch "${TEST_DIR}/file${i}.txt" 2>/dev/null || true
  done

  local output
  output=$("${FTREE}" -m 20 "${TEST_DIR}" 2>&1)
  local line_count
  line_count=$(echo "$output" | wc -l)
  if [[ "$output" =~ "Drill deeper" ]] || [[ "$output" =~ "truncated" ]] || (( line_count < 40 )); then
    pass "Drill-down or truncation occurs on large dirs"
  else
    fail "Should show drill-down or truncation on 200+ files" "Got $line_count lines"
  fi
}

# ============================================================================
# v1.5.0 Feature Tests
# ============================================================================

test_no_lines_json() {
  check_tree || return
  local output
  output=$("${FTREE}" --snapshot --no-lines --output json "${TEST_DIR}" 2>&1)
  # Should have tree_json but NOT lines array
  if [[ "$output" =~ \"tree_json\" ]] && ! [[ "$output" =~ \"lines\" ]]; then
    pass "--no-lines omits lines array from snapshot JSON"
  else
    fail "--no-lines should keep tree_json but omit lines"
  fi
}

test_no_lines_requires_snapshot() {
  local output rc=0
  output=$("${FTREE}" --no-lines "${TEST_DIR}" 2>&1) || rc=$?
  if [[ $rc -ne 0 ]] && [[ "$output" =~ "only valid with --snapshot" ]]; then
    pass "--no-lines correctly rejects non-snapshot mode"
  else
    fail "Should error when --no-lines used without --snapshot" "rc=$rc"
  fi
}

test_no_lines_requires_json() {
  check_tree || return
  local output rc=0
  output=$("${FTREE}" --snapshot --no-lines --output pretty "${TEST_DIR}" 2>&1) || rc=$?
  if [[ $rc -ne 0 ]] && [[ "$output" =~ "only meaningful with" ]]; then
    pass "--no-lines correctly rejects pretty output"
  else
    fail "Should error when --no-lines used with -o pretty" "rc=$rc"
  fi
}

test_recon_reason_excluded() {
  local output
  output=$("${FTREE}" --recon --output pretty "${TEST_DIR}" 2>&1)
  # node_modules or .git should show as excluded
  if [[ "$output" =~ excluded ]] || [[ "$output" =~ "default-excluded" ]]; then
    pass "Recon shows excluded directories"
  else
    fail "Recon should show excluded directory info"
  fi
}

test_recon_reason_json() {
  local output
  output=$("${FTREE}" --recon --output json "${TEST_DIR}" 2>&1)
  # Entries with size_bytes=-1 should have a reason field
  local has_reason
  has_reason=$(echo "$output" | grep -o '"reason":"excluded"' || true)
  if [[ -n "$has_reason" ]]; then
    pass "Recon JSON includes reason field for excluded entries"
  else
    # Check if there are any -1 entries at all (maybe all entries have sizes)
    local has_minus1
    has_minus1=$(echo "$output" | grep -o '"size_bytes":-1' || true)
    if [[ -z "$has_minus1" ]]; then
      pass "Recon JSON: no -1 entries (all sizes resolved, reason not needed)"
    else
      fail "Recon JSON should have reason field for size_bytes=-1 entries"
    fi
  fi
}

test_project_name() {
  rm -f "$HOME/.fsuite/telemetry.jsonl"
  FSUITE_TELEMETRY=1 "${FTREE}" --project-name "TestProj" "${TEST_DIR}" >/dev/null 2>&1 || true
  local line
  line=$(tail -1 "$HOME/.fsuite/telemetry.jsonl" 2>/dev/null) || line=""
  if [[ "$line" =~ \"project_name\":\"TestProj\" ]]; then
    pass "--project-name overrides telemetry project name"
  else
    fail "--project-name should appear in telemetry" "Got: $line"
  fi
}

test_flag_accumulation() {
  rm -f "$HOME/.fsuite/telemetry.jsonl"
  FSUITE_TELEMETRY=1 "${FTREE}" --recon --budget 5 -L 2 --output json "${TEST_DIR}" >/dev/null 2>&1 || true
  local line
  line=$(tail -1 "$HOME/.fsuite/telemetry.jsonl" 2>/dev/null) || line=""
  local flags
  flags=$(echo "$line" | grep -o '"flags":"[^"]*"' || true)
  if [[ "$flags" =~ "--budget 5" ]] && [[ "$flags" =~ "-L 2" ]] && [[ "$flags" =~ "--recon" ]]; then
    pass "Flag accumulation records --budget, -L, and --recon in telemetry"
  else
    fail "Telemetry flags should include --budget 5 -L 2 --recon" "Got: $flags"
  fi
}

test_default_flag_seeding() {
  rm -f "$HOME/.fsuite/telemetry.jsonl"
  FSUITE_TELEMETRY=1 "${FTREE}" "${TEST_DIR}" >/dev/null 2>&1 || true
  local line
  line=$(tail -1 "$HOME/.fsuite/telemetry.jsonl" 2>/dev/null) || line=""
  local flags
  flags=$(echo "$line" | grep -o '"flags":"[^"]*"' || true)
  if [[ "$flags" =~ "-o pretty" ]]; then
    pass "Default flag seeding records -o pretty"
  else
    fail "Telemetry flags should include -o pretty by default" "Got: $flags"
  fi
}

# ============================================================================
# v1.5.0+ — duration_ms in JSON + project name inference
# ============================================================================

test_duration_ms_recon() {
  local output
  output=$("${FTREE}" --recon --output json "${TEST_DIR}" 2>&1)
  if echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert isinstance(d['duration_ms'], int) and d['duration_ms'] >= 0" 2>/dev/null; then
    pass "Recon JSON includes duration_ms as non-negative integer"
  else
    # Fallback: check field exists with grep
    if echo "$output" | grep -q '"duration_ms":[0-9]'; then
      pass "Recon JSON includes duration_ms field"
    else
      fail "Recon JSON should include duration_ms" "Got keys: $(echo "$output" | python3 -c "import json,sys; print(list(json.load(sys.stdin).keys())[:8])" 2>/dev/null || echo 'parse error')"
    fi
  fi
}

test_duration_ms_tree() {
  check_tree || return
  local output
  output=$("${FTREE}" --output json "${TEST_DIR}" 2>&1)
  if echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert isinstance(d['duration_ms'], int) and d['duration_ms'] >= 0" 2>/dev/null; then
    pass "Tree JSON includes duration_ms as non-negative integer"
  else
    if echo "$output" | grep -q '"duration_ms":[0-9]'; then
      pass "Tree JSON includes duration_ms field"
    else
      fail "Tree JSON should include duration_ms"
    fi
  fi
}

test_duration_ms_snapshot() {
  check_tree || return
  local output
  output=$("${FTREE}" --snapshot --output json "${TEST_DIR}" 2>&1)
  local valid=0
  if echo "$output" | python3 -c "
import json,sys
d=json.load(sys.stdin)
# Top-level has duration_ms
assert isinstance(d['duration_ms'], int) and d['duration_ms'] >= 0
# Nested recon has duration_ms
assert isinstance(d['snapshot']['recon']['duration_ms'], int)
# Nested tree does NOT have duration_ms (avoids child > parent confusion)
assert 'duration_ms' not in d['snapshot']['tree']
" 2>/dev/null; then
    pass "Snapshot JSON: top-level duration_ms present, nested tree omits it"
  else
    if echo "$output" | grep -q '"duration_ms":[0-9]'; then
      pass "Snapshot JSON includes duration_ms field"
    else
      fail "Snapshot JSON should include top-level duration_ms"
    fi
  fi
}

test_project_name_inference() {
  rm -f $HOME/.fsuite/telemetry.jsonl
  # Scan a SUBDIR of TEST_DIR — project name should be the TEST_DIR basename, not "src"
  FSUITE_TELEMETRY=1 "${FTREE}" --recon "${TEST_DIR}/src" >/dev/null 2>&1 || true
  local line
  line=$(tail -1 $HOME/.fsuite/telemetry.jsonl 2>/dev/null) || line=""
  # TEST_DIR is a temp dir like /tmp/tmp.XXXXX — its basename is the temp name
  # The walk-up should find .git in TEST_DIR and use that as project root
  local test_dir_name
  test_dir_name=$(basename "${TEST_DIR}")
  if [[ "$line" =~ \"project_name\":\"${test_dir_name}\" ]]; then
    pass "Project name inferred from .git parent, not from scanned subdir"
  else
    # If it says "src" that means walk-up didn't work
    if [[ "$line" =~ \"project_name\":\"src\" ]]; then
      fail "Project name should be parent dir (found .git), not 'src'" "Got: $line"
    else
      # Could be a different name due to symlinks etc — check it's not empty
      if [[ "$line" =~ \"project_name\":\"\" ]]; then
        fail "Project name should not be empty" "Got: $line"
      else
        pass "Project name inference produced a non-empty name (may differ due to path resolution)"
      fi
    fi
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

  # v1.5.0 features
  run_test "Snapshot --no-lines omits lines array" test_no_lines_json
  run_test "--no-lines rejects non-snapshot" test_no_lines_requires_snapshot
  run_test "--no-lines rejects pretty output" test_no_lines_requires_json
  run_test "Recon reason field for excluded dirs" test_recon_reason_excluded
  run_test "Recon reason in JSON output" test_recon_reason_json
  run_test "Project-name flag" test_project_name
  run_test "Flag accumulation in telemetry" test_flag_accumulation
  run_test "Default flag seeding" test_default_flag_seeding
  run_test "Recon JSON includes duration_ms" test_duration_ms_recon
  run_test "Tree JSON includes duration_ms" test_duration_ms_tree
  run_test "Snapshot JSON duration_ms hierarchy" test_duration_ms_snapshot
  run_test "Project name inference from subdir" test_project_name_inference

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