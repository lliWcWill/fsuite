#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_PARENT="$(cd "${REPO_ROOT}/.." && pwd)"
STATE_DIR="${SCRIPT_DIR}/state"
IMAGE_DIR="${STATE_DIR}/images"
SEED_DIR="${STATE_DIR}/seed"
SSH_DIR="${STATE_DIR}/ssh"
SSH_PORT="${SSH_PORT:-}"
SSH_USER="runner"
MEMORY_MB="${MEMORY_MB:-4096}"
CPUS="${CPUS:-2}"
SCENARIO_TIMEOUT="${SCENARIO_TIMEOUT:-900}"
UBUNTU_IMAGE_URL="${UBUNTU_IMAGE_URL:-https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img}"
BASE_IMAGE="${IMAGE_DIR}/ubuntu-noble-amd64.img"
PRIVATE_KEY="${SSH_DIR}/id_ed25519"
PUBLIC_KEY="${PRIVATE_KEY}.pub"
LOCAL_DEB="${LOCAL_DEB:-${REPO_PARENT}/fsuite_2.0.0-1_all.deb}"
SCENARIO_NAME="${SCENARIO_NAME:-smoke}"
CLEANUP_ON_EXIT=1

usage() {
  cat <<USAGE
Usage: $(basename "$0") [--start-only] [--stop] [--reuse] [--scenario smoke|adversarial]

Boot a disposable Ubuntu VM, install the current fsuite .deb, run the selected
scenario, and collect artifacts under vm/state/artifacts/<scenario>/.

Options:
  --start-only   Boot the VM and stop before executing the scenario
  --stop         Shut down the VM referenced by the PID file
  --reuse        Reuse an existing overlay image instead of recreating it
  --scenario     Scenario name: smoke (default) or adversarial
USAGE
}

die() {
  local code=1
  if [[ "${1:-}" =~ ^[0-9]+$ ]]; then code="$1"; shift; fi
  echo "run-smoke.sh: $*" >&2
  exit "$code"
}

START_ONLY=0
STOP_ONLY=0
REUSE_OVERLAY=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --start-only) START_ONLY=1 ;;
    --stop) STOP_ONLY=1 ;;
    --reuse) REUSE_OVERLAY=1 ;;
    --scenario)
      [[ -n "${2:-}" ]] || { echo "Missing value for --scenario" >&2; exit 2; }
      SCENARIO_NAME="$2"
      shift
      ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 2 ;;
  esac
  shift
done

case "$SCENARIO_NAME" in
  smoke|adversarial) ;;
  *) echo "Unsupported scenario: $SCENARIO_NAME" >&2; exit 2 ;;
esac

VM_NAME="fsuite-${SCENARIO_NAME}"
if [[ -z "$SSH_PORT" ]]; then
  case "$SCENARIO_NAME" in
    smoke) SSH_PORT=2222 ;;
    adversarial) SSH_PORT=2223 ;;
  esac
  while ss -ltnH "( sport = :${SSH_PORT} )" 2>/dev/null | grep -q .; do
    SSH_PORT=$((SSH_PORT + 10))
  done
fi
OVERLAY_IMAGE="${STATE_DIR}/${VM_NAME}.qcow2"
SEED_ISO="${STATE_DIR}/${VM_NAME}-seed.iso"
PID_FILE="${STATE_DIR}/${VM_NAME}.pid"
ARTIFACT_DIR="${STATE_DIR}/artifacts/${SCENARIO_NAME}"
SERIAL_LOG="${ARTIFACT_DIR}/${VM_NAME}-serial.log"
SCENARIO_SCRIPT="${SCRIPT_DIR}/scenario-${SCENARIO_NAME}.sh"

mkdir -p "$STATE_DIR" "$IMAGE_DIR" "$SEED_DIR" "$ARTIFACT_DIR" "$SSH_DIR"
[[ -f "$SCENARIO_SCRIPT" ]] || { echo "Scenario script not found: $SCENARIO_SCRIPT" >&2; exit 1; }
[[ -f "$LOCAL_DEB" ]] || die "Local package not found: $LOCAL_DEB"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

for cmd in qemu-system-x86_64 qemu-img genisoimage ssh scp curl timeout ssh-keygen ss; do
  require_cmd "$cmd"
done

stop_vm() {
  if [[ -f "$PID_FILE" ]]; then
    local pid
    pid=$(cat "$PID_FILE" 2>/dev/null || true)
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
      timeout 20 bash -c "while kill -0 '$pid' 2>/dev/null; do sleep 1; done" || true
    fi
    rm -f "$PID_FILE"
  fi
}

on_exit() {
  if (( CLEANUP_ON_EXIT == 1 )); then
    stop_vm
  fi
}
trap on_exit EXIT

if (( STOP_ONLY == 1 )); then
  CLEANUP_ON_EXIT=0
  stop_vm
  exit 0
fi

if [[ ! -f "$PRIVATE_KEY" ]]; then
  ssh-keygen -q -t ed25519 -N '' -f "$PRIVATE_KEY" >/dev/null
fi

if [[ ! -f "$BASE_IMAGE" ]]; then
  curl -L "$UBUNTU_IMAGE_URL" -o "$BASE_IMAGE"
fi

if (( REUSE_OVERLAY == 0 )); then
  rm -f "$OVERLAY_IMAGE" "$SEED_ISO"
  qemu-img create -f qcow2 -b "$BASE_IMAGE" -F qcow2 "$OVERLAY_IMAGE" >/dev/null
fi

PUBKEY_CONTENT=$(cat "$PUBLIC_KEY")
cat > "$SEED_DIR/user-data" <<USERDATA
#cloud-config
users:
  - default
  - name: ${SSH_USER}
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: sudo
    shell: /bin/bash
    ssh_authorized_keys:
      - ${PUBKEY_CONTENT}
package_update: true
packages:
  - qemu-guest-agent
  - python3
  - sqlite3
  - ripgrep
  - tree
write_files:
  - path: /usr/local/bin/fsuite-vm-scenario.sh
    permissions: '0755'
    content: |
$(sed 's/^/      /' "$SCENARIO_SCRIPT")
runcmd:
  - [ bash, -lc, 'mkdir -p /home/${SSH_USER}/workspace /home/${SSH_USER}/artifacts && chown -R ${SSH_USER}:${SSH_USER} /home/${SSH_USER}/workspace /home/${SSH_USER}/artifacts' ]
USERDATA

cat > "$SEED_DIR/meta-data" <<METADATA
instance-id: ${VM_NAME}
local-hostname: ${VM_NAME}
METADATA

genisoimage -output "$SEED_ISO" -volid cidata -joliet -rock "$SEED_DIR/user-data" "$SEED_DIR/meta-data" >/dev/null 2>&1

stop_vm

qemu-system-x86_64 \
  -name "$VM_NAME" \
  -enable-kvm \
  -m "$MEMORY_MB" \
  -smp "$CPUS" \
  -drive "file=$OVERLAY_IMAGE,if=virtio" \
  -drive "file=$SEED_ISO,media=cdrom,if=virtio" \
  -netdev "user,id=net0,hostfwd=tcp::${SSH_PORT}-:22" \
  -device virtio-net-pci,netdev=net0 \
  -display none \
  -serial "file:$SERIAL_LOG" \
  -daemonize \
  -pidfile "$PID_FILE"

wait_for_ssh() {
  timeout 300 bash -c '
    while true; do
      if ssh -i "$0" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -p "$1" "$2@127.0.0.1" "echo ready" >/dev/null 2>&1; then
        exit 0
      fi
      sleep 2
    done
  ' "$PRIVATE_KEY" "$SSH_PORT" "$SSH_USER"
}

wait_for_ssh
ssh -i "$PRIVATE_KEY" -p "$SSH_PORT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  "${SSH_USER}@127.0.0.1" "sudo cloud-init status --wait >/dev/null 2>&1" || die "cloud-init did not complete successfully"

if (( START_ONLY == 1 )); then
  CLEANUP_ON_EXIT=0
  echo "VM started on ssh port ${SSH_PORT} for scenario ${SCENARIO_NAME}"
  exit 0
fi

scp -i "$PRIVATE_KEY" -P "$SSH_PORT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  "$LOCAL_DEB" "${SSH_USER}@127.0.0.1:/home/${SSH_USER}/fsuite.deb" >/dev/null
set +e
timeout "$SCENARIO_TIMEOUT" ssh -i "$PRIVATE_KEY" -p "$SSH_PORT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  "${SSH_USER}@127.0.0.1" \
  "export FSUITE_TELEMETRY=0; sudo dpkg -i /home/${SSH_USER}/fsuite.deb && /usr/local/bin/fsuite-vm-scenario.sh" \
  | tee "$ARTIFACT_DIR/scenario-output.txt"
SCENARIO_RC=${PIPESTATUS[0]}
scp -i "$PRIVATE_KEY" -P "$SSH_PORT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -r \
  "${SSH_USER}@127.0.0.1:/home/${SSH_USER}/artifacts/." "$ARTIFACT_DIR/" >/dev/null 2>&1
set -e

echo "Artifacts written to $ARTIFACT_DIR"
exit "$SCENARIO_RC"
