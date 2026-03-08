#!/usr/bin/env bash
# install.sh — install fsuite from source or an existing Debian package.

set -euo pipefail

VERSION="1.9.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_PREFIX="${HOME}/.local"
PREFIX="$DEFAULT_PREFIX"
MODE="source"
PACKAGE_PATH=""
VERIFY=1

TOOLS=(ftree fsearch fcontent fmap fread fedit fmetrics)
SHARE_FILES=(_fsuite_common.sh fmetrics-predict.py)

die() {
  local code=1
  if [[ "${1:-}" =~ ^[0-9]+$ ]]; then code="$1"; shift; fi
  echo "install.sh: $*" >&2
  exit "$code"
}

has() { command -v "$1" >/dev/null 2>&1; }

usage() {
  cat <<EOF
fsuite installer

USAGE
  ./install.sh [options]

OPTIONS
  --user              Install into ~/.local (default)
  --system            Install into /usr/local
  --prefix PATH       Install into PATH
  --package PATH      Install an existing .deb with dpkg
  --no-verify         Skip post-install verification
  --version           Print installer version
  -h, --help          Show help

EXAMPLES
  ./install.sh
  ./install.sh --system
  ./install.sh --prefix /opt/fsuite
  ./install.sh --package ../fsuite_1.9.0-1_all.deb
EOF
}

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

install_from_source() {
  local bin_dir="${PREFIX}/bin"
  local share_dir="${PREFIX}/share/fsuite"

  run_privileged mkdir -p "$bin_dir" "$share_dir"

  for tool in "${TOOLS[@]}"; do
    [[ -f "${SCRIPT_DIR}/${tool}" ]] || die "Missing tool: ${tool}"
    run_privileged install -m 755 "${SCRIPT_DIR}/${tool}" "${bin_dir}/${tool}"
  done

  run_privileged install -m 644 "${SCRIPT_DIR}/_fsuite_common.sh" "${share_dir}/_fsuite_common.sh"
  run_privileged install -m 644 "${SCRIPT_DIR}/fmetrics-predict.py" "${share_dir}/fmetrics-predict.py"
}

install_from_package() {
  [[ -n "$PACKAGE_PATH" ]] || die "Missing package path"
  [[ -f "$PACKAGE_PATH" ]] || die "Package not found: $PACKAGE_PATH"
  has dpkg || die 3 "dpkg is required for --package mode"
  run_privileged dpkg -i "$PACKAGE_PATH"
}

verify_install() {
  local path_prefix="$PATH"
  if [[ "$MODE" == "source" ]]; then
    path_prefix="${PREFIX}/bin:${path_prefix}"
    export PATH="$path_prefix"
    export FSUITE_SHARE_DIR="${PREFIX}/share/fsuite"
  fi

  echo "Verifying fsuite install..."
  for tool in "${TOOLS[@]}"; do
    "${tool}" --version
  done
}

print_next_steps() {
  echo
  echo "fsuite installed."
  if [[ "$MODE" == "source" ]]; then
    echo "  Prefix: ${PREFIX}"
    if [[ ":$PATH:" != *":${PREFIX}/bin:"* ]]; then
      echo "  Add to PATH:"
      echo "    export PATH=\"${PREFIX}/bin:\$PATH\""
    fi
  else
    echo "  Package: ${PACKAGE_PATH}"
  fi
  echo
  echo "Recommended optional dependencies:"
  echo "  Debian/Ubuntu: sudo apt install tree ripgrep fd-find sqlite3 python3 perl"
  echo "  macOS:         brew install tree ripgrep fd sqlite python3"
}

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

if (( VERIFY == 1 )); then
  verify_install
fi

print_next_steps
