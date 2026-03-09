#!/usr/bin/env bash
# test_fedit.sh — coverage for fedit

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FEDIT="${SCRIPT_DIR}/../fedit"
FMAP="${SCRIPT_DIR}/../fmap"
FMETRICS="${SCRIPT_DIR}/../fmetrics"
TEST_DIR=""
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

setup() {
  TEST_DIR="$(mktemp -d)"

  cat > "${TEST_DIR}/auth.py" <<'EOF'
def authenticate(user):
    if not user:
        return False
    return True

def deny_if_missing(user):
    if not user:
        return False
    return True

class AuthHandler:
    def login(self, user):
        return authenticate(user)
EOF

  cat > "${TEST_DIR}/single.py" <<'EOF'
def authenticate(user):
    if not user:
        return False
    return True
EOF

  cat > "${TEST_DIR}/insert_target.py" <<'EOF'
def authenticate(user):
    return True
EOF

  cat > "${TEST_DIR}/repeated_anchor.py" <<'EOF'
def alpha(user):
    return True

def beta(user):
    return True
EOF

  cat > "${TEST_DIR}/multiline_anchor.py" <<'EOF'
def authenticate(
    user,
):
    return True
EOF

  printf 'def authenticate(user):\r\n    return True\r\n' > "${TEST_DIR}/crlf_target.py"

  cat > "${TEST_DIR}/payload.txt" <<'EOF'
    audit_log(user)
EOF

  cat > "${TEST_DIR}/types.ts" <<'EOF'
import { readFile } from 'fs';
import { writeFile } from 'fs';
const MAX_SIZE = 10;
export type CustomType = { name: string };
export type OtherType = { name: string };
export function x(): CustomType { return { name: 'x' }; }
export function y() { const limit = MAX_SIZE; return limit; }
EOF

  echo 'old content' > "${TEST_DIR}/replace_me.txt"
  echo 'special content' > "${TEST_DIR}/file with spaces.txt"

  cp "${TEST_DIR}/auth.py" "${TEST_DIR}/auth.py.orig"
  cp "${TEST_DIR}/single.py" "${TEST_DIR}/single.py.orig"
  cp "${TEST_DIR}/insert_target.py" "${TEST_DIR}/insert_target.py.orig"
  cp "${TEST_DIR}/repeated_anchor.py" "${TEST_DIR}/repeated_anchor.py.orig"
  cp "${TEST_DIR}/multiline_anchor.py" "${TEST_DIR}/multiline_anchor.py.orig"
  cp "${TEST_DIR}/crlf_target.py" "${TEST_DIR}/crlf_target.py.orig"
  cp "${TEST_DIR}/types.ts" "${TEST_DIR}/types.ts.orig"
  cp "${TEST_DIR}/replace_me.txt" "${TEST_DIR}/replace_me.txt.orig"
  cp "${TEST_DIR}/file with spaces.txt" "${TEST_DIR}/file with spaces.txt.orig"
}

teardown() {
  [[ -n "${TEST_DIR}" && -d "${TEST_DIR}" ]] && rm -rf "${TEST_DIR}"
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

reset_fixture() {
  local name="$1"
  cp "${TEST_DIR}/${name}.orig" "${TEST_DIR}/${name}"
}

sha256_of() {
  local path="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$path" | awk '{print $1}'
  else
    shasum -a 256 "$path" | awk '{print $1}'
  fi
}

run_test() {
  local label="$1"
  TESTS_RUN=$((TESTS_RUN + 1))
  shift
  local before_passed="$TESTS_PASSED"
  local before_failed="$TESTS_FAILED"
  local rc=0
  "$@" || rc=$?
  if (( TESTS_PASSED == before_passed && TESTS_FAILED == before_failed )); then
    fail "${label} crashed or made no assertion" "exit=${rc}"
    return 0
  fi
  if (( rc != 0 )) && (( TESTS_FAILED == before_failed )); then
    fail "${label} exited non-zero without recording failure" "exit=${rc}"
  fi
}

test_version() {
  local output
  output=$("${FEDIT}" --version 2>&1)
  if [[ "$output" =~ ^fedit\ [0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    pass "Version output format is correct"
  else
    fail "Version output should be semantic" "Got: $output"
  fi
}

test_help() {
  local output
  output=$("${FEDIT}" --help 2>&1)
  if [[ "$output" == *"--replace"* ]] && [[ "$output" == *"--symbol"* ]] && [[ "$output" == *"--apply"* ]]; then
    pass "Help output documents patch and symbol modes"
  else
    fail "Help output missing key flags"
  fi
}

test_self_check() {
  local output
  output=$("${FEDIT}" --self-check 2>&1)
  if [[ "$output" == *"perl:"* ]] && [[ "$output" == *"sha256:"* ]]; then
    pass "Self-check reports dependencies"
  else
    fail "Self-check should report dependency status" "Got: $output"
  fi
}

test_install_hints() {
  local output
  output=$("${FEDIT}" --install-hints 2>&1)
  if [[ "$output" == *"apt install"* ]] || [[ "$output" == *"brew install"* ]]; then
    pass "Install hints command works"
  else
    fail "Install hints missing package-manager guidance"
  fi
}

test_dry_run_default() {
  local before output
  reset_fixture "single.py"
  before=$(cat "${TEST_DIR}/single.py")
  output=$(FSUITE_TELEMETRY=0 "${FEDIT}" "${TEST_DIR}/single.py" --replace 'return False' --with 'return deny()' 2>/dev/null)
  if [[ "$output" == *"status: dry-run"* ]] && [[ "$(cat "${TEST_DIR}/single.py")" == "$before" ]]; then
    pass "Dry-run is the default and does not mutate files"
  else
    fail "Dry-run should preview only"
  fi
}

test_apply_replace() {
  reset_fixture "single.py"
  FSUITE_TELEMETRY=0 "${FEDIT}" "${TEST_DIR}/single.py" --replace 'return False' --with 'return deny()' --apply >/dev/null 2>&1 || {
    fail "Apply replace should succeed"
    return
  }
  if grep -q 'return deny()' "${TEST_DIR}/single.py"; then
    pass "Apply mode writes replacement"
  else
    fail "Apply should persist the replacement"
  fi
}

test_replace_missing_fails() {
  local rc=0
  FSUITE_TELEMETRY=0 "${FEDIT}" "${TEST_DIR}/single.py" --replace 'nope' --with 'x' >/dev/null 2>&1 || rc=$?
  if (( rc != 0 )); then
    pass "Missing replace target fails closed"
  else
    fail "Missing replace target should fail"
  fi
}

test_ambiguous_replace_fails() {
  local rc=0
  FSUITE_TELEMETRY=0 "${FEDIT}" "${TEST_DIR}/auth.py" --replace 'return False' --with 'return deny()' >/dev/null 2>&1 || rc=$?
  if (( rc != 0 )); then
    pass "Ambiguous replace fails without allow-multiple"
  else
    fail "Ambiguous replace should fail"
  fi
}

test_allow_multiple_replace() {
  reset_fixture "auth.py"
  FSUITE_TELEMETRY=0 "${FEDIT}" "${TEST_DIR}/auth.py" --replace 'return False' --with 'return deny()' --allow-multiple --apply >/dev/null 2>&1 || {
    fail "allow-multiple replace should succeed"
    return
  }
  local count
  count=$(grep -c 'return deny()' "${TEST_DIR}/auth.py" || true)
  if (( count == 2 )); then
    pass "allow-multiple applies to every exact match"
  else
    fail "allow-multiple should replace both matches" "Count: $count"
  fi
}

test_after_anchor_insert() {
  reset_fixture "insert_target.py"
  FSUITE_TELEMETRY=0 "${FEDIT}" "${TEST_DIR}/insert_target.py" --after 'def authenticate(user):' --content-file "${TEST_DIR}/payload.txt" --apply >/dev/null 2>&1 || {
    fail "After-anchor insertion should succeed"
    return
  }
  if grep -q 'audit_log(user)' "${TEST_DIR}/insert_target.py"; then
    pass "After-anchor insertion works"
  else
    fail "After-anchor insertion should write payload"
  fi
}

test_before_anchor_insert() {
  reset_fixture "insert_target.py"
  local output
  output=$(FSUITE_TELEMETRY=0 "${FEDIT}" "${TEST_DIR}/insert_target.py" --before 'return True' --with $'    prepare(user)\n' 2>/dev/null)
  if [[ "$output" == *"+    prepare(user)"* ]]; then
    pass "Before-anchor dry-run shows inserted diff"
  else
    fail "Before-anchor diff should show inserted line" "Got: $output"
  fi
}

test_after_anchor_ambiguity_fails() {
  local rc=0
  reset_fixture "repeated_anchor.py"
  FSUITE_TELEMETRY=0 "${FEDIT}" "${TEST_DIR}/repeated_anchor.py" --after 'return True' --with $'    audit_log(user)\n' >/dev/null 2>&1 || rc=$?
  if (( rc != 0 )) && cmp -s "${TEST_DIR}/repeated_anchor.py" "${TEST_DIR}/repeated_anchor.py.orig"; then
    pass "Repeated --after anchor fails closed without allow-multiple"
  else
    fail "Repeated --after anchor should fail without mutating file" "rc=$rc"
  fi
}

test_before_anchor_ambiguity_fails() {
  local rc=0
  reset_fixture "repeated_anchor.py"
  FSUITE_TELEMETRY=0 "${FEDIT}" "${TEST_DIR}/repeated_anchor.py" --before 'return True' --with $'    audit_log(user)\n' >/dev/null 2>&1 || rc=$?
  if (( rc != 0 )) && cmp -s "${TEST_DIR}/repeated_anchor.py" "${TEST_DIR}/repeated_anchor.py.orig"; then
    pass "Repeated --before anchor fails closed without allow-multiple"
  else
    fail "Repeated --before anchor should fail without mutating file" "rc=$rc"
  fi
}

test_multiline_after_anchor() {
  reset_fixture "multiline_anchor.py"
  FSUITE_TELEMETRY=0 "${FEDIT}" "${TEST_DIR}/multiline_anchor.py" \
    --after $'def authenticate(\n    user,\n):\n' \
    --with $'    audit_log(user)\n' \
    --apply >/dev/null 2>&1 || {
      fail "Multi-line --after anchor should succeed"
      return
    }
  local content
  content=$(cat "${TEST_DIR}/multiline_anchor.py")
  if [[ "$content" == *$'def authenticate(\n    user,\n):\n    audit_log(user)\n    return True'* ]]; then
    pass "Multi-line anchor text is applied as one block"
  else
    fail "Multi-line --after anchor should insert payload immediately after anchor" "Got: $content"
  fi
}

test_before_anchor_apply() {
  reset_fixture "insert_target.py"
  FSUITE_TELEMETRY=0 "${FEDIT}" "${TEST_DIR}/insert_target.py" --before 'return True' --with $'    prepare(user)\n' --apply >/dev/null 2>&1 || {
    fail "Before-anchor apply should succeed"
    return
  }
  if grep -q 'prepare(user)' "${TEST_DIR}/insert_target.py"; then
    pass "Before-anchor apply writes the payload"
  else
    fail "Before-anchor apply should mutate the target file"
  fi
}

test_stdin_payload() {
  reset_fixture "insert_target.py"
  printf '    prepare(user)\n' | FSUITE_TELEMETRY=0 "${FEDIT}" "${TEST_DIR}/insert_target.py" --before 'return True' --stdin --apply >/dev/null 2>&1 || {
    fail "STDIN payload apply should succeed"
    return
  }
  if grep -q 'prepare(user)' "${TEST_DIR}/insert_target.py"; then
    pass "STDIN payloads are accepted"
  else
    fail "STDIN payload should be written into target file"
  fi
}

test_expect_text_success() {
  local rc=0
  reset_fixture "single.py"
  FSUITE_TELEMETRY=0 "${FEDIT}" "${TEST_DIR}/single.py" --expect 'def authenticate' --replace 'return False' --with 'return deny()' >/dev/null 2>&1 || rc=$?
  if (( rc == 0 )); then
    pass "Expected text precondition passes when present"
  else
    fail "Expected text should pass when present"
  fi
}

test_expect_text_failure() {
  local rc=0
  reset_fixture "single.py"
  FSUITE_TELEMETRY=0 "${FEDIT}" "${TEST_DIR}/single.py" --expect 'missing marker' --replace 'return False' --with 'return deny()' >/dev/null 2>&1 || rc=$?
  if (( rc != 0 )); then
    pass "Expected text precondition fails when absent"
  else
    fail "Expected text should fail when absent"
  fi
}

test_expect_sha_failure() {
  local rc=0
  reset_fixture "single.py"
  FSUITE_TELEMETRY=0 "${FEDIT}" "${TEST_DIR}/single.py" --expect-sha256 deadbeef --replace 'return False' --with 'return deny()' >/dev/null 2>&1 || rc=$?
  if (( rc != 0 )); then
    pass "SHA precondition fails on mismatch"
  else
    fail "SHA mismatch should fail"
  fi
}

test_expect_sha_success() {
  local hash
  reset_fixture "single.py"
  hash=$(sha256_of "${TEST_DIR}/single.py")
  FSUITE_TELEMETRY=0 "${FEDIT}" "${TEST_DIR}/single.py" --expect-sha256 "$hash" --replace 'return False' --with 'return deny()' --apply >/dev/null 2>&1 || {
    fail "SHA precondition happy path should succeed"
    return
  }
  if grep -q 'return deny()' "${TEST_DIR}/single.py"; then
    pass "SHA precondition succeeds when hash matches"
  else
    fail "Expected replacement after matching SHA precondition"
  fi
}

test_create_dry_run() {
  local target="${TEST_DIR}/new_file.py"
  FSUITE_TELEMETRY=0 "${FEDIT}" --create "$target" --with 'print("hello")' >/dev/null 2>&1 || {
    fail "Create dry-run should succeed"
    return
  }
  if [[ ! -e "$target" ]]; then
    pass "Create dry-run does not create the file"
  else
    fail "Create dry-run should not mutate the filesystem"
  fi
}

test_create_apply() {
  local target="${TEST_DIR}/created.py"
  FSUITE_TELEMETRY=0 "${FEDIT}" --create "$target" --with 'print("hello")' --apply >/dev/null 2>&1 || {
    fail "Create apply should succeed"
    return
  }
  if [[ -f "$target" ]] && grep -q 'print("hello")' "$target"; then
    pass "Create apply writes a new file"
  else
    fail "Create apply should create the file"
  fi
}

test_replace_file_apply() {
  cp "${TEST_DIR}/replace_me.txt.orig" "${TEST_DIR}/replace_me.txt"
  FSUITE_TELEMETRY=0 "${FEDIT}" --replace-file "${TEST_DIR}/replace_me.txt" --with 'new content' --apply >/dev/null 2>&1 || {
    fail "replace-file apply should succeed"
    return
  }
  if [[ "$(cat "${TEST_DIR}/replace_me.txt")" == 'new content' ]]; then
    pass "replace-file overwrites the target"
  else
    fail "replace-file should replace file contents"
  fi
}

test_json_output_parseable() {
  if ! command -v python3 >/dev/null 2>&1; then
    pass "JSON parseability test skipped (python3 not available)"
    return 0
  fi
  local output
  reset_fixture "single.py"
  output=$(FSUITE_TELEMETRY=0 "${FEDIT}" -o json "${TEST_DIR}/single.py" --replace 'return False' --with 'return deny()' 2>/dev/null)
  if printf '%s' "$output" | python3 -m json.tool >/dev/null 2>&1; then
    pass "JSON output is parseable"
  else
    fail "JSON output should be valid JSON" "Got: $output"
  fi
}

test_json_error_output() {
  if ! command -v python3 >/dev/null 2>&1; then
    pass "JSON error-output test skipped (python3 not available)"
    return 0
  fi
  local output rc=0
  reset_fixture "single.py"
  output=$(FSUITE_TELEMETRY=0 "${FEDIT}" -o json "${TEST_DIR}/single.py" --replace 'missing target' --with 'x' 2>/dev/null) || rc=$?
  if (( rc != 0 )) && printf '%s' "$output" | python3 -m json.tool >/dev/null 2>&1 && [[ "$output" == *'"error_code":"replace_missing"'* ]]; then
    pass "JSON mode still renders structured output on failure"
  else
    fail "JSON mode should render machine-readable errors" "rc=$rc output=$output"
  fi
}

test_json_anchor_ambiguous_error() {
  if ! command -v python3 >/dev/null 2>&1; then
    pass "JSON anchor-ambiguous test skipped (python3 not available)"
    return 0
  fi
  local output rc=0
  reset_fixture "repeated_anchor.py"
  output=$(FSUITE_TELEMETRY=0 "${FEDIT}" -o json "${TEST_DIR}/repeated_anchor.py" --after 'return True' --with $'    x()\n' 2>/dev/null) || rc=$?
  if (( rc != 0 )) && printf '%s' "$output" | python3 -m json.tool >/dev/null 2>&1 && [[ "$output" == *'"error_code":"anchor_ambiguous"'* ]]; then
    pass "JSON mode reports anchor_ambiguous errors"
  else
    fail "JSON mode should expose anchor_ambiguous" "rc=$rc output=$output"
  fi
}

test_json_precondition_error() {
  if ! command -v python3 >/dev/null 2>&1; then
    pass "JSON precondition-error test skipped (python3 not available)"
    return 0
  fi
  local output rc=0
  reset_fixture "single.py"
  output=$(FSUITE_TELEMETRY=0 "${FEDIT}" -o json "${TEST_DIR}/single.py" --expect 'missing marker' --replace 'return False' --with 'return deny()' 2>/dev/null) || rc=$?
  if (( rc != 0 )) && printf '%s' "$output" | python3 -m json.tool >/dev/null 2>&1 && [[ "$output" == *'"error_code":"precondition_failed"'* ]]; then
    pass "JSON mode reports precondition failures"
  else
    fail "JSON mode should expose precondition_failed" "rc=$rc output=$output"
  fi
}

test_batch_json_error_output() {
  if ! command -v python3 >/dev/null 2>&1; then
    pass "Batch JSON error test skipped (python3 not available)"
    return 0
  fi
  local a="${TEST_DIR}/batch_json_err_a.py" b="${TEST_DIR}/batch_json_err_b.py"
  echo 'x = 1' > "$a"
  echo 'x = 1' > "$b"
  local output rc=0
  output=$(printf '%s\n' "$a" "$b" | FSUITE_TELEMETRY=0 "${FEDIT}" -o json --targets-file - --targets-format paths --replace 'missing_text' --with 'x = 2' 2>/dev/null) || rc=$?
  if (( rc != 0 )) && printf '%s' "$output" | python3 -c '
import json, sys
data = json.load(sys.stdin)
assert data["mode"] == "patch_batch"
assert len(data["results"]) == 2
first, second = data["results"]
assert first["path"] == sys.argv[1]
assert first["state"] == "failed"
assert first["error_code"] == "replace_missing"
assert first["preconditions_ok"] is True
assert second["path"] == sys.argv[2]
assert second["state"] == "skipped"
assert second["error_code"] is None
assert second["preconditions_ok"] is None
' "$a" "$b" >/dev/null 2>&1
  then
    pass "Batch failures render the batch JSON envelope"
  else
    fail "Batch JSON failures should render batch-specific structure" "rc=$rc output=$output"
  fi
}

test_json_not_found_error() {
  if ! command -v python3 >/dev/null 2>&1; then
    pass "JSON not-found test skipped (python3 not available)"
    return 0
  fi
  local missing="${TEST_DIR}/missing.py" output rc=0
  output=$(FSUITE_TELEMETRY=0 "${FEDIT}" -o json "$missing" --replace 'x' --with 'y' 2>/dev/null) || rc=$?
  if (( rc != 0 )) && printf '%s' "$output" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["error_code"]=="not_found"' >/dev/null 2>&1; then
    pass "JSON mode reports not_found errors"
  else
    fail "JSON mode should expose not_found" "rc=$rc output=$output"
  fi
}

test_json_not_regular_error() {
  if ! command -v python3 >/dev/null 2>&1; then
    pass "JSON not-regular test skipped (python3 not available)"
    return 0
  fi
  local output rc=0
  output=$(FSUITE_TELEMETRY=0 "${FEDIT}" -o json "${TEST_DIR}" --replace 'x' --with 'y' 2>/dev/null) || rc=$?
  if (( rc != 0 )) && printf '%s' "$output" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["error_code"]=="not_regular"' >/dev/null 2>&1; then
    pass "JSON mode reports not_regular errors"
  else
    fail "JSON mode should expose not_regular" "rc=$rc output=$output"
  fi
}

test_json_permission_error() {
  if ! command -v python3 >/dev/null 2>&1; then
    pass "JSON permission test skipped (python3 not available)"
    return 0
  fi
  local denied="${TEST_DIR}/permission_denied.py" output rc=0
  printf 'x = 1\n' > "$denied"
  chmod 000 "$denied"
  output=$(FSUITE_TELEMETRY=0 "${FEDIT}" -o json "$denied" --replace 'x = 1' --with 'x = 2' 2>/dev/null) || rc=$?
  chmod 644 "$denied"
  if (( rc != 0 )) && printf '%s' "$output" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["error_code"]=="permission"' >/dev/null 2>&1; then
    pass "JSON mode reports permission errors"
  else
    fail "JSON mode should expose permission" "rc=$rc output=$output"
  fi
}

test_json_symbol_ambiguous_error() {
  if ! command -v python3 >/dev/null 2>&1; then
    pass "JSON symbol-ambiguous test skipped (python3 not available)"
    return 0
  fi
  local dup="${TEST_DIR}/duplicate_symbol.py" output rc=0
  cat > "$dup" <<'EOF'
def authenticate(user):
    return False

def authenticate(user):
    return True
EOF
  output=$(FSUITE_TELEMETRY=0 "${FEDIT}" -o json "$dup" --function authenticate --replace 'return False' --with 'return deny()' 2>/dev/null) || rc=$?
  if (( rc != 0 )) && printf '%s' "$output" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["error_code"]=="symbol_ambiguous"' >/dev/null 2>&1; then
    pass "JSON mode reports symbol_ambiguous errors"
  else
    fail "JSON mode should expose symbol_ambiguous" "rc=$rc output=$output"
  fi
}

test_batch_json_anchor_missing_error() {
  if ! command -v python3 >/dev/null 2>&1; then
    pass "Batch JSON anchor-missing test skipped (python3 not available)"
    return 0
  fi
  local a="${TEST_DIR}/batch_json_anchor_a.py" b="${TEST_DIR}/batch_json_anchor_b.py"
  echo 'x = 1' > "$a"
  echo 'x = 1' > "$b"
  local output rc=0
  output=$(printf '%s\n' "$a" "$b" | FSUITE_TELEMETRY=0 "${FEDIT}" -o json --targets-file - --targets-format paths --after 'missing_anchor()' --with $'    x()\n' 2>/dev/null) || rc=$?
  if (( rc != 0 )) && printf '%s' "$output" | python3 -c '
import json, sys
data = json.load(sys.stdin)
first, second = data["results"]
assert first["path"] == sys.argv[1]
assert first["state"] == "failed"
assert first["error_code"] == "anchor_missing"
assert second["path"] == sys.argv[2]
assert second["state"] == "skipped"
' "$a" "$b" >/dev/null 2>&1
  then
    pass "Batch JSON reports anchor_missing per target"
  else
    fail "Batch JSON should expose anchor_missing on the failing target" "rc=$rc output=$output"
  fi
}

test_dollar_payload_preserved() {
  reset_fixture "single.py"
  FSUITE_TELEMETRY=0 "${FEDIT}" "${TEST_DIR}/single.py" --replace 'return False' --with 'return "$1 \\U \\L ${value}"' --apply >/dev/null 2>&1 || {
    fail "Dollar-heavy payload replace should succeed"
    return
  }
  local content
  content=$(cat "${TEST_DIR}/single.py")
  if [[ "$content" == *'return "$1 \\U \\L ${value}"'* ]]; then
    pass "Replacement payload preserves dollar and backslash sequences literally"
  else
    fail "Replacement payload was interpolated or corrupted" "Got: $content"
  fi
}

test_binary_payload_rejected() {
  local payload="${TEST_DIR}/binary_payload.bin"
  printf 'abc\000def' > "$payload"
  local rc=0
  reset_fixture "single.py"
  FSUITE_TELEMETRY=0 "${FEDIT}" "${TEST_DIR}/single.py" --replace 'return False' --content-file "$payload" >/dev/null 2>&1 || rc=$?
  if (( rc != 0 )); then
    pass "Binary payloads are rejected"
  else
    fail "Binary payloads should fail closed"
  fi
}

test_paths_output_only_when_applied() {
  local dry_output apply_output
  reset_fixture "single.py"
  dry_output=$(FSUITE_TELEMETRY=0 "${FEDIT}" -o paths "${TEST_DIR}/single.py" --replace 'return False' --with 'return deny()' 2>/dev/null)
  reset_fixture "single.py"
  apply_output=$(FSUITE_TELEMETRY=0 "${FEDIT}" -o paths "${TEST_DIR}/single.py" --replace 'return False' --with 'return deny()' --apply 2>/dev/null)
  if [[ -z "$dry_output" ]] && [[ "$apply_output" == "${TEST_DIR}/single.py" ]]; then
    pass "Paths output only emits applied files"
  else
    fail "Paths output should be empty on dry-run and path-only on apply" "dry='$dry_output' apply='$apply_output'"
  fi
}

test_symbol_scoping() {
  reset_fixture "auth.py"
  FSUITE_TELEMETRY=0 "${FEDIT}" "${TEST_DIR}/auth.py" --symbol authenticate --symbol-type function --replace 'return False' --with 'return deny()' --apply >/dev/null 2>&1 || {
    fail "Symbol-scoped replace should succeed"
    return
  }
  local first second
  first=$(sed -n '1,4p' "${TEST_DIR}/auth.py")
  second=$(sed -n '6,9p' "${TEST_DIR}/auth.py")
  if [[ "$first" == *'return deny()'* ]] && [[ "$second" == *'return False'* ]]; then
    pass "Symbol scoping limits the patch to one fmap-resolved symbol"
  else
    fail "Symbol scoping should edit only the chosen symbol"
  fi
}

test_fmap_json_scoping() {
  local fmap_json="${TEST_DIR}/auth-map.json"
  reset_fixture "auth.py"
  FSUITE_TELEMETRY=0 "${FMAP}" -o json "${TEST_DIR}/auth.py" > "$fmap_json" 2>/dev/null || {
    fail "fmap JSON generation should succeed"
    return
  }
  FSUITE_TELEMETRY=0 "${FEDIT}" "${TEST_DIR}/auth.py" --symbol authenticate --symbol-type function --fmap-json "$fmap_json" --replace 'return False' --with 'return deny()' --apply >/dev/null 2>&1 || {
    fail "fedit should accept --fmap-json input"
    return
  }
  local first second
  first=$(sed -n '1,4p' "${TEST_DIR}/auth.py")
  second=$(sed -n '6,9p' "${TEST_DIR}/auth.py")
  if [[ "$first" == *'return deny()'* ]] && [[ "$second" == *'return False'* ]]; then
    pass "--fmap-json path reuse scopes edits correctly"
  else
    fail "--fmap-json scoping should edit only the requested symbol"
  fi
}

test_crlf_payload_normalization() {
  reset_fixture "crlf_target.py"
  FSUITE_TELEMETRY=0 "${FEDIT}" "${TEST_DIR}/crlf_target.py" --after 'def authenticate(user):' --with $'    audit_log(user)\n    notify(user)\n' --apply >/dev/null 2>&1 || {
    fail "CRLF apply should succeed"
    return
  }
  if perl -e '
    use strict;
    use warnings;
    open my $fh, "<:raw", $ARGV[0] or exit 2;
    local $/;
    my $c = <$fh>;
    exit(($c =~ /\r\n/ && $c !~ /(?<!\r)\n/ && $c =~ /audit_log\(user\)\r\n    notify\(user\)\r\n    return True\r\n/) ? 0 : 1);
  ' "${TEST_DIR}/crlf_target.py"; then
    pass "Payload is normalized to CRLF when target file uses CRLF"
  else
    fail "CRLF normalization should preserve inserted content and line endings"
  fi
}

test_spaces_in_filename() {
  reset_fixture "file with spaces.txt"
  FSUITE_TELEMETRY=0 "${FEDIT}" "${TEST_DIR}/file with spaces.txt" --replace 'special content' --with 'updated content' --apply >/dev/null 2>&1 || {
    fail "Files with spaces should be editable"
    return
  }
  if [[ "$(cat "${TEST_DIR}/file with spaces.txt")" == 'updated content' ]]; then
    pass "Files with spaces are handled correctly"
  else
    fail "Expected updated content in spaced filename"
  fi
}

test_tier3_telemetry() {
  if ! command -v sqlite3 >/dev/null 2>&1; then
    pass "Tier 3 telemetry test skipped (sqlite3 not available)"
    return 0
  fi
  reset_fixture "single.py"
  rm -f "$HOME/.fsuite/telemetry.jsonl" "$HOME/.fsuite/telemetry.db"
  FSUITE_TELEMETRY=3 "${FEDIT}" "${TEST_DIR}/single.py" --replace 'return False' --with 'return deny()' >/dev/null 2>&1 || {
    fail "Tier 3 telemetry dry-run should succeed"
    return
  }
  FSUITE_TELEMETRY=0 "${FMETRICS}" import >/dev/null 2>&1 || {
    fail "fmetrics import should ingest fedit telemetry"
    return
  }
  local stats
  stats=$(FSUITE_TELEMETRY=0 "${FMETRICS}" stats -o json 2>/dev/null || true)
  if [[ "$stats" == *'"name":"fedit"'* ]]; then
    pass "Tier 3 telemetry is recorded and imported for fedit"
  else
    fail "Telemetry stats should include fedit" "Got: $stats"
  fi
}

# ==============================
# Symbol Shortcut Tests
# ==============================

test_function_shortcut() {
  reset_fixture "auth.py"
  FSUITE_TELEMETRY=0 "${FEDIT}" "${TEST_DIR}/auth.py" --function authenticate --replace 'return False' --with 'return deny()' --apply >/dev/null 2>&1 || {
    fail "--function shortcut should succeed"
    return
  }
  local first second
  first=$(sed -n '1,4p' "${TEST_DIR}/auth.py")
  second=$(sed -n '6,9p' "${TEST_DIR}/auth.py")
  if [[ "$first" == *'return deny()'* ]] && [[ "$second" == *'return False'* ]]; then
    pass "--function shortcut scopes correctly"
  else
    fail "--function shortcut should scope to the named function only"
  fi
}

test_class_shortcut() {
  local scoped="${TEST_DIR}/class_scope.py"
  cat > "$scoped" <<'EOF'
class AuthHandler:
    def login(self, user):
        return authenticate(user)

def helper(user):
    return authenticate(user)
EOF
  FSUITE_TELEMETRY=0 "${FEDIT}" "$scoped" --class AuthHandler --replace 'return authenticate(user)' --with 'return verify(user)' --apply >/dev/null 2>&1 || {
    fail "--class shortcut should succeed"
    return
  }
  local class_line outside_line
  class_line=$(sed -n '3p' "$scoped")
  outside_line=$(sed -n '6p' "$scoped")
  if [[ "$class_line" == *'return verify(user)'* ]] && [[ "$outside_line" == *'return authenticate(user)'* ]]; then
    pass "--class shortcut scopes correctly"
  else
    fail "--class shortcut should scope to the named class only" "class_line='$class_line' outside='$outside_line'"
  fi
}

test_shortcut_symbol_conflict() {
  local rc=0
  FSUITE_TELEMETRY=0 "${FEDIT}" "${TEST_DIR}/auth.py" --function authenticate --symbol deny_if_missing --replace 'x' --with 'y' >/dev/null 2>&1 || rc=$?
  if (( rc != 0 )); then
    pass "Symbol shortcut + --symbol conflict fails"
  else
    fail "Cannot combine --function with --symbol"
  fi
}

test_method_aliases_function() {
  reset_fixture "auth.py"
  local fn_output method_output
  fn_output=$(FSUITE_TELEMETRY=0 "${FEDIT}" "${TEST_DIR}/auth.py" --function authenticate --replace 'return False' --with 'return deny()' 2>/dev/null)
  reset_fixture "auth.py"
  method_output=$(FSUITE_TELEMETRY=0 "${FEDIT}" "${TEST_DIR}/auth.py" --method authenticate --replace 'return False' --with 'return deny()' 2>/dev/null)
  if [[ "$fn_output" == "$method_output" ]]; then
    pass "--method aliases --function identically"
  else
    fail "--method should produce identical output to --function"
  fi
}

test_multiple_shortcuts_conflict() {
  local rc=0 output
  reset_fixture "auth.py"
  output=$(FSUITE_TELEMETRY=0 "${FEDIT}" "${TEST_DIR}/auth.py" --function authenticate --class AuthHandler --replace 'return False' --with 'return deny()' 2>&1) || rc=$?
  if (( rc != 0 )) && [[ "$output" == *'Only one symbol shortcut may be used at a time'* ]]; then
    pass "Multiple symbol shortcuts are rejected"
  else
    fail "Multiple symbol shortcuts should fail closed" "rc=$rc output=$output"
  fi
}

test_import_shortcut() {
  local scoped="${TEST_DIR}/import_scope.ts"
  cat > "$scoped" <<'EOF'
import { readFile } from 'fs';
import { writeFile } from 'fs';
const msg = "import { readFile } from 'fs';";
EOF
  FSUITE_TELEMETRY=0 "${FEDIT}" "$scoped" --import readFile --replace "import { readFile } from 'fs';" --with "import { writeFile } from 'fs';" --apply >/dev/null 2>&1 || {
    fail "--import shortcut should succeed"
    return
  }
  local import1 import2
  import1=$(sed -n '1p' "$scoped")
  import2=$(sed -n '3p' "$scoped")
  if [[ "$import1" == "import { writeFile } from 'fs';" ]] && [[ "$import2" == *"import { readFile } from 'fs';"* ]]; then
    pass "--import shortcut scopes correctly"
  else
    fail "--import shortcut should only edit the scoped import line" "l1='$import1' l2='$import2'"
  fi
}

test_constant_shortcut() {
  local scoped="${TEST_DIR}/constant_scope.ts"
  cat > "$scoped" <<'EOF'
const MAX_SIZE = 10;
export type Config = { size: number };
const echo = "const MAX_SIZE = 10;";
EOF
  FSUITE_TELEMETRY=0 "${FEDIT}" "$scoped" --constant MAX_SIZE --replace 'MAX_SIZE = 10' --with 'MAX_SIZE = 20' --apply >/dev/null 2>&1 || {
    fail "--constant shortcut should succeed"
    return
  }
  local const_line string_line
  const_line=$(sed -n '1p' "$scoped")
  string_line=$(sed -n '3p' "$scoped")
  if [[ "$const_line" == 'const MAX_SIZE = 20;' ]] && [[ "$string_line" == *'const MAX_SIZE = 10;'* ]]; then
    pass "--constant shortcut scopes correctly"
  else
    fail "--constant shortcut should target only the constant symbol" "const='$const_line' string='$string_line'"
  fi
}

test_type_shortcut() {
  # types.ts has 'name: string' in both CustomType and OtherType
  # --type CustomType should only scope to CustomType's line
  reset_fixture "types.ts"
  FSUITE_TELEMETRY=0 "${FEDIT}" "${TEST_DIR}/types.ts" --type CustomType --replace 'name: string' --with 'name: number' --apply >/dev/null 2>&1 || {
    fail "--type shortcut should succeed"
    return
  }
  local custom_line other_line
  custom_line=$(grep 'CustomType' "${TEST_DIR}/types.ts")
  other_line=$(grep 'OtherType' "${TEST_DIR}/types.ts")
  if [[ "$custom_line" == *'name: number'* ]] && [[ "$other_line" == *'name: string'* ]]; then
    pass "--type shortcut scopes correctly"
  else
    fail "--type shortcut should only edit the scoped type" "custom='$custom_line' other='$other_line'"
  fi
}

# ==============================
# Batch Mode Tests
# ==============================

test_batch_paths_dry_run() {
  local a="${TEST_DIR}/batch_a.py" b="${TEST_DIR}/batch_b.py" c="${TEST_DIR}/batch_c.py"
  echo 'old_value = 1' > "$a"
  echo 'old_value = 1' > "$b"
  echo 'old_value = 1' > "$c"
  local output
  output=$(printf '%s\n' "$a" "$b" "$c" | FSUITE_TELEMETRY=0 "${FEDIT}" --targets-file - --targets-format paths --replace 'old_value = 1' --with 'new_value = 2' 2>/dev/null)
  if [[ "$output" == *"dry-run"* ]] && \
     [[ "$(cat "$a")" == 'old_value = 1' ]] && \
     [[ "$(cat "$b")" == 'old_value = 1' ]] && \
     [[ "$(cat "$c")" == 'old_value = 1' ]]; then
    pass "Batch paths dry-run previews without mutation"
  else
    fail "Batch dry-run should not mutate files" "output: $output"
  fi
}

test_batch_paths_apply() {
  local a="${TEST_DIR}/batch_a2.py" b="${TEST_DIR}/batch_b2.py" c="${TEST_DIR}/batch_c2.py"
  echo 'old_value = 1' > "$a"
  echo 'old_value = 1' > "$b"
  echo 'old_value = 1' > "$c"
  printf '%s\n' "$a" "$b" "$c" | FSUITE_TELEMETRY=0 "${FEDIT}" --targets-file - --targets-format paths --replace 'old_value = 1' --with 'new_value = 2' --apply >/dev/null 2>&1 || {
    fail "Batch apply should succeed"
    return
  }
  if [[ "$(cat "$a")" == 'new_value = 2' ]] && \
     [[ "$(cat "$b")" == 'new_value = 2' ]] && \
     [[ "$(cat "$c")" == 'new_value = 2' ]]; then
    pass "Batch paths apply writes all targets"
  else
    fail "All batch targets should be mutated"
  fi
}

test_batch_preflight_failure_writes_nothing() {
  local a="${TEST_DIR}/batch_pf_a.py" b="${TEST_DIR}/batch_pf_b.py" c="${TEST_DIR}/batch_pf_c.py"
  echo 'old_value = 1' > "$a"
  echo 'old_value = 1' > "$b"
  echo 'different_text = 99' > "$c"
  local rc=0
  printf '%s\n' "$a" "$b" "$c" | FSUITE_TELEMETRY=0 "${FEDIT}" --targets-file - --targets-format paths --replace 'old_value = 1' --with 'new_value = 2' --apply >/dev/null 2>&1 || rc=$?
  if (( rc != 0 )) && \
     [[ "$(cat "$a")" == 'old_value = 1' ]] && \
     [[ "$(cat "$b")" == 'old_value = 1' ]] && \
     [[ "$(cat "$c")" == 'different_text = 99' ]]; then
    pass "Preflight failure writes nothing"
  else
    fail "When one target fails planning, no files should be mutated" "rc=$rc a=$(cat "$a") b=$(cat "$b") c=$(cat "$c")"
  fi
}

test_batch_symbol_scoped() {
  local a="${TEST_DIR}/batch_sym_a.py" b="${TEST_DIR}/batch_sym_b.py"
  cat > "$a" <<'PYEOF'
def authenticate(user):
    return False

def other(user):
    return False
PYEOF
  cat > "$b" <<'PYEOF'
def authenticate(user):
    return False

def other(user):
    return False
PYEOF
  printf '%s\n' "$a" "$b" | FSUITE_TELEMETRY=0 "${FEDIT}" --targets-file - --targets-format paths --function authenticate --replace 'return False' --with 'return deny()' --apply >/dev/null 2>&1 || {
    fail "Batch symbol-scoped should succeed"
    return
  }
  local a_auth a_other b_auth b_other
  a_auth=$(sed -n '2p' "$a")
  a_other=$(sed -n '5p' "$a")
  b_auth=$(sed -n '2p' "$b")
  b_other=$(sed -n '5p' "$b")
  if [[ "$a_auth" == *'return deny()'* ]] && [[ "$a_other" == *'return False'* ]] && \
     [[ "$b_auth" == *'return deny()'* ]] && [[ "$b_other" == *'return False'* ]]; then
    pass "Batch + --function scopes each file independently"
  else
    fail "Batch symbol scoping should only edit the target symbol per file"
  fi
}

test_batch_fmap_json() {
  local a="${TEST_DIR}/batch_fmap_a.py" b="${TEST_DIR}/batch_fmap_b.py"
  cat > "$a" <<'PYEOF'
def authenticate(user):
    return False

def other(user):
    return False
PYEOF
  cat > "$b" <<'PYEOF'
def authenticate(user):
    return False

def helper():
    return True
PYEOF
  local fmap_json="${TEST_DIR}/batch-map.json"
  printf '%s\n%s\n' "$a" "$b" | FSUITE_TELEMETRY=0 "${FMAP}" -o json > "$fmap_json" 2>/dev/null || {
    fail "fmap JSON generation for batch should succeed"
    return
  }
  FSUITE_TELEMETRY=0 "${FEDIT}" --targets-file "$fmap_json" --targets-format fmap-json --function authenticate --replace 'return False' --with 'return deny()' --apply >/dev/null 2>&1 || {
    fail "Batch fmap-json should succeed"
    return
  }
  local a_auth a_other b_auth b_helper
  a_auth=$(sed -n '2p' "$a")
  a_other=$(sed -n '5p' "$a")
  b_auth=$(sed -n '2p' "$b")
  b_helper=$(sed -n '5p' "$b")
  if [[ "$a_auth" == *'return deny()'* ]] && [[ "$a_other" == *'return False'* ]] && \
     [[ "$b_auth" == *'return deny()'* ]] && [[ "$b_helper" == *'return True'* ]]; then
    pass "Batch fmap-json targets format works"
  else
    fail "fmap-json batch should scope correctly" "a_auth='$a_auth' a_other='$a_other' b_auth='$b_auth' b_helper='$b_helper'"
  fi
}

test_batch_stdin_targets() {
  local a="${TEST_DIR}/batch_stdin_a.py"
  echo 'old = 1' > "$a"
  local output
  output=$(echo "$a" | FSUITE_TELEMETRY=0 "${FEDIT}" --targets-file - --targets-format paths --replace 'old = 1' --with 'new = 2' 2>/dev/null)
  if [[ "$output" == *"dry-run"* ]] && [[ "$output" == *"$a"* ]]; then
    pass "--targets-file - reads from stdin"
  else
    fail "--targets-file - should read targets from stdin" "Got: $output"
  fi
}

test_batch_stdin_payload_conflict() {
  local rc=0 output
  output=$(echo "/tmp/dummy.py" | FSUITE_TELEMETRY=0 "${FEDIT}" --targets-file - --targets-format paths --stdin --replace 'x' --with 'y' 2>&1) || rc=$?
  if (( rc != 0 )) && [[ "$output" == *'--targets-file - (stdin targets) is mutually exclusive with --stdin (payload)'* ]]; then
    pass "--targets-file - + --stdin conflict detected"
  else
    fail "--targets-file - and --stdin should fail for the explicit conflict reason" "rc=$rc output=$output"
  fi
}

test_batch_json_envelope() {
  if ! command -v python3 >/dev/null 2>&1; then
    pass "Batch JSON envelope test skipped (python3 not available)"
    return 0
  fi
  local a="${TEST_DIR}/batch_json_a.py" b="${TEST_DIR}/batch_json_b.py"
  echo 'x = 1' > "$a"
  echo 'x = 1' > "$b"
  local output
  output=$(printf '%s\n' "$a" "$b" | FSUITE_TELEMETRY=0 "${FEDIT}" -o json --targets-file - --targets-format paths --replace 'x = 1' --with 'x = 2' 2>/dev/null)
  if printf '%s' "$output" | python3 -m json.tool >/dev/null 2>&1 && \
     [[ "$output" == *'"mode":"patch_batch"'* ]] && \
     [[ "$output" == *'"targets_total":2'* ]] && \
     [[ "$output" == *'"targets_ready":2'* ]] && \
     [[ "$output" == *'"preflighted":true'* ]] && \
     [[ "$output" == *'"results":'* ]]; then
    pass "Batch JSON envelope has correct structure"
  else
    fail "Batch JSON should have batch-specific fields" "Got: $output"
  fi
}

test_batch_paths_output() {
  local a="${TEST_DIR}/batch_po_a.py" b="${TEST_DIR}/batch_po_b.py"
  echo 'x = 1' > "$a"
  echo 'x = 1' > "$b"
  local dry_output apply_output
  dry_output=$(printf '%s\n' "$a" "$b" | FSUITE_TELEMETRY=0 "${FEDIT}" -o paths --targets-file - --targets-format paths --replace 'x = 1' --with 'x = 2' 2>/dev/null)
  echo 'x = 1' > "$a"
  echo 'x = 1' > "$b"
  apply_output=$(printf '%s\n' "$a" "$b" | FSUITE_TELEMETRY=0 "${FEDIT}" -o paths --targets-file - --targets-format paths --replace 'x = 1' --with 'x = 2' --apply 2>/dev/null)
  if [[ -z "$dry_output" ]] && [[ "$apply_output" == *"$a"* ]] && [[ "$apply_output" == *"$b"* ]]; then
    pass "Batch paths output only emits applied paths"
  else
    fail "Paths: empty on dry-run, one per applied on apply" "dry='$dry_output' apply='$apply_output'"
  fi
}

test_batch_expect_precondition() {
  local a="${TEST_DIR}/batch_expect_a.py" b="${TEST_DIR}/batch_expect_b.py"
  cat > "$a" <<'EOF'
def authenticate(user):
    return False
EOF
  cat > "$b" <<'EOF'
def authenticate(user):
    return False
EOF
  printf '%s\n' "$a" "$b" | FSUITE_TELEMETRY=0 "${FEDIT}" --targets-file - --targets-format paths --expect 'def authenticate' --replace 'return False' --with 'return deny()' --apply >/dev/null 2>&1 || {
    fail "Batch --expect precondition should succeed when all targets match"
    return
  }
  if [[ "$(cat "$a")" == *'return deny()'* ]] && [[ "$(cat "$b")" == *'return deny()'* ]]; then
    pass "Batch + --expect precondition works"
  else
    fail "Batch --expect should allow apply when all files satisfy the precondition"
  fi
}

test_batch_deduplicates_paths() {
  if ! command -v python3 >/dev/null 2>&1; then
    pass "Batch dedup test skipped (python3 not available)"
    return 0
  fi
  local a="${TEST_DIR}/batch_dedup_a.py"
  echo 'x = 1' > "$a"
  local output targets_total
  output=$(printf '%s\n%s\n' "$a" "$a" | FSUITE_TELEMETRY=0 "${FEDIT}" -o json --targets-file - --targets-format paths --replace 'x = 1' --with 'x = 2' 2>/dev/null)
  targets_total=$(printf '%s' "$output" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['targets_total'])" 2>/dev/null || true)
  if [[ "$targets_total" == "1" ]]; then
    pass "Batch deduplicates repeated target paths"
  else
    fail "Batch should deduplicate repeated target paths" "targets_total=$targets_total output=$output"
  fi
}

test_batch_allow_multiple() {
  local a="${TEST_DIR}/batch_multi_a.py" b="${TEST_DIR}/batch_multi_b.py"
  cat > "$a" <<'EOF'
x = 1
x = 1
EOF
  cat > "$b" <<'EOF'
x = 1
x = 1
EOF
  printf '%s\n' "$a" "$b" | FSUITE_TELEMETRY=0 "${FEDIT}" --targets-file - --targets-format paths --replace 'x = 1' --with 'x = 2' --allow-multiple --apply >/dev/null 2>&1 || {
    fail "Batch + --allow-multiple should succeed"
    return
  }
  if [[ "$(grep -c 'x = 2' "$a")" == "2" ]] && [[ "$(grep -c 'x = 2' "$b")" == "2" ]]; then
    pass "Batch + --allow-multiple applies to each target"
  else
    fail "Batch --allow-multiple should replace every match in each file"
  fi
}

test_batch_content_file_payload() {
  local a="${TEST_DIR}/batch_cf_a.py" b="${TEST_DIR}/batch_cf_b.py" payload="${TEST_DIR}/batch_payload.txt"
  cat > "$a" <<'EOF'
def authenticate(user):
    return True
EOF
  cat > "$b" <<'EOF'
def authenticate(user):
    return True
EOF
  cat > "$payload" <<'EOF'
    audit_log(user)
EOF
  printf '%s\n' "$a" "$b" | FSUITE_TELEMETRY=0 "${FEDIT}" --targets-file - --targets-format paths --after 'def authenticate(user):' --content-file "$payload" --apply >/dev/null 2>&1 || {
    fail "Batch + --content-file should succeed"
    return
  }
  if [[ "$(sed -n '2p' "$a")" == '    audit_log(user)' ]] && [[ "$(sed -n '2p' "$b")" == '    audit_log(user)' ]]; then
    pass "Batch + --content-file payload works"
  else
    fail "Batch content-file payload should be inserted into each target"
  fi
}

test_batch_spaces_in_paths() {
  local spaced="${TEST_DIR}/batch spaced file.py"
  echo 'x = 1' > "$spaced"
  local output
  output=$(printf '%s\n' "$spaced" | FSUITE_TELEMETRY=0 "${FEDIT}" --targets-file - --targets-format paths --replace 'x = 1' --with 'x = 2' --apply 2>/dev/null)
  if [[ "$(cat "$spaced")" == 'x = 2' ]]; then
    pass "Batch handles spaces in file paths"
  else
    fail "Batch should handle spaces in paths" "content: $(cat "$spaced")"
  fi
}

test_batch_preserves_order() {
  if ! command -v python3 >/dev/null 2>&1; then
    pass "Batch order test skipped (python3 not available)"
    return 0
  fi
  local a="${TEST_DIR}/batch_ord_a.py" b="${TEST_DIR}/batch_ord_b.py" c="${TEST_DIR}/batch_ord_c.py"
  echo 'x = 1' > "$a"
  echo 'x = 1' > "$b"
  echo 'x = 1' > "$c"
  local output
  output=$(printf '%s\n' "$c" "$a" "$b" | FSUITE_TELEMETRY=0 "${FEDIT}" -o json --targets-file - --targets-format paths --replace 'x = 1' --with 'x = 2' 2>/dev/null)
  local first_path
  first_path=$(printf '%s' "$output" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['results'][0]['path'])" 2>/dev/null || true)
  if [[ "$first_path" == "$c" ]]; then
    pass "Batch JSON results preserve input order"
  else
    fail "Results order should match input order" "first_path=$first_path expected=$c"
  fi
}

test_batch_empty_input() {
  local rc=0
  printf '' | FSUITE_TELEMETRY=0 "${FEDIT}" --targets-file - --targets-format paths --replace 'x' --with 'y' >/dev/null 2>&1 || rc=$?
  if (( rc != 0 )); then
    pass "Empty batch targets produces structured error"
  else
    fail "Empty targets should fail"
  fi
}

main() {
  echo "======================================"
  echo "  fedit Test Suite"
  echo "======================================"
  echo ""
  echo "Running tests..."
  echo ""

  [[ -x "${FEDIT}" ]] || { echo "fedit missing: ${FEDIT}" >&2; exit 1; }

  setup
  trap teardown EXIT

  # --- Original tests (41) ---
  run_test "Version output" test_version
  run_test "Help output" test_help
  run_test "Self-check" test_self_check
  run_test "Install hints" test_install_hints
  run_test "Dry-run default" test_dry_run_default
  run_test "Apply replace" test_apply_replace
  run_test "Replace missing" test_replace_missing_fails
  run_test "Ambiguous replace" test_ambiguous_replace_fails
  run_test "Allow multiple" test_allow_multiple_replace
  run_test "After anchor insert" test_after_anchor_insert
  run_test "Before anchor insert" test_before_anchor_insert
  run_test "After anchor ambiguity" test_after_anchor_ambiguity_fails
  run_test "Before anchor ambiguity" test_before_anchor_ambiguity_fails
  run_test "Multi-line after anchor" test_multiline_after_anchor
  run_test "Before anchor apply" test_before_anchor_apply
  run_test "STDIN payload" test_stdin_payload
  run_test "Expect text success" test_expect_text_success
  run_test "Expect text failure" test_expect_text_failure
  run_test "Expect sha failure" test_expect_sha_failure
  run_test "Expect sha success" test_expect_sha_success
  run_test "Create dry-run" test_create_dry_run
  run_test "Create apply" test_create_apply
  run_test "Replace-file apply" test_replace_file_apply
  run_test "JSON parseability" test_json_output_parseable
  run_test "JSON error output" test_json_error_output
  run_test "JSON not_found" test_json_not_found_error
  run_test "JSON not_regular" test_json_not_regular_error
  run_test "JSON permission" test_json_permission_error
  run_test "JSON anchor ambiguous" test_json_anchor_ambiguous_error
  run_test "JSON precondition error" test_json_precondition_error
  run_test "JSON symbol ambiguous" test_json_symbol_ambiguous_error
  run_test "Batch JSON error output" test_batch_json_error_output
  run_test "Batch JSON anchor missing" test_batch_json_anchor_missing_error
  run_test "Dollar payload preservation" test_dollar_payload_preserved
  run_test "Binary payload rejection" test_binary_payload_rejected
  run_test "Paths output" test_paths_output_only_when_applied
  run_test "Symbol scoping" test_symbol_scoping
  run_test "fmap JSON scoping" test_fmap_json_scoping
  run_test "CRLF normalization" test_crlf_payload_normalization
  run_test "Spaces in filename" test_spaces_in_filename
  run_test "Tier 3 telemetry" test_tier3_telemetry

  # --- Symbol shortcut tests (7) ---
  run_test "Function shortcut" test_function_shortcut
  run_test "Class shortcut" test_class_shortcut
  run_test "Shortcut+symbol conflict" test_shortcut_symbol_conflict
  run_test "Multiple shortcuts conflict" test_multiple_shortcuts_conflict
  run_test "Method aliases function" test_method_aliases_function
  run_test "Import shortcut" test_import_shortcut
  run_test "Constant shortcut" test_constant_shortcut
  run_test "Type shortcut" test_type_shortcut

  # --- Batch mode tests (17) ---
  run_test "Batch paths dry-run" test_batch_paths_dry_run
  run_test "Batch paths apply" test_batch_paths_apply
  run_test "Batch preflight failure" test_batch_preflight_failure_writes_nothing
  run_test "Batch symbol scoped" test_batch_symbol_scoped
  run_test "Batch fmap-json" test_batch_fmap_json
  run_test "Batch stdin targets" test_batch_stdin_targets
  run_test "Batch stdin+payload conflict" test_batch_stdin_payload_conflict
  run_test "Batch JSON envelope" test_batch_json_envelope
  run_test "Batch paths output" test_batch_paths_output
  run_test "Batch spaces in paths" test_batch_spaces_in_paths
  run_test "Batch preserves order" test_batch_preserves_order
  run_test "Batch empty input" test_batch_empty_input
  run_test "Batch expect precondition" test_batch_expect_precondition
  run_test "Batch deduplicates paths" test_batch_deduplicates_paths
  run_test "Batch allow-multiple" test_batch_allow_multiple
  run_test "Batch content-file payload" test_batch_content_file_payload

  echo ""
  echo "======================================"
  echo "  Test Results"
  echo "======================================"
  echo "Total:  ${TESTS_RUN}"
  echo -e "${GREEN}Passed: ${TESTS_PASSED}${NC}"
  echo -e "${RED}Failed: ${TESTS_FAILED}${NC}"

  if (( TESTS_PASSED + TESTS_FAILED != TESTS_RUN )); then
    echo "Counter mismatch: run=${TESTS_RUN} passed=${TESTS_PASSED} failed=${TESTS_FAILED}" >&2
    exit 1
  fi

  if (( TESTS_FAILED > 0 )); then
    exit 1
  fi

  echo -e "${GREEN}All tests passed!${NC}"
}

main "$@"
