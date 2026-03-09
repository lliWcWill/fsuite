#!/usr/bin/env bash
set -euo pipefail

export FSUITE_TELEMETRY=0

WORKDIR="$HOME/workspace/adversarial-ts-app"
ARTIFACT_DIR="$HOME/artifacts"
mkdir -p "$ARTIFACT_DIR"
rm -rf "$WORKDIR"
mkdir -p "$WORKDIR/src/auth" "$WORKDIR/node_modules/trap-pkg" "$WORKDIR/dist"

cat > "$WORKDIR/src/auth/service.ts" <<'TS'
export function authenticate(user: string): boolean {
  return false;
}
TS

cat > "$WORKDIR/src/auth/unreadable.ts" <<'TS'
export function secretGate(): boolean {
  return false;
}
TS
chmod 000 "$WORKDIR/src/auth/unreadable.ts"

cat > "$WORKDIR/src/auth/later.ts" <<'TS'
export function laterGate(): boolean {
  return false;
}
TS

cat > "$WORKDIR/node_modules/trap-pkg/package.json" <<'JSON'
{ "name": "trap-pkg", "version": "1.0.0" }
JSON

cat > "$WORKDIR/dist/package.json" <<'JSON'
{ "name": "dist-trap", "version": "1.0.0" }
JSON

printf '%s\n%s\n%s\n' \
  "$WORKDIR/src/auth/service.ts" \
  "$WORKDIR/src/auth/missing.ts" \
  "$WORKDIR/src/auth/later.ts" > "$WORKDIR/targets.txt"

set +e
fedit --targets-file "$WORKDIR/targets.txt" --targets-format paths \
  --replace 'return false;' --with 'return true;' --apply -o json \
  > "$ARTIFACT_DIR/batch_stale.json" 2> "$ARTIFACT_DIR/batch_stale.err"
STALE_RC=$?

fedit "$WORKDIR/src/auth/unreadable.ts" \
  --replace 'return false;' --with 'return true;' -o json \
  > "$ARTIFACT_DIR/unreadable.json" 2> "$ARTIFACT_DIR/unreadable.err"
UNREADABLE_RC=$?
set -e

grep -q '"error_code":"not_found"' "$ARTIFACT_DIR/batch_stale.json" || {
  echo "stale batch did not report not_found" >&2
  exit 21
}
grep -q '"state":"failed"' "$ARTIFACT_DIR/batch_stale.json" || {
  echo "stale batch did not mark failed target" >&2
  exit 22
}
grep -q '"state":"skipped"' "$ARTIFACT_DIR/batch_stale.json" || {
  echo "stale batch did not mark skipped target" >&2
  exit 23
}
grep -q 'return false;' "$WORKDIR/src/auth/service.ts" || {
  echo "valid file changed during stale batch failure" >&2
  exit 24
}
grep -q 'return false;' "$WORKDIR/src/auth/later.ts" || {
  echo "later file changed despite skipped state" >&2
  exit 28
}
[[ "$STALE_RC" -ne 0 ]] || {
  echo "stale batch unexpectedly succeeded" >&2
  exit 25
}

grep -q '"error_code":"permission"' "$ARTIFACT_DIR/unreadable.json" || {
  echo "unreadable file did not report permission" >&2
  exit 26
}
[[ "$UNREADABLE_RC" -ne 0 ]] || {
  echo "unreadable file unexpectedly succeeded" >&2
  exit 27
}

{
  echo "scenario: adversarial-ok"
  echo "workdir: $WORKDIR"
} > "$ARTIFACT_DIR/summary.txt"

echo "adversarial scenario ok"
