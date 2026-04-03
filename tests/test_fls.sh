#!/usr/bin/env bash
# test_fls.sh — tests for fls (thin ftree router)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLS="${SCRIPT_DIR}/../fls"
TEST_DIR=""
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() { TESTS_PASSED=$((TESTS_PASSED + 1)); echo -e "${GREEN}✓${NC} $1"; }
fail() { TESTS_FAILED=$((TESTS_FAILED + 1)); echo -e "${RED}✗${NC} $1"; [[ -n "${2:-}" ]] && echo "  Details: $2"; }
run_test() { TESTS_RUN=$((TESTS_RUN + 1)); local n="$1"; shift; "$@" || true; }

setup() {
  TEST_DIR="$(mktemp -d)"
  mkdir -p "${TEST_DIR}/src/auth"
  mkdir -p "${TEST_DIR}/docs"
  touch "${TEST_DIR}/README.md"
  touch "${TEST_DIR}/package.json"
  touch "${TEST_DIR}/src/index.ts"
  touch "${TEST_DIR}/src/auth/login.ts"
  touch "${TEST_DIR}/docs/guide.md"
}

teardown() { [[ -n "${TEST_DIR}" && -d "${TEST_DIR}" ]] && rm -rf "${TEST_DIR}"; }

# ── Basic ────────────────────────────────────────────────────────

test_version() {
  local output
  output=$("${FLS}" --version 2>&1)
  [[ "$output" =~ ^fls\ [0-9]+\.[0-9]+\.[0-9]+ ]] && pass "Version output" || fail "Version output" "$output"
}

test_help() {
  local output
  output=$("${FLS}" --help 2>&1)
  [[ "$output" == *"USAGE"* ]] && [[ "$output" == *"MODES"* ]] && pass "Help output" || fail "Help output"
}

# ── List mode (default) → ftree -L 1 ────────────────────────────

test_list_shows_children() {
  local output
  output=$("${FLS}" "${TEST_DIR}" 2>&1)
  [[ "$output" == *"README.md"* ]] && [[ "$output" == *"src"* ]] && pass "List shows direct children" || fail "List shows direct children" "$output"
}

test_list_depth_is_one() {
  local output
  output=$("${FLS}" "${TEST_DIR}" 2>&1)
  # depth 1 should NOT show nested files like src/index.ts
  [[ "$output" != *"index.ts"* ]] && pass "List depth is 1 (no nested files)" || fail "List depth is 1" "found nested file"
}

test_list_json_depth() {
  local output
  output=$("${FLS}" -o json "${TEST_DIR}" 2>&1)
  local depth
  depth=$(echo "$output" | python3 -c 'import sys,json; print(json.load(sys.stdin)["depth"])')
  [[ "$depth" == "1" ]] && pass "List JSON depth=1" || fail "List JSON depth" "depth=$depth"
}

test_cwd_default() {
  local output
  output=$(cd "${TEST_DIR}" && "${FLS}" 2>&1)
  [[ "$output" == *"README.md"* ]] && pass "No arg defaults to cwd" || fail "No arg defaults to cwd"
}

# ── Tree mode (-t) → ftree -L 2 ─────────────────────────────────

test_tree_shows_nested() {
  local output
  output=$("${FLS}" -t "${TEST_DIR}" 2>&1)
  # depth 2 SHOULD show nested files like index.ts
  [[ "$output" == *"index.ts"* ]] && pass "Tree mode shows depth 2" || fail "Tree mode shows depth 2" "$output"
}

test_tree_json_depth() {
  local output depth
  output=$("${FLS}" -t -o json "${TEST_DIR}" 2>&1)
  depth=$(echo "$output" | python3 -c 'import sys,json; print(json.load(sys.stdin)["depth"])')
  [[ "$depth" == "2" ]] && pass "Tree JSON depth=2" || fail "Tree JSON depth" "depth=$depth"
}

# ── Recon mode (-r) → ftree --recon -L 1 ────────────────────────

test_recon_json_mode() {
  local output mode tool
  output=$("${FLS}" -r -o json "${TEST_DIR}" 2>&1)
  mode=$(echo "$output" | python3 -c 'import sys,json; print(json.load(sys.stdin)["mode"])')
  tool=$(echo "$output" | python3 -c 'import sys,json; print(json.load(sys.stdin)["tool"])')
  [[ "$mode" == "recon" ]] && [[ "$tool" == "ftree" ]] && pass "Recon JSON: mode=recon, tool=ftree" || fail "Recon JSON" "mode=$mode tool=$tool"
}

# ── Routing contract ─────────────────────────────────────────────

test_output_is_ftree() {
  # JSON must have tool=ftree — proves we route, not reimplement
  local output tool
  output=$("${FLS}" -o json "${TEST_DIR}" 2>&1)
  tool=$(echo "$output" | python3 -c 'import sys,json; print(json.load(sys.stdin)["tool"])')
  [[ "$tool" == "ftree" ]] && pass "Output is ftree (routing, not reimplementation)" || fail "Output tool field" "tool=$tool"
}

test_json_is_valid() {
  local output
  output=$("${FLS}" -o json "${TEST_DIR}" 2>&1)
  echo "$output" | python3 -c 'import sys,json; json.load(sys.stdin)' 2>/dev/null && pass "JSON is valid" || fail "JSON is valid"
}

# ── Edge cases ───────────────────────────────────────────────────

test_nonexistent_path() {
  local rc
  "${FLS}" /nonexistent/path >/dev/null 2>&1 && rc=0 || rc=$?
  (( rc != 0 )) && pass "Nonexistent path exits non-zero" || fail "Nonexistent path should fail"
}

test_empty_dir() {
  local empty output files
  empty=$(mktemp -d)
  output=$("${FLS}" -o json "${empty}" 2>&1)
  files=$(echo "$output" | python3 -c 'import sys,json; print(json.load(sys.stdin)["total_files"])')
  rm -rf "$empty"
  [[ "$files" == "0" ]] && pass "Empty dir returns 0 files" || fail "Empty dir" "total_files=$files"
}

test_unknown_option() {
  local rc output
  output=$("${FLS}" --bogus 2>&1) && rc=0 || rc=$?
  (( rc != 0 )) && [[ "$output" == *"unknown option"* ]] && pass "Unknown option rejected" || fail "Unknown option" "rc=$rc output=$output"
}

# ── Main ─────────────────────────────────────────────────────────

main() {
  echo "======================================"
  echo "  fls Test Suite"
  echo "======================================"
  echo ""

  [[ -x "${FLS}" ]] || { echo "fls not found at ${FLS}"; exit 1; }

  setup

  run_test "Version" test_version
  run_test "Help" test_help
  run_test "List shows children" test_list_shows_children
  run_test "List depth is 1" test_list_depth_is_one
  run_test "List JSON depth=1" test_list_json_depth
  run_test "Defaults to cwd" test_cwd_default
  run_test "Tree shows nested" test_tree_shows_nested
  run_test "Tree JSON depth=2" test_tree_json_depth
  run_test "Recon JSON mode+depth" test_recon_json_mode
  run_test "Output is ftree" test_output_is_ftree
  run_test "JSON is valid" test_json_is_valid
  run_test "Nonexistent path" test_nonexistent_path
  run_test "Empty dir" test_empty_dir
  run_test "Unknown option rejected" test_unknown_option

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
