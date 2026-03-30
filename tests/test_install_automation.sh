#!/usr/bin/env bash
# test_install_automation.sh — comprehensive installer automation tests
#
# Covers:
#   1. Dependency detection (check_deps output during install, --skip-deps)
#   2. Source install flow (all 12 tools, share helper files, permissions)
#   3. MCP setup (npm install, node -c syntax check, --mcp-only flag)
#   4. Agent configuration (Claude Code mcp.json, Codex config.toml, idempotency)
#   5. Uninstall (tools removed, share files removed, MCP configs removed)
#   6. Edge cases (--mcp-only, --skip-mcp, idempotent double-install)
#
# All tests use isolated temp dirs and a HOME override so they never mutate the
# developer's live ~/.claude or ~/.codex configs.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="${SCRIPT_DIR}/.."
INSTALLER="${REPO_DIR}/install.sh"
MCP_DIR="${REPO_DIR}/mcp"
TEST_ROOT=""
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ── Framework helpers ────────────────────────────────────────────────────────

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

skip() {
  TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
  echo -e "${YELLOW}⊘${NC} $1 ${YELLOW}(skipped — not available in this environment)${NC}"
}

run_test() {
  TESTS_RUN=$((TESTS_RUN + 1))
  local name="$1"
  shift
  "$@" || true
}

# Returns 0 when the installer --help text contains the given string.
installer_supports() {
  "${INSTALLER}" --help 2>&1 | grep -qF -- "$1"
}

# Run the installer with a clean HOME so agent config writes go to an isolated dir.
# Usage: run_installer <fake_home> [installer args...]
run_installer() {
  local fake_home="$1"; shift
  mkdir -p "${fake_home}/.claude" "${fake_home}/.codex"
  HOME="$fake_home" FSUITE_TELEMETRY=0 "${INSTALLER}" "$@"
}

# ── Shared fixture arrays (mirror install.sh) ────────────────────────────────

EXPECTED_TOOLS=(fsuite ftree fsearch fcontent fmap fread fcase fedit fmetrics freplay fprobe fs)
EXPECTED_SHARE_FILES=(_fsuite_common.sh _fsuite_db.sh fmetrics-predict.py fmetrics-import.py fprobe-engine.py fs-engine.py)

# ── §1  Dependency detection ─────────────────────────────────────────────────

test_check_deps_reports_bash_present() {
  # check_deps runs automatically during a normal install.
  # We install with --skip-mcp --no-verify to keep the run fast, and capture output.
  local prefix="${TEST_ROOT}/deps-bash"
  local fake_home="${TEST_ROOT}/deps-bash-home"
  local output rc=0
  output=$(run_installer "$fake_home" --prefix "$prefix" --skip-mcp --no-verify 2>&1) || rc=$?

  # check_deps prints "bash X.Y" when bash >= 4 is found.
  if [[ "$output" == *"bash"* ]] && [[ "$output" != *"bash — version 4+ required"* ]]; then
    pass "check_deps reports bash as present and at correct version"
  else
    fail "check_deps should detect bash >= 4" "rc=$rc output=${output:0:200}"
  fi
}

test_check_deps_reports_python3_present() {
  if ! command -v python3 >/dev/null 2>&1; then
    skip "python3 not available in test environment"
    return
  fi

  local prefix="${TEST_ROOT}/deps-py"
  local fake_home="${TEST_ROOT}/deps-py-home"
  local output rc=0
  output=$(run_installer "$fake_home" --prefix "$prefix" --skip-mcp --no-verify 2>&1) || rc=$?

  if [[ "$output" == *"python3"* ]] && [[ "$output" != *"python3 — not found"* ]]; then
    pass "check_deps reports python3 as present"
  else
    fail "check_deps should detect python3" "rc=$rc output=${output:0:200}"
  fi
}

test_check_deps_reports_node_present() {
  if ! command -v node >/dev/null 2>&1; then
    skip "node not available in test environment"
    return
  fi

  local prefix="${TEST_ROOT}/deps-node"
  local fake_home="${TEST_ROOT}/deps-node-home"
  local output rc=0
  output=$(run_installer "$fake_home" --prefix "$prefix" --skip-mcp --no-verify 2>&1) || rc=$?

  if [[ "$output" == *"node"* ]] && [[ "$output" != *"node — not found"* ]]; then
    pass "check_deps reports node as present"
  else
    fail "check_deps should detect node" "rc=$rc output=${output:0:200}"
  fi
}

test_check_deps_reports_missing_dep_clearly() {
  if ! installer_supports "--skip-deps"; then
    skip "--skip-deps not in this installer"
    return
  fi

  # Create a shadow directory that intercepts node and npm with wrappers that
  # report command-not-found behaviour, then prepend it to PATH.
  # We keep all of the real PATH so bash, python3, etc. remain reachable.
  local shadow_dir="${TEST_ROOT}/shadow-intercept"
  local fake_home="${TEST_ROOT}/shadow-home"
  local prefix="${TEST_ROOT}/shadow-prefix"
  mkdir -p "$shadow_dir" "${fake_home}/.claude" "${fake_home}/.codex"

  # Wrappers print "not found" to stderr and exit 1 so check_deps's `has`
  # helper finds the wrapper via command -v, but the version probe fails.
  # More importantly: we need `has node` to return FAILURE — so the wrapper
  # must not be named "node".  Instead we rename the real node in a temp
  # wrapper and use a "fake has" approach by making the interceptor exit
  # with a non-zero on --version but succeed on command -v.
  #
  # Cleanest approach: wrap node to exit 1 on all invocations — `has node`
  # will still return 0 (command exists), but the version string will be
  # empty, causing the (( node_maj >= 18 )) arithmetic to evaluate 0 >= 18
  # (false) → missing_required gets "node18".  That gives us the "missing"
  # output we assert on.
  cat > "${shadow_dir}/node" <<'EOF'
#!/usr/bin/env bash
# Simulated ancient/broken node that reports an unusably old version
echo "v4.0.0"
exit 0
EOF
  chmod +x "${shadow_dir}/node"

  # Shadow npm as truly missing (exit 127 on --version but the wrapper itself
  # is executable so command -v finds it, then npm --version returns empty).
  cat > "${shadow_dir}/npm" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
  chmod +x "${shadow_dir}/npm"

  local output rc=0
  output=$(PATH="${shadow_dir}:${PATH}" HOME="$fake_home" FSUITE_TELEMETRY=0 \
    "${INSTALLER}" --prefix "$prefix" --no-verify 2>&1) || rc=$?

  # check_deps should emit "version 18+ required" (node too old) and fail.
  if (( rc != 0 )) && { [[ "$output" == *"not found"* ]] || [[ "$output" == *"missing"* ]] || \
      [[ "$output" == *"Dependency check failed"* ]] || [[ "$output" == *"version 18+ required"* ]]; }; then
    pass "check_deps reports unsatisfied dependency clearly and exits non-zero"
  else
    fail "check_deps should flag unsatisfied deps and exit non-zero" \
      "rc=$rc output=${output:0:300}"
  fi
}

test_skip_deps_bypasses_dependency_check() {
  if ! installer_supports "--skip-deps"; then
    skip "--skip-deps not in this installer"
    return
  fi

  # Shadow node/npm so a normal check would fail.
  local shadow_dir="${TEST_ROOT}/nodeps-bin"
  local prefix="${TEST_ROOT}/nodeps-prefix"
  local fake_home="${TEST_ROOT}/nodeps-home"
  mkdir -p "$shadow_dir"
  local real_bash_dir
  real_bash_dir="$(dirname "$(command -v bash)")"

  for cmd in node npm; do
    cat > "${shadow_dir}/${cmd}" <<'EOF'
#!/usr/bin/env bash
echo "blocked" >&2; exit 127
EOF
    chmod +x "${shadow_dir}/${cmd}"
  done

  local rc=0
  PATH="${real_bash_dir}:${shadow_dir}:$(echo "$PATH" | tr ':' '\n' \
    | grep -v "^${shadow_dir}$" | tr '\n' ':' | sed 's/:$//')" \
    HOME="$fake_home" FSUITE_TELEMETRY=0 \
    "${INSTALLER}" --prefix "$prefix" --skip-deps --skip-mcp --no-verify 2>/dev/null || rc=$?

  if (( rc == 0 )) && [[ -f "${prefix}/bin/fsuite" ]]; then
    pass "--skip-deps bypasses dependency check and allows install to complete"
  else
    fail "--skip-deps should bypass dep check and allow install" \
      "rc=$rc fsuite_present=$([[ -f "${prefix}/bin/fsuite" ]] && echo yes || echo no)"
  fi
}

# ── §2  Source install flow ───────────────────────────────────────────────────

test_source_install_all_12_tools_present() {
  local prefix="${TEST_ROOT}/src-tools"
  local fake_home="${TEST_ROOT}/src-tools-home"
  run_installer "$fake_home" --prefix "$prefix" --skip-mcp --no-verify >/dev/null 2>&1 || {
    fail "Source install should succeed"
    return
  }

  local missing=()
  local tool
  for tool in "${EXPECTED_TOOLS[@]}"; do
    [[ -f "${prefix}/bin/${tool}" ]] || missing+=("$tool")
  done

  if (( ${#missing[@]} == 0 )); then
    pass "All 12 tools are present in bin/ after source install"
  else
    fail "Source install is missing tools in bin/" "missing: ${missing[*]}"
  fi
}

test_source_install_all_6_share_files_present() {
  local prefix="${TEST_ROOT}/src-share"
  local fake_home="${TEST_ROOT}/src-share-home"
  run_installer "$fake_home" --prefix "$prefix" --skip-mcp --no-verify >/dev/null 2>&1 || {
    fail "Source install should succeed"
    return
  }

  local missing=()
  local sf
  for sf in "${EXPECTED_SHARE_FILES[@]}"; do
    [[ -f "${prefix}/share/fsuite/${sf}" ]] || missing+=("$sf")
  done

  if (( ${#missing[@]} == 0 )); then
    pass "All ${#EXPECTED_SHARE_FILES[@]} share files are present in share/fsuite/ after source install"
  else
    fail "Source install is missing share files" "missing: ${missing[*]}"
  fi
}

test_source_install_tool_permissions_755() {
  local prefix="${TEST_ROOT}/perm-tools"
  local fake_home="${TEST_ROOT}/perm-tools-home"
  run_installer "$fake_home" --prefix "$prefix" --skip-mcp --no-verify >/dev/null 2>&1 || {
    fail "Source install should succeed"
    return
  }

  local bad=()
  local tool
  for tool in "${EXPECTED_TOOLS[@]}"; do
    local perms
    perms="$(stat -c '%a' "${prefix}/bin/${tool}" 2>/dev/null || echo missing)"
    [[ "$perms" == "755" ]] || bad+=("${tool}:${perms}")
  done

  if (( ${#bad[@]} == 0 )); then
    pass "All installed tools have 755 permissions"
  else
    fail "Some tools have wrong permissions" "bad: ${bad[*]}"
  fi
}

test_source_install_shell_lib_permissions_644() {
  local prefix="${TEST_ROOT}/perm-libs"
  local fake_home="${TEST_ROOT}/perm-libs-home"
  run_installer "$fake_home" --prefix "$prefix" --skip-mcp --no-verify >/dev/null 2>&1 || {
    fail "Source install should succeed"
    return
  }

  # Shell library files must be 644 (not executable).
  local lib_files=(_fsuite_common.sh _fsuite_db.sh)
  local bad=()
  local sf
  for sf in "${lib_files[@]}"; do
    local perms
    perms="$(stat -c '%a' "${prefix}/share/fsuite/${sf}" 2>/dev/null || echo missing)"
    [[ "$perms" == "644" ]] || bad+=("${sf}:${perms}")
  done

  if (( ${#bad[@]} == 0 )); then
    pass "Shell library share files have 644 permissions"
  else
    fail "Some shell library share files have wrong permissions" "bad: ${bad[*]}"
  fi
}

test_source_install_fmetrics_helpers_permissions_755() {
  local prefix="${TEST_ROOT}/perm-py-exec"
  local fake_home="${TEST_ROOT}/perm-py-exec-home"
  run_installer "$fake_home" --prefix "$prefix" --skip-mcp --no-verify >/dev/null 2>&1 || {
    fail "Source install should succeed"
    return
  }

local helpers=(fmetrics-predict.py fmetrics-import.py)
local bad=()
local helper perms
for helper in "${helpers[@]}"; do
perms="$(stat -c '%a' "${prefix}/share/fsuite/${helper}" 2>/dev/null || echo missing)"
[[ "$perms" == "755" ]] || bad+=("${helper}:${perms}")
done
if (( ${#bad[@]} == 0 )); then
    pass "fmetrics helper Python files installed with 755 permissions"
else
    fail "fmetrics helper Python files should be 755" "bad: ${bad[*]}"
fi
}

test_source_install_non_executable_py_engines_644() {
  local prefix="${TEST_ROOT}/perm-py-lib"
  local fake_home="${TEST_ROOT}/perm-py-lib-home"
  run_installer "$fake_home" --prefix "$prefix" --skip-mcp --no-verify >/dev/null 2>&1 || {
    fail "Source install should succeed"
    return
  }

  # fprobe-engine.py and fs-engine.py should be 644 (library, not executable).
  local lib_py_files=(fprobe-engine.py fs-engine.py)
  local bad=()
  local sf
  for sf in "${lib_py_files[@]}"; do
    local perms
    perms="$(stat -c '%a' "${prefix}/share/fsuite/${sf}" 2>/dev/null || echo missing)"
    [[ "$perms" == "644" ]] || bad+=("${sf}:${perms}")
  done

  if (( ${#bad[@]} == 0 )); then
    pass "Non-executable Python engine files installed with 644 permissions"
  else
    fail "Some Python engine files have wrong permissions" "bad: ${bad[*]}"
  fi
}

# ── §3  MCP setup ────────────────────────────────────────────────────────────

test_mcp_npm_install_populates_node_modules() {
  if [[ ! -d "${MCP_DIR}" ]]; then
    skip "mcp/ directory not present in repo"
    return
  fi

  if ! command -v npm >/dev/null 2>&1; then
    skip "npm not available in test environment"
    return
  fi

  # Work in a copy so we don't mutate the repo's node_modules.
  local mcp_copy="${TEST_ROOT}/mcp-npm-copy"
  cp -r "${MCP_DIR}" "$mcp_copy"
  rm -rf "${mcp_copy}/node_modules"

  local rc=0
  npm --prefix "$mcp_copy" install --silent 2>/dev/null || rc=$?

  if (( rc == 0 )) && [[ -d "${mcp_copy}/node_modules" ]]; then
    pass "npm install in mcp/ succeeds and populates node_modules"
  else
    fail "npm install in mcp/ should populate node_modules" "rc=$rc"
  fi
}

test_mcp_index_js_syntax_clean() {
  if [[ ! -f "${MCP_DIR}/index.js" ]]; then
    skip "mcp/index.js not present"
    return
  fi

  if ! command -v node >/dev/null 2>&1; then
    skip "node not available in test environment"
    return
  fi

  local rc=0
  node --check "${MCP_DIR}/index.js" 2>/dev/null || rc=$?

  if (( rc == 0 )); then
    pass "node --check mcp/index.js passes (no syntax errors)"
  else
    local err
    err="$(node --check "${MCP_DIR}/index.js" 2>&1 || true)"
    fail "mcp/index.js should pass node syntax check" "$err"
  fi
}

test_mcp_setup_runs_during_normal_install() {
  if ! command -v npm >/dev/null 2>&1; then
    skip "npm not available in test environment"
    return
  fi

  local prefix="${TEST_ROOT}/mcp-auto"
  local fake_home="${TEST_ROOT}/mcp-auto-home"
  local output rc=0
  output=$(run_installer "$fake_home" --prefix "$prefix" --no-verify 2>&1) || rc=$?

  # The installer should emit "npm install" progress text.
  if [[ "$output" == *"npm install"* ]] || [[ "$output" == *"MCP server"* ]]; then
    pass "MCP setup (npm install) runs during a normal install"
  else
    fail "Normal install should run MCP setup" "rc=$rc output=${output:0:300}"
  fi
}

# ── §4  Agent configuration ──────────────────────────────────────────────────

test_mcp_only_configures_claude_mcp_json() {
  if ! installer_supports "--mcp-only"; then
    skip "--mcp-only not in this installer"
    return
  fi

  if ! command -v npm >/dev/null 2>&1; then
    skip "npm not available in test environment"
    return
  fi

  local fake_home="${TEST_ROOT}/claude-mcp-home"
  mkdir -p "${fake_home}/.claude" "${fake_home}/.codex"

  local rc=0
  HOME="$fake_home" FSUITE_TELEMETRY=0 \
    "${INSTALLER}" --mcp-only 2>/dev/null || rc=$?

  local content
  content="$(cat "${fake_home}/.claude/mcp.json" 2>/dev/null || echo "")"

  if [[ "$content" == *"fsuite"* ]]; then
    pass "--mcp-only adds fsuite entry to Claude Code mcp.json"
  else
    fail "--mcp-only should write fsuite entry to ~/.claude/mcp.json" \
      "rc=$rc content=$content"
  fi
}

test_mcp_only_configures_codex_config_toml() {
  if ! installer_supports "--mcp-only"; then
    skip "--mcp-only not in this installer"
    return
  fi

  if ! command -v npm >/dev/null 2>&1; then
    skip "npm not available in test environment"
    return
  fi

  local fake_home="${TEST_ROOT}/codex-mcp-home"
  mkdir -p "${fake_home}/.claude" "${fake_home}/.codex"
  # Pre-existing config without fsuite.
  printf '[settings]\ntheme = "dark"\n' > "${fake_home}/.codex/config.toml"

  HOME="$fake_home" FSUITE_TELEMETRY=0 \
    "${INSTALLER}" --mcp-only 2>/dev/null || true

  local content
  content="$(cat "${fake_home}/.codex/config.toml" 2>/dev/null || echo "")"

  if [[ "$content" == *"[mcp_servers.fsuite]"* ]]; then
    pass "--mcp-only adds [mcp_servers.fsuite] to Codex config.toml"
  else
    fail "--mcp-only should add [mcp_servers.fsuite] to ~/.codex/config.toml" \
      "content=$content"
  fi
}

test_agent_config_mcp_json_idempotent() {
  if ! command -v npm >/dev/null 2>&1; then
    skip "npm not available in test environment"
    return
  fi

  local fake_home="${TEST_ROOT}/idem-claude-home"
  mkdir -p "${fake_home}/.claude" "${fake_home}/.codex"

  # Run full install twice with the same HOME.
  local prefix="${TEST_ROOT}/idem-prefix"
  run_installer "$fake_home" --prefix "$prefix" --no-verify 2>/dev/null || true
  run_installer "$fake_home" --prefix "$prefix" --no-verify 2>/dev/null || true

  local content
  content="$(cat "${fake_home}/.claude/mcp.json" 2>/dev/null || echo "")"

  # "fsuite" key should appear exactly once (as a JSON key).
  local count
  count="$(echo "$content" | grep -c '"fsuite"' 2>/dev/null || echo 0)"

  if [[ "$count" -eq 1 ]]; then
    pass "Repeated installs are idempotent: fsuite appears exactly once in mcp.json"
  else
    fail "Repeated installs should not duplicate fsuite entry in mcp.json" \
      "count=$count content=$content"
  fi
}

test_agent_config_codex_toml_idempotent() {
  local fake_home="${TEST_ROOT}/idem-codex-home"
  mkdir -p "${fake_home}/.claude" "${fake_home}/.codex"
  printf '[settings]\ntheme = "dark"\n' > "${fake_home}/.codex/config.toml"

  local prefix="${TEST_ROOT}/idem-codex-prefix"
  # Run install twice.
  run_installer "$fake_home" --prefix "$prefix" --no-verify 2>/dev/null || true
  run_installer "$fake_home" --prefix "$prefix" --no-verify 2>/dev/null || true

  local content
  content="$(cat "${fake_home}/.codex/config.toml" 2>/dev/null || echo "")"

  local count
  count="$(echo "$content" | grep -c '\[mcp_servers\.fsuite\]' 2>/dev/null || echo 0)"

  if [[ "$count" -eq 1 ]]; then
    pass "Repeated installs are idempotent: [mcp_servers.fsuite] appears exactly once in config.toml"
  else
    fail "Repeated installs should not duplicate [mcp_servers.fsuite] in config.toml" \
      "count=$count"
  fi
}

# ── §5  Uninstall ────────────────────────────────────────────────────────────

test_uninstall_removes_all_tools() {
  if ! installer_supports "--uninstall"; then
    skip "--uninstall not in this installer"
    return
  fi

  local prefix="${TEST_ROOT}/uninstall-tools"
  local fake_home="${TEST_ROOT}/uninstall-tools-home"

  run_installer "$fake_home" --prefix "$prefix" --no-verify >/dev/null 2>&1 || {
    fail "Pre-uninstall: source install should succeed"
    return
  }

  [[ -f "${prefix}/bin/fsuite" ]] || {
    fail "Pre-uninstall: fsuite should exist before uninstall"
    return
  }

  local rc=0
  HOME="$fake_home" FSUITE_TELEMETRY=0 \
    "${INSTALLER}" --prefix "$prefix" --uninstall 2>/dev/null || rc=$?

  local remaining=()
  local tool
  for tool in "${EXPECTED_TOOLS[@]}"; do
    [[ -f "${prefix}/bin/${tool}" ]] && remaining+=("$tool")
  done

  if (( rc == 0 )) && (( ${#remaining[@]} == 0 )); then
    pass "--uninstall removes all 12 tools from prefix/bin/"
  else
    fail "--uninstall should remove all tools from prefix/bin/" \
      "rc=$rc remaining: ${remaining[*]:-none}"
  fi
}

test_uninstall_removes_share_dir() {
  if ! installer_supports "--uninstall"; then
    skip "--uninstall not in this installer"
    return
  fi

  local prefix="${TEST_ROOT}/uninstall-share"
  local fake_home="${TEST_ROOT}/uninstall-share-home"

  run_installer "$fake_home" --prefix "$prefix" --no-verify >/dev/null 2>&1 || {
    fail "Pre-uninstall: source install should succeed"
    return
  }

  HOME="$fake_home" FSUITE_TELEMETRY=0 \
    "${INSTALLER}" --prefix "$prefix" --uninstall 2>/dev/null || true

  if [[ ! -d "${prefix}/share/fsuite" ]]; then
    pass "--uninstall removes the share/fsuite/ directory"
  else
    local remaining_files=()
    local sf
    for sf in "${EXPECTED_SHARE_FILES[@]}"; do
      [[ -f "${prefix}/share/fsuite/${sf}" ]] && remaining_files+=("$sf")
    done
    if (( ${#remaining_files[@]} == 0 )); then
      pass "--uninstall removes all share files (directory may remain empty)"
    else
      fail "--uninstall should remove share files" "remaining: ${remaining_files[*]}"
    fi
  fi
}

test_uninstall_removes_claude_mcp_entry() {
  if ! installer_supports "--uninstall"; then
    skip "--uninstall not in this installer"
    return
  fi

  if ! command -v npm >/dev/null 2>&1; then
    skip "npm not available (needed so install writes the MCP config)"
    return
  fi

  local prefix="${TEST_ROOT}/uninstall-mcp"
  local fake_home="${TEST_ROOT}/uninstall-mcp-home"
  mkdir -p "${fake_home}/.claude" "${fake_home}/.codex"

  # Install (this writes the MCP config).
  run_installer "$fake_home" --prefix "$prefix" --no-verify 2>/dev/null || true

  local before
  before="$(cat "${fake_home}/.claude/mcp.json" 2>/dev/null || echo "")"
  [[ "$before" == *"fsuite"* ]] || {
    fail "Pre-uninstall: fsuite should be in mcp.json after install" "content=$before"
    return
  }

  # Uninstall.
  HOME="$fake_home" FSUITE_TELEMETRY=0 \
    "${INSTALLER}" --prefix "$prefix" --uninstall 2>/dev/null || true

  local after
  after="$(cat "${fake_home}/.claude/mcp.json" 2>/dev/null || echo "")"

  if [[ "$after" != *'"fsuite"'* ]]; then
    pass "--uninstall removes fsuite entry from Claude Code mcp.json"
  else
    fail "--uninstall should remove fsuite from mcp.json" "content=$after"
  fi
}

test_uninstall_removes_codex_mcp_entry() {
  if ! installer_supports "--uninstall"; then
    skip "--uninstall not in this installer"
    return
  fi

  local prefix="${TEST_ROOT}/uninstall-codex"
  local fake_home="${TEST_ROOT}/uninstall-codex-home"
  mkdir -p "${fake_home}/.claude" "${fake_home}/.codex"
  printf '[settings]\ntheme = "dark"\n' > "${fake_home}/.codex/config.toml"

  run_installer "$fake_home" --prefix "$prefix" --no-verify 2>/dev/null || true

  local before
  before="$(cat "${fake_home}/.codex/config.toml" 2>/dev/null || echo "")"
  [[ "$before" == *"[mcp_servers.fsuite]"* ]] || {
    fail "Pre-uninstall: [mcp_servers.fsuite] should be in config.toml after install" \
      "content=$before"
    return
  }

  HOME="$fake_home" FSUITE_TELEMETRY=0 \
    "${INSTALLER}" --prefix "$prefix" --uninstall 2>/dev/null || true

  local after
  after="$(cat "${fake_home}/.codex/config.toml" 2>/dev/null || echo "")"

  if [[ "$after" != *"[mcp_servers.fsuite]"* ]]; then
    pass "--uninstall removes [mcp_servers.fsuite] from Codex config.toml"
  else
    fail "--uninstall should remove [mcp_servers.fsuite] from config.toml" "content=$after"
  fi
}

# ── §6  Edge cases ────────────────────────────────────────────────────────────

test_mcp_only_skips_tool_install() {
  if ! installer_supports "--mcp-only"; then
    skip "--mcp-only not in this installer"
    return
  fi

  local prefix="${TEST_ROOT}/mcp-only-skip"
  local fake_home="${TEST_ROOT}/mcp-only-skip-home"
  mkdir -p "${fake_home}/.claude" "${fake_home}/.codex"

  HOME="$fake_home" FSUITE_TELEMETRY=0 \
    "${INSTALLER}" --prefix "$prefix" --mcp-only 2>/dev/null || true

  local found=()
  local tool
  for tool in "${EXPECTED_TOOLS[@]}"; do
    [[ -f "${prefix}/bin/${tool}" ]] && found+=("$tool")
  done

  if (( ${#found[@]} == 0 )); then
    pass "--mcp-only does not install tool binaries into prefix/bin/"
  else
    fail "--mcp-only should skip tool install" "found in bin/: ${found[*]}"
  fi
}

test_skip_mcp_skips_mcp_and_agent_config() {
  if ! installer_supports "--skip-mcp"; then
    skip "--skip-mcp not in this installer"
    return
  fi

  local prefix="${TEST_ROOT}/skip-mcp"
  local fake_home="${TEST_ROOT}/skip-mcp-home"
  mkdir -p "${fake_home}/.claude" "${fake_home}/.codex"

  local output rc=0
  output=$(HOME="$fake_home" FSUITE_TELEMETRY=0 \
    "${INSTALLER}" --prefix "$prefix" --skip-mcp --no-verify 2>&1) || rc=$?

  # Tools should be installed.
  local tools_ok=0
  [[ -f "${prefix}/bin/fsuite" ]] && tools_ok=1

  # MCP/agent config should NOT have run (no "Configuring AI agents" text).
  local mcp_ran=0
  [[ "$output" == *"Configuring AI agents"* ]] && mcp_ran=1

  if (( tools_ok == 1 )) && (( mcp_ran == 0 )); then
    pass "--skip-mcp installs tools but skips MCP setup and agent configuration"
  else
    fail "--skip-mcp should install tools and skip MCP/agent config" \
      "rc=$rc tools_ok=$tools_ok mcp_ran=$mcp_ran"
  fi
}

test_double_install_is_idempotent() {
  local prefix="${TEST_ROOT}/idempotent"
  local fake_home="${TEST_ROOT}/idempotent-home"
  mkdir -p "${fake_home}/.claude" "${fake_home}/.codex"

  local rc1=0 rc2=0
  run_installer "$fake_home" --prefix "$prefix" --no-verify >/dev/null 2>&1 || rc1=$?
  run_installer "$fake_home" --prefix "$prefix" --no-verify >/dev/null 2>&1 || rc2=$?

  if (( rc1 != 0 )) || (( rc2 != 0 )); then
    fail "Double install: both runs must exit 0" "rc1=$rc1 rc2=$rc2"
    return
  fi

  local bad=()
  local tool
  for tool in "${EXPECTED_TOOLS[@]}"; do
    [[ -x "${prefix}/bin/${tool}" ]] || bad+=("$tool")
  done

  if (( ${#bad[@]} == 0 )); then
    pass "Double install is idempotent: all 12 tools present and executable after two runs"
  else
    fail "Double install left some tools non-executable" "bad: ${bad[*]}"
  fi
}

test_no_verify_flag_skips_verification() {
  local prefix="${TEST_ROOT}/no-verify"
  local fake_home="${TEST_ROOT}/no-verify-home"
  local output rc=0
  output=$(run_installer "$fake_home" --prefix "$prefix" --skip-mcp --no-verify 2>&1) || rc=$?

  # Install succeeds and the "Verifying" section should not appear.
  local verify_ran=0
  [[ "$output" == *"Verifying"* ]] && verify_ran=1

  if (( rc == 0 )) && [[ -f "${prefix}/bin/fsuite" ]] && (( verify_ran == 0 )); then
    pass "--no-verify completes install and skips post-install verification"
  else
    fail "--no-verify install should succeed and skip verification" \
      "rc=$rc verify_ran=$verify_ran"
  fi
}

test_unknown_flag_exits_nonzero() {
  local rc=0
  "${INSTALLER}" --this-flag-does-not-exist-9x7z 2>/dev/null || rc=$?
  if (( rc != 0 )); then
    pass "Unknown flag causes installer to exit non-zero"
  else
    fail "Installer should reject unknown flags with non-zero exit"
  fi
}

test_installed_tools_are_executable() {
  local prefix="${TEST_ROOT}/exec-check"
  local fake_home="${TEST_ROOT}/exec-check-home"
  run_installer "$fake_home" --prefix "$prefix" --skip-mcp --no-verify >/dev/null 2>&1 || {
    fail "Install to temp prefix should succeed"
    return
  }

  local not_exec=()
  local tool
  for tool in "${EXPECTED_TOOLS[@]}"; do
    [[ -x "${prefix}/bin/${tool}" ]] || not_exec+=("$tool")
  done

  if (( ${#not_exec[@]} == 0 )); then
    pass "All installed tools are executable from the temp prefix"
  else
    fail "Some installed tools are not executable" "not_exec: ${not_exec[*]}"
  fi
}

# ── Runner ────────────────────────────────────────────────────────────────────

main() {
  echo -e "${BOLD}══════════════════════════════════════════${NC}"
  echo -e "${BOLD}  fsuite Installer Automation Test Suite  ${NC}"
  echo -e "${BOLD}══════════════════════════════════════════${NC}"
  echo ""
  echo "Installer : ${INSTALLER}"
  echo "MCP dir   : ${MCP_DIR}"
  echo ""

  [[ -x "${INSTALLER}" ]] || {
    echo "ERROR: Installer missing or not executable: ${INSTALLER}" >&2
    exit 1
  }

  setup
  trap teardown EXIT

  echo -e "${CYAN}── §1  Dependency detection ─────────────────${NC}"
  run_test "check_deps detects bash present"           test_check_deps_reports_bash_present
  run_test "check_deps detects python3 present"        test_check_deps_reports_python3_present
  run_test "check_deps detects node present"           test_check_deps_reports_node_present
  run_test "check_deps reports missing dep clearly"    test_check_deps_reports_missing_dep_clearly
  run_test "--skip-deps bypasses dep check"            test_skip_deps_bypasses_dependency_check
  echo ""

  echo -e "${CYAN}── §2  Source install flow ──────────────────${NC}"
  run_test "All 12 tools present in bin/"               test_source_install_all_12_tools_present
run_test "All 6 share files present in share/fsuite/" test_source_install_all_6_share_files_present
  run_test "Tool permissions are 755"                   test_source_install_tool_permissions_755
  run_test "Shell lib permissions are 644"              test_source_install_shell_lib_permissions_644
run_test "fmetrics helpers are 755"                  test_source_install_fmetrics_helpers_permissions_755
  run_test "Non-exec Python engines are 644"            test_source_install_non_executable_py_engines_644
  echo ""

  echo -e "${CYAN}── §3  MCP setup ────────────────────────────${NC}"
  run_test "npm install populates node_modules"         test_mcp_npm_install_populates_node_modules
  run_test "mcp/index.js passes node --check"           test_mcp_index_js_syntax_clean
  run_test "MCP setup runs during normal install"       test_mcp_setup_runs_during_normal_install
  echo ""

  echo -e "${CYAN}── §4  Agent configuration ──────────────────${NC}"
  run_test "--mcp-only writes to mcp.json"              test_mcp_only_configures_claude_mcp_json
  run_test "--mcp-only writes to config.toml"           test_mcp_only_configures_codex_config_toml
  run_test "mcp.json is idempotent on re-install"       test_agent_config_mcp_json_idempotent
  run_test "config.toml is idempotent on re-install"    test_agent_config_codex_toml_idempotent
  echo ""

  echo -e "${CYAN}── §5  Uninstall ────────────────────────────${NC}"
  run_test "--uninstall removes all 12 tools"           test_uninstall_removes_all_tools
  run_test "--uninstall removes share/fsuite/"          test_uninstall_removes_share_dir
  run_test "--uninstall removes Claude mcp.json entry"  test_uninstall_removes_claude_mcp_entry
  run_test "--uninstall removes Codex config entry"     test_uninstall_removes_codex_mcp_entry
  echo ""

  echo -e "${CYAN}── §6  Edge cases ───────────────────────────${NC}"
  run_test "--mcp-only skips tool install"              test_mcp_only_skips_tool_install
  run_test "--skip-mcp skips MCP and agent config"      test_skip_mcp_skips_mcp_and_agent_config
  run_test "Double install is idempotent"               test_double_install_is_idempotent
  run_test "--no-verify skips verification step"        test_no_verify_flag_skips_verification
  run_test "Unknown flag exits non-zero"                test_unknown_flag_exits_nonzero
  run_test "Installed tools are executable"             test_installed_tools_are_executable
  echo ""

  echo -e "${BOLD}══════════════════════════════════════════${NC}"
  echo -e "${BOLD}  Test Results${NC}"
  echo -e "${BOLD}══════════════════════════════════════════${NC}"
  printf "Total:   %d\n" "${TESTS_RUN}"
  echo -e "${GREEN}Passed:  ${TESTS_PASSED}${NC}"
  echo -e "${YELLOW}Skipped: ${TESTS_SKIPPED}${NC}"

  if (( TESTS_FAILED > 0 )); then
    echo -e "${RED}Failed:  ${TESTS_FAILED}${NC}"
    exit 1
  fi

  echo -e "${GREEN}All tests passed!${NC}"
}

main "$@"
