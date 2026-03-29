#!/usr/bin/env bash
# test_fcase_lifecycle.sh — schema migration tests for fcase lifecycle (v3)
# Run with: bash tests/test_fcase_lifecycle.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
FCASE="$REPO_DIR/fcase"
PASS=0; FAIL=0; TOTAL=0

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  TOTAL=$((TOTAL + 1))
  if [[ "$expected" == "$actual" ]]; then
    PASS=$((PASS + 1)); echo -e "  \033[0;32m✓\033[0m $label"
  else
    FAIL=$((FAIL + 1)); echo -e "  \033[0;31m✗\033[0m $label"
    echo "    expected: $expected"; echo "    actual:   $actual"
  fi
}

assert_contains() {
  local label="$1" haystack="$2" needle="$3"
  TOTAL=$((TOTAL + 1))
  if [[ "$haystack" == *"$needle"* ]]; then
    PASS=$((PASS + 1)); echo -e "  \033[0;32m✓\033[0m $label"
  else
    FAIL=$((FAIL + 1)); echo -e "  \033[0;31m✗\033[0m $label"
    echo "    expected to contain: $needle"
    echo "    haystack: $haystack"
  fi
}

# Use isolated test DB via HOME override (matches existing test pattern)
TEST_HOME=""

setup_test_db() {
  TEST_HOME="$(mktemp -d)"
}

teardown_test_db() {
  rm -rf "${TEST_HOME:-}" 2>/dev/null || true
  TEST_HOME=""
}

run_fcase() {
  HOME="${TEST_HOME}" FSUITE_TELEMETRY=0 "$FCASE" "$@"
}

trap teardown_test_db EXIT

echo ""
echo "═══════════════════════════════════════════"
echo " fcase lifecycle test suite"
echo "═══════════════════════════════════════════"

# ── Section 1: Schema Migration ─────────────────────────────────
echo ""
echo "── Section 1: Schema Migration ──"

setup_test_db

# Create a case to trigger ensure_db (which runs all migrations)
run_fcase init migration-test --goal "Test migration" -o json >/dev/null 2>&1 || true

DB="$TEST_HOME/.fsuite/fcase.db"

# Check new columns exist
result=$(sqlite3 "$DB" "PRAGMA table_info(cases);" 2>&1)
assert_contains "resolution_summary column exists" "$result" "resolution_summary"
assert_contains "resolved_at column exists" "$result" "resolved_at"
assert_contains "archived_at column exists" "$result" "archived_at"
assert_contains "deleted_at column exists" "$result" "deleted_at"
assert_contains "delete_reason column exists" "$result" "delete_reason"

# Check indexes exist
result=$(sqlite3 "$DB" ".indexes" 2>&1)
assert_contains "status+updated index exists" "$result" "idx_cases_status_updated"
assert_contains "events case_id index exists" "$result" "idx_events_case_id"
assert_contains "evidence case_id index exists" "$result" "idx_evidence_case_id"
assert_contains "hypotheses case_id index exists" "$result" "idx_hypotheses_case_id"
assert_contains "targets case_id index exists" "$result" "idx_targets_case_id"
assert_contains "sessions case_id index exists" "$result" "idx_sessions_case_id"

# Check FTS table exists and is queryable
result=$(sqlite3 "$DB" "SELECT count(*) FROM cases_fts;" 2>&1)
assert_eq "FTS table exists and queryable" "1" "$result"

# Check FTS has the case we just created
result=$(sqlite3 "$DB" "SELECT slug FROM cases_fts WHERE cases_fts MATCH 'migration';" 2>&1)
assert_contains "FTS contains migrated case" "$result" "migration-test"

# Check user_version bumped to 3
result=$(sqlite3 "$DB" "PRAGMA user_version;" 2>&1)
assert_eq "user_version is 3" "3" "$result"

# ── Section 2: Idempotency ──────────────────────────────────────
echo ""
echo "── Section 2: Idempotency ──"

# Running init again on same DB should not fail (migration is idempotent)
rc=0
run_fcase init idempotency-test --goal "Second case" -o json >/dev/null 2>&1 || rc=$?
assert_eq "second init succeeds on same DB" "0" "$rc"

# FTS should now have 2 rows
result=$(sqlite3 "$DB" "SELECT count(*) FROM cases_fts;" 2>&1)
assert_eq "FTS has 2 rows after second init" "2" "$result"

teardown_test_db

echo ""
echo "═══════════════════════════════════════════"
echo " Results: $PASS passed, $FAIL failed, $TOTAL total"
echo "═══════════════════════════════════════════"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
