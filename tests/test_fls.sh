#!/usr/bin/env bash
# test_fls.sh — tests for fls companion tool
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
  mkdir -p "${TEST_DIR}/.hidden_dir"
  touch "${TEST_DIR}/README.md"
  touch "${TEST_DIR}/package.json"
  touch "${TEST_DIR}/src/index.ts"
  touch "${TEST_DIR}/src/auth/login.ts"
  touch "${TEST_DIR}/docs/guide.md"
  touch "${TEST_DIR}/.env"
  touch "${TEST_DIR}/.hidden_dir/secret.txt"
  ln -s "${TEST_DIR}/README.md" "${TEST_DIR}/link_to_readme"
}

teardown() { [[ -n "${TEST_DIR}" && -d "${TEST_DIR}" ]] && rm -rf "${TEST_DIR}"; }

# ── Basic functionality ──────────────────────────────────────────

test_version() {
  local output
  output=$("${FLS}" --version 2>&1)
  if [[ "$output" =~ ^fls\ [0-9]+\.[0-9]+\.[0-9]+ ]]; then
    pass "Version output"
  else
    fail "Version output" "$output"
  fi
}

test_help() {
  local output
  output=$("${FLS}" --help 2>&1)
  if [[ "$output" == *"USAGE"* ]] && [[ "$output" == *"OPTIONS"* ]]; then
    pass "Help output"
  else
    fail "Help output"
  fi
}

test_lists_directory() {
  local output
  output=$("${FLS}" "${TEST_DIR}" 2>&1)
  if [[ "$output" == *"README.md"* ]] && [[ "$output" == *"src/"* ]] && [[ "$output" == *"docs/"* ]]; then
    pass "Lists directory contents"
  else
    fail "Lists directory contents" "$output"
  fi
}

test_default_hides_dotfiles() {
  local output
  output=$("${FLS}" "${TEST_DIR}" 2>&1)
  if [[ "$output" != *".env"* ]] && [[ "$output" != *".hidden_dir"* ]]; then
    pass "Default hides dotfiles"
  else
    fail "Default hides dotfiles" "found hidden files in default output"
  fi
}

test_all_shows_dotfiles() {
  local output
  output=$("${FLS}" -a "${TEST_DIR}" 2>&1)
  if [[ "$output" == *".env"* ]] && [[ "$output" == *".hidden_dir/"* ]]; then
    pass "-a shows dotfiles"
  else
    fail "-a shows dotfiles" "$output"
  fi
}

test_dir_suffix() {
  local output
  output=$("${FLS}" "${TEST_DIR}" 2>&1)
  if [[ "$output" == *"src/"* ]] && [[ "$output" == *"docs/"* ]]; then
    pass "Directories get / suffix"
  else
    fail "Directories get / suffix" "$output"
  fi
}

test_symlink_suffix() {
  local output
  output=$("${FLS}" "${TEST_DIR}" 2>&1)
  if [[ "$output" == *"link_to_readme@"* ]]; then
    pass "Symlinks get @ suffix"
  else
    fail "Symlinks get @ suffix" "$output"
  fi
}

# ── JSON output ──────────────────────────────────────────────────

test_json_valid() {
  local output
  output=$("${FLS}" -o json "${TEST_DIR}" 2>&1)
  if echo "$output" | python3 -c 'import sys,json; json.load(sys.stdin)' 2>/dev/null; then
    pass "JSON output is valid"
  else
    fail "JSON output is valid" "$output"
  fi
}

test_json_fields() {
  local output
  output=$("${FLS}" -o json "${TEST_DIR}" 2>&1)
  local ok
  ok=$(echo "$output" | python3 -c '
import sys,json
d = json.load(sys.stdin)
fields = ["tool","version","path","total","entries"]
print("ok" if all(f in d for f in fields) else "missing")
')
  if [[ "$ok" == "ok" ]]; then
    pass "JSON has required fields"
  else
    fail "JSON has required fields" "$output"
  fi
}

test_json_entry_kinds() {
  local output
  output=$("${FLS}" -o json "${TEST_DIR}" 2>&1)
  local kinds
  kinds=$(echo "$output" | python3 -c '
import sys,json
d = json.load(sys.stdin)
print(",".join(sorted(set(e["kind"] for e in d["entries"]))))
')
  if [[ "$kinds" == *"dir"* ]] && [[ "$kinds" == *"file"* ]]; then
    pass "JSON entries have dir and file kinds"
  else
    fail "JSON entries have dir and file kinds" "kinds=$kinds"
  fi
}

test_json_total_matches_entries() {
  local output
  output=$("${FLS}" -o json "${TEST_DIR}" 2>&1)
  local match
  match=$(echo "$output" | python3 -c '
import sys,json
d = json.load(sys.stdin)
print("ok" if d["total"] == len(d["entries"]) else "mismatch")
')
  if [[ "$match" == "ok" ]]; then
    pass "JSON total matches entries length"
  else
    fail "JSON total matches entries length"
  fi
}

test_json_symlink_kind() {
  local output
  output=$("${FLS}" -o json "${TEST_DIR}" 2>&1)
  local found
  found=$(echo "$output" | python3 -c '
import sys,json
d = json.load(sys.stdin)
print("ok" if any(e["kind"] == "symlink" for e in d["entries"]) else "no")
')
  if [[ "$found" == "ok" ]]; then
    pass "JSON detects symlink kind"
  else
    fail "JSON detects symlink kind"
  fi
}

# ── Long format ──────────────────────────────────────────────────

test_long_json_has_metadata() {
  local output
  output=$("${FLS}" -o json -l "${TEST_DIR}" 2>&1)
  local ok
  ok=$(echo "$output" | python3 -c '
import sys,json
d = json.load(sys.stdin)
e = d["entries"][0]
print("ok" if "size" in e and "mtime" in e and "mode" in e else "missing")
')
  if [[ "$ok" == "ok" ]]; then
    pass "Long JSON has size, mtime, mode"
  else
    fail "Long JSON has size, mtime, mode"
  fi
}

# ── Edge cases ───────────────────────────────────────────────────

test_empty_dir() {
  local empty
  empty=$(mktemp -d)
  local output
  output=$("${FLS}" -o json "${empty}" 2>&1)
  local total
  total=$(echo "$output" | python3 -c 'import sys,json; print(json.load(sys.stdin)["total"])')
  rmdir "$empty"
  if [[ "$total" == "0" ]]; then
    pass "Empty directory returns 0 entries"
  else
    fail "Empty directory returns 0 entries" "total=$total"
  fi
}

test_nonexistent_path() {
  local output rc
  output=$("${FLS}" "/nonexistent/path" 2>&1) && rc=0 || rc=$?
  if (( rc != 0 )) && [[ "$output" == *"not a directory"* ]]; then
    pass "Nonexistent path errors cleanly"
  else
    fail "Nonexistent path errors cleanly" "rc=$rc output=$output"
  fi
}

test_cwd_default() {
  local output
  output=$(cd "${TEST_DIR}" && "${FLS}" 2>&1)
  if [[ "$output" == *"README.md"* ]]; then
    pass "No argument defaults to cwd"
  else
    fail "No argument defaults to cwd" "$output"
  fi
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
  run_test "Lists directory" test_lists_directory
  run_test "Default hides dotfiles" test_default_hides_dotfiles
  run_test "-a shows dotfiles" test_all_shows_dotfiles
  run_test "Dir suffix" test_dir_suffix
  run_test "Symlink suffix" test_symlink_suffix
  run_test "JSON valid" test_json_valid
  run_test "JSON fields" test_json_fields
  run_test "JSON entry kinds" test_json_entry_kinds
  run_test "JSON total matches entries" test_json_total_matches_entries
  run_test "JSON symlink kind" test_json_symlink_kind
  run_test "Long JSON metadata" test_long_json_has_metadata
  run_test "Empty directory" test_empty_dir
  run_test "Nonexistent path" test_nonexistent_path
  run_test "Default cwd" test_cwd_default

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
