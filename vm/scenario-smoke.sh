#!/usr/bin/env bash
set -euo pipefail

WORKDIR="$HOME/workspace/noisy-ts-app"
ARTIFACT_DIR="$HOME/artifacts"
mkdir -p "$ARTIFACT_DIR"
rm -rf "$WORKDIR"
mkdir -p "$WORKDIR/src/auth" "$WORKDIR/docs" "$WORKDIR/node_modules/noisy-pkg" "$WORKDIR/dist"

cat > "$WORKDIR/package.json" <<'JSON'
{
  "name": "noisy-ts-app",
  "version": "0.0.1",
  "type": "module"
}
JSON

cat > "$WORKDIR/src/auth/service.ts" <<'TS'
export const AUTH_MODE = 'strict';

function validateLength(user: string): boolean {
  return user.length > 3;
}

export function authenticate(user: string): boolean {
  return validateLength(user);
}

export function authorize(user: string): boolean {
  return authenticate(user);
}
TS

cat > "$WORKDIR/src/index.ts" <<'TS'
import { authenticate } from './auth/service.js';

export function main(user: string): boolean {
  return authenticate(user);
}
TS

cat > "$WORKDIR/docs/notes.md" <<'MD'
Authenticate flow notes.
MD

cat > "$WORKDIR/node_modules/noisy-pkg/package.json" <<'JSON'
{ "name": "noisy-pkg", "version": "1.0.0" }
JSON

cat > "$WORKDIR/node_modules/noisy-pkg/index.js" <<'JS'
module.exports = function authenticate() { return true; };
JS

cat > "$WORKDIR/dist/package.json" <<'JSON'
{ "name": "dist-noise", "version": "1.0.0" }
JSON

run_cmd() {
  local name="$1"
  shift
  {
    echo "## $name"
    echo "$*"
    "$@"
  } > "$ARTIFACT_DIR/${name}.txt" 2>&1
}

run_cmd versions ftree --version
run_cmd tree ftree -L 2 "$WORKDIR"
run_cmd search_default fsearch package.json "$WORKDIR" -o paths
run_cmd search_node_modules fsearch package.json "$WORKDIR/node_modules" -o paths
run_cmd map_auth fmap "$WORKDIR/src/auth/service.ts" -o json
run_cmd read_auth fread "$WORKDIR/src/auth/service.ts" --head 40 -o json
run_cmd content_auth fcontent authenticate "$WORKDIR" -o paths
run_cmd fedit_preview fedit "$WORKDIR/src/auth/service.ts" --function validateLength --replace 'return user.length > 3;' --with 'return user.length > 5;' -o json
run_cmd fedit_apply fedit "$WORKDIR/src/auth/service.ts" --function validateLength --replace 'return user.length > 3;' --with 'return user.length > 5;' --apply -o json
run_cmd read_after fread "$WORKDIR/src/auth/service.ts" --head 40 -o json

DEFAULT_SEARCH=$(cat "$ARTIFACT_DIR/search_default.txt")
NODE_SEARCH=$(cat "$ARTIFACT_DIR/search_node_modules.txt")
CONTENT_SEARCH=$(cat "$ARTIFACT_DIR/content_auth.txt")
AFTER_READ=$(cat "$ARTIFACT_DIR/read_after.txt")

if grep -q 'node_modules' <<<"$DEFAULT_SEARCH"; then
  echo "default fsearch leaked node_modules" >&2
  exit 11
fi
if ! grep -q "$WORKDIR/package.json" <<<"$DEFAULT_SEARCH"; then
  echo "default fsearch missed root package.json" >&2
  exit 12
fi
if ! grep -q 'node_modules/noisy-pkg/package.json' <<<"$NODE_SEARCH"; then
  echo "explicit node_modules root search did not return dependency package" >&2
  exit 13
fi
if grep -q 'node_modules' <<<"$CONTENT_SEARCH"; then
  echo "default fcontent leaked node_modules" >&2
  exit 14
fi
if ! grep -q 'src/auth/service.ts' <<<"$CONTENT_SEARCH"; then
  echo "fcontent missed source file" >&2
  exit 15
fi
if ! grep -q 'return user.length > 5;' <<<"$AFTER_READ"; then
  echo "fedit did not update the target function" >&2
  exit 16
fi
if grep -q 'src/index.ts.*5' <<<"$AFTER_READ"; then
  echo "fedit leaked outside the target file" >&2
  exit 17
fi

{
  echo "scenario: smoke-ok"
  echo "workdir: $WORKDIR"
} > "$ARTIFACT_DIR/summary.txt"

echo "smoke scenario ok"
