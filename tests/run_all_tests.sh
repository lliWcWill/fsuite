#!/usr/bin/env bash
# run_all_tests.sh — master test runner for fsuite
# Run with: bash run_all_tests.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ORIGINAL_HOME="${HOME:-}"
RUN_ALL_TEST_HOME="$(mktemp -d)"
export FSUITE_TELEMETRY="${FSUITE_TELEMETRY:-1}"
export HOME="$RUN_ALL_TEST_HOME"
mkdir -p "$HOME/.fsuite"

cleanup() {
  if [[ -n "${RUN_ALL_TEST_HOME:-}" && -d "$RUN_ALL_TEST_HOME" && "$RUN_ALL_TEST_HOME" != "${ORIGINAL_HOME:-}" ]]; then
    rm -rf "$RUN_ALL_TEST_HOME"
  fi
}
trap cleanup EXIT

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

TOTAL_PASSED=0
TOTAL_FAILED=0

run_test_suite() {
  local test_script="$1"
  local test_name="$2"

  echo -e "${BLUE}======================================${NC}"
  echo -e "${BLUE}Running: ${test_name}${NC}"
  echo -e "${BLUE}======================================${NC}"
  echo ""

  if [[ ! -f "${test_script}" ]]; then
    echo -e "${RED}Error: ${test_script} not found${NC}"
    return 1
  fi

  local output_file rc
  output_file="$(mktemp)"
  rc=0
  bash "${test_script}" 2>&1 | tee "$output_file" || rc=$?

  if (( rc == 0 )) && [[ ! -s "$output_file" ]]; then
    echo -e "${RED}Error: ${test_script} exited successfully without producing test output${NC}"
    rc=1
  fi
  rm -f "$output_file"

  if (( rc == 0 )); then
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
  echo -e "Telemetry tier: ${FSUITE_TELEMETRY}"
  echo -e "Sandbox HOME: ${HOME}"
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

  # Run fbash tests
  echo ""
  if run_test_suite "${SCRIPT_DIR}/test_fbash.sh" "fbash Test Suite"; then
    TOTAL_PASSED=$((TOTAL_PASSED + 1))
  else
    TOTAL_FAILED=$((TOTAL_FAILED + 1))
    failed_suites+=("fbash")
  fi

  # Run fcase tests
  echo ""
  if run_test_suite "${SCRIPT_DIR}/test_fcase.sh" "fcase Test Suite"; then
    TOTAL_PASSED=$((TOTAL_PASSED + 1))
  else
    TOTAL_FAILED=$((TOTAL_FAILED + 1))
    failed_suites+=("fcase")
  fi

  # Run fcase lifecycle tests
  echo ""
  if run_test_suite "${SCRIPT_DIR}/test_fcase_lifecycle.sh" "fcase lifecycle"; then
    TOTAL_PASSED=$((TOTAL_PASSED + 1))
  else
    TOTAL_FAILED=$((TOTAL_FAILED + 1))
    failed_suites+=("fcase-lifecycle")
  fi

  # Run fmap tests
  echo ""
  if run_test_suite "${SCRIPT_DIR}/test_fmap.sh" "fmap Test Suite"; then
    TOTAL_PASSED=$((TOTAL_PASSED + 1))
  else
    TOTAL_FAILED=$((TOTAL_FAILED + 1))
    failed_suites+=("fmap")
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

  # Run fread tests
  echo ""
  if run_test_suite "${SCRIPT_DIR}/test_fread.sh" "fread Test Suite"; then
    TOTAL_PASSED=$((TOTAL_PASSED + 1))
  else
    TOTAL_FAILED=$((TOTAL_FAILED + 1))
    failed_suites+=("fread")
  fi

  # Run fread symbol tests
  echo ""
  if run_test_suite "${SCRIPT_DIR}/test_fread_symbols.sh" "fread symbol resolution"; then
    TOTAL_PASSED=$((TOTAL_PASSED + 1))
  else
    TOTAL_FAILED=$((TOTAL_FAILED + 1))
    failed_suites+=("fread-symbols")
  fi

  # Run fedit tests
  echo ""
  if run_test_suite "${SCRIPT_DIR}/test_fedit.sh" "fedit Test Suite"; then
    TOTAL_PASSED=$((TOTAL_PASSED + 1))
  else
    TOTAL_FAILED=$((TOTAL_FAILED + 1))
    failed_suites+=("fedit")
  fi

  # Run fedit validation tests
  echo ""
  if run_test_suite "${SCRIPT_DIR}/test_fedit_validation.sh" "fedit validation"; then
    TOTAL_PASSED=$((TOTAL_PASSED + 1))
  else
    TOTAL_FAILED=$((TOTAL_FAILED + 1))
    failed_suites+=("fedit-validation")
  fi

  # Run freplay tests
  echo ""
  if run_test_suite "${SCRIPT_DIR}/test_freplay.sh" "freplay Test Suite"; then
    TOTAL_PASSED=$((TOTAL_PASSED + 1))
  else
    TOTAL_FAILED=$((TOTAL_FAILED + 1))
    failed_suites+=("freplay")
  fi

  # Run fprobe tests
  echo ""
  if run_test_suite "${SCRIPT_DIR}/test_fprobe.sh" "fprobe Test Suite"; then
    TOTAL_PASSED=$((TOTAL_PASSED + 1))
  else
    TOTAL_FAILED=$((TOTAL_FAILED + 1))
    failed_suites+=("fprobe")
  fi

  # ── fs ─────────────────────────────────────────────────────────
  echo ""
  if run_test_suite "${SCRIPT_DIR}/test_fs.sh" "fs (unified search)"; then
    TOTAL_PASSED=$((TOTAL_PASSED + 1))
  else
    TOTAL_FAILED=$((TOTAL_FAILED + 1))
    failed_suites+=("fs")
  fi

  # ── fls ────────────────────────────────────────────────────────
  echo ""
  if run_test_suite "${SCRIPT_DIR}/test_fls.sh" "fls Test Suite"; then
    TOTAL_PASSED=$((TOTAL_PASSED + 1))
  else
    TOTAL_FAILED=$((TOTAL_FAILED + 1))
    failed_suites+=("fls")
  fi

  # ── mcp ────────────────────────────────────────────────────────
  echo ""
  if run_test_suite "${SCRIPT_DIR}/test_mcp.sh" "MCP Node Test Suite"; then
    TOTAL_PASSED=$((TOTAL_PASSED + 1))
  else
    TOTAL_FAILED=$((TOTAL_FAILED + 1))
    failed_suites+=("mcp")
  fi

  # Run installer tests
  echo ""
  if run_test_suite "${SCRIPT_DIR}/test_install.sh" "install.sh Test Suite"; then
    TOTAL_PASSED=$((TOTAL_PASSED + 1))
  else
    TOTAL_FAILED=$((TOTAL_FAILED + 1))
    failed_suites+=("install")
  fi

  # Run installer automation tests
  echo ""
  if run_test_suite "${SCRIPT_DIR}/test_install_automation.sh" "install automation"; then
    TOTAL_PASSED=$((TOTAL_PASSED + 1))
  else
    TOTAL_FAILED=$((TOTAL_FAILED + 1))
    failed_suites+=("install-automation")
  fi

  # Run telemetry tests
  echo ""
  if run_test_suite "${SCRIPT_DIR}/test_telemetry.sh" "Telemetry Test Suite"; then
    TOTAL_PASSED=$((TOTAL_PASSED + 1))
  else
    TOTAL_FAILED=$((TOTAL_FAILED + 1))
    failed_suites+=("telemetry")
  fi

  # Run regression bucket tests
  echo ""
  if run_test_suite "${SCRIPT_DIR}/test_coderabbit_fixes.sh" "CodeRabbit regression bucket"; then
    TOTAL_PASSED=$((TOTAL_PASSED + 1))
  else
    TOTAL_FAILED=$((TOTAL_FAILED + 1))
    failed_suites+=("coderabbit-fixes")
  fi

  # Run memory-ingest helper tests (Phase 4/5)
  echo ""
  if run_test_suite "${SCRIPT_DIR}/test_memory_ingest.sh" "memory-ingest helper Test Suite"; then
    TOTAL_PASSED=$((TOTAL_PASSED + 1))
  else
    TOTAL_FAILED=$((TOTAL_FAILED + 1))
    failed_suites+=("memory-ingest")
  fi

  # Calculate total after all suites have run
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
