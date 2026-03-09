# VM Smoke Harness

This directory contains a minimal KVM/QEMU harness for validating `fsuite`
in a clean Ubuntu guest.

## What it does

- downloads the Ubuntu Noble cloud image on first run
- boots a disposable VM with cloud-init
- installs the local `fsuite_2.0.0-1_all.deb`
- runs one of two scenarios:
  - `smoke`: noisy TypeScript fixture, source-first discovery, and a targeted `fedit` patch
  - `adversarial`: stale batch targets, unreadable files, and fail-closed behavior

## Run

```bash
cd /home/player3vsgpt/Desktop/Scripts/fsuite
vm/run-smoke.sh --scenario smoke
vm/run-smoke.sh --scenario adversarial
```

Artifacts land in `vm/state/artifacts/<scenario>/`.

## Options

```bash
vm/run-smoke.sh --start-only --scenario smoke
vm/run-smoke.sh --stop --scenario smoke
vm/run-smoke.sh --reuse --scenario adversarial
```

## Notes

- requires: `qemu-system-x86_64`, `qemu-img`, `genisoimage`, `ssh`, `scp`, `curl`
- uses default guest SSH ports `2222` (smoke) and `2223` (adversarial), with automatic bumping if the port is already taken
- waits for `cloud-init status --wait` before installing or running the scenario
- applies a timeout to scenario execution with `SCENARIO_TIMEOUT` (default: 900 seconds)
- the guest user is `runner` with passwordless sudo, created only inside the disposable VM
