#!/usr/bin/env bash
# test_install.sh — smoke tests for install.sh and relocatable installs

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="${SCRIPT_DIR}/.."
INSTALLER="${REPO_DIR}/install.sh"
TEST_ROOT=""
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

setup() {
  TEST_ROOT="$(mktemp -d)"
}

teardown() {
  [[ -n "${TEST_ROOT}" && -d "${TEST_ROOT}" ]] && rm -rf "${TEST_ROOT}"
}

pass() {
  TESTS_PASSED=$((TESTS_PASSED + 1))
  echo -e "${GREEN}✓${NC} $1"
}

fail() {
  TESTS_FAILED=$((TESTS_FAILED + 1))
  echo -e "${RED}✗${NC} $1"
  [[ -n "${2:-}" ]] && echo "  Details: $2"
}

run_test() {
  TESTS_RUN=$((TESTS_RUN + 1))
  local name="$1"
  shift
  "$@" || true
}

test_installer_help() {
  local output
  output=$("${INSTALLER}" --help 2>&1)
  if [[ "$output" == *"fsuite installer"* ]] && [[ "$output" == *"--prefix PATH"* ]]; then
    pass "Installer help output is correct"
  else
    fail "Installer help should describe usage" "Got: $output"
  fi
}

test_prefix_install_copies_tools_and_assets() {
  local prefix="${TEST_ROOT}/prefix"
  FSUITE_TELEMETRY=0 "${INSTALLER}" --prefix "$prefix" >/dev/null 2>&1 || {
    fail "Prefix install should succeed"
    return
  }

  local missing=0
  local path
  for path in \
    "${prefix}/bin/ftree" \
    "${prefix}/bin/fsearch" \
    "${prefix}/bin/fcontent" \
    "${prefix}/bin/fmap" \
    "${prefix}/bin/fread" \
    "${prefix}/bin/fmetrics" \
    "${prefix}/share/fsuite/_fsuite_common.sh" \
    "${prefix}/share/fsuite/fmetrics-predict.py"; do
    [[ -e "$path" ]] || missing=1
  done

  if (( missing == 0 )); then
    pass "Prefix install copies tools and shared assets"
  else
    fail "Prefix install should place tools and shared assets under the prefix"
  fi
}

test_prefix_install_versions_work() {
  local prefix="${TEST_ROOT}/versions"
  FSUITE_TELEMETRY=0 "${INSTALLER}" --prefix "$prefix" >/dev/null 2>&1 || {
    fail "Version install should succeed"
    return
  }

  local output
  output=$(
    FSUITE_TELEMETRY=0 "${prefix}/bin/ftree" --version
    FSUITE_TELEMETRY=0 "${prefix}/bin/fsearch" --version
    FSUITE_TELEMETRY=0 "${prefix}/bin/fcontent" --version
    FSUITE_TELEMETRY=0 "${prefix}/bin/fmap" --version
    FSUITE_TELEMETRY=0 "${prefix}/bin/fread" --version
    FSUITE_TELEMETRY=0 "${prefix}/bin/fmetrics" --version
  )

  if [[ "$output" =~ ftree\ [0-9]+\.[0-9]+\.[0-9]+ ]] && \
     [[ "$output" =~ fsearch\ [0-9]+\.[0-9]+\.[0-9]+ ]] && \
     [[ "$output" =~ fcontent\ [0-9]+\.[0-9]+\.[0-9]+ ]] && \
     [[ "$output" =~ fmap\ [0-9]+\.[0-9]+\.[0-9]+ ]] && \
     [[ "$output" =~ fread\ [0-9]+\.[0-9]+\.[0-9]+ ]] && \
     [[ "$output" =~ fmetrics\ [0-9]+\.[0-9]+\.[0-9]+ ]]; then
    pass "Installed tools report versions from the prefix"
  else
    fail "Installed tools should be executable from the prefix" "Got: $output"
  fi
}

test_installed_fmetrics_finds_predict_helper() {
  local prefix="${TEST_ROOT}/metrics"
  FSUITE_TELEMETRY=0 "${INSTALLER}" --prefix "$prefix" >/dev/null 2>&1 || {
    fail "Metrics install should succeed"
    return
  }

  local output
  output=$(
    FSUITE_TELEMETRY=0 "${prefix}/bin/fmetrics" --self-check 2>&1
  )

  if [[ "$output" == *"fmetrics-predict.py: found"* ]]; then
    pass "Installed fmetrics locates the predict helper from the prefix"
  else
    fail "Installed fmetrics should find the predict helper" "Got: $output"
  fi
}

main() {
  echo "======================================"
  echo "  install.sh Test Suite"
  echo "======================================"
  echo ""
  echo "Running tests..."
  echo ""

  [[ -x "${INSTALLER}" ]] || { echo "Installer missing: ${INSTALLER}" >&2; exit 1; }

  setup
  trap teardown EXIT

  run_test "Installer help output" test_installer_help
  run_test "Prefix install copies tools and assets" test_prefix_install_copies_tools_and_assets
  run_test "Installed tools report versions" test_prefix_install_versions_work
  run_test "Installed fmetrics finds predict helper" test_installed_fmetrics_finds_predict_helper

  echo ""
  echo "======================================"
  echo "  Test Results"
  echo "======================================"
  echo "Total:  ${TESTS_RUN}"
  echo -e "${GREEN}Passed: ${TESTS_PASSED}${NC}"

  if (( TESTS_FAILED > 0 )); then
    echo -e "${RED}Failed: ${TESTS_FAILED}${NC}"
    exit 1
  fi

  echo -e "${GREEN}All tests passed!${NC}"
}

main "$@"
