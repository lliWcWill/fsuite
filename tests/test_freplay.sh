#!/usr/bin/env bash
# test_freplay.sh — tests for freplay derivation replay ledger
# Run with: bash test_freplay.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FREPLAY="${SCRIPT_DIR}/../freplay"
FCASE="${SCRIPT_DIR}/../fcase"
FTREE="${SCRIPT_DIR}/../ftree"
FSEARCH="${SCRIPT_DIR}/../fsearch"
FCASE_CMD="${SCRIPT_DIR}/../fcase"  # for recording fcase subcommands
TEST_HOME=""
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

setup() {
  TEST_HOME="$(mktemp -d)"
}

teardown() {
  if [[ -n "${TEST_HOME}" && -d "${TEST_HOME}" ]]; then
    rm -rf "${TEST_HOME}"
  fi
  TEST_HOME=""
}

pass() {
  TESTS_PASSED=$((TESTS_PASSED + 1))
  echo -e "${GREEN}✓${NC} $1"
}

fail() {
  TESTS_FAILED=$((TESTS_FAILED + 1))
  echo -e "${RED}✗${NC} $1"
  if [[ -n "${2:-}" ]]; then
    echo "  Details: $2"
  fi
}

run_test() {
  TESTS_RUN=$((TESTS_RUN + 1))
  setup
  local rc=0
  "$@" || rc=$?
  teardown
  if (( rc != 0 )); then
    fail "$1 exited non-zero" "rc=$rc"
  fi
}

run_freplay() {
  HOME="${TEST_HOME}" FSUITE_TELEMETRY=0 "${FREPLAY}" "$@"
}

run_freplay_with_telemetry() {
  local telemetry_tier="${1:-1}"
  shift || true
  HOME="${TEST_HOME}" FSUITE_TELEMETRY="${telemetry_tier}" "${FREPLAY}" "$@"
}

run_fcase() {
  HOME="${TEST_HOME}" FSUITE_TELEMETRY=0 "${FCASE}" "$@"
}

# Helper to init a case for tests
init_case() {
  local slug="${1:-test-case}"
  local goal="${2:-test goal}"
  run_fcase init "$slug" --goal "$goal" >/dev/null 2>&1
}

# Helper to query DB
query_db() {
  sqlite3 "${TEST_HOME}/.fsuite/fcase.db" "$1"
}

# =========================================================================
# Record flow (tests 1-20)
# =========================================================================

test_version() {
  local output
  output=$(run_freplay --version 2>&1)
  if [[ "$output" =~ ^freplay\ [0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    pass "Version output format is correct"
  else
    fail "Version output format should be 'freplay X.Y.Z'" "Got: $output"
  fi
}

test_help() {
  local output
  output=$(run_freplay --help 2>&1)
  if [[ "$output" == *"freplay"* ]] && [[ "$output" == *"record"* ]] && [[ "$output" == *"show"* ]]; then
    pass "Help output documents freplay core commands"
  else
    fail "Help output should contain freplay, record, show" "Got: $output"
  fi
}

test_self_check() {
  init_case "selfcheck-case" "self check test"
  local output rc=0
  output=$(run_freplay --self-check 2>&1) || rc=$?
  if (( rc == 0 )); then
    pass "Self-check exits 0 when deps present"
  else
    fail "Self-check should exit 0 when deps present" "rc=$rc output=$output"
  fi
}

test_record_single_step() {
  init_case "rec-single" "record single step"
  run_freplay record rec-single -- "${FTREE}" --version >/dev/null 2>&1 || true
  local count
  count=$(query_db "PRAGMA foreign_keys=ON; SELECT COUNT(*) FROM replay_steps;")
  if [[ "$count" == "1" ]]; then
    pass "Record creates 1 row in replay_steps"
  else
    fail "Record should create 1 row in replay_steps" "count=$count"
  fi
}

test_record_multiple_steps() {
  init_case "rec-multi" "record multiple steps"
  run_freplay record rec-multi -- "${FTREE}" --version >/dev/null 2>&1 || true
  run_freplay record rec-multi -- "${FSEARCH}" --version >/dev/null 2>&1 || true
  local count
  count=$(query_db "PRAGMA foreign_keys=ON; SELECT COUNT(*) FROM replay_steps;")
  local orders
  orders=$(query_db "PRAGMA foreign_keys=ON; SELECT group_concat(order_num) FROM replay_steps ORDER BY order_num;")
  if [[ "$count" == "2" ]] && [[ "$orders" == "1,2" ]]; then
    pass "Record creates 2 rows with order_num 1 and 2"
  else
    fail "Record should create 2 rows with sequential order_nums" "count=$count orders=$orders"
  fi
}

test_record_auto_creates_draft() {
  init_case "rec-draft" "auto-draft creation"
  run_freplay record rec-draft -- "${FTREE}" --version >/dev/null 2>&1 || true
  local status
  status=$(query_db "PRAGMA foreign_keys=ON; SELECT status FROM replays LIMIT 1;")
  if [[ "$status" == "draft" ]]; then
    pass "Record auto-creates a draft replay"
  else
    fail "Record should auto-create a draft replay" "status=$status"
  fi
}

test_record_appends_to_draft() {
  init_case "rec-append" "append to draft"
  run_freplay record rec-append -- "${FTREE}" --version >/dev/null 2>&1 || true
  run_freplay record rec-append -- "${FSEARCH}" --version >/dev/null 2>&1 || true
  local replay_count
  replay_count=$(query_db "PRAGMA foreign_keys=ON; SELECT COUNT(*) FROM replays;")
  local step_count
  step_count=$(query_db "PRAGMA foreign_keys=ON; SELECT COUNT(*) FROM replay_steps;")
  if [[ "$replay_count" == "1" ]] && [[ "$step_count" == "2" ]]; then
    pass "Record appends both steps to same replay_id"
  else
    fail "Record should append to existing draft replay" "replays=$replay_count steps=$step_count"
  fi
}

test_record_with_purpose() {
  init_case "rec-purpose" "purpose test"
  run_freplay record rec-purpose --purpose "test purpose text" -- "${FTREE}" --version >/dev/null 2>&1 || true
  local purpose
  purpose=$(query_db "PRAGMA foreign_keys=ON; SELECT purpose FROM replay_steps LIMIT 1;")
  if [[ "$purpose" == "test purpose text" ]]; then
    pass "Record stores purpose in DB"
  else
    fail "Record should store purpose in DB" "purpose=$purpose"
  fi
}

test_record_with_link() {
  init_case "rec-link" "link test"
  # Create an evidence row so link target exists
  run_fcase evidence rec-link --tool fread --body "test evidence" >/dev/null 2>&1 || true
  run_freplay record rec-link --link evidence:1 -- "${FTREE}" --version >/dev/null 2>&1 || true
  local link_count
  link_count=$(query_db "PRAGMA foreign_keys=ON; SELECT COUNT(*) FROM replay_step_links;")
  if [[ "$link_count" == "1" ]]; then
    pass "Record stores link in replay_step_links"
  else
    fail "Record should store link in replay_step_links" "link_count=$link_count"
  fi
}

test_record_rejects_non_fsuite() {
  init_case "rec-reject" "reject non-fsuite"
  local output rc=0
  output=$(run_freplay record rec-reject -- ls /tmp 2>&1) || rc=$?
  if (( rc != 0 )) && [[ "$output" == *"not an fsuite tool"* ]]; then
    pass "Record rejects non-fsuite tools"
  else
    fail "Record should reject non-fsuite tools" "rc=$rc output=$output"
  fi
}

test_record_rejects_freplay() {
  init_case "rec-reject-freplay" "reject freplay"
  local output rc=0
  output=$(run_freplay record rec-reject-freplay -- "${FREPLAY}" --version 2>&1) || rc=$?
  if (( rc != 0 )) && [[ "$output" == *"excluded"* ]]; then
    pass "Record rejects freplay (excluded from recording)"
  else
    fail "Record should reject freplay" "rc=$rc output=$output"
  fi
}

test_record_rejects_fmetrics() {
  init_case "rec-reject-fmetrics" "reject fmetrics"
  local output rc=0
  output=$(run_freplay record rec-reject-fmetrics -- "${SCRIPT_DIR}/../fmetrics" --version 2>&1) || rc=$?
  if (( rc != 0 )) && [[ "$output" == *"excluded"* ]]; then
    pass "Record rejects fmetrics (excluded from recording)"
  else
    fail "Record should reject fmetrics" "rc=$rc output=$output"
  fi
}

test_record_argv_json() {
  init_case "rec-argv" "argv json test"
  run_freplay record rec-argv -- "${FTREE}" --version >/dev/null 2>&1 || true
  local argv
  argv=$(query_db "PRAGMA foreign_keys=ON; SELECT argv_json FROM replay_steps LIMIT 1;")
  if [[ "$argv" == '["--version"]' ]]; then
    pass "Record stores argv_json without tool path"
  else
    fail "Record should store argv_json as [\"--version\"]" "argv=$argv"
  fi
}

test_record_cwd() {
  init_case "rec-cwd" "cwd test"
  run_freplay record rec-cwd -- "${FTREE}" --version >/dev/null 2>&1 || true
  local cwd
  cwd=$(query_db "PRAGMA foreign_keys=ON; SELECT cwd FROM replay_steps LIMIT 1;")
  if [[ "$cwd" == /* ]]; then
    pass "Record stores an absolute cwd path"
  else
    fail "Record should store absolute cwd path" "cwd=$cwd"
  fi
}

test_record_mode_read_only() {
  init_case "rec-mode-ro" "mode read_only test"
  run_freplay record rec-mode-ro -- "${FTREE}" --version >/dev/null 2>&1 || true
  local mode
  mode=$(query_db "PRAGMA foreign_keys=ON; SELECT mode FROM replay_steps LIMIT 1;")
  if [[ "$mode" == "read_only" ]]; then
    pass "Record classifies ftree as read_only"
  else
    fail "Record should classify ftree as read_only" "mode=$mode"
  fi
}

test_record_mode_mutating() {
  init_case "rec-mode-mut" "mode mutating test"
  run_freplay record rec-mode-mut -- "${FCASE_CMD}" note rec-mode-mut --body "x" >/dev/null 2>&1 || true
  local mode
  mode=$(query_db "PRAGMA foreign_keys=ON; SELECT mode FROM replay_steps LIMIT 1;")
  if [[ "$mode" == "mutating" ]]; then
    pass "Record classifies fcase note as mutating"
  else
    fail "Record should classify fcase note as mutating" "mode=$mode"
  fi
}

test_record_mode_fcase_subcommand() {
  init_case "rec-mode-fcase" "fcase subcommand mode test"
  run_freplay record rec-mode-fcase -- "${FCASE_CMD}" status rec-mode-fcase >/dev/null 2>&1 || true
  local mode
  mode=$(query_db "PRAGMA foreign_keys=ON; SELECT mode FROM replay_steps LIMIT 1;")
  if [[ "$mode" == "read_only" ]]; then
    pass "Record classifies fcase status as read_only"
  else
    fail "Record should classify fcase status as read_only" "mode=$mode"
  fi
}

test_record_exit_code() {
  init_case "rec-exit" "exit code test"
  local rc=0
  run_freplay record rec-exit -- "${FCASE_CMD}" status nonexistent-slug-xyz >/dev/null 2>&1 || rc=$?
  local exit_code
  exit_code=$(query_db "PRAGMA foreign_keys=ON; SELECT exit_code FROM replay_steps LIMIT 1;")
  if (( rc != 0 )) && [[ "$exit_code" != "0" ]]; then
    pass "Record captures non-zero exit code and freplay exits with same code"
  else
    fail "Record should capture non-zero exit code" "rc=$rc exit_code=$exit_code"
  fi
}

test_record_error_excerpt() {
  init_case "rec-error" "error excerpt test"
  run_freplay record rec-error -- "${FCASE_CMD}" status nonexistent-slug-xyz >/dev/null 2>&1 || true
  local error_excerpt
  error_excerpt=$(query_db "PRAGMA foreign_keys=ON; SELECT error_excerpt FROM replay_steps LIMIT 1;")
  if [[ -n "$error_excerpt" ]]; then
    pass "Record stores error_excerpt for failing commands"
  else
    fail "Record should store error_excerpt for failing commands" "error_excerpt=$error_excerpt"
  fi
}

test_record_result_summary() {
  init_case "rec-result" "result summary test"
  run_freplay record rec-result -- "${FTREE}" --version >/dev/null 2>&1 || true
  local result_summary
  result_summary=$(query_db "PRAGMA foreign_keys=ON; SELECT result_summary FROM replay_steps LIMIT 1;")
  if [[ -n "$result_summary" ]]; then
    pass "Record stores result_summary for read_only commands"
  else
    fail "Record should store result_summary for read_only commands" "result_summary=$result_summary"
  fi
}

test_record_persists_telemetry_run_id() {
  init_case "rec-telem-link" "telemetry linkage test"
  mkdir -p "${TEST_HOME}/workspace/combo-impact"
  : > "${TEST_HOME}/workspace/combo-impact/Makefile"

  run_freplay_with_telemetry 1 record rec-telem-link -- "${FTREE}" "${TEST_HOME}/workspace/combo-impact" >/dev/null 2>&1 || true

  local run_id
  run_id=$(query_db "PRAGMA foreign_keys=ON; SELECT COALESCE(telemetry_run_id, '') FROM replay_steps LIMIT 1;")

  if [[ -n "$run_id" ]] && grep -q "\"run_id\":\"$run_id\"" "${TEST_HOME}/.fsuite/telemetry.jsonl"; then
    pass "Record persists telemetry_run_id and matches emitted telemetry"
  else
    fail "Record should persist telemetry_run_id and match emitted telemetry" "run_id=${run_id:-<empty>}"
  fi
}

# =========================================================================
# Lifecycle (tests 21-24)
# =========================================================================

test_promote() {
  init_case "promote-test" "promote test"
  run_freplay record promote-test -- "${FTREE}" --version >/dev/null 2>&1 || true
  local replay_id
  replay_id=$(query_db "PRAGMA foreign_keys=ON; SELECT id FROM replays LIMIT 1;")
  run_freplay promote promote-test "$replay_id" >/dev/null 2>&1 || true
  local status
  status=$(query_db "PRAGMA foreign_keys=ON; SELECT status FROM replays WHERE id=$replay_id;")
  if [[ "$status" == "canonical" ]]; then
    pass "Promote sets replay status to canonical"
  else
    fail "Promote should set status to canonical" "status=$status"
  fi
}

test_promote_demotes_existing() {
  init_case "promote-demote" "promote demotes test"
  # Create replay A
  run_freplay record promote-demote -- "${FTREE}" --version >/dev/null 2>&1 || true
  local replay_a
  replay_a=$(query_db "PRAGMA foreign_keys=ON; SELECT id FROM replays ORDER BY id ASC LIMIT 1;")
  run_freplay promote promote-demote "$replay_a" >/dev/null 2>&1 || true

  # Create replay B
  run_freplay record promote-demote --new -- "${FSEARCH}" --version >/dev/null 2>&1 || true
  local replay_b
  replay_b=$(query_db "PRAGMA foreign_keys=ON; SELECT id FROM replays ORDER BY id DESC LIMIT 1;")
  run_freplay promote promote-demote "$replay_b" >/dev/null 2>&1 || true

  local status_a status_b
  status_a=$(query_db "PRAGMA foreign_keys=ON; SELECT status FROM replays WHERE id=$replay_a;")
  status_b=$(query_db "PRAGMA foreign_keys=ON; SELECT status FROM replays WHERE id=$replay_b;")
  if [[ "$status_a" == "archived" ]] && [[ "$status_b" == "canonical" ]]; then
    pass "Promote demotes existing canonical to archived"
  else
    fail "Promote should demote old canonical" "status_a=$status_a status_b=$status_b"
  fi
}

test_canonical_unique_index() {
  init_case "canonical-uniq" "canonical unique index"
  run_freplay record canonical-uniq -- "${FTREE}" --version >/dev/null 2>&1 || true
  local replay_a
  replay_a=$(query_db "PRAGMA foreign_keys=ON; SELECT id FROM replays ORDER BY id ASC LIMIT 1;")
  run_freplay promote canonical-uniq "$replay_a" >/dev/null 2>&1 || true

  # Create a second replay
  run_freplay record canonical-uniq --new -- "${FSEARCH}" --version >/dev/null 2>&1 || true
  local replay_b
  replay_b=$(query_db "PRAGMA foreign_keys=ON; SELECT id FROM replays ORDER BY id DESC LIMIT 1;")

  # Try to directly INSERT a second canonical via sqlite3 — should fail
  local rc=0
  sqlite3 "${TEST_HOME}/.fsuite/fcase.db" "PRAGMA foreign_keys=ON; UPDATE replays SET status='canonical' WHERE id=$replay_b;" 2>/dev/null || rc=$?
  if (( rc != 0 )); then
    pass "Canonical unique index prevents two canonical replays for same case"
  else
    # Check if there's actually two canonicals (constraint might have been silently ignored)
    local canon_count
    canon_count=$(query_db "PRAGMA foreign_keys=ON; SELECT COUNT(*) FROM replays WHERE status='canonical';")
    if [[ "$canon_count" != "1" ]]; then
      fail "Canonical unique index should prevent two canonical replays" "canon_count=$canon_count"
    else
      # Constraint enforced but rc was 0 — sqlite3 might return 0 for partial index violations
      # The partial unique index should have prevented it; let's re-check
      fail "Unique index should have rejected the INSERT" "canon_count=$canon_count but expected constraint violation"
    fi
  fi
}

test_archive() {
  init_case "archive-test" "archive test"
  run_freplay record archive-test -- "${FTREE}" --version >/dev/null 2>&1 || true
  local replay_id
  replay_id=$(query_db "PRAGMA foreign_keys=ON; SELECT id FROM replays LIMIT 1;")
  run_freplay promote archive-test "$replay_id" >/dev/null 2>&1 || true
  run_freplay archive archive-test "$replay_id" >/dev/null 2>&1 || true
  local status
  status=$(query_db "PRAGMA foreign_keys=ON; SELECT status FROM replays WHERE id=$replay_id;")
  if [[ "$status" == "archived" ]]; then
    pass "Archive sets replay status to archived"
  else
    fail "Archive should set status to archived" "status=$status"
  fi
}

# =========================================================================
# Show/Export (tests 25-30)
# =========================================================================

test_show_defaults_canonical() {
  init_case "show-canon" "show canonical default"
  run_freplay record show-canon -- "${FTREE}" --version >/dev/null 2>&1 || true
  local replay_id
  replay_id=$(query_db "PRAGMA foreign_keys=ON; SELECT id FROM replays LIMIT 1;")
  run_freplay promote show-canon "$replay_id" >/dev/null 2>&1 || true
  local output
  output=$(run_freplay show show-canon -o json 2>&1)
  local shown_id
  shown_id=$(python3 -c "import json,sys; print(json.loads(sys.stdin.read())['replay_id'])" <<< "$output" 2>/dev/null || true)
  if [[ "$shown_id" == "$replay_id" ]]; then
    pass "Show defaults to canonical replay"
  else
    fail "Show should default to canonical replay" "shown_id=$shown_id expected=$replay_id"
  fi
}

test_show_falls_back_draft() {
  init_case "show-draft" "show draft fallback"
  run_freplay record show-draft -- "${FTREE}" --version >/dev/null 2>&1 || true
  local output rc=0
  output=$(run_freplay show show-draft -o json 2>&1) || rc=$?
  local shown_status
  shown_status=$(python3 -c "import json,sys; print(json.loads(sys.stdin.read())['replay_status'])" <<< "$output" 2>/dev/null || true)
  if [[ "$shown_status" == "draft" ]]; then
    pass "Show falls back to draft when no canonical exists"
  else
    fail "Show should fall back to draft replay" "shown_status=$shown_status rc=$rc"
  fi
}

test_show_specific_replay() {
  init_case "show-specific" "show specific replay"
  run_freplay record show-specific -- "${FTREE}" --version >/dev/null 2>&1 || true
  local replay_id
  replay_id=$(query_db "PRAGMA foreign_keys=ON; SELECT id FROM replays LIMIT 1;")
  local output
  output=$(run_freplay show show-specific --replay-id "$replay_id" -o json 2>&1)
  local shown_id
  shown_id=$(python3 -c "import json,sys; print(json.loads(sys.stdin.read())['replay_id'])" <<< "$output" 2>/dev/null || true)
  if [[ "$shown_id" == "$replay_id" ]]; then
    pass "Show returns correct replay for --replay-id"
  else
    fail "Show should return specific replay" "shown_id=$shown_id expected=$replay_id"
  fi
}

test_show_json() {
  init_case "show-json" "show json test"
  run_freplay record show-json -- "${FTREE}" --version >/dev/null 2>&1 || true
  local output rc=0
  output=$(run_freplay show show-json -o json 2>&1) || rc=$?
  local valid
  valid=$(python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
assert 'version' in data
assert 'tool' in data
assert 'steps' in data
print('ok')
" <<< "$output" 2>/dev/null || true)
  if [[ "$valid" == "ok" ]]; then
    pass "Show JSON output has required fields (version, tool, steps)"
  else
    fail "Show JSON should contain version, tool, steps" "output=$output"
  fi
}

test_export_replaypack() {
  init_case "export-pack" "export replaypack"
  run_freplay record export-pack -- "${FTREE}" --version >/dev/null 2>&1 || true
  local output rc=0
  output=$(run_freplay export export-pack 2>&1) || rc=$?
  local valid
  valid=$(python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
assert data.get('version') == '1.0'
print('ok')
" <<< "$output" 2>/dev/null || true)
  if [[ "$valid" == "ok" ]]; then
    pass "Export produces valid ReplayPack with version=1.0"
  else
    fail "Export should produce ReplayPack with version=1.0" "output=$output"
  fi
}

test_list_json() {
  init_case "list-json" "list json test"
  run_freplay record list-json -- "${FTREE}" --version >/dev/null 2>&1 || true
  local output rc=0
  output=$(run_freplay list list-json -o json 2>&1) || rc=$?
  local valid
  valid=$(python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
assert 'replays' in data
assert isinstance(data['replays'], list)
print('ok')
" <<< "$output" 2>/dev/null || true)
  if [[ "$valid" == "ok" ]]; then
    pass "List JSON output has 'replays' array"
  else
    fail "List JSON should have 'replays' array" "output=$output"
  fi
}

# =========================================================================
# Verify (tests 31-34)
# =========================================================================

test_verify_pass() {
  init_case "verify-pass" "verify pass test"
  run_freplay record verify-pass -- "${FTREE}" --version >/dev/null 2>&1 || true
  local output rc=0
  output=$(run_freplay verify verify-pass -o json 2>&1) || rc=$?
  local overall
  overall=$(python3 -c "import json,sys; print(json.loads(sys.stdin.read())['overall'])" <<< "$output" 2>/dev/null || true)
  if [[ "$overall" == "pass" ]]; then
    pass "Verify outputs overall=pass for valid replay"
  else
    fail "Verify should output overall=pass" "overall=$overall rc=$rc output=$output"
  fi
}

test_verify_missing_tool() {
  init_case "verify-missing" "verify missing tool"
  run_freplay record verify-missing -- "${FTREE}" --version >/dev/null 2>&1 || true
  # Manipulate DB to set tool to nonexistent
  query_db "PRAGMA foreign_keys=ON; UPDATE replay_steps SET tool='nonexistent_tool_xyz';"
  local output rc=0
  output=$(run_freplay verify verify-missing -o json 2>&1) || rc=$?
  local overall
  overall=$(python3 -c "import json,sys; print(json.loads(sys.stdin.read())['overall'])" <<< "$output" 2>/dev/null || true)
  if [[ "$overall" == "fail" ]]; then
    pass "Verify reports fail when tool is missing"
  else
    fail "Verify should report fail for missing tool" "overall=$overall rc=$rc"
  fi
}

test_verify_no_execution() {
  init_case "verify-noexec" "verify does not execute"
  # Record a fcase note command (which is mutating and would add events to the DB)
  run_freplay record verify-noexec -- "${FCASE_CMD}" note verify-noexec --body "original note" >/dev/null 2>&1 || true
  local event_count_before
  event_count_before=$(query_db "PRAGMA foreign_keys=ON; SELECT COUNT(*) FROM events;")
  # Run verify — it should NOT execute the note command
  run_freplay verify verify-noexec >/dev/null 2>&1 || true
  local event_count_after
  event_count_after=$(query_db "PRAGMA foreign_keys=ON; SELECT COUNT(*) FROM events;")
  if [[ "$event_count_before" == "$event_count_after" ]]; then
    pass "Verify does NOT execute recorded commands"
  else
    fail "Verify should not execute commands" "events_before=$event_count_before events_after=$event_count_after"
  fi
}

test_verify_json() {
  init_case "verify-json" "verify json output"
  run_freplay record verify-json -- "${FTREE}" --version >/dev/null 2>&1 || true
  local output rc=0
  output=$(run_freplay verify verify-json -o json 2>&1) || rc=$?
  local valid
  valid=$(python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
assert 'overall' in data
assert 'steps' in data
print('ok')
" <<< "$output" 2>/dev/null || true)
  if [[ "$valid" == "ok" ]]; then
    pass "Verify JSON has overall and steps fields"
  else
    fail "Verify JSON should have overall and steps" "output=$output"
  fi
}

test_verify_source_tree_tool_resolution() {
  init_case "verify-src" "verify source-tree tool resolution"
  run_freplay record verify-src -- "${FTREE}" --version >/dev/null 2>&1 || true

  local shim_dir
  shim_dir="$(mktemp -d)"
  local cmd
  for cmd in bash cat dirname python3 readlink realpath sqlite3 whoami; do
    ln -sf "$(command -v "${cmd}")" "${shim_dir}/${cmd}"
  done

  local output rc=0 overall
  output=$(HOME="${TEST_HOME}" FSUITE_TELEMETRY=0 PATH="${shim_dir}" bash "${FREPLAY}" verify verify-src -o json 2>&1) || rc=$?
  overall=$(python3 -c "import json,sys; print(json.loads(sys.stdin.read())['overall'])" <<< "$output" 2>/dev/null || true)

  rm -rf "${shim_dir}"

  if [[ "$overall" == "pass" ]]; then
    pass "Verify resolves repo-local tools without relying on PATH installs"
  else
    fail "Verify should resolve repo-local tools without relying on PATH installs" "overall=$overall rc=$rc output=$output"
  fi
}

# =========================================================================
# Edge cases (tests 35-53)
# =========================================================================

test_nonexistent_case() {
  # Need fcase.db to exist but case must not exist
  init_case "exists-case" "dummy"
  local output rc=0
  output=$(run_freplay record nonexistent-slug-xyz -- "${FTREE}" --version 2>&1) || rc=$?
  if (( rc != 0 )); then
    pass "Record fails for non-existent case"
  else
    fail "Record should fail for non-existent case" "rc=$rc output=$output"
  fi
}

test_no_db_read_commands() {
  # No DB exists — show/list/export/verify should all fail cleanly
  local all_ok=1
  local cmd output rc

  for cmd in "show test-slug" "list test-slug" "export test-slug" "verify test-slug"; do
    rc=0
    output=$(run_freplay $cmd 2>&1) || rc=$?
    if (( rc == 0 )) || [[ "$output" != *"no fcase.db found"* && "$output" != *"case not found"* ]]; then
      all_ok=0
    fi
  done

  if (( all_ok )); then
    pass "Read commands produce clean error when no DB exists"
  else
    fail "Read commands should fail cleanly without DB" "at least one command did not fail properly"
  fi
}

test_link_non_numeric() {
  init_case "link-bad" "non-numeric link"
  local output rc=0
  output=$(run_freplay record link-bad --link evidence:abc -- "${FTREE}" --version 2>&1) || rc=$?
  if (( rc != 0 )); then
    pass "Non-numeric link reference is rejected"
  else
    fail "Non-numeric link reference should be rejected" "rc=$rc output=$output"
  fi
}

test_long_output_bounded() {
  init_case "long-output" "long output bounded"
  # Create a directory with lots of files to generate verbose ftree output
  mkdir -p "${TEST_HOME}/big-dir"
  for i in $(seq 1 100); do
    touch "${TEST_HOME}/big-dir/file_${i}.txt"
  done
  run_freplay record long-output -- "${FTREE}" "${TEST_HOME}/big-dir" >/dev/null 2>&1 || true
  local summary_len
  summary_len=$(query_db "PRAGMA foreign_keys=ON; SELECT length(result_summary) FROM replay_steps LIMIT 1;")
  if [[ -n "$summary_len" ]] && (( summary_len <= 240 )); then
    pass "Result summary length is bounded to <= 240 chars"
  else
    fail "Result summary should be <= 240 chars" "summary_len=$summary_len"
  fi
}

test_record_multiple_drafts_error() {
  init_case "multi-draft" "multiple drafts error"
  # Create first draft
  run_freplay record multi-draft -- "${FTREE}" --version >/dev/null 2>&1 || true
  # Create second draft via --new
  run_freplay record multi-draft --new -- "${FTREE}" --version >/dev/null 2>&1 || true
  # Now record without --replay-id or --new — should error about multiple drafts
  local output rc=0
  output=$(run_freplay record multi-draft -- "${FTREE}" --version 2>&1) || rc=$?
  if (( rc != 0 )) && [[ "$output" == *"multiple draft"* ]]; then
    pass "Record errors when multiple draft replays exist"
  else
    fail "Record should error with multiple draft replays" "rc=$rc output=$output"
  fi
}

test_record_with_new_flag() {
  init_case "new-flag" "new flag test"
  run_freplay record new-flag -- "${FTREE}" --version >/dev/null 2>&1 || true
  run_freplay record new-flag --new -- "${FSEARCH}" --version >/dev/null 2>&1 || true
  local replay_count
  replay_count=$(query_db "PRAGMA foreign_keys=ON; SELECT COUNT(*) FROM replays;")
  if [[ "$replay_count" == "2" ]]; then
    pass "--new creates a fresh draft even when one exists"
  else
    fail "--new should create a second replay" "replay_count=$replay_count"
  fi
}

test_record_with_replay_id() {
  init_case "replay-id" "replay-id targeting"
  run_freplay record replay-id -- "${FTREE}" --version >/dev/null 2>&1 || true
  local replay_id
  replay_id=$(query_db "PRAGMA foreign_keys=ON; SELECT id FROM replays LIMIT 1;")
  run_freplay record replay-id --replay-id "$replay_id" -- "${FSEARCH}" --version >/dev/null 2>&1 || true
  local step_count
  step_count=$(query_db "PRAGMA foreign_keys=ON; SELECT COUNT(*) FROM replay_steps WHERE replay_id=$replay_id;")
  if [[ "$step_count" == "2" ]]; then
    pass "--replay-id targets specific replay"
  else
    fail "--replay-id should target specific replay" "step_count=$step_count"
  fi
}

test_record_exit_passthrough() {
  init_case "exit-pass" "exit passthrough"
  local rc=0
  run_freplay record exit-pass -- "${FCASE_CMD}" status nonexistent-slug-xyz >/dev/null 2>&1 || rc=$?
  if (( rc != 0 )); then
    pass "Wrapper exits with child's non-zero exit code"
  else
    fail "Wrapper should exit with child's exit code" "rc=$rc"
  fi
}

test_record_stderr_passthrough() {
  init_case "stderr-pass" "stderr passthrough"
  local output rc=0
  # Capture stderr from a failing command — fcase status nonexistent should emit error on stderr
  output=$(run_freplay record stderr-pass -- "${FCASE_CMD}" status nonexistent-slug-xyz 2>&1) || rc=$?
  if [[ "$output" == *"case not found"* || "$output" == *"not found"* ]]; then
    pass "Child stderr is visible to caller"
  else
    fail "Child stderr should be visible" "output=$output rc=$rc"
  fi
}

test_verify_missing_cwd() {
  init_case "verify-cwd" "verify missing cwd"
  run_freplay record verify-cwd -- "${FTREE}" --version >/dev/null 2>&1 || true
  # Manipulate DB to set cwd to nonexistent path
  query_db "PRAGMA foreign_keys=ON; UPDATE replay_steps SET cwd='/nonexistent/path/that/does/not/exist';"
  local output rc=0
  output=$(run_freplay verify verify-cwd -o json 2>&1) || rc=$?
  local overall
  overall=$(python3 -c "import json,sys; print(json.loads(sys.stdin.read())['overall'])" <<< "$output" 2>/dev/null || true)
  if [[ "$overall" == "warn" ]]; then
    pass "Verify reports WARN for missing cwd"
  else
    fail "Verify should report WARN for missing cwd" "overall=$overall rc=$rc"
  fi
}

test_verify_link_reference() {
  init_case "verify-link-ref" "verify link reference"
  run_freplay record verify-link-ref --link evidence:99999 -- "${FTREE}" --version >/dev/null 2>&1 || true
  local output rc=0
  output=$(run_freplay verify verify-link-ref -o json 2>&1) || rc=$?
  local has_warn
  has_warn=$(python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
overall = data['overall']
issues = ' '.join(s.get('issues','') for s in data['steps'])
if overall == 'warn' or 'not found' in issues:
    print('yes')
else:
    print('no')
" <<< "$output" 2>/dev/null || true)
  if [[ "$has_warn" == "yes" ]]; then
    pass "Verify warns about link references that do not exist in DB"
  else
    fail "Verify should warn about invalid link references" "output=$output"
  fi
}

test_verify_mode_reclassification() {
  init_case "verify-reclass" "verify mode reclassification"
  run_freplay record verify-reclass -- "${FTREE}" --version >/dev/null 2>&1 || true
  # Manipulate DB to change stored mode from read_only to mutating
  query_db "PRAGMA foreign_keys=ON; UPDATE replay_steps SET mode='mutating';"
  local output rc=0
  output=$(run_freplay verify verify-reclass -o json 2>&1) || rc=$?
  local has_mismatch
  has_mismatch=$(python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
issues = ' '.join(s.get('issues','') for s in data['steps'])
if 'mode mismatch' in issues:
    print('yes')
else:
    print('no')
" <<< "$output" 2>/dev/null || true)
  if [[ "$has_mismatch" == "yes" ]]; then
    pass "Verify warns about mode reclassification mismatch"
  else
    fail "Verify should warn about mode mismatch" "output=$output"
  fi
}

test_verify_path_args_resolve() {
  init_case "verify-path" "verify path args"
  # Create a path, record it as an arg, then delete
  local temp_path="${TEST_HOME}/verify-target-dir"
  mkdir -p "$temp_path"
  run_freplay record verify-path -- "${FTREE}" "$temp_path" >/dev/null 2>&1 || true
  # Delete the path
  rm -rf "$temp_path"
  local output rc=0
  output=$(run_freplay verify verify-path -o json 2>&1) || rc=$?
  local has_warn
  has_warn=$(python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
issues = ' '.join(s.get('issues','') for s in data['steps'])
if 'does not exist' in issues:
    print('yes')
else:
    print('no')
" <<< "$output" 2>/dev/null || true)
  if [[ "$has_warn" == "yes" ]]; then
    pass "Verify warns when path argument no longer exists"
  else
    fail "Verify should warn when path args are missing" "output=$output"
  fi
}

test_cascade_delete_case() {
  init_case "cascade-case" "cascade delete case"
  run_freplay record cascade-case --link evidence:1 -- "${FTREE}" --version >/dev/null 2>&1 || true
  # Get counts before delete
  local replay_count_before step_count_before
  replay_count_before=$(query_db "PRAGMA foreign_keys=ON; SELECT COUNT(*) FROM replays;")
  step_count_before=$(query_db "PRAGMA foreign_keys=ON; SELECT COUNT(*) FROM replay_steps;")
  # Delete the case
  local case_id
  case_id=$(query_db "PRAGMA foreign_keys=ON; SELECT id FROM cases WHERE slug='cascade-case';")
  query_db "PRAGMA foreign_keys=ON; DELETE FROM cases WHERE id=$case_id;"
  # Check cascade
  local replay_count_after step_count_after link_count_after
  replay_count_after=$(query_db "PRAGMA foreign_keys=ON; SELECT COUNT(*) FROM replays;")
  step_count_after=$(query_db "PRAGMA foreign_keys=ON; SELECT COUNT(*) FROM replay_steps;")
  link_count_after=$(query_db "PRAGMA foreign_keys=ON; SELECT COUNT(*) FROM replay_step_links;")
  if [[ "$replay_count_after" == "0" ]] && [[ "$step_count_after" == "0" ]] && [[ "$link_count_after" == "0" ]]; then
    pass "Deleting a case cascades to replays/steps/links"
  else
    fail "Cascade delete should remove replays/steps/links" "replays=$replay_count_after steps=$step_count_after links=$link_count_after"
  fi
}

test_cascade_delete_replay() {
  init_case "cascade-replay" "cascade delete replay"
  run_fcase evidence cascade-replay --tool fread --body "test evidence" >/dev/null 2>&1 || true
  run_freplay record cascade-replay --link evidence:1 -- "${FTREE}" --version >/dev/null 2>&1 || true
  local replay_id
  replay_id=$(query_db "PRAGMA foreign_keys=ON; SELECT id FROM replays LIMIT 1;")
  # Delete the replay
  query_db "PRAGMA foreign_keys=ON; DELETE FROM replays WHERE id=$replay_id;"
  # Check cascade
  local step_count link_count
  step_count=$(query_db "PRAGMA foreign_keys=ON; SELECT COUNT(*) FROM replay_steps;")
  link_count=$(query_db "PRAGMA foreign_keys=ON; SELECT COUNT(*) FROM replay_step_links;")
  if [[ "$step_count" == "0" ]] && [[ "$link_count" == "0" ]]; then
    pass "Deleting a replay cascades to steps and links"
  else
    fail "Cascade delete replay should remove steps/links" "steps=$step_count links=$link_count"
  fi
}

test_concurrent_record() {
  init_case "concurrent" "concurrent record test"
  # Run two record commands in parallel
  run_freplay record concurrent -- "${FTREE}" --version >/dev/null 2>&1 &
  local pid1=$!
  run_freplay record concurrent -- "${FSEARCH}" --version >/dev/null 2>&1 &
  local pid2=$!
  wait "$pid1" 2>/dev/null || true
  wait "$pid2" 2>/dev/null || true

  local step_count
  step_count=$(query_db "PRAGMA foreign_keys=ON; SELECT COUNT(*) FROM replay_steps;")
  local distinct_orders
  distinct_orders=$(query_db "PRAGMA foreign_keys=ON; SELECT COUNT(DISTINCT order_num) FROM replay_steps;")
  if [[ "$step_count" == "2" ]] && [[ "$distinct_orders" == "2" ]]; then
    pass "Concurrent record creates 2 steps with distinct order_nums"
  else
    fail "Concurrent record should create distinct order_nums" "steps=$step_count distinct=$distinct_orders"
  fi
}

test_show_archived_only_errors() {
  init_case "show-archived" "show archived only"
  run_freplay record show-archived -- "${FTREE}" --version >/dev/null 2>&1 || true
  local replay_id
  replay_id=$(query_db "PRAGMA foreign_keys=ON; SELECT id FROM replays LIMIT 1;")
  run_freplay promote show-archived "$replay_id" >/dev/null 2>&1 || true
  run_freplay archive show-archived "$replay_id" >/dev/null 2>&1 || true
  local output rc=0
  output=$(run_freplay show show-archived 2>&1) || rc=$?
  if (( rc != 0 )) && [[ "$output" == *"no active replay"* ]]; then
    pass "Show errors when only archived replays exist"
  else
    fail "Show should error when only archived replays exist" "rc=$rc output=$output"
  fi
}

test_show_multiple_drafts_newest() {
  init_case "show-drafts" "show multiple drafts"
  run_freplay record show-drafts -- "${FTREE}" --version >/dev/null 2>&1 || true
  run_freplay record show-drafts --new -- "${FSEARCH}" --version >/dev/null 2>&1 || true
  local highest_id
  highest_id=$(query_db "PRAGMA foreign_keys=ON; SELECT id FROM replays ORDER BY id DESC LIMIT 1;")
  local output
  output=$(run_freplay show show-drafts -o json 2>&1)
  local shown_id
  shown_id=$(python3 -c "import json,sys; print(json.loads(sys.stdin.read())['replay_id'])" <<< "$output" 2>/dev/null || true)
  if [[ "$shown_id" == "$highest_id" ]]; then
    pass "Show picks highest id draft when multiple drafts exist"
  else
    fail "Show should pick newest draft" "shown_id=$shown_id expected=$highest_id"
  fi
}

test_list_ordered_by_id_desc() {
  init_case "list-order" "list order test"
  run_freplay record list-order -- "${FTREE}" --version >/dev/null 2>&1 || true
  run_freplay record list-order --new -- "${FSEARCH}" --version >/dev/null 2>&1 || true
  run_freplay record list-order --new -- "${FTREE}" --version >/dev/null 2>&1 || true
  local output
  output=$(run_freplay list list-order -o json 2>&1)
  local order_ok
  order_ok=$(python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
ids = [r['id'] for r in data['replays']]
# Should be descending
if ids == sorted(ids, reverse=True) and len(ids) == 3:
    print('ok')
else:
    print('fail')
" <<< "$output" 2>/dev/null || true)
  if [[ "$order_ok" == "ok" ]]; then
    pass "List output is ordered by id DESC"
  else
    fail "List should be ordered by id DESC" "output=$output"
  fi
}

# =========================================================================
# Main
# =========================================================================

main() {
  echo "======================================"
  echo "  freplay Test Suite"
  echo "======================================"
  echo ""
  echo "Running tests..."
  echo ""

  [[ -n "${FREPLAY}" && -x "${FREPLAY}" ]] || {
    echo "FREPLAY is required and must be executable: ${FREPLAY}" >&2
    exit 1
  }

  [[ -n "${FCASE}" && -x "${FCASE}" ]] || {
    echo "FCASE is required and must be executable: ${FCASE}" >&2
    exit 1
  }

  command -v python3 >/dev/null 2>&1 || {
    echo "python3 is required for test_freplay.sh" >&2
    exit 1
  }

  command -v sqlite3 >/dev/null 2>&1 || {
    echo "sqlite3 is required for test_freplay.sh" >&2
    exit 1
  }

  trap teardown EXIT

  # Record flow (tests 1-20)
  run_test test_version
  run_test test_help
  run_test test_self_check
  run_test test_record_single_step
  run_test test_record_multiple_steps
  run_test test_record_auto_creates_draft
  run_test test_record_appends_to_draft
  run_test test_record_with_purpose
  run_test test_record_with_link
  run_test test_record_rejects_non_fsuite
  run_test test_record_rejects_freplay
  run_test test_record_rejects_fmetrics
  run_test test_record_argv_json
  run_test test_record_cwd
  run_test test_record_mode_read_only
  run_test test_record_mode_mutating
  run_test test_record_mode_fcase_subcommand
run_test test_record_exit_code
run_test test_record_error_excerpt
run_test test_record_result_summary
run_test test_record_persists_telemetry_run_id

# Lifecycle (tests 21-24)
  run_test test_promote
  run_test test_promote_demotes_existing
  run_test test_canonical_unique_index
  run_test test_archive

  # Show/Export (tests 25-30)
  run_test test_show_defaults_canonical
  run_test test_show_falls_back_draft
  run_test test_show_specific_replay
  run_test test_show_json
  run_test test_export_replaypack
  run_test test_list_json

  # Verify (tests 31-34)
  run_test test_verify_pass
  run_test test_verify_missing_tool
  run_test test_verify_no_execution
  run_test test_verify_json
  run_test test_verify_source_tree_tool_resolution

  # Edge cases (tests 35-53)
  run_test test_nonexistent_case
  run_test test_no_db_read_commands
  run_test test_link_non_numeric
  run_test test_long_output_bounded
  run_test test_record_multiple_drafts_error
  run_test test_record_with_new_flag
  run_test test_record_with_replay_id
  run_test test_record_exit_passthrough
  run_test test_record_stderr_passthrough
  run_test test_verify_missing_cwd
  run_test test_verify_link_reference
  run_test test_verify_mode_reclassification
  run_test test_verify_path_args_resolve
  run_test test_cascade_delete_case
  run_test test_cascade_delete_replay
  run_test test_concurrent_record
  run_test test_show_archived_only_errors
  run_test test_show_multiple_drafts_newest
  run_test test_list_ordered_by_id_desc

  echo ""
  echo "======================================"
  echo "  Test Results"
  echo "======================================"
  echo -e "Total:  ${TESTS_RUN}"
  echo -e "${GREEN}Passed: ${TESTS_PASSED}${NC}"
  if [[ ${TESTS_FAILED} -gt 0 ]]; then
    echo -e "${RED}Failed: ${TESTS_FAILED}${NC}"
    exit 1
  else
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
  fi
}

main "$@"
