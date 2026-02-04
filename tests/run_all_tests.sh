#!/usr/bin/env bash
# run_all_tests.sh — master test runner for fsuite
# Run with: bash run_all_tests.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

TOTAL_TESTS=0
TOTAL_PASSED=0
TOTAL_FAILED=0

run_test_suite() {
  local test_script="$1"
  local test_name="$2"

  echo -e "${BLUE}======================================${NC}"
  echo -e "${BLUE}Running: ${test_name}${NC}"
  echo -e "${BLUE}======================================${NC}"
  echo ""

  if [[ ! -x "${test_script}" ]]; then
    echo -e "${RED}Error: ${test_script} not found or not executable${NC}"
    return 1
  fi

  if bash "${test_script}"; then
    echo ""
    echo -e "${GREEN}${test_name}: PASSED${NC}"
    return 0
  else
    echo ""
    echo -e "${RED}${test_name}: FAILED${NC}"
    return 1
  fi
}

main() {
  echo ""
  echo -e "${BLUE}============================================${NC}"
  echo -e "${BLUE}  fsuite Master Test Runner${NC}"
  echo -e "${BLUE}============================================${NC}"
  echo ""

  local failed_suites=()

  # Run fsearch tests
  echo ""
  if run_test_suite "${SCRIPT_DIR}/test_fsearch.sh" "fsearch Test Suite"; then
    TOTAL_PASSED=$((TOTAL_PASSED + 1))
  else
    TOTAL_FAILED=$((TOTAL_FAILED + 1))
    failed_suites+=("fsearch")
  fi

  # Run fcontent tests
  echo ""
  if run_test_suite "${SCRIPT_DIR}/test_fcontent.sh" "fcontent Test Suite"; then
    TOTAL_PASSED=$((TOTAL_PASSED + 1))
  else
    TOTAL_FAILED=$((TOTAL_FAILED + 1))
    failed_suites+=("fcontent")
  fi

  # Run ftree tests
  echo ""
  if run_test_suite "${SCRIPT_DIR}/test_ftree.sh" "ftree Test Suite"; then
    TOTAL_PASSED=$((TOTAL_PASSED + 1))
  else
    TOTAL_FAILED=$((TOTAL_FAILED + 1))
    failed_suites+=("ftree")
  fi

  # Run integration tests
  echo ""
  if run_test_suite "${SCRIPT_DIR}/test_integration.sh" "Integration Test Suite"; then
    TOTAL_PASSED=$((TOTAL_PASSED + 1))
  else
    TOTAL_FAILED=$((TOTAL_FAILED + 1))
    failed_suites+=("integration")
  fi

  TOTAL_TESTS=$((TOTAL_PASSED + TOTAL_FAILED))

  # Final summary
  echo ""
  echo -e "${BLUE}============================================${NC}"
  echo -e "${BLUE}  Final Test Summary${NC}"
  echo -e "${BLUE}============================================${NC}"
  echo -e "Total Test Suites: ${TOTAL_TESTS}"
  echo -e "${GREEN}Passed: ${TOTAL_PASSED}${NC}"

  if [[ ${TOTAL_FAILED} -gt 0 ]]; then
    echo -e "${RED}Failed: ${TOTAL_FAILED}${NC}"
    echo ""
    echo -e "${RED}Failed test suites:${NC}"
    for suite in "${failed_suites[@]}"; do
      echo -e "${RED}  - ${suite}${NC}"
    done
    echo ""
    exit 1
  else
    echo -e "${GREEN}All test suites passed!${NC}"
    echo ""
    exit 0
  fi
}

main "$@"