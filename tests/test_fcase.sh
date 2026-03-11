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
  local before_output hypothesis_id
  before_output=$(run_fcase status hypothesis-bug -o json 2>&1)
  hypothesis_id=$(python3 -c 'import json,sys; data=json.loads(sys.stdin.read()); print(data["hypotheses"][0]["id"])' <<< "$before_output" 2>/dev/null || true)
  run_fcase hypothesis set hypothesis-bug --id "${hypothesis_id}" --status active --reason "Repro still points at cache path" --confidence high >/dev/null 2>&1 || true
  local output rc=0
  output=$(run_fcase status hypothesis-bug -o json 2>&1) || rc=$?
  if [[ $rc -eq 0 ]] && [[ "$output" == *'"status":"active"'* ]] && [[ "$output" == *'"confidence":"high"'* ]]; then
    pass "hypothesis add and set update structured state"
  else
    fail "hypothesis set should update structured state" "rc=$rc output=$output"
  fi
}

test_hypothesis_set_preserves_reason_when_omitted() {
  run_fcase init hypothesis-reason --goal "Preserve reason on status-only update" >/dev/null 2>&1 || true
  run_fcase hypothesis add hypothesis-reason --body "Cache bypass causes failure" --confidence medium >/dev/null 2>&1 || true
  local before_output hypothesis_id
  before_output=$(run_fcase status hypothesis-reason -o json 2>&1)
  hypothesis_id=$(python3 -c 'import json,sys; data=json.loads(sys.stdin.read()); print(data["hypotheses"][0]["id"])' <<< "$before_output" 2>/dev/null || true)
  run_fcase hypothesis set hypothesis-reason --id "${hypothesis_id}" --status active --reason "Repro still points at cache path" >/dev/null 2>&1 || true
  run_fcase hypothesis set hypothesis-reason --id "${hypothesis_id}" --status validated --confidence high >/dev/null 2>&1 || true

  local output rc=0
  output=$(run_fcase status hypothesis-reason -o json 2>&1) || rc=$?
  if [[ $rc -eq 0 ]] && python3 -c 'import json,sys; data=json.loads(sys.stdin.read()); hypo=data["hypotheses"][0]; assert hypo["status"] == "validated"; assert hypo["reason"] == "Repro still points at cache path"; assert hypo["confidence"] == "high"' <<< "$output" 2>/dev/null; then
    pass "hypothesis set preserves the existing reason when --reason is omitted"
  else
    fail "hypothesis set should preserve reason unless explicitly changed" "rc=$rc output=$output"
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

test_event_payload_json_escapes_control_chars() {
  run_fcase init control-bug --goal "Escape control chars" >/dev/null 2>&1 || true
  local note_body payload
  note_body=$'bad \b formfeed \f and unit \001 markers'
  run_fcase note control-bug --body "$note_body" >/dev/null 2>&1 || true
  payload=$(sqlite3 "${TEST_HOME}/.fsuite/fcase.db" "PRAGMA foreign_keys=ON; SELECT payload_json FROM events WHERE event_type = 'note' ORDER BY id DESC LIMIT 1;")

  if python3 -c 'import json,sys; data=json.loads(sys.stdin.read()); assert "body" in data' <<< "$payload" 2>/dev/null; then
    pass "event payload JSON escapes control characters safely"
  else
    fail "event payload JSON should remain valid when note bodies contain control chars" "payload=$payload"
  fi
}

test_source_routes_db_access_through_fk_helpers() {
  local rc=0
  python3 - "${FCASE}" <<'PY' || rc=$?
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text()
assert "db_query() {" in text
assert "db_exec() {" in text
assert 'sqlite3 "$DB_FILE"' in text
assert text.count('PRAGMA foreign_keys=ON;') >= 1
assert text.count('conn.execute("PRAGMA foreign_keys=ON")') >= 1
PY

  if [[ $rc -eq 0 ]]; then
    pass "fcase routes DB access through foreign-key-aware helpers"
  else
    fail "fcase should route DB access through foreign-key-aware helpers"
  fi
}

test_target_import_ingests_fmap_json() {
  run_fcase init import-targets --goal "Import fmap targets" >/dev/null 2>&1 || true
  local fmap_json
  fmap_json=$(cat <<'EOF'
{"tool":"fmap","version":"2.1.0","mode":"single_file","path":"/repo/src/auth.py","files":[{"path":"/repo/src/auth.py","language":"python","symbol_count":2,"symbols":[{"line":10,"type":"function","indent":0,"text":"authenticate(user):"},{"line":24,"type":"class","indent":0,"text":"AuthHandler:"}]}]}
EOF
)

  local output rc=0
  output=$(printf '%s' "$fmap_json" | run_fcase target import import-targets 2>&1) || rc=$?
  local status_output
  status_output=$(run_fcase status import-targets -o json 2>&1 || true)

  if [[ $rc -eq 0 ]] && python3 -c 'import json,sys; data=json.loads(sys.stdin.read()); targets=data["targets"]; assert len(targets) == 2; assert any(t["path"] == "/repo/src/auth.py" and t["symbol"] == "authenticate" and t["symbol_type"] == "function" and "line 10" in (t["reason"] or "") for t in targets); assert any(t["symbol"] == "AuthHandler" and t["symbol_type"] == "class" for t in targets)' <<< "$status_output" 2>/dev/null; then
    pass "target import ingests fmap JSON into structured targets"
  else
    fail "target import should ingest fmap JSON" "rc=$rc output=$output status=$status_output"
  fi
}

test_target_import_handles_large_fmap_json_file() {
  run_fcase init import-targets-large --goal "Import large fmap targets safely" >/dev/null 2>&1 || true

  local payload_path="${TEST_HOME}/huge-fmap.json"
  local arg_max target_bytes payload_size output rc=0 status_output
  arg_max=$(getconf ARG_MAX 2>/dev/null || echo 2097152)
  target_bytes=$((arg_max + 65536))

  python3 - "$payload_path" "$target_bytes" <<'PY'
import json
import sys

path = sys.argv[1]
target_bytes = int(sys.argv[2])
symbol_count = max(2000, target_bytes // 110)
symbols = [
    {
        "line": i + 1,
        "type": "function",
        "indent": 0,
        "text": f"def giant_symbol_{i:05d}(): return {'x' * 48}",
    }
    for i in range(symbol_count)
]
payload = {
    "tool": "fmap",
    "version": "2.1.0",
    "mode": "single_file",
    "path": "/repo/src/big.py",
    "files": [
        {
            "path": "/repo/src/big.py",
            "language": "python",
            "symbol_count": len(symbols),
            "symbols": symbols,
        }
    ],
}
encoded = json.dumps(payload)
with open(path, "w", encoding="utf-8") as fh:
    fh.write(encoded)
PY

  payload_size=$(wc -c < "$payload_path")
  if (( payload_size <= arg_max )); then
    fail "large fmap import fixture should exceed ARG_MAX" "size=$payload_size arg_max=$arg_max"
    return
  fi

  output=$(run_fcase target import import-targets-large --input "$payload_path" 2>&1) || rc=$?
  status_output=$(run_fcase status import-targets-large -o json 2>&1 || true)

  if [[ $rc -eq 0 ]] && python3 -c 'import json,sys; data=json.loads(sys.stdin.read()); targets=data["targets"]; assert len(targets) > 1000; assert any(t["path"] == "/repo/src/big.py" for t in targets)' <<< "$status_output" 2>/dev/null; then
    pass "target import handles large fmap JSON files without env-size failure"
  else
    fail "target import should handle large fmap JSON files" "rc=$rc size=$payload_size output=$output status=$status_output"
  fi
}

test_evidence_import_ingests_fread_json() {
  run_fcase init import-evidence --goal "Import fread evidence" >/dev/null 2>&1 || true
  local fread_json
  fread_json=$(cat <<'EOF'
{"tool":"fread","version":"2.1.0","mode":"around","chunks":[{"path":"/repo/src/auth.py","start_line":40,"end_line":52,"match_line":44,"content":["40  def authenticate(user):","41      if not user:","44          return deny()"]}],"files":[{"path":"/repo/src/auth.py","status":"read"}],"warnings":[],"errors":[]}
EOF
)

  local output rc=0
  output=$(printf '%s' "$fread_json" | run_fcase evidence import import-evidence 2>&1) || rc=$?
  local status_output
  status_output=$(run_fcase status import-evidence -o json 2>&1 || true)

  if [[ $rc -eq 0 ]] && python3 -c 'import json,sys; data=json.loads(sys.stdin.read()); evidence=data["evidence"]; assert len(evidence) == 1; ev=evidence[0]; assert ev["tool"] == "fread"; assert ev["line_start"] == 40; assert ev["line_end"] == 52; assert ev["match_line"] == 44; assert "return deny()" in ev["body"]; assert ev["payload_json"] is not None' <<< "$status_output" 2>/dev/null; then
    pass "evidence import ingests fread JSON into structured evidence"
  else
    fail "evidence import should ingest fread JSON" "rc=$rc output=$output status=$status_output"
  fi
}

test_evidence_import_handles_large_fread_json_file() {
  run_fcase init import-evidence-large --goal "Import large fread evidence safely" >/dev/null 2>&1 || true

  local payload_path="${TEST_HOME}/huge-fread.json"
  local arg_max target_bytes payload_size output rc=0 status_output
  arg_max=$(getconf ARG_MAX 2>/dev/null || echo 2097152)
  target_bytes=$((arg_max + 65536))

  python3 - "$payload_path" "$target_bytes" <<'PY'
import json
import sys

path = sys.argv[1]
target_bytes = int(sys.argv[2])
chunk_count = max(4000, target_bytes // 220)
content_lines = ["40  def authenticate(user):", "41      return " + ("x" * 140)]
chunks = [
    {
        "path": "/repo/src/big.py",
        "start_line": i + 1,
        "end_line": i + 2,
        "match_line": i + 1,
        "content": content_lines,
    }
    for i in range(chunk_count)
]
payload = {
    "tool": "fread",
    "version": "2.1.0",
    "mode": "around",
    "chunks": chunks,
    "files": [{"path": "/repo/src/big.py", "status": "read"}],
    "warnings": [],
    "errors": [],
}
encoded = json.dumps(payload)
with open(path, "w", encoding="utf-8") as fh:
    fh.write(encoded)
PY

  payload_size=$(wc -c < "$payload_path")
  if (( payload_size <= arg_max )); then
    fail "large fread import fixture should exceed ARG_MAX" "size=$payload_size arg_max=$arg_max"
    return
  fi

  output=$(run_fcase evidence import import-evidence-large --input "$payload_path" 2>&1) || rc=$?
  status_output=$(run_fcase status import-evidence-large -o json 2>&1 || true)

  if [[ $rc -eq 0 ]] && python3 -c 'import json,sys; data=json.loads(sys.stdin.read()); evidence=data["evidence"]; assert len(evidence) > 1000; assert all(ev["tool"] == "fread" for ev in evidence[:10])' <<< "$status_output" 2>/dev/null; then
    pass "evidence import handles large fread JSON files without env-size failure"
  else
    fail "evidence import should handle large fread JSON files" "rc=$rc size=$payload_size output=$output status=$status_output"
  fi
}

test_target_import_rejects_wrong_tool_json() {
  run_fcase init bad-import --goal "Reject wrong import tool" >/dev/null 2>&1 || true
  if printf '%s' '{"tool":"fread","chunks":[]}' | run_fcase target import bad-import >/dev/null 2>&1; then
    fail "target import should reject non-fmap JSON"
  else
    pass "target import rejects mismatched tool JSON"
  fi
}

main() {
  echo "======================================"
  echo "  fcase Test Suite"
  echo "======================================"
  echo ""
  echo "Running tests..."
  echo ""

  [[ -n "${FCASE}" && -x "${FCASE}" ]] || {
    echo "FCASE is required and must be executable: ${FCASE}" >&2
    exit 1
  }

  command -v python3 >/dev/null 2>&1 || {
    echo "python3 is required for test_fcase.sh" >&2
    exit 1
  }

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
  run_test test_hypothesis_set_preserves_reason_when_omitted
  run_test test_reject_maps_to_hypothesis_rejected
  run_test test_reject_fails_without_selector
  run_test test_evidence_rejects_invalid_line_range
  run_test test_event_payload_json_escapes_control_chars
  run_test test_source_routes_db_access_through_fk_helpers
  run_test test_target_import_ingests_fmap_json
  run_test test_target_import_handles_large_fmap_json_file
  run_test test_evidence_import_ingests_fread_json
  run_test test_evidence_import_handles_large_fread_json_file
  run_test test_target_import_rejects_wrong_tool_json

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
