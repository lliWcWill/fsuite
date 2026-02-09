#!/usr/bin/env bash
# deploy-fsuite.sh — Deploy fsuite to Bertta and its RADis
# Part of fsuite. Handles offline install, SSH key deployment, and config updates.
#
# Respects MaxStartups limit by running operations sequentially.
# Requires: sshpass on Bertta, packages staged in /var/db/fusion/

set -euo pipefail

VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Packages (relative to script dir or absolute)
FSUITE_DEB="${SCRIPT_DIR}/fsuite_1.3.0_amd64.deb"
TREE_DEB="${SCRIPT_DIR}/../tree_2.1.0-1_amd64.deb"

# Credentials for RADi access
RADI_USER="fusion"
RADI_PASS="fusionproject"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# -------------------------
# Helpers
# -------------------------
log_info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }
die()       { log_error "$*"; exit 1; }

usage() {
  cat <<'EOF'
deploy-fsuite.sh — Deploy fsuite to Bertta and its RADis

USAGE
  ./deploy-fsuite.sh <bertta>              Deploy to Bertta and all its RADis
  ./deploy-fsuite.sh <bertta> --bertta-only Deploy only to Bertta
  ./deploy-fsuite.sh <bertta> --check       Check deployment status only
  ./deploy-fsuite.sh --update-ssh-config    Update local SSH config for all known RADis

OPTIONS
  --bertta-only     Only install on Bertta, skip RADis
  --skip-ssh-keys   Skip SSH key deployment
  --check           Check status without making changes
  --dry-run         Show what would be done without executing
  -h, --help        Show this help

EXAMPLES
  # Deploy to NPI (bertta103 and its RADis)
  ./deploy-fsuite.sh bertta103

  # Check what's already deployed
  ./deploy-fsuite.sh bertta103 --check

  # Just update local SSH config
  ./deploy-fsuite.sh --update-ssh-config

REQUIREMENTS
  - Packages must be in script directory or stage on Bertta at /var/db/fusion/
  - SSH access to Bertta configured (~/.ssh/config)
  - sshpass installed on Bertta
  - tree package available (bundled or pre-installed)

EOF
}

# -------------------------
# Check prerequisites
# -------------------------
check_packages() {
  local missing=0

  if [[ ! -f "$FSUITE_DEB" ]]; then
    log_warn "fsuite package not found: $FSUITE_DEB"
    missing=1
  else
    log_ok "Found fsuite package: $FSUITE_DEB"
  fi

  if [[ ! -f "$TREE_DEB" ]]; then
    log_warn "tree package not found: $TREE_DEB (may already be installed)"
  else
    log_ok "Found tree package: $TREE_DEB"
  fi

  return $missing
}

check_bertta_connectivity() {
  local bertta="$1"
  log_info "Checking connectivity to $bertta..."

  if ssh -o ConnectTimeout=10 "$bertta" "echo OK" >/dev/null 2>&1; then
    log_ok "Connected to $bertta"
    return 0
  else
    log_error "Cannot connect to $bertta"
    return 1
  fi
}

# -------------------------
# Get RADi list from Bertta
# -------------------------
get_radi_list() {
  local bertta="$1"
  ssh "$bertta" "sudo dhcp-lease-list 2>/dev/null | grep radi | awk '{print \$3, \$2}'" 2>/dev/null || true
}

# -------------------------
# Deploy to Bertta
# -------------------------
deploy_to_bertta() {
  local bertta="$1"

  log_info "=== Deploying to $bertta ==="

  # Check if fsuite already installed
  local installed_version
  installed_version=$(ssh "$bertta" "dpkg -l fsuite 2>/dev/null | grep ^ii | awk '{print \$3}'" || true)

  if [[ -n "$installed_version" ]]; then
    log_info "fsuite $installed_version already installed on $bertta"

    # Check if upgrade needed
    if [[ "$installed_version" == "1.3.0" ]]; then
      log_ok "$bertta already has fsuite 1.3.0"
      return 0
    else
      log_info "Upgrading from $installed_version to 1.3.0..."
    fi
  fi

  # Copy packages to Bertta
  log_info "Copying packages to $bertta:/var/db/fusion/..."
  scp "$FSUITE_DEB" "$bertta:/var/db/fusion/" 2>/dev/null

  if [[ -f "$TREE_DEB" ]]; then
    scp "$TREE_DEB" "$bertta:/var/db/fusion/" 2>/dev/null
  fi

  # Check if tree is installed
  local tree_installed
  tree_installed=$(ssh "$bertta" "dpkg -l tree 2>/dev/null | grep ^ii" || true)

  if [[ -z "$tree_installed" ]] && [[ -f "$TREE_DEB" ]]; then
    log_info "Installing tree dependency..."
    ssh "$bertta" "echo $RADI_PASS | sudo -S dpkg -i /var/db/fusion/tree_*.deb 2>&1" || true
  fi

  # Install fsuite
  log_info "Installing fsuite on $bertta..."
  ssh "$bertta" "echo $RADI_PASS | sudo -S dpkg -i /var/db/fusion/fsuite_1.3.0_amd64.deb 2>&1"

  # Verify installation
  local new_version
  new_version=$(ssh "$bertta" "ftree --version 2>/dev/null" || true)

  if [[ "$new_version" == *"1.2.0"* ]]; then
    log_ok "fsuite installed successfully on $bertta"
  else
    log_warn "fsuite installation may have issues on $bertta"
  fi
}

# -------------------------
# Deploy SSH keys
# -------------------------
deploy_ssh_keys_to_radi() {
  local bertta="$1"
  local radi_name="$2"
  local radi_ip="$3"

  log_info "Deploying SSH keys to $radi_name ($radi_ip)..."

  # Deploy Bertta's key to RADi
  local bertta_key_deployed
  bertta_key_deployed=$(ssh -n "$bertta" "ssh -o BatchMode=yes -o ConnectTimeout=5 $RADI_USER@$radi_ip 'echo OK' 2>/dev/null" || true)

  if [[ "$bertta_key_deployed" != "OK" ]]; then
    log_info "  Deploying $bertta key to $radi_name..."
    ssh -n "$bertta" "sshpass -p '$RADI_PASS' ssh-copy-id -o StrictHostKeyChecking=no $RADI_USER@$radi_ip 2>/dev/null" || true
  else
    log_ok "  $bertta key already on $radi_name"
  fi

  # Deploy local (WSL) key to RADi
  local local_pubkey
  local_pubkey=$(cat ~/.ssh/id_rsa.pub 2>/dev/null || true)

  if [[ -n "$local_pubkey" ]]; then
    log_info "  Deploying local key to $radi_name..."
    ssh -n "$bertta" "sshpass -p '$RADI_PASS' ssh -o StrictHostKeyChecking=no $RADI_USER@$radi_ip 'mkdir -p ~/.ssh && chmod 700 ~/.ssh && grep -qF \"$(echo "$local_pubkey" | cut -d' ' -f2)\" ~/.ssh/authorized_keys 2>/dev/null || echo \"$local_pubkey\" >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys'" 2>/dev/null || true
  fi
}

# -------------------------
# Deploy fsuite to RADi
# -------------------------
deploy_fsuite_to_radi() {
  local bertta="$1"
  local radi_name="$2"
  local radi_ip="$3"

  log_info "Deploying fsuite to $radi_name..."

  # Check current version
  local installed_version
  installed_version=$(ssh -n "$bertta" "ssh -o BatchMode=yes -o ConnectTimeout=5 $RADI_USER@$radi_ip 'dpkg -l fsuite 2>/dev/null | grep ^ii | awk \"{print \\\$3}\"'" 2>/dev/null || true)

  if [[ "$installed_version" == "1.3.0" ]]; then
    log_ok "  $radi_name already has fsuite 1.3.0"
    return 0
  fi

  # Install fsuite (package is on shared mount /mnt/bertta)
  log_info "  Installing fsuite on $radi_name..."
  ssh -n "$bertta" "ssh -o BatchMode=yes $RADI_USER@$radi_ip 'echo $RADI_PASS | sudo -S dpkg -i /mnt/bertta/fsuite_1.3.0_amd64.deb 2>&1'" 2>/dev/null || log_warn "  Install may have failed on $radi_name"

  # Verify
  local new_version
  new_version=$(ssh -n "$bertta" "ssh -o BatchMode=yes $RADI_USER@$radi_ip 'flog --version 2>/dev/null'" 2>/dev/null || true)

  if [[ "$new_version" == *"1.0.0"* ]]; then
    log_ok "  fsuite installed on $radi_name"
  fi
}

# -------------------------
# Update local SSH config
# -------------------------
update_ssh_config() {
  local radi_name="$1"
  local radi_ip="$2"
  local bertta="$3"

  local ssh_config="$HOME/.ssh/config"

  # Check if entry exists
  if grep -q "^Host $radi_name\$" "$ssh_config" 2>/dev/null; then
    log_ok "  SSH config entry for $radi_name already exists"
    return 0
  fi

  log_info "  Adding $radi_name to SSH config..."

  cat >> "$ssh_config" <<EOF

Host $radi_name
  HostName $radi_ip
  User fusion
  ProxyCommand ssh -W %h:%p $bertta
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
EOF

  log_ok "  Added $radi_name to SSH config"
}

# -------------------------
# Check deployment status
# -------------------------
check_deployment() {
  local bertta="$1"

  log_info "=== Checking deployment status for $bertta ==="

  # Check Bertta
  local bertta_version
  bertta_version=$(ssh "$bertta" "ftree --version 2>/dev/null" || echo "NOT INSTALLED")
  echo -e "  $bertta: ${GREEN}$bertta_version${NC}"

  # Get RADi list
  local radi_list
  radi_list=$(get_radi_list "$bertta")

  if [[ -z "$radi_list" ]]; then
    log_warn "No RADis found on $bertta"
    return
  fi

  echo ""
  echo "  RADi Status:"
  echo "  ─────────────────────────────────────────────"
  printf "  %-12s %-16s %-12s %-10s\n" "RADi" "IP" "fsuite" "SSH Key"
  echo "  ─────────────────────────────────────────────"

  while IFS=' ' read -r radi_name radi_ip; do
    [[ -z "$radi_name" ]] && continue

    # Check fsuite version (use -n to prevent stdin consumption)
    local version
    version=$(ssh -n "$bertta" "sshpass -p '$RADI_PASS' ssh -o StrictHostKeyChecking=no -o ConnectTimeout=3 $RADI_USER@$radi_ip 'flog --version 2>/dev/null'" 2>/dev/null || echo "NONE")

    # Check if local SSH config has this RADi AND key works
    local ssh_ok="NO"
    if grep -q "^Host $radi_name\$" "$HOME/.ssh/config" 2>/dev/null; then
      if ssh -n -o BatchMode=yes -o ConnectTimeout=3 "$radi_name" "echo OK" 2>/dev/null | grep -q OK; then
        ssh_ok="YES"
      else
        ssh_ok="CONFIG"  # Config exists but key not deployed
      fi
    fi

    printf "  %-12s %-16s %-12s %-10s\n" "$radi_name" "$radi_ip" "$version" "$ssh_ok"
  done <<< "$radi_list"
}

# -------------------------
# Main
# -------------------------
BERTTA=""
BERTTA_ONLY=0
SKIP_SSH_KEYS=0
CHECK_ONLY=0
DRY_RUN=0
UPDATE_SSH_ONLY=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bertta-only)    BERTTA_ONLY=1; shift ;;
    --skip-ssh-keys)  SKIP_SSH_KEYS=1; shift ;;
    --check)          CHECK_ONLY=1; shift ;;
    --dry-run)        DRY_RUN=1; shift ;;
    --update-ssh-config) UPDATE_SSH_ONLY=1; shift ;;
    -h|--help)        usage; exit 0 ;;
    --version)        echo "deploy-fsuite.sh $VERSION"; exit 0 ;;
    -*)               die "Unknown option: $1" ;;
    *)                BERTTA="$1"; shift ;;
  esac
done

# Handle update-ssh-config mode
if (( UPDATE_SSH_ONLY == 1 )); then
  log_info "Updating SSH config for all known RADis..."
  # TODO: Read from inventory file
  die "Not implemented yet. Use deploy with specific bertta."
fi

[[ -z "$BERTTA" ]] && { usage; die "Missing bertta hostname"; }

# Check connectivity
check_bertta_connectivity "$BERTTA" || exit 1

# Check-only mode
if (( CHECK_ONLY == 1 )); then
  check_deployment "$BERTTA"
  exit 0
fi

# Check packages exist
check_packages || die "Missing required packages"

echo ""
log_info "╔═══════════════════════════════════════════════════════════╗"
log_info "║  fsuite Deployment to $BERTTA"
log_info "╚═══════════════════════════════════════════════════════════╝"
echo ""

# Step 1: Deploy to Bertta
deploy_to_bertta "$BERTTA"

if (( BERTTA_ONLY == 1 )); then
  log_ok "Bertta-only deployment complete"
  exit 0
fi

# Step 2: Get RADi list
echo ""
log_info "Getting RADi list from $BERTTA..."
RADI_LIST=$(get_radi_list "$BERTTA")

if [[ -z "$RADI_LIST" ]]; then
  log_warn "No RADis found on $BERTTA"
  exit 0
fi

echo "$RADI_LIST" | while IFS=' ' read -r radi_name radi_ip; do
  [[ -z "$radi_name" ]] && continue
  echo "  Found: $radi_name ($radi_ip)"
done

# Step 3: Deploy to each RADi (sequentially to avoid MaxStartups)
echo ""
log_info "Deploying to RADis (sequentially for safety)..."

# Read RADi list into array first to avoid stdin consumption issues
RADI_NAMES=()
RADI_IPS=()
while IFS=' ' read -r _name _ip; do
  [[ -z "$_name" ]] && continue
  RADI_NAMES+=("$_name")
  RADI_IPS+=("$_ip")
done <<< "$RADI_LIST"

for (( idx=0; idx<${#RADI_NAMES[@]}; idx++ )); do
  radi_name="${RADI_NAMES[$idx]}"
  radi_ip="${RADI_IPS[$idx]}"

  echo ""
  log_info "─── $radi_name ($radi_ip) [$((idx+1))/${#RADI_NAMES[@]}] ───"

  # Deploy SSH keys
  if (( SKIP_SSH_KEYS == 0 )); then
    deploy_ssh_keys_to_radi "$BERTTA" "$radi_name" "$radi_ip"
  fi

  # Deploy fsuite
  deploy_fsuite_to_radi "$BERTTA" "$radi_name" "$radi_ip"

  # Update local SSH config
  update_ssh_config "$radi_name" "$radi_ip" "$BERTTA"

done

echo ""
log_info "╔═══════════════════════════════════════════════════════════╗"
log_info "║  Deployment Complete!                                      ║"
log_info "╚═══════════════════════════════════════════════════════════╝"
echo ""
log_info "Test with:"
echo "  ssh <radi_name> 'flog tower'"
echo "  ssh <radi_name> 'ftree --snapshot /home/fusion'"
echo ""
