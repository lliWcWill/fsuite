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

  echo 'old content' > "${TEST_DIR}/replace_me.txt"
  echo 'special content' > "${TEST_DIR}/file with spaces.txt"

  cp "${TEST_DIR}/auth.py" "${TEST_DIR}/auth.py.orig"
  cp "${TEST_DIR}/single.py" "${TEST_DIR}/single.py.orig"
  cp "${TEST_DIR}/insert_target.py" "${TEST_DIR}/insert_target.py.orig"
  cp "${TEST_DIR}/repeated_anchor.py" "${TEST_DIR}/repeated_anchor.py.orig"
  cp "${TEST_DIR}/multiline_anchor.py" "${TEST_DIR}/multiline_anchor.py.orig"
  cp "${TEST_DIR}/crlf_target.py" "${TEST_DIR}/crlf_target.py.orig"
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
  run_test "JSON anchor ambiguous" test_json_anchor_ambiguous_error
  run_test "JSON precondition error" test_json_precondition_error
  run_test "Dollar payload preservation" test_dollar_payload_preserved
  run_test "Binary payload rejection" test_binary_payload_rejected
  run_test "Paths output" test_paths_output_only_when_applied
  run_test "Symbol scoping" test_symbol_scoping
  run_test "fmap JSON scoping" test_fmap_json_scoping
  run_test "CRLF normalization" test_crlf_payload_normalization
  run_test "Spaces in filename" test_spaces_in_filename
  run_test "Tier 3 telemetry" test_tier3_telemetry

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
