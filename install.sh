#!/usr/bin/env bash
# install.sh — production-grade autobot installer for fsuite.
# Safe to curl-pipe: curl -fsSL <url> | bash
# Safe to run multiple times (idempotent).

set -euo pipefail

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
VERSION="2.3.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_PREFIX="${HOME}/.local"
PREFIX="$DEFAULT_PREFIX"
MODE="source"
PACKAGE_PATH=""
VERIFY=1
SKIP_DEPS=0
SKIP_MCP=0
MCP_ONLY=0
DO_UNINSTALL=0

TOOLS=(fsuite ftree fsearch fcontent fmap fread fcase fedit fmetrics freplay fprobe fs fls)
SHARE_FILES=(_fsuite_common.sh _fsuite_db.sh fmetrics-predict.py fmetrics-import.py fprobe-engine.py fs-engine.py)

# ---------------------------------------------------------------------------
# Colors
# ---------------------------------------------------------------------------
if [[ -t 1 ]] || [[ "${FORCE_COLOR:-0}" != "0" ]]; then
  C_GREEN="\033[0;32m"
  C_RED="\033[0;31m"
  C_YELLOW="\033[0;33m"
  C_CYAN="\033[0;36m"
  C_BOLD="\033[1m"
  C_RESET="\033[0m"
else
  C_GREEN="" C_RED="" C_YELLOW="" C_CYAN="" C_BOLD="" C_RESET=""
fi

ok()   { echo -e "${C_GREEN}✓${C_RESET} $*"; }
fail() { echo -e "${C_RED}✗${C_RESET} $*"; }
warn() { echo -e "${C_YELLOW}⚠${C_RESET}  $*"; }
info() { echo -e "${C_CYAN}→${C_RESET} $*"; }

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
die() {
  local code=1
  if [[ "${1:-}" =~ ^[0-9]+$ ]]; then code="$1"; shift; fi
  echo -e "${C_RED}install.sh: $*${C_RESET}" >&2
  exit "$code"
}

has() { command -v "$1" >/dev/null 2>&1; }

run_privileged() {
  if "$@"; then
    return 0
  fi
  if has sudo; then
    sudo "$@"
    return 0
  fi
  die "Command failed and sudo is not available: $*"
}

# ---------------------------------------------------------------------------
# Banner
# ---------------------------------------------------------------------------
print_banner() {
  echo -e "${C_BOLD}${C_CYAN}"
  echo "  ███████╗███████╗██╗   ██╗██╗████████╗███████╗"
  echo "  ██╔════╝██╔════╝██║   ██║██║╚══██╔══╝██╔════╝"
  echo "  █████╗  ███████╗██║   ██║██║   ██║   █████╗  "
  echo "  ██╔══╝  ╚════██║██║   ██║██║   ██║   ██╔══╝  "
  echo "  ██║     ███████║╚██████╔╝██║   ██║   ███████╗"
  echo "  ╚═╝     ╚══════╝ ╚═════╝ ╚═╝   ╚═╝   ╚══════╝"
  echo -e "${C_RESET}"
  echo -e "  ${C_BOLD}fsuite installer v${VERSION}${C_RESET}"
  echo ""
}

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
usage() {
cat <<EOF
fsuite installer v${VERSION}

USAGE
  ./install.sh [options]

OPTIONS
  --user              Install into ~/.local (default)
  --system            Install into /usr/local
  --prefix PATH       Install into PATH
  --package PATH      Install an existing .deb with dpkg
  --no-verify         Skip post-install verification
  --skip-deps         Skip dependency check
  --skip-mcp          Skip MCP setup and agent configuration
  --mcp-only          Only run MCP setup + agent config (no tool install)
  --uninstall         Remove tools from PREFIX and MCP configs
  --version           Print installer version
  -h, --help          Show help

EXAMPLES
  ./install.sh
  ./install.sh --system
  ./install.sh --prefix /opt/fsuite
  ./install.sh --package ../fsuite_2.3.0-1_all.deb
  ./install.sh --skip-deps --skip-mcp
  ./install.sh --mcp-only
  ./install.sh --uninstall

CURL INSTALL
  curl -fsSL https://raw.githubusercontent.com/user/fsuite/main/install.sh | bash
EOF
}

# ---------------------------------------------------------------------------
# 1. Dependency checker
# ---------------------------------------------------------------------------
check_deps() {
  echo ""
  echo -e "${C_BOLD}Checking dependencies...${C_RESET}"
  echo ""

  local missing_required=()

  # --- Required: runtime environment ---
  echo -e "  ${C_BOLD}Core requirements${C_RESET}"

  # bash 4+
  local bash_ver
  bash_ver="${BASH_VERSINFO[0]}"
  if (( bash_ver >= 4 )); then
    ok "  bash ${BASH_VERSION} (>= 4 required)"
  else
    fail "  bash ${BASH_VERSION} — version 4+ required"
    missing_required+=("bash4")
  fi

  # python3
  if has python3; then
    local py_ver
    py_ver="$(python3 --version 2>&1 | awk '{print $2}')"
    ok "  python3 ${py_ver}"
  else
    fail "  python3 — not found"
    missing_required+=("python3")
  fi

  # node 18+
  if has node; then
    local node_ver node_maj
    node_ver="$(node --version 2>&1 | tr -d 'v')"
    node_maj="$(echo "$node_ver" | cut -d. -f1)"
    if (( node_maj >= 18 )); then
      ok "  node v${node_ver} (>= 18 required)"
    else
      fail "  node v${node_ver} — version 18+ required"
      missing_required+=("node18")
    fi
  else
    fail "  node — not found (required for MCP server)"
    missing_required+=("node")
  fi

  # npm
  if has npm; then
    local npm_ver
    npm_ver="$(npm --version 2>&1)"
    ok "  npm ${npm_ver}"
  else
    fail "  npm — not found"
    missing_required+=("npm")
  fi

  echo ""
  echo -e "  ${C_BOLD}Required by tools${C_RESET}"

  # sqlite3 (fcase, freplay, fmetrics)
  if has sqlite3; then
    ok "  sqlite3 — fcase / freplay / fmetrics"
  else
    fail "  sqlite3 — missing (required by fcase, freplay, fmetrics)"
    missing_required+=("sqlite3")
  fi

  # ripgrep / rg (fcontent)
  if has rg; then
    local rg_ver
    rg_ver="$(rg --version 2>&1 | head -1 | awk '{print $2}')"
    ok "  ripgrep (rg) ${rg_ver} — fcontent"
  else
    fail "  ripgrep (rg) — missing (required by fcontent)"
    missing_required+=("ripgrep")
  fi

  # perl (fread)
  if has perl; then
    local perl_ver
    perl_ver="$(perl -e 'print $^V' 2>&1)"
    ok "  perl ${perl_ver} — fread"
  else
    fail "  perl — missing (required by fread)"
    missing_required+=("perl")
  fi

  echo ""
  echo -e "  ${C_BOLD}Optional enhancements${C_RESET}"

  # fd-find (fsearch)
  if has fd; then
    ok "  fd — faster backend for fsearch"
  elif has fdfind; then
    ok "  fdfind — faster backend for fsearch"
  else
    warn "  fd-find — not found (fsearch will fall back to find)"
  fi

  # tree (ftree tree mode)
  if has tree; then
    ok "  tree — ftree tree mode"
  else
    warn "  tree — not found (ftree tree mode unavailable)"
  fi

  echo ""

  if [[ ${#missing_required[@]} -gt 0 ]]; then
    echo -e "${C_RED}${C_BOLD}Missing required dependencies: ${missing_required[*]}${C_RESET}"
    echo ""
    echo "Install suggestions:"
    echo "  Debian/Ubuntu: sudo apt install sqlite3 ripgrep perl nodejs npm python3"
    echo "  macOS:         brew install sqlite ripgrep perl node python3"
    echo ""
    die "Dependency check failed. Use --skip-deps to bypass."
  fi

  ok "All required dependencies satisfied."
  echo ""
}

# ---------------------------------------------------------------------------
# 2. Install from source
# ---------------------------------------------------------------------------
install_from_source() {
  local bin_dir="${PREFIX}/bin"
  local share_dir="${PREFIX}/share/fsuite"

  info "Installing tools to ${bin_dir} ..."
  run_privileged mkdir -p "$bin_dir" "$share_dir"

  for tool in "${TOOLS[@]}"; do
    [[ -f "${SCRIPT_DIR}/${tool}" ]] || die "Missing tool: ${tool}"
    run_privileged install -m 755 "${SCRIPT_DIR}/${tool}" "${bin_dir}/${tool}"
    ok "  ${tool}"
  done

  info "Installing shared files to ${share_dir} ..."
  local share_file
  local mode
  for share_file in "${SHARE_FILES[@]}"; do
    [[ -f "${SCRIPT_DIR}/${share_file}" ]] || die "Missing shared file: ${share_file}"
    case "$share_file" in
      fmetrics-predict.py|fmetrics-import.py) mode=755 ;;
      *) mode=644 ;;
    esac
    run_privileged install -m "$mode" "${SCRIPT_DIR}/${share_file}" "${share_dir}/${share_file}"
    ok "  ${share_file}"
  done
}

# ---------------------------------------------------------------------------
# 3. Install from .deb package
# ---------------------------------------------------------------------------
install_from_package() {
  [[ -n "$PACKAGE_PATH" ]] || die "Missing package path"
  [[ -f "$PACKAGE_PATH" ]] || die "Package not found: $PACKAGE_PATH"
  has dpkg || die 3 "dpkg is required for --package mode"
  info "Installing package ${PACKAGE_PATH} ..."
  run_privileged dpkg -i "$PACKAGE_PATH"
}

# ---------------------------------------------------------------------------
# 4. MCP setup — npm install in mcp/
# ---------------------------------------------------------------------------
setup_mcp() {
  local mcp_dir="${SCRIPT_DIR}/mcp"

  # When curl-piped SCRIPT_DIR is the tmpdir holding the unpacked script,
  # not a git checkout — skip silently if mcp/ doesn't exist.
  if [[ ! -d "$mcp_dir" ]]; then
    warn "MCP directory not found at ${mcp_dir} — skipping npm install."
    warn "If you want MCP support, clone the repo and re-run install.sh."
    return 0
  fi

  if [[ ! -f "${mcp_dir}/package.json" ]]; then
    warn "No package.json in ${mcp_dir} — skipping npm install."
    return 0
  fi

  info "Running npm install --production in ${mcp_dir} ..."
  if npm install --production --prefix "$mcp_dir" >/dev/null 2>&1; then
    ok "npm install succeeded."
  else
    warn "npm install failed — MCP server may not work, but CLI tools are fine."
    return 0
  fi
}

# ---------------------------------------------------------------------------
# 5. Resolve MCP index.js path
#    For source installs: SCRIPT_DIR/mcp/index.js
#    For package installs: PREFIX/share/fsuite/mcp/index.js (best guess)
# ---------------------------------------------------------------------------
_mcp_index_path() {
  local candidate_src="${SCRIPT_DIR}/mcp/index.js"
  local candidate_pkg="${PREFIX}/share/fsuite/mcp/index.js"
  if [[ -f "$candidate_src" ]]; then
    echo "$candidate_src"
  elif [[ -f "$candidate_pkg" ]]; then
    echo "$candidate_pkg"
  else
    # Return the share path as canonical even if not yet present
    echo "$candidate_pkg"
  fi
}

# ---------------------------------------------------------------------------
# 6. Agent auto-configuration
# ---------------------------------------------------------------------------

# --- Claude Code ---
_configure_claude() {
  local mcp_index
  mcp_index="$(_mcp_index_path)"
  local config_file="${HOME}/.claude/mcp.json"
  local config_dir
  config_dir="$(dirname "$config_file")"

  info "Configuring Claude Code (${config_file}) ..."
  mkdir -p "$config_dir"

  # Build the fsuite entry JSON snippet
  local entry
  entry="$(cat <<JSON
{
  "type": "stdio",
  "command": "node",
  "args": ["${mcp_index}"],
  "env": {"FORCE_COLOR": "3"}
}
JSON
)"

  if [[ -f "$config_file" ]]; then
    # File exists — use python3 to merge safely (no jq dependency)
    local merged
    if merged="$(python3 - "$config_file" "$entry" <<'PYEOF'
import sys, json
cfg = json.load(open(sys.argv[1]))
entry = json.loads(sys.argv[2])
cfg.setdefault("mcpServers", {})
cfg["mcpServers"]["fsuite"] = entry
print(json.dumps(cfg, indent=2))
PYEOF
)"; then
      echo "$merged" > "$config_file"
      ok "  Claude Code — updated ${config_file}"
    else
      warn "  Claude Code — could not parse ${config_file}; skipping. Add manually:"
      _print_claude_manual "$mcp_index"
    fi
  else
    # Create new
    python3 - "$entry" <<'PYEOF' > "$config_file"
import sys, json
entry = json.loads(sys.argv[1])
cfg = {"mcpServers": {"fsuite": entry}}
print(json.dumps(cfg, indent=2))
PYEOF
    ok "  Claude Code — created ${config_file}"
  fi
}

_print_claude_manual() {
  local mcp_index="${1:-<path-to-mcp/index.js>}"
  cat <<EOF
  Manual Claude Code config (~/.claude/mcp.json):
  {
    "mcpServers": {
      "fsuite": {
        "type": "stdio",
        "command": "node",
        "args": ["${mcp_index}"],
        "env": {"FORCE_COLOR": "3"}
      }
    }
  }
EOF
}

# --- Codex ---
_configure_codex() {
  local mcp_index
  mcp_index="$(_mcp_index_path)"
  local config_file="${HOME}/.codex/config.toml"
  local config_dir
  config_dir="$(dirname "$config_file")"

  info "Configuring Codex (${config_file}) ..."
  mkdir -p "$config_dir"

  local toml_block
  toml_block="$(cat <<TOML

[mcp_servers.fsuite]
command = "node"
args = ["${mcp_index}"]
env = { FORCE_COLOR = "3" }
TOML
)"

  if [[ -f "$config_file" ]]; then
    if grep -q '\[mcp_servers\.fsuite\]' "$config_file" 2>/dev/null; then
      ok "  Codex — [mcp_servers.fsuite] already present in ${config_file}"
    else
      echo "$toml_block" >> "$config_file"
      ok "  Codex — appended to ${config_file}"
    fi
  else
    # Create minimal config with just the fsuite block (strip leading newline)
    printf '%s\n' "${toml_block#$'\n'}" > "$config_file"
    ok "  Codex — created ${config_file}"
  fi
}

# --- OpenCode ---
_configure_opencode() {
  local mcp_index
  mcp_index="$(_mcp_index_path)"

  info "Detecting OpenCode config ..."

  # Candidate paths (add more as the project evolves)
  local candidates=(
    "${HOME}/.opencode/config.json"
    "${HOME}/.config/opencode/config.json"
    "${HOME}/.opencode/config.jsonc"
    "${HOME}/.config/opencode/config.jsonc"
  )

  local found_cfg=""
  for c in "${candidates[@]}"; do
    if [[ -f "$c" ]]; then
      found_cfg="$c"
      break
    fi
  done

  if [[ -n "$found_cfg" ]]; then
    # Try JSON merge (works for .json; .jsonc may fail — warn instead)
    if [[ "$found_cfg" == *.json ]]; then
      local merged
      if merged="$(python3 - "$found_cfg" "$mcp_index" <<'PYEOF' 2>/dev/null
import sys, json
cfg = json.load(open(sys.argv[1]))
mcp_path = sys.argv[2]
cfg.setdefault("mcp", {}).setdefault("servers", {})
cfg["mcp"]["servers"]["fsuite"] = {
    "type": "stdio",
    "command": "node",
    "args": [mcp_path],
    "env": {"FORCE_COLOR": "3"}
}
print(json.dumps(cfg, indent=2))
PYEOF
)"; then
        echo "$merged" > "$found_cfg"
        ok "  OpenCode — updated ${found_cfg}"
        return 0
      fi
    fi
    warn "  OpenCode config found at ${found_cfg} but format is unknown or JSONC."
  else
    warn "  OpenCode config not found (checked ${candidates[*]})."
  fi

  echo ""
  echo -e "${C_YELLOW}  OpenCode manual configuration:${C_RESET}"
  cat <<EOF
  Add to your OpenCode config (mcp.servers section):
  "fsuite": {
    "type": "stdio",
    "command": "node",
    "args": ["${mcp_index}"],
    "env": {"FORCE_COLOR": "3"}
  }
EOF
}

configure_agents() {
  echo ""
  echo -e "${C_BOLD}Configuring AI agents...${C_RESET}"
  echo ""
  _configure_claude
  _configure_codex
  _configure_opencode
  echo ""
}

# ---------------------------------------------------------------------------
# 7. Verify install
# ---------------------------------------------------------------------------
verify_install() {
  local path_prefix="$PATH"
  local verify_home=""
  local rc=0
  local verify_output=""
  local mcp_index

  if [[ "$MODE" == "source" ]]; then
    path_prefix="${PREFIX}/bin:${path_prefix}"
    export PATH="$path_prefix"
    export FSUITE_SHARE_DIR="${PREFIX}/share/fsuite"
  fi

  echo ""
  echo -e "${C_BOLD}Verifying install...${C_RESET}"
  echo ""

  # -- Tool --version checks --
  local tool_ok=0 tool_fail=0
  for tool in "${TOOLS[@]}"; do
    if "${tool}" --version >/dev/null 2>&1; then
      ok "  ${tool} --version"
      (( tool_ok++ )) || true
    else
      fail "  ${tool} --version"
      (( tool_fail++ )) || true
    fi
  done

  echo ""

  # -- fprobe engine resolution --
  if command -v fprobe >/dev/null 2>&1; then
    if fprobe strings /etc/hosts >/dev/null 2>&1; then
      ok "  fprobe engine resolution"
    else
      warn "  fprobe engine resolution failed"
    fi
  fi

  # -- fs engine --
  if command -v python3 >/dev/null 2>&1; then
    local fs_engine="${PREFIX}/share/fsuite/fs-engine.py"
    if [[ ! -f "$fs_engine" ]] && [[ -f "${SCRIPT_DIR}/fs-engine.py" ]]; then
      fs_engine="${SCRIPT_DIR}/fs-engine.py"
    fi
    if [[ -f "$fs_engine" ]]; then
      local fs_out
      if fs_out="$(echo '{"query":"test","path":"/tmp"}' \
            | timeout 5 python3 "$fs_engine" 2>&1)"; then
        ok "  fs-engine.py smoke test"
      else
        warn "  fs-engine.py smoke test failed: ${fs_out:0:80}"
      fi
    else
      warn "  fs-engine.py not found at ${fs_engine} — skipping"
    fi
  fi

  # -- MCP server syntax check --
  if (( SKIP_MCP == 0 )); then
    mcp_index="$(_mcp_index_path)"
    if [[ -f "$mcp_index" ]] && has node; then
      if node --check "$mcp_index" >/dev/null 2>&1; then
        ok "  node --check mcp/index.js"
      else
        warn "  node --check mcp/index.js failed — MCP server may have syntax errors"
      fi
    fi
  fi

  echo ""

  # -- fcase functional test (requires sqlite3) --
  if has sqlite3; then
    verify_home="$(mktemp -d)"
    if ! verify_output="$(sqlite3 ':memory:' 'SELECT 1;' 2>&1 >/dev/null)"; then
      rm -rf "$verify_home"
      echo "install.sh: sqlite3 must be functional for fcase verification: ${verify_output:-sqlite3 probe failed}" >&2
      return 3
    fi

    HOME="$verify_home" fcase list -o json >/dev/null 2>"${verify_home}/fcase-verify.err" || rc=$?
    if (( rc != 0 )); then
      verify_output="$(cat "${verify_home}/fcase-verify.err" 2>/dev/null || true)"
    fi
    rm -rf "$verify_home"
    if (( rc != 0 )) && [[ -n "$verify_output" ]]; then
      echo "install.sh: fcase verification failed: ${verify_output}" >&2
    fi
    (( rc == 0 )) && ok "  fcase functional test"
    (( rc == 0 )) || warn "  fcase functional test failed (rc=${rc})"
  fi

  # -- Summary line --
  echo ""
  if (( tool_fail == 0 )); then
    ok "All ${tool_ok} tools verified."
  else
    warn "${tool_ok} tools OK, ${tool_fail} failed."
  fi
}

# ---------------------------------------------------------------------------
# 8. Uninstall
# ---------------------------------------------------------------------------
do_uninstall() {
  echo ""
  echo -e "${C_BOLD}Uninstalling fsuite...${C_RESET}"
  echo ""

  local bin_dir="${PREFIX}/bin"
  local share_dir="${PREFIX}/share/fsuite"

  info "Removing tools from ${bin_dir} ..."
  for tool in "${TOOLS[@]}"; do
    local t="${bin_dir}/${tool}"
    if [[ -f "$t" ]]; then
      run_privileged rm -f "$t"
      ok "  removed ${t}"
    fi
  done

  info "Removing shared files from ${share_dir} ..."
  if [[ -d "$share_dir" ]]; then
    run_privileged rm -rf "$share_dir"
    ok "  removed ${share_dir}"
  fi

  # Remove MCP agent configs
  echo ""
  info "Removing MCP agent configurations ..."

  # Claude Code
  local claude_cfg="${HOME}/.claude/mcp.json"
  if [[ -f "$claude_cfg" ]]; then
    if python3 - "$claude_cfg" <<'PYEOF' > "${claude_cfg}.tmp" 2>/dev/null && mv "${claude_cfg}.tmp" "$claude_cfg"; then
import sys, json
cfg = json.load(open(sys.argv[1]))
cfg.get("mcpServers", {}).pop("fsuite", None)
print(json.dumps(cfg, indent=2))
PYEOF
      ok "  Removed fsuite from ${claude_cfg}"
    else
      warn "  Could not update ${claude_cfg} — remove mcpServers.fsuite manually"
      rm -f "${claude_cfg}.tmp" 2>/dev/null || true
    fi
  fi

  # Codex
  local codex_cfg="${HOME}/.codex/config.toml"
  if [[ -f "$codex_cfg" ]]; then
    # Remove the [mcp_servers.fsuite] block (the section until the next header or EOF)
    python3 - "$codex_cfg" <<'PYEOF' > "${codex_cfg}.tmp" 2>/dev/null && mv "${codex_cfg}.tmp" "$codex_cfg" && ok "  Removed [mcp_servers.fsuite] from ${codex_cfg}" || warn "  Could not update ${codex_cfg} — remove [mcp_servers.fsuite] manually"
import sys, re
content = open(sys.argv[1]).read()
# Remove the fsuite block: from [mcp_servers.fsuite] to next [ header or EOF
content = re.sub(
    r'\n\[mcp_servers\.fsuite\][^\[]*',
    '',
    content,
    flags=re.DOTALL
)
sys.stdout.write(content)
PYEOF
    rm -f "${codex_cfg}.tmp" 2>/dev/null || true
  fi

  echo ""
  ok "Uninstall complete."
}

# ---------------------------------------------------------------------------
# 9. Summary / next steps
# ---------------------------------------------------------------------------
print_summary() {
  local mcp_index
  mcp_index="$(_mcp_index_path)"

  echo ""
  echo -e "${C_BOLD}${C_GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
  echo -e "${C_BOLD}  fsuite ${VERSION} installation complete${C_RESET}"
  echo -e "${C_BOLD}${C_GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
  echo ""

  if [[ "$MODE" == "source" ]]; then
    echo -e "  ${C_BOLD}Install prefix:${C_RESET}  ${PREFIX}"
    echo -e "  ${C_BOLD}Tools:${C_RESET}          ${PREFIX}/bin/{${TOOLS[*]}}"
    echo -e "  ${C_BOLD}Shared files:${C_RESET}   ${PREFIX}/share/fsuite/"
    if (( SKIP_MCP == 0 )); then
      echo -e "  ${C_BOLD}MCP server:${C_RESET}     ${mcp_index}"
    fi
    echo ""
    if [[ ":$PATH:" != *":${PREFIX}/bin:"* ]]; then
      echo -e "  ${C_YELLOW}Add to PATH:${C_RESET}"
      echo -e "    export PATH=\"${PREFIX}/bin:\$PATH\""
      echo ""
    fi
  elif [[ "$MODE" == "package" ]]; then
    echo -e "  ${C_BOLD}Package installed:${C_RESET} ${PACKAGE_PATH}"
    echo ""
  fi

  if (( SKIP_MCP == 0 )); then
    echo -e "  ${C_BOLD}MCP configured for:${C_RESET}"
    [[ -f "${HOME}/.claude/mcp.json" ]]      && echo "    ✓ Claude Code  (~/.claude/mcp.json)"
    [[ -f "${HOME}/.codex/config.toml" ]]    && echo "    ✓ Codex        (~/.codex/config.toml)"
    echo ""
  fi

  echo -e "  ${C_BOLD}Runtime deps:${C_RESET}"
  echo "    sqlite3  — fcase / freplay / fmetrics"
  echo "    ripgrep  — fcontent"
  echo "    perl     — fread"
  echo "    python3  — fmetrics predict, fcase imports, fs"
  echo ""
  echo -e "  ${C_BOLD}Optional:${C_RESET}"
  echo "    fd-find  — faster fsearch backend"
  echo "    tree     — ftree tree mode"
  echo ""
  echo "  Install suggestions:"
  echo "    Debian/Ubuntu: sudo apt install sqlite3 ripgrep tree perl fd-find python3"
  echo "    macOS:         brew install sqlite ripgrep tree python3"
  echo ""
  echo -e "  ${C_BOLD}One-liner re-install:${C_RESET}"
  echo "    curl -fsSL https://raw.githubusercontent.com/user/fsuite/main/install.sh | bash"
  echo ""
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --user)
      MODE="source"
      PREFIX="$DEFAULT_PREFIX"
      shift
      ;;
    --system)
      MODE="source"
      PREFIX="/usr/local"
      shift
      ;;
    --prefix)
      [[ -n "${2:-}" ]] || die "Missing value for --prefix"
      MODE="source"
      PREFIX="$2"
      shift 2
      ;;
    --package)
      [[ -n "${2:-}" ]] || die "Missing value for --package"
      MODE="package"
      PACKAGE_PATH="$2"
      shift 2
      ;;
    --no-verify)
      VERIFY=0
      shift
      ;;
    --skip-deps)
      SKIP_DEPS=1
      shift
      ;;
    --skip-mcp)
      SKIP_MCP=1
      shift
      ;;
    --mcp-only)
      MCP_ONLY=1
      shift
      ;;
    --uninstall)
      DO_UNINSTALL=1
      shift
      ;;
    --version)
      echo "install.sh ${VERSION}"
      exit 0
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown option: $1"
      ;;
  esac
done

# ---------------------------------------------------------------------------
# Main execution
# ---------------------------------------------------------------------------
print_banner

# -- Uninstall path --
if (( DO_UNINSTALL == 1 )); then
  do_uninstall
  exit 0
fi

# -- Dependency check --
if (( SKIP_DEPS == 0 )) && (( MCP_ONLY == 0 )); then
  check_deps
fi

# -- Install tools (unless --mcp-only) --
if (( MCP_ONLY == 0 )); then
  echo ""
  echo -e "${C_BOLD}Installing fsuite ${VERSION}...${C_RESET}"
  echo ""

  case "$MODE" in
    source)
      install_from_source
      ;;
    package)
      install_from_package
      ;;
    *)
      die "Invalid install mode: $MODE"
      ;;
  esac
fi

# -- MCP setup --
if (( SKIP_MCP == 0 )); then
  echo ""
  echo -e "${C_BOLD}Setting up MCP server...${C_RESET}"
  echo ""
  setup_mcp
  configure_agents
fi

# -- Verify --
if (( VERIFY == 1 )) && (( MCP_ONLY == 0 )); then
  verify_install
fi

# -- Summary --
print_summary
