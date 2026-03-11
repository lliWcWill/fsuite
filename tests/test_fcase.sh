#!/usr/bin/env bash
# test_fcase.sh — focused tests for fcase continuity ledger
# Run with: bash test_fcase.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FCASE="${SCRIPT_DIR}/../fcase"
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
  "$@" || true
}

run_fcase() {
  HOME="${TEST_HOME}" FSUITE_TELEMETRY=0 "${FCASE}" "$@"
}

test_help() {
  local output
  output=$(run_fcase --help 2>&1)
  if [[ "$output" == *"fcase"* ]] && [[ "$output" == *"init"* ]] && [[ "$output" == *"status"* ]]; then
    pass "Help output documents fcase core commands"
  else
    fail "Help output should document fcase commands" "Got: $output"
  fi
}

test_version() {
  local output
  output=$(run_fcase --version 2>&1)
  if [[ "$output" =~ ^fcase\ [0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    pass "Version output format is correct"
  else
    fail "Version output format should be semver" "Got: $output"
  fi
}

test_init_creates_case() {
  local output rc=0
  output=$(run_fcase init auth-bug --goal "Find auth failure root cause" --priority high -o json 2>&1) || rc=$?
  if [[ $rc -eq 0 ]] && python3 -c 'import json,sys; data=json.loads(sys.stdin.read()); assert data["case"]["slug"] == "auth-bug"; assert data["case"]["goal"] == "Find auth failure root cause"; assert data["session"]["id"] >= 1; assert data["event"]["event_type"] == "case_init"' <<< "$output" 2>/dev/null; then
    pass "init creates a case"
  else
    fail "init should create a case with JSON envelope" "rc=$rc output=$output"
  fi
}

test_list_shows_case() {
  run_fcase init auth-bug --goal "Find auth failure root cause" >/dev/null 2>&1 || true
  local output rc=0
  output=$(run_fcase list -o json 2>&1) || rc=$?
  if [[ $rc -eq 0 ]] && [[ "$output" == *'"slug":"auth-bug"'* ]]; then
    pass "list shows initialized cases"
  else
    fail "list should show initialized cases" "rc=$rc output=$output"
  fi
}

test_init_bootstraps_database() {
  run_fcase init auth-bug --goal "Find auth failure root cause" >/dev/null 2>&1 || true
  local db_path="${TEST_HOME}/.fsuite/fcase.db"
  if [[ -f "${db_path}" ]]; then
    pass "init bootstraps the fcase database"
  else
    fail "init should create the fcase database" "Missing: ${db_path}"
  fi
}

test_status_shows_core_case_state() {
  run_fcase init auth-bug --goal "Find auth failure root cause" --priority high >/dev/null 2>&1 || true
  local output rc=0
  output=$(run_fcase status auth-bug -o json 2>&1) || rc=$?
  if [[ $rc -eq 0 ]] && python3 -c 'import json,sys; data=json.loads(sys.stdin.read()); assert data["case"]["slug"] == "auth-bug"; assert data["case"]["priority"] == "high"; assert isinstance(data["targets"], list); assert isinstance(data["evidence"], list); assert isinstance(data["hypotheses"], list); assert isinstance(data["recent_events"], list); assert data["active_session"]["ended_at"] is None' <<< "$output" 2>/dev/null; then
    pass "status shows core case state"
  else
    fail "status should show core case state" "rc=$rc output=$output"
  fi
}

test_init_rejects_duplicate_slug() {
  if ! run_fcase init duplicate-bug --goal "Find duplicate rejection" >/dev/null 2>&1; then
    fail "duplicate slug test requires a successful initial init"
    return
  fi
  if run_fcase init duplicate-bug --goal "Duplicate" >/dev/null 2>&1; then
    fail "duplicate slug should fail"
  else
    pass "duplicate slug is rejected"
  fi
}

test_next_updates_current_state() {
  run_fcase init next-bug --goal "Track next move" >/dev/null 2>&1 || true
  run_fcase next next-bug --body "Inspect refresh-token branch in auth.py" >/dev/null 2>&1 || true
  local output rc=0
  output=$(run_fcase status next-bug -o json 2>&1) || rc=$?
  if [[ $rc -eq 0 ]] && [[ "$output" == *'"next_move":"Inspect refresh-token branch in auth.py"'* ]]; then
    pass "next updates current case state"
  else
    fail "next should update current case state" "rc=$rc output=$output"
  fi
}

test_note_records_recent_event() {
  run_fcase init note-bug --goal "Track note event" >/dev/null 2>&1 || true
  run_fcase note note-bug --body "Auth failure reproduces only on refresh path" >/dev/null 2>&1 || true
  local output rc=0
  output=$(run_fcase status note-bug -o json 2>&1) || rc=$?
  if [[ $rc -eq 0 ]] && [[ "$output" == *'"event_type":"note"'* ]] && [[ "$output" == *'refresh path'* ]]; then
    pass "note records a recent event"
  else
    fail "note should append an event" "rc=$rc output=$output"
  fi
}

test_handoff_includes_current_state_and_recent_events() {
  run_fcase init handoff-bug --goal "Prepare handoff" >/dev/null 2>&1 || true
  run_fcase note handoff-bug --body "Auth failure reproduces only on refresh path" >/dev/null 2>&1 || true
  run_fcase next handoff-bug --body "Inspect refresh-token branch in auth.py" >/dev/null 2>&1 || true
  local output rc=0
  output=$(run_fcase handoff handoff-bug -o json 2>&1) || rc=$?
  if [[ $rc -eq 0 ]] && [[ "$output" == *'"next_move":"Inspect refresh-token branch in auth.py"'* ]] && [[ "$output" == *'"event_type":"note"'* ]]; then
    pass "handoff includes current state and recent events"
  else
    fail "handoff should summarize current case state" "rc=$rc output=$output"
  fi
}

test_export_emits_full_case_envelope() {
  run_fcase init export-bug --goal "Export full case envelope" >/dev/null 2>&1 || true
  run_fcase note export-bug --body "Export note body" >/dev/null 2>&1 || true
  local output rc=0
  output=$(run_fcase export export-bug -o json 2>&1) || rc=$?
  if [[ $rc -eq 0 ]] && python3 -c 'import json,sys; data=json.loads(sys.stdin.read()); assert data["case"]["slug"] == "export-bug"; assert isinstance(data["sessions"], list); assert isinstance(data["events"], list); assert len(data["events"]) >= 2' <<< "$output" 2>/dev/null; then
    pass "export emits full case envelope"
  else
    fail "export should emit full case envelope" "rc=$rc output=$output"
  fi
}

test_target_add_records_symbol_state() {
  run_fcase init target-bug --goal "Track a target" >/dev/null 2>&1 || true
  run_fcase target add target-bug --path /repo/src/auth.py --symbol authenticate --symbol-type function --rank 9 --reason "entry suspect" --state active >/dev/null 2>&1 || true
  local output rc=0
  output=$(run_fcase status target-bug -o json 2>&1) || rc=$?
  if [[ $rc -eq 0 ]] && [[ "$output" == *'"symbol":"authenticate"'* ]] && [[ "$output" == *'"state":"active"'* ]]; then
    pass "target add records structured target state"
  else
    fail "target add should record structured target state" "rc=$rc output=$output"
  fi
}

test_evidence_records_body_and_line_metadata() {
  run_fcase init evidence-bug --goal "Track evidence" >/dev/null 2>&1 || true
  run_fcase evidence evidence-bug --tool fread --path /repo/src/auth.py --lines 120:148 --match-line 125 --summary "refresh path excerpt" --body "if refresh_token is invalid then return 401" >/dev/null 2>&1 || true
  local output rc=0
  output=$(run_fcase status evidence-bug -o json 2>&1) || rc=$?
  if [[ $rc -eq 0 ]] && python3 -c 'import json,sys; data=json.loads(sys.stdin.read()); ev=data["evidence"][0]; assert ev["line_start"] == 120; assert ev["line_end"] == 148; assert ev["match_line"] == 125; assert "refresh_token" in ev["body"]' <<< "$output" 2>/dev/null; then
    pass "evidence records body and line metadata"
  else
    fail "evidence should record body and line metadata" "rc=$rc output=$output"
  fi
}

test_hypothesis_add_and_set_update_state() {
  run_fcase init hypothesis-bug --goal "Track hypothesis state" >/dev/null 2>&1 || true
  run_fcase hypothesis add hypothesis-bug --body "Cache bypass causes failure" --confidence medium >/dev/null 2>&1 || true
  run_fcase hypothesis set hypothesis-bug --id 1 --status active --reason "Repro still points at cache path" --confidence high >/dev/null 2>&1 || true
  local output rc=0
  output=$(run_fcase status hypothesis-bug -o json 2>&1) || rc=$?
  if [[ $rc -eq 0 ]] && [[ "$output" == *'"status":"active"'* ]] && [[ "$output" == *'"confidence":"high"'* ]]; then
    pass "hypothesis add and set update structured state"
  else
    fail "hypothesis set should update structured state" "rc=$rc output=$output"
  fi
}

test_reject_maps_to_hypothesis_rejected() {
  run_fcase init reject-bug --goal "Reject a hypothesis" >/dev/null 2>&1 || true
  run_fcase hypothesis add reject-bug --body "Cache bypass causes failure" --confidence medium >/dev/null 2>&1 || true
  local before_output hypothesis_id
  before_output=$(run_fcase status reject-bug -o json 2>&1)
  hypothesis_id=$(python3 -c 'import json,sys; data=json.loads(sys.stdin.read()); print(data["hypotheses"][0]["id"])' <<< "$before_output" 2>/dev/null || true)
  run_fcase reject reject-bug --hypothesis-id "${hypothesis_id}" --reason "Repro disproves cache path" >/dev/null 2>&1 || true
  local output rc=0
  output=$(run_fcase status reject-bug -o json 2>&1) || rc=$?
  if [[ $rc -eq 0 ]] && [[ "$output" == *'"status":"rejected"'* ]]; then
    pass "reject maps cleanly to hypothesis rejected"
  else
    fail "reject should map to a typed hypothesis rejection" "rc=$rc output=$output"
  fi
}

test_reject_fails_without_selector() {
  run_fcase init reject-missing-selector --goal "Reject needs selector" >/dev/null 2>&1 || true
  if run_fcase reject reject-missing-selector --reason "No selector provided" >/dev/null 2>&1; then
    fail "reject should fail without a selector"
  else
    pass "reject fails without a selector"
  fi
}

test_evidence_rejects_invalid_line_range() {
  run_fcase init bad-lines-bug --goal "Reject invalid line ranges" >/dev/null 2>&1 || true
  if run_fcase evidence bad-lines-bug --tool fread --lines 148:120 --body "bad range" >/dev/null 2>&1; then
    fail "evidence should fail on descending line ranges"
  else
    pass "evidence rejects invalid line ranges"
  fi
}

main() {
  echo "======================================"
  echo "  fcase Test Suite"
  echo "======================================"
  echo ""
  echo "Running tests..."
  echo ""

  setup
  trap teardown EXIT

  run_test test_help
  run_test test_version
  run_test test_init_creates_case
  run_test test_list_shows_case
  run_test test_init_bootstraps_database
  run_test test_status_shows_core_case_state
  run_test test_init_rejects_duplicate_slug
  run_test test_next_updates_current_state
  run_test test_note_records_recent_event
  run_test test_handoff_includes_current_state_and_recent_events
  run_test test_export_emits_full_case_envelope
  run_test test_target_add_records_symbol_state
  run_test test_evidence_records_body_and_line_metadata
  run_test test_hypothesis_add_and_set_update_state
  run_test test_reject_maps_to_hypothesis_rejected
  run_test test_reject_fails_without_selector
  run_test test_evidence_rejects_invalid_line_range

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
