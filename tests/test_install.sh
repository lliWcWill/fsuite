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

# test_prefix_install_copies_tools_and_assets verifies that the installer places expected binaries and shared assets under the test prefix.
test_prefix_install_copies_tools_and_assets() {
  local prefix="${TEST_ROOT}/prefix"
  FSUITE_TELEMETRY=0 "${INSTALLER}" --prefix "$prefix" >/dev/null 2>&1 || {
    fail "Prefix install should succeed"
    return
  }

  local missing=0
  local path
  for path in \
    "${prefix}/bin/fsuite" \
    "${prefix}/bin/ftree" \
    "${prefix}/bin/fsearch" \
    "${prefix}/bin/fcontent" \
    "${prefix}/bin/fmap" \
    "${prefix}/bin/fread" \
    "${prefix}/bin/fcase" \
    "${prefix}/bin/fedit" \
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

# test_prefix_install_versions_work verifies that running the installer with --prefix installs binaries into the prefix and that each installed tool (fsuite, ftree, fsearch, fcontent, fmap, fread, fcase, fedit, fmetrics) reports a semantic version string when invoked from that prefix.
test_prefix_install_versions_work() {
  local prefix="${TEST_ROOT}/versions"
  FSUITE_TELEMETRY=0 "${INSTALLER}" --prefix "$prefix" >/dev/null 2>&1 || {
    fail "Version install should succeed"
    return
  }

  local output
  output=$(
    FSUITE_TELEMETRY=0 "${prefix}/bin/fsuite" --version
    FSUITE_TELEMETRY=0 "${prefix}/bin/ftree" --version
    FSUITE_TELEMETRY=0 "${prefix}/bin/fsearch" --version
    FSUITE_TELEMETRY=0 "${prefix}/bin/fcontent" --version
    FSUITE_TELEMETRY=0 "${prefix}/bin/fmap" --version
    FSUITE_TELEMETRY=0 "${prefix}/bin/fread" --version
    FSUITE_TELEMETRY=0 "${prefix}/bin/fcase" --version
    FSUITE_TELEMETRY=0 "${prefix}/bin/fedit" --version
    FSUITE_TELEMETRY=0 "${prefix}/bin/fmetrics" --version
  )

  if [[ "$output" =~ fsuite\ [0-9]+\.[0-9]+\.[0-9]+ ]] && \
     [[ "$output" =~ ftree\ [0-9]+\.[0-9]+\.[0-9]+ ]] && \
     [[ "$output" =~ fsearch\ [0-9]+\.[0-9]+\.[0-9]+ ]] && \
     [[ "$output" =~ fcontent\ [0-9]+\.[0-9]+\.[0-9]+ ]] && \
     [[ "$output" =~ fmap\ [0-9]+\.[0-9]+\.[0-9]+ ]] && \
     [[ "$output" =~ fread\ [0-9]+\.[0-9]+\.[0-9]+ ]] && \
     [[ "$output" =~ fcase\ [0-9]+\.[0-9]+\.[0-9]+ ]] && \
     [[ "$output" =~ fedit\ [0-9]+\.[0-9]+\.[0-9]+ ]] && \
     [[ "$output" =~ fmetrics\ [0-9]+\.[0-9]+\.[0-9]+ ]]; then
    pass "Installed tools report versions from the prefix"
  else
    fail "Installed tools should be executable from the prefix" "Got: $output"
  fi
}

# test_installed_fcase_runs_case_commands verifies that an fcase installed into the test prefix can execute case-related commands (for example `list -o json`) using an isolated HOME and records pass or fail based on the command's exit code and output.
test_installed_fcase_runs_case_commands() {
  local prefix="${TEST_ROOT}/fcase"
  local fcase_home="${TEST_ROOT}/fcase-home"
  FSUITE_TELEMETRY=0 "${INSTALLER}" --prefix "$prefix" >/dev/null 2>&1 || {
    fail "fcase install should succeed"
    return
  }

  mkdir -p "${fcase_home}"

  local output rc=0
  output=$(HOME="${fcase_home}" FSUITE_TELEMETRY=0 "${prefix}/bin/fcase" list -o json 2>&1) || rc=$?

  if [[ $rc -eq 0 ]] && [[ "$output" == *'"cases"'* ]]; then
    pass "Installed fcase runs real case commands from the prefix"
  else
    fail "Installed fcase should execute beyond --version" "rc=$rc output=$output"
  fi
}

# test_verify_install_surfaces_sqlite3_failures verifies that a failing `sqlite3` on PATH causes the installer to fail and that the installer's output includes the sqlite3 error message.
# It creates a temporary shim `sqlite3` that exits non-zero with a diagnostic, runs the installer with that shim prepended to PATH, and marks the test passed only if the installer returns a non-zero status and prints the shim message.
test_verify_install_surfaces_sqlite3_failures() {
  local prefix="${TEST_ROOT}/verify-sqlite"
  local shim_dir="${TEST_ROOT}/shim-bin"
  mkdir -p "${shim_dir}"

  cat > "${shim_dir}/sqlite3" <<'EOF'
#!/usr/bin/env bash
echo "sqlite3 shim failure" >&2
exit 127
EOF
  chmod +x "${shim_dir}/sqlite3"

  local output rc=0
  output=$(PATH="${shim_dir}:$PATH" FSUITE_TELEMETRY=0 "${INSTALLER}" --prefix "$prefix" 2>&1) || rc=$?

  if [[ $rc -ne 0 ]] && [[ "$output" == *"sqlite3 shim failure"* ]]; then
    pass "Installer verification surfaces sqlite3 runtime failures"
  else
    fail "Installer verification should surface sqlite3 runtime failures" "rc=$rc output=$output"
  fi
}

# test_fsuite_help_explains_flow verifies that the installed `fsuite` command's help/intro text describes the expected suite flow and contains key explanatory phrases.
# Checks that the help output includes phrases for the canonical agent flow, the component pipeline (`ftree -> fsearch | fcontent -> fmap -> fread -> fcase -> fedit -> fmetrics`), a composable sensor suite note, literal-search guidance, and an fcase description.
test_fsuite_help_explains_flow() {
  local prefix="${TEST_ROOT}/meta"
  FSUITE_TELEMETRY=0 "${INSTALLER}" --prefix "$prefix" >/dev/null 2>&1 || {
    fail "Meta install should succeed"
    return
  }

  local output
  output=$(FSUITE_TELEMETRY=0 "${prefix}/bin/fsuite" 2>&1)

  if [[ "$output" == *"Canonical agent flow"* ]] && \
     [[ "$output" == *"ftree -> fsearch | fcontent -> fmap -> fread -> fcase -> fedit -> fmetrics"* ]] && \
     [[ "$output" == *"Composable sensor suite"* ]] && \
     [[ "$output" == *"Literal search is a strength here, not a fallback."* ]] && \
     [[ "$output" == *"fcase     Preserve investigation state and hand off cleanly"* ]]; then
    pass "fsuite command explains the suite flow"
  else
    fail "fsuite command should explain the suite workflow" "Got: $output"
  fi
}

# test_installed_fmetrics_finds_predict_helper verifies that an installed `fmetrics` locates the `fmetrics-predict.py` helper under the installation prefix and records success or failure.
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

# test_debian_packaging_declares_fcase_runtime_contract verifies that debian/control and debian/rules exist, that control declares a dependency on `sqlite3`, and that rules install `fcase` using `install -D -m 755`.
test_debian_packaging_declares_fcase_runtime_contract() {
  local control_file="${REPO_DIR}/debian/control"
  local rules_file="${REPO_DIR}/debian/rules"

  if [[ ! -f "$control_file" ]] || [[ ! -f "$rules_file" ]]; then
    fail "Debian packaging metadata should exist"
    return
  fi

  local control rules
  control="$(cat "$control_file")"
  rules="$(cat "$rules_file")"

  if [[ "$control" == *"Depends: "* ]] && \
     [[ "$control" == *"sqlite3"* ]] && \
     [[ "$rules" == *"install -D -m 755 fcase "* ]]; then
    pass "Debian packaging declares fcase runtime dependency and install path"
  else
    fail "Debian packaging should include sqlite3 and install fcase" "control=$control rules=$rules"
  fi
}

# main runs the install.sh test suite: it prepares a temporary environment, executes all defined smoke tests, prints a pass/fail summary, and exits non-zero if any test failed.
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
  run_test "Installed fcase runs real commands" test_installed_fcase_runs_case_commands
  run_test "Installer surfaces sqlite3 verify failures" test_verify_install_surfaces_sqlite3_failures
  run_test "fsuite command explains flow" test_fsuite_help_explains_flow
  run_test "Installed fmetrics finds predict helper" test_installed_fmetrics_finds_predict_helper
  run_test "Debian packaging declares fcase runtime contract" test_debian_packaging_declares_fcase_runtime_contract

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
