#!/usr/bin/env bash
# test_fcase.sh — focused tests for fcase continuity ledger
# Run with: bash test_fcase.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FCASE="${SCRIPT_DIR}/../fcase"
TEST_HOME=""
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

setup() {
  TEST_HOME="$(mktemp -d)"
}

teardown() {
  if [[ -n "${TEST_HOME}" && -d "${TEST_HOME}" ]]; then
    rm -rf "${TEST_HOME}"
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
  "$@" || true
}

run_fcase() {
  HOME="${TEST_HOME}" FSUITE_TELEMETRY=0 "${FCASE}" "$@"
}

test_help() {
  local output
  output=$(run_fcase --help 2>&1)
  if [[ "$output" == *"fcase"* ]] && [[ "$output" == *"init"* ]] && [[ "$output" == *"status"* ]]; then
    pass "Help output documents fcase core commands"
  else
    fail "Help output should document fcase commands" "Got: $output"
  fi
}

test_version() {
  local output
  output=$(run_fcase --version 2>&1)
  if [[ "$output" =~ ^fcase\ [0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    pass "Version output format is correct"
  else
    fail "Version output format should be semver" "Got: $output"
  fi
}

test_init_creates_case() {
  local output rc=0
  output=$(run_fcase init auth-bug --goal "Find auth failure root cause" --priority high -o json 2>&1) || rc=$?
  if [[ $rc -eq 0 ]] && python3 -c 'import json,sys; data=json.loads(sys.stdin.read()); assert data["case"]["slug"] == "auth-bug"; assert data["case"]["goal"] == "Find auth failure root cause"; assert data["session"]["id"] >= 1; assert data["event"]["event_type"] == "case_init"' <<< "$output" 2>/dev/null; then
    pass "init creates a case"
  else
    fail "init should create a case with JSON envelope" "rc=$rc output=$output"
  fi
}

test_list_shows_case() {
  run_fcase init auth-bug --goal "Find auth failure root cause" >/dev/null 2>&1 || true
  local output rc=0
  output=$(run_fcase list -o json 2>&1) || rc=$?
  if [[ $rc -eq 0 ]] && [[ "$output" == *'"slug":"auth-bug"'* ]]; then
    pass "list shows initialized cases"
  else
    fail "list should show initialized cases" "rc=$rc output=$output"
  fi
}

main() {
  echo "======================================"
  echo "  fcase Test Suite"
  echo "======================================"
  echo ""
  echo "Running tests..."
  echo ""

  setup
  trap teardown EXIT

  run_test test_help
  run_test test_version
  run_test test_init_creates_case
  run_test test_list_shows_case

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
