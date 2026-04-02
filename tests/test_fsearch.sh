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
  mkdir -p "${TEST_DIR}/src"
  mkdir -p "${TEST_DIR}/src/auth"
  mkdir -p "${TEST_DIR}/dist"
  mkdir -p "${TEST_DIR}/node_modules"
  mkdir -p "${TEST_DIR}/node_modules/cache"
  mkdir -p "${TEST_DIR}/docs/handoffs"
  mkdir -p "${TEST_DIR}/docs/plans"
  mkdir -p "${TEST_DIR}/docs/node_modules"
  mkdir -p "${TEST_DIR}/.config/opencode"
  mkdir -p "${TEST_DIR}/.local/share"
  mkdir -p "${TEST_DIR}/.ssh"
  mkdir -p "${TEST_DIR}/visible"
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
  touch "${TEST_DIR}/docs/handoffs/note.md"
  touch "${TEST_DIR}/docs/plans/plan.md"
  touch "${TEST_DIR}/docs/node_modules/hidden.js"
  touch "${TEST_DIR}/src/auth/index.ts"
  touch "${TEST_DIR}/node_modules/cache/bundle.log"
  touch "${TEST_DIR}/node_modules/legacy.log"
  touch "${TEST_DIR}/package.json"
  touch "${TEST_DIR}/src/package.json"
  touch "${TEST_DIR}/dist/package.json"
  touch "${TEST_DIR}/node_modules/package.json"
  touch "${TEST_DIR}/.config/opencode/opencode.json"
  touch "${TEST_DIR}/.local/share/opencode.json"
  touch "${TEST_DIR}/.toolrc"
  touch "${TEST_DIR}/.ssh/config"
  touch "${TEST_DIR}/visible/opencode.json"
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

github_command_escape() {
  local value="${1:-}"
  value="${value//'%'/'%25'}"
  value="${value//$'\r'/'%0D'}"
  value="${value//$'\n'/'%0A'}"
  printf '%s' "$value"
}

github_report_failure() {
  local title="$1"
  local details="$2"

  if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    printf '::error title=%s::%s\n' \
      "$(github_command_escape "$title")" \
      "$(github_command_escape "$details")"
  fi

  if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    {
      echo "### $title"
      echo
      echo '```text'
      printf '%s\n' "$details"
      echo '```'
      echo
    } >> "$GITHUB_STEP_SUMMARY"
  fi
}

persist_failure_artifacts() {
  local prefix="$1"
  local stdout_file="$2"
  local stderr_file="$3"
  local artifact_dir="${FSUITE_TEST_ARTIFACT_DIR:-}"

  [[ -n "$artifact_dir" ]] || return 0

  mkdir -p "$artifact_dir"
  cp "$stdout_file" "$artifact_dir/${prefix}.stdout.txt"
  cp "$stderr_file" "$artifact_dir/${prefix}.stderr.txt"
}

run_test() {
  TESTS_RUN=$((TESTS_RUN + 1))
  local test_name="$1"
  shift
  "$@" || true
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

test_invalid_type() {
  local output rc=0
  output=$("${FSEARCH}" --type invalid "docs" "${TEST_DIR}" 2>&1) || rc=$?
  if [[ $rc -ne 0 ]] && [[ "$output" =~ "Invalid --type" ]]; then
    pass "Correctly errors on invalid type"
  else
    fail "Should error on invalid type"
  fi
}

test_invalid_match() {
  local output rc=0
  output=$("${FSEARCH}" --match invalid "docs" "${TEST_DIR}" 2>&1) || rc=$?
  if [[ $rc -ne 0 ]] && [[ "$output" =~ "Invalid --match" ]]; then
    pass "Correctly errors on invalid match"
  else
    fail "Should error on invalid match"
  fi
}

test_invalid_mode() {
  local output rc=0
  output=$("${FSEARCH}" --mode invalid "docs" "${TEST_DIR}" 2>&1) || rc=$?
  if [[ $rc -ne 0 ]] && [[ "$output" =~ "Invalid --mode" ]]; then
    pass "Correctly errors on invalid mode"
  else
    fail "Should error on invalid mode"
  fi
}

test_invalid_preview() {
  local output rc=0
  output=$("${FSEARCH}" --preview nope "docs" "${TEST_DIR}" 2>&1) || rc=$?
  if [[ $rc -ne 0 ]] && [[ "$output" =~ "Invalid --preview" ]]; then
    pass "Correctly errors on invalid preview"
  else
    fail "Should error on invalid preview"
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
    pass "Glob pattern *.log skips low-signal directories by default"
  else
    fail "Glob pattern *.log should find 3 files with default ignores" "Found: $count"
  fi
}

test_bare_extension() {
  local output
  output=$("${FSEARCH}" --output paths "log" "${TEST_DIR}" 2>&1)
  local count
  count=$(echo "$output" | grep -c "\.log$" || true)
  if [[ $count -eq 3 ]]; then
    pass "Bare extension 'log' expands to *.log with default ignores"
  else
    fail "Bare extension 'log' should find 3 files with default ignores" "Found: $count"
  fi
}

test_default_mode_keeps_extension_heuristic() {
  local output
  output=$("${FSEARCH}" --output json "docs" "${TEST_DIR}" 2>&1)
  if [[ "$output" == *'"name_glob":"*.docs"'* ]]; then
    pass "Default file mode keeps the short-token extension heuristic"
  else
    fail "Default file mode should keep the short-token extension heuristic" "Output: $output"
  fi
}

test_dir_mode_disables_extension_heuristic() {
  local output
  output=$("${FSEARCH}" --type dir --mode auto --output json "docs" "${TEST_DIR}" 2>&1)
  if [[ "$output" == *'"name_glob":"docs"'* ]]; then
    pass "Dir mode disables the short-token extension heuristic"
  else
    fail "Dir mode should disable the short-token extension heuristic" "Output: $output"
  fi
}

test_ext_mode_forces_extension_normalization() {
  local output
  output=$("${FSEARCH}" --mode ext --output json "log" "${TEST_DIR}" 2>&1)
  if [[ "$output" == *'"name_glob":"*.log"'* ]]; then
    pass "Ext mode forces bare tokens to extension globs"
  else
    fail "Ext mode should normalize bare tokens as extensions" "Output: $output"
  fi
}

test_ext_mode_keeps_dotted_extensions_valid() {
  local output
  output=$("${FSEARCH}" --mode ext --output json ".log" "${TEST_DIR}" 2>&1)
  if [[ "$output" == *'"name_glob":"*.log"'* ]]; then
    pass "Ext mode normalizes dotted extensions to extension globs"
  else
    fail "Ext mode should normalize dotted extensions as extension globs" "Output: $output"
  fi
}

test_dotted_extension() {
  local output
  output=$("${FSEARCH}" --output paths ".log" "${TEST_DIR}" 2>&1)
  local count
  count=$(echo "$output" | grep -c "\.log$" || true)
  if [[ $count -eq 3 ]]; then
    pass "Dotted extension '.log' expands to *.log with default ignores"
  else
    fail "Dotted extension '.log' should find 3 files with default ignores" "Found: $count"
  fi
}

test_include_pattern() {
  local output
  output=$("${FSEARCH}" --include "*/subdir*" --output paths "*.log" "${TEST_DIR}" 2>&1)
  local count
  count=$(echo "$output" | grep -c "\.log$" || true)
  if [[ $count -eq 2 ]]; then
    pass "--include filters results to matching paths only"
  else
    fail "--include should keep only matching paths" "Found: $count"
  fi
}

test_exclude_pattern() {
  local output
  output=$("${FSEARCH}" --exclude "*node_modules*" --output paths "*.log" "${TEST_DIR}" 2>&1)
  local count
  count=$(echo "$output" | grep -c "\.log$" || true)
  if [[ $count -eq 3 ]]; then
    pass "--exclude removes matching paths"
  else
    fail "--exclude should remove node_modules logs" "Found: $count"
  fi
}

test_default_ignore_filters_dependency_trees() {
  local output
  output=$("${FSEARCH}" --output paths "package.json" "${TEST_DIR}" 2>&1)
  if [[ "$output" == *"${TEST_DIR}/package.json"* ]] && \
     [[ "$output" == *"${TEST_DIR}/src/package.json"* ]] && \
     [[ "$output" != *"${TEST_DIR}/node_modules/package.json"* ]] && \
     [[ "$output" != *"${TEST_DIR}/dist/package.json"* ]]; then
    pass "Default ignore filters dependency/build trees"
  else
    fail "Default ignore should suppress node_modules and dist package manifests" "Output: $output"
  fi
}

test_no_default_ignore_restores_dependency_trees() {
  local output
  output=$("${FSEARCH}" --no-default-ignore --output paths "package.json" "${TEST_DIR}" 2>&1)
  if [[ "$output" == *"${TEST_DIR}/node_modules/package.json"* ]] && \
     [[ "$output" == *"${TEST_DIR}/dist/package.json"* ]]; then
    pass "--no-default-ignore restores dependency/build tree results"
  else
    fail "--no-default-ignore should include node_modules and dist results" "Output: $output"
  fi
}

test_config_only_limits_to_config_roots() {
  local output
  output=$("${FSEARCH}" --config-only --output paths "opencode.json" "${TEST_DIR}" 2>&1)
  if [[ "$output" == *"${TEST_DIR}/.config/opencode/opencode.json"* ]] && \
     [[ "$output" == *"${TEST_DIR}/.local/share/opencode.json"* ]] && \
     [[ "$output" != *"${TEST_DIR}/visible/opencode.json"* ]]; then
    pass "--config-only narrows to config roots and skips visible siblings"
  else
    fail "--config-only should search only config-like roots" "Output: $output"
  fi
}

test_config_only_includes_top_level_hidden_files() {
  local output
  output=$("${FSEARCH}" --config-only --output paths ".toolrc" "${TEST_DIR}" 2>&1)
  if [[ "$output" == *"${TEST_DIR}/.toolrc"* ]]; then
    pass "--config-only includes top-level hidden files"
  else
    fail "--config-only should include top-level hidden files" "Output: $output"
  fi
}

test_config_only_surfaces_top_level_hidden_dirs_in_nav_mode() {
  local output
  output=$("${FSEARCH}" --config-only --type dir --mode literal --output paths ".ssh" "${TEST_DIR}" 2>&1)
  if [[ "$output" == *"${TEST_DIR}/.ssh"* ]]; then
    pass "--config-only nav mode surfaces top-level hidden dirs"
  else
    fail "--config-only should surface top-level hidden dirs in nav mode" "Output: $output"
  fi
}

test_config_only_searches_nested_config_subtrees() {
  local output nested_root
  nested_root="${TEST_DIR}/.config/opencode"
  output=$("${FSEARCH}" --config-only --output paths "opencode.json" "${nested_root}" 2>&1)
  if [[ "$output" == *"${nested_root}/opencode.json"* ]]; then
    pass "--config-only searches nested config subtrees"
  else
    fail "--config-only should search recursively from nested config subtree roots" "Output: $output"
  fi
}

test_config_only_dedupes_hidden_hits_in_nested_roots() {
  local nested_root hidden_dir output count
  nested_root="${TEST_DIR}/.config/opencode"
  hidden_dir="${nested_root}/.agent"
  mkdir -p "${hidden_dir}"

  output=$("${FSEARCH}" --config-only --type dir --output json ".agent" "${nested_root}" 2>&1)
  count=$(printf "%s" "$output" | python3 -c 'import json, sys; data = json.load(sys.stdin); print(data["results"].count(data["results"][0]) if data.get("results") else 0)' 2>/dev/null || echo 0)

  if [[ "$output" == *"\"total_found\":1"* ]] && [[ "$count" == "1" ]]; then
    pass "--config-only dedupes hidden hits in nested roots"
  else
    fail "--config-only should not emit duplicate hidden hits from nested roots" "Output: $output"
  fi
}

test_tilde_path_expansion() {
  local home_dir
  home_dir="$(mktemp -d "${HOME}/fsuite-fsearch-home.XXXXXX")"
  local rc=0
  touch "${home_dir}/tilde_test.log"
  local output
  output=$("${FSEARCH}" --output paths "*.log" "~/${home_dir##${HOME}/}" 2>&1) || rc=$?
  rm -rf "${home_dir}"
  if [[ $rc -eq 0 ]] && [[ "$output" == *"tilde_test.log"* ]]; then
    pass "Tilde path expansion works"
  else
    fail "Tilde path expansion should resolve to HOME" "rc=$rc output=$output"
  fi
}

test_include_and_exclude_combined() {
  local output
  output=$("${FSEARCH}" --include "*/subdir*" --exclude "*nested*" --output paths "*.log" "${TEST_DIR}" 2>&1)
  if [[ "$output" == *"subdir1/test.log"* ]] && [[ "$output" != *"nested/deep.log"* ]]; then
    pass "--include + --exclude combine correctly"
  else
    fail "Combined include/exclude should return only subdir1 logs" "Output: $output"
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

test_default_ignore_filters_low_signal_dir_roots() {
  local output
  output=$("${FSEARCH}" --type dir --output paths "node_modules" "${TEST_DIR}" 2>&1)
  if [[ -z "$output" ]]; then
    pass "Default ignore filters low-signal directory roots in nav mode"
  else
    fail "Default ignore should suppress low-signal directory roots in nav mode" "Output: $output"
  fi
}

test_no_default_ignore_restores_low_signal_dir_roots() {
  local output
  output=$("${FSEARCH}" --no-default-ignore --type dir --output paths "node_modules" "${TEST_DIR}" 2>&1)
  if [[ "$output" == *"${TEST_DIR}/node_modules"* ]] && [[ "$output" == *"${TEST_DIR}/docs/node_modules"* ]]; then
    pass "--no-default-ignore restores low-signal directory roots in nav mode"
  else
    fail "--no-default-ignore should restore low-signal directory roots in nav mode" "Output: $output"
  fi
}

test_type_dir_finds_directory() {
  local output
  output=$("${FSEARCH}" --type dir --output paths "docs" "${TEST_DIR}" 2>&1)
  if [[ "$output" == "${TEST_DIR}/docs" ]]; then
    pass "--type dir returns directory hits"
  else
    fail "--type dir should find docs directory without backend-specific suffixes" "Output: $output"
  fi
}

test_type_both_path_match_finds_dir_and_file() {
  local output
  output=$("${FSEARCH}" --type both --match path --output json "auth" "${TEST_DIR}" 2>&1)
  if [[ "$output" == *'"search_type":"both"'* ]] && \
     [[ "$output" == *'"match_mode":"path"'* ]] && \
     [[ "$output" == *"${TEST_DIR}/src/auth"* ]] && \
     [[ "$output" == *"${TEST_DIR}/src/auth/index.ts"* ]]; then
    pass "--type both with path matching finds directories and files"
  else
    fail "--type both with --match path should include auth dir and file hits" "Output: $output"
  fi
}

test_json_hits_are_additive() {
  local output
  output=$("${FSEARCH}" --type dir --preview 2 --output json "docs" "${TEST_DIR}" 2>&1)
  if [[ "$output" == *'"results":['* ]] && \
     [[ "$output" == *'"hits":['* ]] && \
     [[ "$output" == *'"preview_limit":2'* ]] && \
     [[ "$output" == *'"search_type":"dir"'* ]]; then
    pass "JSON keeps results[] and adds hits[]"
  else
    fail "JSON should include additive navigation fields" "Output: $output"
  fi
}

test_dir_preview_is_shallow_and_deterministic() {
  local output
  output=$("${FSEARCH}" --type dir --preview 2 --output json "docs" "${TEST_DIR}" 2>&1)
  local preview_ok
  preview_ok=$(echo "$output" | python3 -c '
import sys, json
data = json.load(sys.stdin)
hits = data.get("hits", [])
preview = hits[0].get("preview") if hits else None
expected = [
    {"name": "handoffs", "kind": "dir"},
    {"name": "plans", "kind": "dir"},
]
print("yes" if preview == expected else "no")
' 2>/dev/null || echo "no")
  if [[ "$preview_ok" == "yes" ]]; then
    pass "Preview is shallow, sorted, and deterministic"
  else
    fail "Preview should list immediate sorted children only" "Output: $output"
  fi
}

test_dir_preview_filters_low_signal_children() {
  local output
  output=$("${FSEARCH}" --type dir --preview 5 --output json "docs" "${TEST_DIR}" 2>&1)
  if [[ "$output" != *'"name":"node_modules"'* ]]; then
    pass "Preview filters low-signal child directories"
  else
    fail "Preview should suppress low-signal child directories by default" "Output: $output"
  fi
}

test_top_level_next_hint_stays_null_when_truncated() {
  local output
  mkdir -p "${TEST_DIR}/alt/docs"
  output=$("${FSEARCH}" --type dir --preview 1 --max 1 --output json "docs" "${TEST_DIR}" 2>&1)
  if [[ "$output" == *'"total_found":2'* ]] && [[ "$output" == *'"shown":1'* ]] && [[ "$output" == *'"next_hint":null'* ]]; then
    pass "Top-level next_hint stays null when max truncates ambiguous results"
  else
    fail "Top-level next_hint should stay null when multiple hits were truncated" "Output: $output"
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
    fail "JSON total_found should be 3 with default ignores"
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

test_max_limit_with_include_filter_total_count() {
  local scoped="${TEST_DIR}/filter_scope_case"
  mkdir -p "${scoped}/a" "${scoped}/z"
  local i
  for i in $(seq -w 1 120); do touch "${scoped}/a/a_${i}.log"; done
  for i in $(seq -w 1 120); do touch "${scoped}/z/z_${i}.log"; done

  local output
  output=$("${FSEARCH}" --output json --max 10 --include "*/z/*" "*.log" "${scoped}" 2>&1)
  # total_found is the collected count (MAX+1=11) when truncated, not an
  # exact recount.  shown should be capped at MAX (10).
  if [[ "$output" =~ \"total_found\":11 ]] && [[ "$output" =~ \"shown\":10 ]] && [[ "$output" =~ \"count_mode\":\"lower_bound\" ]]; then
    pass "JSON filtered total_found reports capped count with max cap"
  else
    fail "Filtered max JSON count is incorrect" "Output: $output"
  fi
  rm -rf "${scoped}"
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

test_backend_find_supports_nav_modes() {
  local output rc=0
  output=$("${FSEARCH}" --backend find --type both --match path --output json "auth" "${TEST_DIR}" 2>&1) || rc=$?
  if [[ $rc -eq 0 ]] && \
     [[ "$output" == *'"backend":"find"'* ]] && \
     [[ "$output" == *"${TEST_DIR}/src/auth"* ]] && \
     [[ "$output" == *"${TEST_DIR}/src/auth/index.ts"* ]]; then
    pass "Backend 'find' supports nav-style dir and path matching"
  else
    fail "Backend 'find' should support nav-style dir and path matching" "Output: $output"
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
  local output
  output=$(cd "${TEST_DIR}" && "${FSEARCH}" --output paths "*.log" 2>&1)
  if [[ -n "$output" ]] && [[ "$output" =~ \.log$ ]]; then
    pass "Default path (current directory) works"
  else
    fail "Should search current directory by default"
  fi
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
  local output
  local basename
  basename=$(basename "${TEST_DIR}")
  output=$(cd "$(dirname "${TEST_DIR}")" && "${FSEARCH}" --output paths "*.log" "./${basename}" 2>&1)
  if [[ -n "$output" ]]; then
    pass "Relative path works"
  else
    fail "Should work with relative paths"
  fi
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

test_json_escapes_control_chars_in_paths() {
  local control_name control_dir output parsed
  control_name=$'docs-\001control'
  control_dir="${TEST_DIR}/${control_name}"
  mkdir -p "${control_dir}"

  output=$("${FSEARCH}" --output json --type dir --mode literal "${control_name}" "${TEST_DIR}" 2>&1)
  parsed=$(printf '%s' "${output}" | python3 -c '
import json
import sys

data = json.load(sys.stdin)
if len(data.get("hits", [])) != 1:
    print("no")
    raise SystemExit(0)

hit = data["hits"][0]
next_hint = data.get("next_hint") or {}
ok = (
    hit.get("kind") == "dir"
    and hit.get("path", "").endswith("docs-\x01control")
    and next_hint.get("tool") == "fls"
    and (next_hint.get("args") or {}).get("path") == hit.get("path")
    and (next_hint.get("args") or {}).get("mode") == "tree"
)
print("yes" if ok else "no")
' 2>/dev/null || echo "no")

  if [[ "${parsed}" == "yes" ]]; then
    pass "JSON escapes control characters in nav paths"
  else
    fail "JSON output should remain parseable for control-character paths"
  fi
}

test_paths_pipeable() {
  local output
  output=$("${FSEARCH}" --output paths "*.log" "${TEST_DIR}" 2>&1) || true
  local first_line
  first_line=$(echo "$output" | head -n 1)
  if [[ "$first_line" =~ \.log$ ]]; then
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
# v1.5.0 Feature Tests
# ============================================================================

test_project_name() {
  rm -f "$HOME/.fsuite/telemetry.jsonl"
  FSUITE_TELEMETRY=1 "${FSEARCH}" --project-name "TestProj" --output paths "*.log" "${TEST_DIR}" >/dev/null 2>&1 || true
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
  FSUITE_TELEMETRY=1 "${FSEARCH}" -m 5 -b find --output json "*.log" "${TEST_DIR}" >/dev/null 2>&1 || true
  local line
  line=$(tail -1 "$HOME/.fsuite/telemetry.jsonl" 2>/dev/null) || line=""
  local flags
  flags=$(echo "$line" | grep -o '"flags":"[^"]*"' || true)
  if [[ "$flags" =~ "-m 5" ]] && [[ "$flags" =~ "-b find" ]]; then
    pass "Flag accumulation records -m and -b in telemetry"
  else
    fail "Telemetry flags should include -m 5 and -b find" "Got: $flags"
  fi
}

test_nav_flag_accumulation() {
  rm -f "$HOME/.fsuite/telemetry.jsonl"
  FSUITE_TELEMETRY=1 "${FSEARCH}" --type dir --match path --mode literal --preview 3 --output json "docs" "${TEST_DIR}" >/dev/null 2>&1 || true
  local line
  line=$(tail -1 "$HOME/.fsuite/telemetry.jsonl" 2>/dev/null) || line=""
  local flags
  flags=$(echo "$line" | grep -o '"flags":"[^"]*"' || true)
  if [[ "$flags" =~ "--type dir" ]] && \
     [[ "$flags" =~ "--match path" ]] && \
     [[ "$flags" =~ "--mode literal" ]] && \
     [[ "$flags" =~ "--preview 3" ]]; then
    pass "Telemetry flags record explicit nav contract values"
  else
    fail "Telemetry flags should include the explicit nav contract values" "Got: $flags"
  fi
}

test_default_flag_seeding() {
  rm -f "$HOME/.fsuite/telemetry.jsonl"
  FSUITE_TELEMETRY=1 "${FSEARCH}" --output paths "*.log" "${TEST_DIR}" >/dev/null 2>&1 || true
  local line
  line=$(tail -1 "$HOME/.fsuite/telemetry.jsonl" 2>/dev/null) || line=""
  local flags
  flags=$(echo "$line" | grep -o '"flags":"[^"]*"' || true)
  if [[ "$flags" =~ "-o paths" ]] && \
     [[ "$flags" =~ "--type file" ]] && \
     [[ "$flags" =~ "--match name" ]] && \
     [[ "$flags" =~ "--mode auto" ]] && \
     [[ "$flags" =~ "--preview 0" ]]; then
    pass "Default flag seeding records output format and nav defaults"
  else
    fail "Telemetry flags should include output format and nav defaults" "Got: $flags"
  fi
}

# ============================================================================
# Regression: node_modules prune must apply in path/both match mode
# ============================================================================

test_match_both_excludes_node_modules() {
  # The bug: run_find in path/both mode ran bare `find` with no prune,
  # so it traversed all of node_modules.  filter_results_stream hid them
  # from output, making result-based assertions useless.
  #
  # This test uses the FSEARCH_META debug hook to observe how many items
  # the pipeline actually enumerated BEFORE filtering.  With prune, find
  # never enters node_modules so items_enumerated stays small.  Without
  # prune, find enumerates every file in node_modules even though the
  # filter later removes them.
  mkdir -p "${TEST_DIR}/node_modules/xyzzy-pkg/lib"
  for i in $(seq 1 100); do : > "${TEST_DIR}/node_modules/xyzzy-pkg/lib/f${i}.js"; done
  mkdir -p "${TEST_DIR}/src/xyzzy"
  touch "${TEST_DIR}/src/xyzzy/real.ts"

  local meta_file
  meta_file=$(mktemp)
FSEARCH_META="$meta_file" "${FSEARCH}" -o json --type both --match both --backend find -m 200 xyzzy "${TEST_DIR}" >/dev/null 2>&1

  local enumerated
  enumerated=$(python3 -c "import sys,json; print(json.load(open('$meta_file'))['items_enumerated'])")
  rm -f "$meta_file"

  # With prune: find never enters node_modules, so enumerated should be
  # very small (just the src/xyzzy tree + a few top-level items).
  # Without prune: find lists 100+ files in node_modules/xyzzy-pkg/lib,
  # so enumerated would be >100.
  if (( enumerated < 30 )); then
    pass "match-both prunes node_modules at find level (enumerated=$enumerated)"
  else
    fail "match-both prunes node_modules at find level" "items_enumerated=$enumerated (want <30; find is traversing excluded dirs)"
  fi

  rm -rf "${TEST_DIR}/node_modules/xyzzy-pkg" "${TEST_DIR}/src/xyzzy"
}

test_match_both_no_recount_on_truncation() {
  # The old code ran the full search pipeline TWICE when results > MAX:
  # once for results (head -n MAX+1), again unbounded for wc -l.
  # On large trees this doubled runtime.  After the fix, total_found
  # is the collected count (MAX+1) when truncated, and total_found_exact
  # is false.  If someone reintroduces the recount, total_found will be
  # the exact number (60) and/or total_found_exact will be true/missing.
  local matchdir="${TEST_DIR}/many_matches"
  mkdir -p "$matchdir"
  for i in $(seq 1 60); do
    touch "$matchdir/item_${i}.txt"
  done

  local output_file error_file parse_file
  local total count_mode truncated has_more
  local rc=0 parse_rc=0
  output_file=$(mktemp)
  error_file=$(mktemp)
  parse_file=$(mktemp)

  "${FSEARCH}" -o json --match both --backend find -m 50 item "${matchdir}" >"${output_file}" 2>"${error_file}" || rc=$?
  if [[ $rc -ne 0 ]] || [[ ! -s "${output_file}" ]]; then
    local stderr stdout_preview json_bytes details
    stderr=$(tr '\n' ' ' < "${error_file}" 2>/dev/null || true)
    stdout_preview=$(head -c 200 "${output_file}" 2>/dev/null || true)
    json_bytes=$(wc -c < "${output_file}" 2>/dev/null || echo 0)
    persist_failure_artifacts "fsearch-truncation" "${output_file}" "${error_file}"
    details="fsearch rc=${rc}, json_bytes=${json_bytes}, stderr=${stderr:-<empty>}, stdout_preview=${stdout_preview:-<empty>}"
    github_report_failure "Truncated search contract" "$details"
    rm -f "${output_file}" "${error_file}" "${parse_file}"
    fail "Truncated search contract" "$details"
    return
  fi

  python3 - "${output_file}" >"${parse_file}" <<'PY' || parse_rc=$?
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as fh:
    data = json.load(fh)

print(data["total_found"])
print(data.get("count_mode", "MISSING"))
print(data.get("truncated", "MISSING"))
print(data.get("has_more", "MISSING"))
PY

  if [[ $parse_rc -ne 0 ]]; then
    local stderr stdout_preview details
    stderr=$(tr '\n' ' ' < "${error_file}" 2>/dev/null || true)
    stdout_preview=$(head -c 200 "${output_file}" 2>/dev/null || true)
    persist_failure_artifacts "fsearch-truncation" "${output_file}" "${error_file}"
    details="json parse failed rc=${parse_rc}, stderr=${stderr:-<empty>}, stdout_preview=${stdout_preview:-<empty>}"
    github_report_failure "Truncated search contract" "$details"
    rm -f "${output_file}" "${error_file}" "${parse_file}"
    fail "Truncated search contract" "$details"
    return
  fi

  total=$(sed -n '1p' "${parse_file}")
  count_mode=$(sed -n '2p' "${parse_file}")
  truncated=$(sed -n '3p' "${parse_file}")
  has_more=$(sed -n '4p' "${parse_file}")
  rm -f "${output_file}" "${error_file}" "${parse_file}"

  local ok=1
  (( total == 51 )) || ok=0
  [[ "$count_mode" == "lower_bound" ]] || ok=0
  [[ "$truncated" == "True" ]] || ok=0
  [[ "$has_more" == "True" ]] || ok=0

  if (( ok )); then
    pass "Truncated search: count_mode=lower_bound, truncated=true, has_more=true"
  else
    fail "Truncated search contract" "total=$total (want 51), count_mode=$count_mode, truncated=$truncated, has_more=$has_more"
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
  run_test "Invalid type error" test_invalid_type
  run_test "Invalid match error" test_invalid_match
  run_test "Invalid mode error" test_invalid_mode
  run_test "Invalid preview error" test_invalid_preview

  # Pattern matching
  run_test "Glob extension pattern" test_glob_extension
  run_test "Bare extension" test_bare_extension
  run_test "Default mode keeps extension heuristic" test_default_mode_keeps_extension_heuristic
  run_test "Dir mode disables extension heuristic" test_dir_mode_disables_extension_heuristic
  run_test "Ext mode forces extension normalization" test_ext_mode_forces_extension_normalization
  run_test "Ext mode normalizes dotted extensions" test_ext_mode_keeps_dotted_extensions_valid
  run_test "Dotted extension" test_dotted_extension
  run_test "Starts-with pattern" test_starts_with_pattern
  run_test "Contains pattern" test_contains_pattern
  run_test "Ends-with pattern" test_ends_with_pattern
  run_test "Question mark wildcard" test_question_mark_wildcard
  run_test "--include filter" test_include_pattern
  run_test "--exclude filter" test_exclude_pattern
  run_test "Combined include and exclude" test_include_and_exclude_combined
  run_test "Default ignore filters dependency trees" test_default_ignore_filters_dependency_trees
  run_test "--no-default-ignore restores dependency trees" test_no_default_ignore_restores_dependency_trees
  run_test "--config-only limits to config roots" test_config_only_limits_to_config_roots
  run_test "--config-only includes top-level hidden files" test_config_only_includes_top_level_hidden_files
  run_test "--config-only nav surfaces hidden dirs" test_config_only_surfaces_top_level_hidden_dirs_in_nav_mode
  run_test "--config-only searches nested config subtrees" test_config_only_searches_nested_config_subtrees
  run_test "--config-only dedupes nested hidden hits" test_config_only_dedupes_hidden_hits_in_nested_roots
  run_test "Default ignore filters low-signal dir roots" test_default_ignore_filters_low_signal_dir_roots
  run_test "--no-default-ignore restores low-signal dir roots" test_no_default_ignore_restores_low_signal_dir_roots
  run_test "--type dir returns directory hits" test_type_dir_finds_directory
  run_test "--type both path matching finds dirs and files" test_type_both_path_match_finds_dir_and_file
  run_test "JSON keeps additive hit metadata" test_json_hits_are_additive
  run_test "Preview is shallow and deterministic" test_dir_preview_is_shallow_and_deterministic
  run_test "Preview filters low-signal child dirs" test_dir_preview_filters_low_signal_children
  run_test "Top-level next_hint stays null when truncated" test_top_level_next_hint_stays_null_when_truncated

  # Output formats
  run_test "Pretty output format" test_pretty_output
  run_test "Paths output format" test_paths_output
  run_test "JSON output structure" test_json_output
  run_test "JSON total_found field" test_json_total_found
  run_test "JSON backend field" test_json_backend_field

  # Max limit
  run_test "Max limit pretty output" test_max_limit
  run_test "Max limit JSON output" test_max_limit_in_json
  run_test "Max limit JSON with include filter" test_max_limit_with_include_filter_total_count

  # Backends
  run_test "Backend find" test_backend_find
  run_test "Backend auto" test_backend_auto
  run_test "Backend find supports nav modes" test_backend_find_supports_nav_modes

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
  run_test "Tilde path expansion" test_tilde_path_expansion

  # Integration
  run_test "JSON parseable" test_json_parseable
  run_test "JSON escapes control-char paths" test_json_escapes_control_chars_in_paths
  run_test "Paths pipeable" test_paths_pipeable

  # Negative tests
  run_test "Invalid max value" test_invalid_max_value
  run_test "Unknown option" test_unknown_option

  # Regression: node_modules prune + no recount on truncation
  run_test "match-both excludes node_modules path hits" test_match_both_excludes_node_modules
  run_test "Truncated search reports capped total (no recount)" test_match_both_no_recount_on_truncation

  # v1.5.0 features
  run_test "Project-name flag" test_project_name
  run_test "Flag accumulation in telemetry" test_flag_accumulation
  run_test "Nav flag accumulation in telemetry" test_nav_flag_accumulation
  run_test "Default flag seeding" test_default_flag_seeding

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
