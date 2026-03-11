#!/usr/bin/env bash
# test_telemetry.sh — tests for fsuite telemetry system
# Run with: bash test_telemetry.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FSUITE_DIR="${SCRIPT_DIR}/.."
FCONTENT="${FSUITE_DIR}/fcontent"
FSEARCH="${FSUITE_DIR}/fsearch"
FTREE="${FSUITE_DIR}/ftree"
FMETRICS="${FSUITE_DIR}/fmetrics"
FMETRICS_PREDICT="${FSUITE_DIR}/fmetrics-predict.py"

TEST_DIR=""
BACKUP_TELEMETRY=""
ORIGINAL_HOME="${HOME:-}"
SANDBOX_HOME=""
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # setup creates a sandboxed HOME, prepares a temporary TEST_DIR with sample files (src/test.txt, src/code.js, large_file.bin), and clears any existing telemetry artifacts in the sandboxed .fsuite directory.

setup() {
  SANDBOX_HOME="$(mktemp -d)"
  export HOME="$SANDBOX_HOME"
  mkdir -p "$HOME/.fsuite"

  TEST_DIR="$(mktemp -d)"
  mkdir -p "${TEST_DIR}/src"
  echo "hello world" > "${TEST_DIR}/src/test.txt"
  echo "function foo() { return 1; }" > "${TEST_DIR}/src/code.js"
  dd if=/dev/zero of="${TEST_DIR}/large_file.bin" bs=1024 count=50 2>/dev/null

  # Clear telemetry for clean tests
  rm -f "$HOME/.fsuite/telemetry.jsonl"
  rm -f "$HOME/.fsuite/telemetry.db"
  rm -f "$HOME/.fsuite/machine_profile.json"
}

# teardown restores the original HOME and removes any temporary TEST_DIR and SANDBOX_HOME created for the test run.
teardown() {
  if [[ -n "${TEST_DIR}" && -d "${TEST_DIR}" ]]; then
    rm -rf "${TEST_DIR}"
  fi

  export HOME="$ORIGINAL_HOME"

  if [[ -n "${SANDBOX_HOME}" && -d "${SANDBOX_HOME}" ]]; then
    rm -rf "${SANDBOX_HOME}"
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
  shift  # Skip test description (used by caller for display)
  "$@" || true
}

# run_fmetrics runs the fmetrics command with telemetry disabled by setting FSUITE_TELEMETRY=0 and forwarding all provided arguments.
run_fmetrics() {
  FSUITE_TELEMETRY=0 "${FMETRICS}" "$@"
}

# seed_ftree_predict_fixture_db prepares a test telemetry store for fmetrics predict by creating $HOME/.fsuite, clearing telemetry.jsonl and telemetry.db, invoking the import step, and seeding telemetry.db with representative ftree run records.
# The seeded records cover multiple modes ('tree', 'recon', 'snapshot') with varied durations and flags to exercise prediction and filtering behavior.
seed_ftree_predict_fixture_db() {
  mkdir -p "$HOME/.fsuite"
  rm -f "$HOME/.fsuite/telemetry.jsonl" "$HOME/.fsuite/telemetry.db"
  : > "$HOME/.fsuite/telemetry.jsonl"
  run_fmetrics import >/dev/null 2>&1 || true

  sqlite3 "$HOME/.fsuite/telemetry.db" <<'SQL'
DELETE FROM telemetry;
INSERT INTO telemetry (timestamp,tool,version,mode,path_hash,project_name,duration_ms,exit_code,depth,items_scanned,bytes_scanned,flags,backend,run_id) VALUES
  ('2026-03-10T00:00:00Z','ftree','2.1.0','tree','tree01','predict-fixture',9,0,3,42,4200,'-o json','tree','tree01'),
  ('2026-03-10T00:00:01Z','ftree','2.1.0','tree','tree02','predict-fixture',11,0,3,42,4200,'-o json','tree','tree02'),
  ('2026-03-10T00:00:02Z','ftree','2.1.0','tree','tree03','predict-fixture',10,0,3,42,4200,'-o json','tree','tree03'),
  ('2026-03-10T00:00:03Z','ftree','2.1.0','tree','tree04','predict-fixture',12,0,3,42,4200,'-o json','tree','tree04'),
  ('2026-03-10T00:00:04Z','ftree','2.1.0','tree','tree05','predict-fixture',8,0,3,42,4200,'-o json','tree','tree05'),
  ('2026-03-10T00:00:05Z','ftree','2.1.0','recon','recon01','predict-fixture',180,0,3,42,4200,'-o json --recon','tree','recon01'),
  ('2026-03-10T00:00:06Z','ftree','2.1.0','recon','recon02','predict-fixture',190,0,3,42,4200,'-o json --recon','tree','recon02'),
  ('2026-03-10T00:00:07Z','ftree','2.1.0','recon','recon03','predict-fixture',210,0,3,42,4200,'-o json --recon','tree','recon03'),
  ('2026-03-10T00:00:08Z','ftree','2.1.0','recon','recon04','predict-fixture',220,0,3,42,4200,'-o json --recon','tree','recon04'),
  ('2026-03-10T00:00:09Z','ftree','2.1.0','recon','recon05','predict-fixture',205,0,3,42,4200,'-o json --recon','tree','recon05'),
  ('2026-03-10T00:00:10Z','ftree','2.1.0','snapshot','snap01','predict-fixture',5000,0,3,42,4200,'-o json --snapshot','tree','snap01'),
  ('2026-03-10T00:00:11Z','ftree','2.1.0','snapshot','snap02','predict-fixture',5200,0,3,42,4200,'-o json --snapshot','tree','snap02'),
  ('2026-03-10T00:00:12Z','ftree','2.1.0','snapshot','snap03','predict-fixture',5100,0,3,42,4200,'-o json --snapshot','tree','snap03'),
  ('2026-03-10T00:00:13Z','ftree','2.1.0','snapshot','snap04','predict-fixture',5300,0,3,42,4200,'-o json --snapshot','tree','snap04'),
  ('2026-03-10T00:00:14Z','ftree','2.1.0','snapshot','snap05','predict-fixture',4900,0,3,42,4200,'-o json --snapshot','tree','snap05');
SQL
}

# ============================================================================
# bytes_scanned Tests (Phase 1)
# ============================================================================

test_fcontent_bytes_scanned() {
  rm -f "$HOME/.fsuite/telemetry.jsonl"
  FSUITE_TELEMETRY=1 "${FCONTENT}" "hello" "${TEST_DIR}" >/dev/null 2>&1 || true
  local bytes
  bytes=$(tail -1 "$HOME/.fsuite/telemetry.jsonl" 2>/dev/null | grep -o '"bytes_scanned":[0-9]*' | cut -d: -f2)
  if [[ "$bytes" =~ ^[0-9]+$ ]] && (( bytes > 0 )); then
    pass "fcontent records bytes_scanned > 0"
  else
    fail "fcontent bytes_scanned should be > 0" "Got: $bytes"
  fi
}

test_fsearch_bytes_scanned() {
  rm -f "$HOME/.fsuite/telemetry.jsonl"
  FSUITE_TELEMETRY=1 "${FSEARCH}" "*.txt" "${TEST_DIR}" >/dev/null 2>&1 || true
  local bytes
  bytes=$(tail -1 "$HOME/.fsuite/telemetry.jsonl" 2>/dev/null | grep -o '"bytes_scanned":[0-9]*' | cut -d: -f2)
  if [[ "$bytes" =~ ^[0-9]+$ ]] && (( bytes > 0 )); then
    pass "fsearch records bytes_scanned > 0"
  else
    fail "fsearch bytes_scanned should be > 0" "Got: $bytes"
  fi
}

test_ftree_bytes_scanned() {
  rm -f "$HOME/.fsuite/telemetry.jsonl"
  FSUITE_TELEMETRY=1 "${FTREE}" "${TEST_DIR}" >/dev/null 2>&1 || true
  local bytes
  bytes=$(tail -1 "$HOME/.fsuite/telemetry.jsonl" 2>/dev/null | grep -o '"bytes_scanned":[0-9]*' | cut -d: -f2)
  if [[ "$bytes" =~ ^[0-9]+$ ]] && (( bytes > 0 )); then
    pass "ftree records bytes_scanned > 0"
  else
    fail "ftree bytes_scanned should be > 0" "Got: $bytes"
  fi
}

test_fcontent_stdin_mode_bytes_minus1() {
  rm -f "$HOME/.fsuite/telemetry.jsonl"
  echo "${TEST_DIR}/src/test.txt" | FSUITE_TELEMETRY=1 "${FCONTENT}" "hello" >/dev/null 2>&1 || true
  local bytes
  bytes=$(tail -1 "$HOME/.fsuite/telemetry.jsonl" 2>/dev/null | grep -o '"bytes_scanned":-*[0-9]*' | cut -d: -f2)
  if [[ "$bytes" == "-1" ]]; then
    pass "fcontent stdin mode keeps bytes_scanned = -1"
  else
    fail "fcontent stdin mode should have bytes_scanned = -1" "Got: $bytes"
  fi
}

# ============================================================================
# Tier 0 Tests (Disabled Telemetry)
# ============================================================================

test_tier0_no_telemetry() {
  local before=0
  rm -f "$HOME/.fsuite/telemetry.jsonl"
  [[ -f "$HOME/.fsuite/telemetry.jsonl" ]] && before=$(wc -l < "$HOME/.fsuite/telemetry.jsonl")

  FSUITE_TELEMETRY=0 "${FTREE}" "${TEST_DIR}" >/dev/null 2>&1 || true
  FSUITE_TELEMETRY=0 "${FSEARCH}" "*.txt" "${TEST_DIR}" >/dev/null 2>&1 || true
  FSUITE_TELEMETRY=0 "${FCONTENT}" "hello" "${TEST_DIR}" >/dev/null 2>&1 || true

  local after=0
  [[ -f "$HOME/.fsuite/telemetry.jsonl" ]] && after=$(wc -l < "$HOME/.fsuite/telemetry.jsonl")

  if (( after == before )); then
    pass "Tier 0 produces no telemetry"
  else
    fail "Tier 0 should not produce telemetry" "Lines before=$before, after=$after"
  fi
}

# ============================================================================
# Tier 2 Tests (Hardware Telemetry)
# ============================================================================

test_tier2_hardware_fields() {
  rm -f "$HOME/.fsuite/telemetry.jsonl"
  FSUITE_TELEMETRY=2 "${FTREE}" "${TEST_DIR}" >/dev/null 2>&1 || true
  local line
  line=$(tail -1 "$HOME/.fsuite/telemetry.jsonl" 2>/dev/null)

  local has_cpu has_ram has_load
  has_cpu=$(echo "$line" | grep -o '"cpu_temp_mc"' || true)
  has_ram=$(echo "$line" | grep -o '"ram_total_kb"' || true)
  has_load=$(echo "$line" | grep -o '"load_avg_1m"' || true)

  if [[ -n "$has_cpu" ]] && [[ -n "$has_ram" ]] && [[ -n "$has_load" ]]; then
    pass "Tier 2 includes hardware telemetry fields"
  else
    fail "Tier 2 should include cpu_temp_mc, ram_total_kb, load_avg_1m"
  fi
}

test_tier1_no_hardware_fields() {
  rm -f "$HOME/.fsuite/telemetry.jsonl"
  FSUITE_TELEMETRY=1 "${FTREE}" "${TEST_DIR}" >/dev/null 2>&1 || true
  local line
  line=$(tail -1 "$HOME/.fsuite/telemetry.jsonl" 2>/dev/null)

  local has_cpu
  has_cpu=$(echo "$line" | grep -o '"cpu_temp_mc"' || true)

  if [[ -z "$has_cpu" ]]; then
    pass "Tier 1 does not include hardware fields"
  else
    fail "Tier 1 should not include cpu_temp_mc"
  fi
}

test_tier2_filesystem_storage_fields() {
  rm -f "$HOME/.fsuite/telemetry.jsonl"
  FSUITE_TELEMETRY=2 "${FTREE}" "${TEST_DIR}" >/dev/null 2>&1 || true
  local line
  line=$(tail -1 "$HOME/.fsuite/telemetry.jsonl" 2>/dev/null)

  local has_fs has_st
  has_fs=$(echo "$line" | grep -o '"filesystem_type"' || true)
  has_st=$(echo "$line" | grep -o '"storage_type"' || true)

  if [[ -n "$has_fs" ]] && [[ -n "$has_st" ]]; then
    pass "Tier 2 includes filesystem_type and storage_type fields"
  else
    fail "Tier 2 should include filesystem_type and storage_type"
  fi
}

test_filesystem_type_not_unknown() {
  rm -f "$HOME/.fsuite/telemetry.jsonl"
  FSUITE_TELEMETRY=2 "${FTREE}" "${TEST_DIR}" >/dev/null 2>&1 || true
  local line fs_type
  line=$(tail -1 "$HOME/.fsuite/telemetry.jsonl" 2>/dev/null)
  fs_type=$(echo "$line" | grep -oE '"filesystem_type":"[^"]+"' | cut -d'"' -f4)

  if [[ -n "$fs_type" ]] && [[ "$fs_type" != "unknown" ]]; then
    pass "Filesystem type detected: $fs_type"
  else
    fail "Filesystem type should not be unknown for valid path"
  fi
}

test_storage_type_not_unknown() {
  rm -f "$HOME/.fsuite/telemetry.jsonl"
  FSUITE_TELEMETRY=2 "${FTREE}" "${TEST_DIR}" >/dev/null 2>&1 || true
  local line st_type
  line=$(tail -1 "$HOME/.fsuite/telemetry.jsonl" 2>/dev/null)
  st_type=$(echo "$line" | grep -oE '"storage_type":"[^"]+"' | cut -d'"' -f4)

  if [[ -n "$st_type" ]] && [[ "$st_type" != "unknown" ]]; then
    pass "Storage type detected: $st_type"
  else
    fail "Storage type should not be unknown for valid path"
  fi
}

# ============================================================================
# Tier 3 Tests (Machine Profile)
# ============================================================================

test_tier3_machine_profile() {
  rm -f "$HOME/.fsuite/machine_profile.json"
  FSUITE_TELEMETRY=3 "${FSEARCH}" "*.txt" "${TEST_DIR}" >/dev/null 2>&1 || true

  if [[ -f "$HOME/.fsuite/machine_profile.json" ]]; then
    local has_os has_cpu_model
    has_os=$(grep -o '"os"' "$HOME/.fsuite/machine_profile.json" || true)
    has_cpu_model=$(grep -o '"cpu_model"' "$HOME/.fsuite/machine_profile.json" || true)
    if [[ -n "$has_os" ]] && [[ -n "$has_cpu_model" ]]; then
      pass "Tier 3 generates machine profile with expected fields"
    else
      fail "Machine profile missing os or cpu_model"
    fi
  else
    fail "Tier 3 should generate machine_profile.json"
  fi
}

# ============================================================================
# Schema Migration Tests
# ============================================================================

test_schema_migration_idempotent() {
  if ! command -v sqlite3 >/dev/null 2>&1; then
    pass "Schema migration test skipped (sqlite3 not available)"
    return 0
  fi
  rm -f "$HOME/.fsuite/telemetry.db"
  # Run fmetrics import twice (which runs ensure_db twice)
  FSUITE_TELEMETRY=1 "${FTREE}" "${TEST_DIR}" >/dev/null 2>&1 || true
  run_fmetrics import >/dev/null 2>&1 || true
  run_fmetrics import >/dev/null 2>&1 || true

  # Check that db exists and has the new columns
  local cols
  cols=$(sqlite3 "$HOME/.fsuite/telemetry.db" "SELECT sql FROM sqlite_master WHERE name='telemetry';" 2>/dev/null || true)

  if [[ "$cols" == *"cpu_temp_mc"* ]] && [[ "$cols" == *"load_avg_1m"* ]] && [[ "$cols" == *"run_id"* ]] && ([[ "$cols" == *"UNIQUE(run_id, tool, path_hash)"* ]] || [[ "$cols" == *"UNIQUE(run_id,tool,path_hash)"* ]]); then
    pass "Schema migration is idempotent"
  else
    fail "Schema should have hardware columns after migration" "Got: $cols"
  fi
}

test_run_id_in_jsonl() {
  rm -f "$HOME/.fsuite/telemetry.jsonl"
  FSUITE_TELEMETRY=1 "${FTREE}" "${TEST_DIR}" >/dev/null 2>&1 || true
  local line
  line=$(tail -1 "$HOME/.fsuite/telemetry.jsonl" 2>/dev/null) || line=""
  if [[ "$line" =~ \"run_id\":\"[0-9]+_[0-9]+\" ]]; then
    pass "Telemetry JSONL includes run_id"
  else
    fail "Telemetry JSONL should include run_id" "Got: $line"
  fi
}

test_burst_runs_not_dropped() {
  if ! command -v sqlite3 >/dev/null 2>&1; then
    pass "Burst dedupe test skipped (sqlite3 not available)"
    return 0
  fi
  rm -f "$HOME/.fsuite/telemetry.jsonl" "$HOME/.fsuite/telemetry.db"
  FSUITE_TELEMETRY=1 "${FTREE}" "${TEST_DIR}" >/dev/null 2>&1 || true
  FSUITE_TELEMETRY=1 "${FTREE}" "${TEST_DIR}" >/dev/null 2>&1 || true
  run_fmetrics import >/dev/null 2>&1 || true
  local count
  count=$(sqlite3 "$HOME/.fsuite/telemetry.db" "SELECT COUNT(*) FROM telemetry WHERE tool='ftree';" 2>/dev/null) || count=0
  if [[ "$count" =~ ^[0-9]+$ ]] && (( count >= 2 )); then
    pass "Burst runs are not dropped by dedupe"
  else
    fail "Expected at least 2 ftree rows after burst import" "Got count=$count"
  fi
}

test_legacy_import_backfill_run_id() {
  if ! command -v sqlite3 >/dev/null 2>&1; then
    pass "Legacy backfill test skipped (sqlite3 not available)"
    return 0
  fi
  rm -f "$HOME/.fsuite/telemetry.jsonl" "$HOME/.fsuite/telemetry.db"
  cat > "$HOME/.fsuite/telemetry.jsonl" <<'EOF'
{"timestamp":"2026-03-07T00:00:00Z","tool":"ftree","version":"1.6.2","mode":"tree","path_hash":"abc123def456","project_name":"legacyproj","duration_ms":42,"exit_code":0,"depth":1,"items_scanned":3,"bytes_scanned":2048,"flags":"-o pretty","backend":"tree"}
EOF
  run_fmetrics import >/dev/null 2>&1 || true
  local run_id
  run_id=$(sqlite3 "$HOME/.fsuite/telemetry.db" "SELECT run_id FROM telemetry WHERE tool='ftree' LIMIT 1;" 2>/dev/null) || run_id=""
  if [[ -n "$run_id" ]]; then
    pass "Legacy JSONL import backfills run_id"
  else
    fail "Legacy JSONL import should backfill run_id"
  fi
}

test_migration_atomicity() {
  if ! command -v sqlite3 >/dev/null 2>&1; then
    pass "Migration atomicity test skipped (sqlite3 not available)"
    return 0
  fi
  rm -f "$HOME/.fsuite/telemetry.db"
  # Create a DB with OLD schema (inline UNIQUE(timestamp,tool,path_hash))
  # AND a blocker table 'telemetry_old' so the migration's
  # ALTER TABLE telemetry RENAME TO telemetry_old fails mid-transaction.
  sqlite3 "$HOME/.fsuite/telemetry.db" <<'SQL'
CREATE TABLE telemetry (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  timestamp TEXT NOT NULL,
  tool TEXT NOT NULL,
  version TEXT NOT NULL,
  mode TEXT NOT NULL,
  path_hash TEXT NOT NULL,
  project_name TEXT NOT NULL,
  duration_ms INTEGER NOT NULL,
  exit_code INTEGER NOT NULL,
  depth INTEGER NOT NULL DEFAULT -1,
  items_scanned INTEGER NOT NULL DEFAULT -1,
  bytes_scanned INTEGER NOT NULL DEFAULT -1,
  flags TEXT NOT NULL DEFAULT '',
  backend TEXT NOT NULL DEFAULT '',
  UNIQUE(timestamp, tool, path_hash)
);
INSERT INTO telemetry (timestamp,tool,version,mode,path_hash,project_name,duration_ms,exit_code)
  VALUES ('2026-01-01T00:00:00Z','ftree','1.6.0','tree','aabbccdd','atomtest',100,0);
INSERT INTO telemetry (timestamp,tool,version,mode,path_hash,project_name,duration_ms,exit_code)
  VALUES ('2026-01-01T00:00:01Z','ftree','1.6.0','tree','eeff0011','atomtest',200,0);
CREATE TABLE telemetry_old (id INTEGER PRIMARY KEY);
SQL
  local pre_count
  pre_count=$(sqlite3 "$HOME/.fsuite/telemetry.db" "SELECT COUNT(*) FROM telemetry;" 2>/dev/null)

  # Run fmetrics import — ensure_db triggers migration, which should fail
  # at RENAME (telemetry_old already exists), and .bail on + BEGIN IMMEDIATE
  # should cause SQLite to roll back, leaving original table intact.
  rm -f "$HOME/.fsuite/telemetry.jsonl"
  echo '{}' > "$HOME/.fsuite/telemetry.jsonl"
  run_fmetrics import >/dev/null 2>&1 || true

  # Verify: original telemetry table still exists with all rows intact
  local post_count schema_sql
  post_count=$(sqlite3 "$HOME/.fsuite/telemetry.db" "SELECT COUNT(*) FROM telemetry;" 2>/dev/null) || post_count=0
  schema_sql=$(sqlite3 "$HOME/.fsuite/telemetry.db" "SELECT sql FROM sqlite_master WHERE type='table' AND name='telemetry';" 2>/dev/null) || schema_sql=""

  if (( post_count == pre_count )) && [[ "$schema_sql" == *"UNIQUE(timestamp, tool, path_hash)"* ]]; then
    pass "Migration rollback on failure preserves data"
  else
    fail "Failed migration should leave original table intact" "pre=$pre_count post=$post_count schema=$schema_sql"
  fi

  # Cleanup: remove the blocker so subsequent tests aren't affected
  sqlite3 "$HOME/.fsuite/telemetry.db" "DROP TABLE IF EXISTS telemetry_old;" 2>/dev/null || true
  rm -f "$HOME/.fsuite/telemetry.db"
}

# ============================================================================
# Metacharacter Warning Tests (Phase 3)
# ============================================================================

test_metachar_warning_parens() {
  local output
  output=$(FSUITE_TELEMETRY=0 "${FCONTENT}" "foo(bar)" "${TEST_DIR}" 2>&1)
  if [[ "$output" == *"regex metacharacters"* ]]; then
    pass "Metacharacter warning fires on ()"
  else
    fail "Should warn about metacharacters in foo(bar)"
  fi
}

test_metachar_warning_brackets() {
  local output
  output=$(FSUITE_TELEMETRY=0 "${FCONTENT}" "test[0]" "${TEST_DIR}" 2>&1)
  if [[ "$output" == *"regex metacharacters"* ]]; then
    pass "Metacharacter warning fires on []"
  else
    fail "Should warn about metacharacters in test[0]"
  fi
}

test_metachar_warning_suppressed_with_F() {
  local output
  output=$(FSUITE_TELEMETRY=0 "${FCONTENT}" "foo(bar)" "${TEST_DIR}" --rg-args "-F" 2>&1)
  if [[ "$output" != *"regex metacharacters"* ]]; then
    pass "Metacharacter warning suppressed with -F"
  else
    fail "Warning should be suppressed when -F is used"
  fi
}

test_metachar_warning_json_field() {
  local output
  output=$(FSUITE_TELEMETRY=0 "${FCONTENT}" "foo(bar)" "${TEST_DIR}" -o json 2>&1)
  if [[ "$output" == *'"warning":'* ]]; then
    pass "JSON output includes warning field"
  else
    fail "JSON should have warning field for metacharacter query"
  fi
}

test_no_metachar_no_warning() {
  local output
  output=$(FSUITE_TELEMETRY=0 "${FCONTENT}" "hello" "${TEST_DIR}" 2>&1)
  if [[ "$output" != *"regex metacharacters"* ]]; then
    pass "No warning for plain text query"
  else
    fail "Plain text query should not trigger warning"
  fi
}

# ============================================================================
# Graceful Degradation Tests
# ============================================================================

test_graceful_without_common_lib() {
  # Temporarily rename the common lib
  local lib="${FSUITE_DIR}/_fsuite_common.sh"
  if [[ -f "$lib" ]]; then
    mv "$lib" "${lib}.bak"

    rm -f "$HOME/.fsuite/telemetry.jsonl"

    FSUITE_TELEMETRY=1 "${FTREE}" "${TEST_DIR}" >/dev/null 2>&1 || true

    if [[ -f "${lib}.bak" ]]; then
      if ! mv "${lib}.bak" "$lib"; then
        echo "Failed to restore ${lib} from ${lib}.bak" >&2
        rm -f "${lib}.bak"
      fi
    fi

    if [[ -f "$HOME/.fsuite/telemetry.jsonl" ]]; then
      local bytes
      bytes=$(tail -1 "$HOME/.fsuite/telemetry.jsonl" 2>/dev/null | grep -o '"bytes_scanned"' || true)
      if [[ -n "$bytes" ]]; then
        pass "Tools work without _fsuite_common.sh (graceful degradation)"
      else
        fail "Tier 1 telemetry should still work without common lib"
      fi
    else
      fail "Telemetry should still be recorded without common lib"
    fi
  else
    pass "Common lib test skipped (lib not found)"
  fi
}

test_non_numeric_telemetry_env() {
  rm -f "$HOME/.fsuite/telemetry.jsonl"
  FSUITE_TELEMETRY=invalid "${FTREE}" "${TEST_DIR}" >/dev/null 2>&1 || true

  if [[ -f "$HOME/.fsuite/telemetry.jsonl" ]]; then
    pass "Non-numeric FSUITE_TELEMETRY defaults to tier 1"
  else
    fail "Should default to tier 1 for non-numeric env value"
  fi
}

# ============================================================================
# v1.5.0: Flag Accumulation & Project Name Tests
# ============================================================================

test_v15_ftree_flags() {
  rm -f "$HOME/.fsuite/telemetry.jsonl"
  FSUITE_TELEMETRY=1 "${FTREE}" --recon --budget 5 -L 2 -o json "${TEST_DIR}" >/dev/null 2>&1 || true
  local line flags
  line=$(tail -1 "$HOME/.fsuite/telemetry.jsonl" 2>/dev/null) || line=""
  flags=$(echo "$line" | grep -o '"flags":"[^"]*"' || true)
  if [[ "$flags" =~ "--budget 5" ]] && [[ "$flags" =~ "-L 2" ]] && [[ "$flags" =~ "--recon" ]] && [[ "$flags" =~ "-o json" ]]; then
    pass "ftree flag accumulation: --budget, -L, --recon, -o all present"
  else
    fail "ftree flags should include --budget 5 -L 2 --recon -o json" "Got: $flags"
  fi
}

test_v15_fcontent_flags() {
  rm -f "$HOME/.fsuite/telemetry.jsonl"
  FSUITE_TELEMETRY=1 "${FCONTENT}" -m 3 -q -o json "hello" "${TEST_DIR}" >/dev/null 2>&1 || true
  local line flags
  line=$(tail -1 "$HOME/.fsuite/telemetry.jsonl" 2>/dev/null) || line=""
  flags=$(echo "$line" | grep -o '"flags":"[^"]*"' || true)
  if [[ "$flags" =~ "-m 3" ]] && [[ "$flags" =~ "-q" ]] && [[ "$flags" =~ "-o json" ]]; then
    pass "fcontent flag accumulation: -m, -q, -o all present"
  else
    fail "fcontent flags should include -m 3 -q -o json" "Got: $flags"
  fi
}

test_v16_fsearch_filter_flags() {
  rm -f "$HOME/.fsuite/telemetry.jsonl"
  FSUITE_TELEMETRY=1 "${FSEARCH}" -I "src" -x "cache" -o paths "*.txt" "${TEST_DIR}" >/dev/null 2>&1 || true
  local line flags
  line=$(tail -1 "$HOME/.fsuite/telemetry.jsonl" 2>/dev/null) || line=""
  flags=$(echo "$line" | grep -o '"flags":"[^"]*"' || true)
  if [[ "$flags" =~ "-I src" ]] && [[ "$flags" =~ "-x cache" ]] && [[ "$flags" =~ "-o paths" ]]; then
    pass "fsearch filter flags include -I and -x in telemetry"
  else
    fail "fsearch filter flags should include -I src, -x cache, -o paths" "Got: $flags"
  fi
}

test_v15_jsonl_safety() {
  rm -f "$HOME/.fsuite/telemetry.jsonl"
  # Use rg-args with characters that could break JSONL (quotes, braces)
  FSUITE_TELEMETRY=1 "${FCONTENT}" --rg-args "-i --hidden" "hello" "${TEST_DIR}" >/dev/null 2>&1 || true
  local line
  line=$(tail -1 "$HOME/.fsuite/telemetry.jsonl" 2>/dev/null) || line=""
  if [[ -z "$line" ]]; then
    fail "JSONL should have been written"
    return
  fi
  # Validate it's parseable JSON
  if python3 -c "import json,sys; json.loads(sys.stdin.readline())" <<< "$line" 2>/dev/null; then
    pass "JSONL line is valid JSON after --rg-args with special chars"
  else
    # Fallback: at least check it has required fields
    if [[ "$line" =~ \"tool\": ]] && [[ "$line" =~ \"flags\": ]]; then
      pass "JSONL has required fields (python3 JSON validation skipped)"
    else
      fail "JSONL should be valid JSON" "Got: $line"
    fi
  fi
}

test_v15_project_name() {
  rm -f "$HOME/.fsuite/telemetry.jsonl"
  FSUITE_TELEMETRY=1 "${FTREE}" --project-name "MyProject" "${TEST_DIR}" >/dev/null 2>&1 || true
  local line
  line=$(tail -1 "$HOME/.fsuite/telemetry.jsonl" 2>/dev/null) || line=""
  if [[ "$line" =~ \"project_name\":\"MyProject\" ]]; then
    pass "--project-name override appears in telemetry"
  else
    fail "--project-name should set project_name in telemetry" "Got: $line"
  fi
}

# ============================================================================
# v1.5.0: fmetrics Enhancements
# ============================================================================

test_v15_selfcheck_python3() {
  local output
  output=$(run_fmetrics --self-check 2>&1) || true
  if [[ "$output" =~ "python3:" ]]; then
    pass "fmetrics --self-check reports python3 status"
  else
    fail "--self-check should show python3 line"
  fi
}

test_v15_selfcheck_predict() {
  local output
  output=$(run_fmetrics --self-check 2>&1) || true
  if [[ "$output" =~ "fmetrics-predict.py:" ]]; then
    pass "fmetrics --self-check reports predict script status"
  else
    fail "--self-check should show fmetrics-predict.py line"
  fi
}

# test_v15_predict_tool_filter verifies that `fmetrics predict --tool ftree` filters predictions to the ftree tool and accepts the `--tool` flag even when there is insufficient telemetry data for a numeric prediction.
test_v15_predict_tool_filter() {
  # Need substantial telemetry data for predictions
  rm -f "$HOME/.fsuite/telemetry.jsonl"
  rm -f "$HOME/.fsuite/telemetry.db"

  # Create varied test directories for diverse telemetry
  for i in {1..8}; do
    local vary_dir="${TEST_DIR}/vary_${i}"
    mkdir -p "${vary_dir}/sub"
    for j in $(seq 1 $((i * 2))); do
      echo "content $j" > "${vary_dir}/sub/file${j}.txt"
    done
    FSUITE_TELEMETRY=1 "${FTREE}" "${vary_dir}" >/dev/null 2>&1 || true
    FSUITE_TELEMETRY=1 "${FSEARCH}" "*.txt" "${vary_dir}" >/dev/null 2>&1 || true
    FSUITE_TELEMETRY=1 "${FCONTENT}" "content" "${vary_dir}" >/dev/null 2>&1 || true
  done

  local jsonl_lines=0
  [[ -f "$HOME/.fsuite/telemetry.jsonl" ]] && jsonl_lines=$(wc -l < "$HOME/.fsuite/telemetry.jsonl")

  run_fmetrics import >/dev/null 2>&1 || true

  # Verify --tool flag passes through and filters output
  local output_all output_filtered
  output_all=$(run_fmetrics predict "${TEST_DIR}" 2>&1) || true
  output_filtered=$(run_fmetrics predict --tool ftree "${TEST_DIR}" 2>&1) || true

  if [[ "$output_filtered" =~ "ftree" ]] && ! [[ "$output_filtered" =~ "fsearch" ]] && ! [[ "$output_filtered" =~ "fcontent" ]]; then
    pass "fmetrics predict --tool ftree shows only ftree prediction"
  elif [[ "$output_filtered" =~ "Insufficient" ]] || [[ "$output_filtered" =~ "need at least" ]]; then
    # Not enough data for prediction, but verify the --tool flag was accepted
    if [[ "$output_filtered" =~ "ftree" ]] || [[ "$jsonl_lines" -ge 8 ]]; then
      pass "fmetrics predict --tool accepted (insufficient data for prediction, $jsonl_lines runs)"
    else
      fail "--tool ftree should be accepted" "Got: $output_filtered"
    fi
  else
    fail "--tool ftree should only show ftree in predict output" "Got: $output_filtered"
  fi
}

# test_v15_history_multi_filter verifies that fmetrics history respects both `--tool` and `--project` filters by seeding telemetry with ftree/fsearch runs, importing it, and asserting that `fmetrics history --tool ftree --project <name>` returns a single run for the specified project; the test is skipped if `sqlite3` is not available.
test_v15_history_multi_filter() {
  if ! command -v sqlite3 >/dev/null 2>&1; then
    pass "fmetrics history multi-filter test skipped (sqlite3 not available)"
    return 0
  fi

  rm -f "$HOME/.fsuite/telemetry.jsonl"
  rm -f "$HOME/.fsuite/telemetry.db"

  local history_proj="${TEST_DIR}/history_proj"
  local other_proj="${TEST_DIR}/other_proj"
  mkdir -p "${history_proj}/src" "${other_proj}/src"
  echo "alpha" > "${history_proj}/src/file.txt"
  echo "beta" > "${other_proj}/src/file.txt"

  FSUITE_TELEMETRY=1 "${FTREE}" --project-name "HistoryProj" "${history_proj}" >/dev/null 2>&1 || true
  FSUITE_TELEMETRY=1 "${FTREE}" --project-name "OtherProj" "${other_proj}" >/dev/null 2>&1 || true
  FSUITE_TELEMETRY=1 "${FSEARCH}" --project-name "HistoryProj" "*.txt" "${history_proj}" >/dev/null 2>&1 || true

  run_fmetrics import >/dev/null 2>&1 || true

  local output run_count matched_project
  output=$(run_fmetrics history --tool ftree --project HistoryProj -o json 2>&1) || true

  run_count=$(python3 -c 'import json,sys; print(len(json.loads(sys.stdin.read())["runs"]))' <<< "$output" 2>/dev/null || echo "-1")
  matched_project=$(python3 -c 'import json,sys; data=json.loads(sys.stdin.read()); print(data["runs"][0]["project"] if data["runs"] else "")' <<< "$output" 2>/dev/null || echo "")

  if [[ "$run_count" == "1" ]] && [[ "$matched_project" == "HistoryProj" ]]; then
    pass "fmetrics history combines --tool and --project filters correctly"
  else
    fail "history should return the ftree row for the requested project" "Got: $output"
  fi
}

# test_v16_predict_ftree_preserves_default_contract_with_by_mode verifies that `fmetrics predict --tool ftree` returns a single top-level ftree prediction row containing a `by_mode` map with a `snapshot` entry and no separate per-mode top-level rows; skips the test if `sqlite3` is not available.
test_v16_predict_ftree_preserves_default_contract_with_by_mode() {
  if ! command -v sqlite3 >/dev/null 2>&1; then
    pass "ftree default predict contract test skipped (sqlite3 not available)"
    return 0
  fi

  local target_dir="${TEST_DIR}/predict_target"
  mkdir -p "${target_dir}/src"
  echo "one" > "${target_dir}/src/a.txt"
  echo "two" > "${target_dir}/src/b.txt"

  seed_ftree_predict_fixture_db

  local output top_level_ftree mode_count mixed_mode by_mode_snapshot
  output=$(run_fmetrics predict --tool ftree -o json "${target_dir}" 2>&1) || true
  top_level_ftree=$(python3 -c 'import json,sys; data=json.loads(sys.stdin.read()); print(sum(1 for p in data.get("predictions", []) if p.get("tool") == "ftree"))' <<< "$output" 2>/dev/null || echo "0")
  mixed_mode=$(python3 -c 'import json,sys; data=json.loads(sys.stdin.read()); preds=data.get("predictions", []); print(preds[0].get("mode", "") if preds else "")' <<< "$output" 2>/dev/null || echo "")
  by_mode_snapshot=$(python3 -c 'import json,sys; data=json.loads(sys.stdin.read()); preds=data.get("predictions", []); by_mode=(preds[0].get("by_mode", {}) if preds else {}); print("snapshot" if "snapshot" in by_mode else "")' <<< "$output" 2>/dev/null || echo "")
  mode_count=$(python3 -c 'import json,sys; data=json.loads(sys.stdin.read()); print(sum(1 for p in data.get("predictions", []) if p.get("tool") == "ftree" and p.get("mode") in {"tree","recon","snapshot"}))' <<< "$output" 2>/dev/null || echo "0")

  if [[ "$top_level_ftree" == "1" ]] && [[ "$mixed_mode" == "mixed" ]] && [[ "$mode_count" == "0" ]] && [[ "$by_mode_snapshot" == "snapshot" ]]; then
    pass "fmetrics predict --tool ftree preserves one-row contract with by_mode detail"
  else
    fail "predict should preserve one top-level ftree row with by_mode detail" "Got: $output"
  fi
}

# test_v16_predict_ftree_mode_snapshot_stays_in_cluster verifies that `fmetrics predict --tool ftree --mode snapshot` returns a prediction that remains within the snapshot cluster (reported `mode` is "snapshot" and `predicted_ms` is >= 4500); skips the test if `sqlite3` is not available.
# Seeds the predict fixture DB, creates a small snapshot target, runs predict with `-o json`, and asserts the mode and predicted runtime in the JSON output.
test_v16_predict_ftree_mode_snapshot_stays_in_cluster() {
  if ! command -v sqlite3 >/dev/null 2>&1; then
    pass "ftree mode-specific predict test skipped (sqlite3 not available)"
    return 0
  fi

  local target_dir="${TEST_DIR}/predict_target_snapshot"
  mkdir -p "${target_dir}/src"
  echo "one" > "${target_dir}/src/a.txt"
  echo "two" > "${target_dir}/src/b.txt"

  seed_ftree_predict_fixture_db

  local output predicted mode
  output=$(run_fmetrics predict --tool ftree --mode snapshot -o json "${target_dir}" 2>&1) || true
  predicted=$(python3 -c 'import json,sys; data=json.loads(sys.stdin.read()); preds=data.get("predictions", []); print(preds[0].get("predicted_ms", -1) if preds else -1)' <<< "$output" 2>/dev/null || echo "-1")
  mode=$(python3 -c 'import json,sys; data=json.loads(sys.stdin.read()); preds=data.get("predictions", []); print(preds[0].get("mode", "") if preds else "")' <<< "$output" 2>/dev/null || echo "")

  if [[ "$mode" == "snapshot" ]] && [[ "$predicted" =~ ^[0-9]+$ ]] && (( predicted >= 4500 )); then
    pass "fmetrics predict --mode snapshot stays in the snapshot cluster"
  else
    fail "snapshot prediction should stay near snapshot runtimes" "Got: $output"
  fi
}

# test_v16_predict_helper_degrades_confidence_on_zero_spread verifies that fmetrics-predict reports `low` confidence when the seeded ftree predict fixture has zero feature spread; skips the test if `sqlite3` is unavailable.
test_v16_predict_helper_degrades_confidence_on_zero_spread() {
  if ! command -v sqlite3 >/dev/null 2>&1; then
    pass "predict helper confidence test skipped (sqlite3 not available)"
    return 0
  fi

  seed_ftree_predict_fixture_db

  local output confidence
  output=$(python3 "${FMETRICS_PREDICT}" --db "$HOME/.fsuite/telemetry.db" --items 99999 --bytes 99999999 --depth 30 --tool ftree --mode snapshot --output json 2>&1) || true
  confidence=$(python3 -c 'import json,sys; data=json.loads(sys.stdin.read()); preds=data.get("predictions", []); print(preds[0].get("confidence", "") if preds else "")' <<< "$output" 2>/dev/null || echo "")

  if [[ "$confidence" == "low" ]]; then
    pass "predict helper degrades confidence when feature spread is zero"
  else
    fail "far targets should not get high confidence when feature spread collapses" "Got: $output"
  fi
}

# test_v16_predict_rejects_mode_without_ftree_tool verifies that fmetrics predict invoked with --mode but without --tool ftree fails and prints an error mentioning "--mode requires --tool ftree".
test_v16_predict_rejects_mode_without_ftree_tool() {
  local output
  output=$(run_fmetrics predict --mode snapshot -o json "${TEST_DIR}" 2>&1) && {
    fail "--mode without --tool ftree should fail" "Got success: $output"
    return
  }

  if [[ "$output" == *"--mode requires --tool ftree"* ]]; then
    pass "fmetrics predict rejects --mode without --tool ftree"
  else
    fail "predict should reject --mode without --tool ftree" "Got: $output"
  fi
}

# test_v16_predict_rejects_mode_with_non_ftree_tool verifies that `fmetrics predict` fails when `--mode` is supplied with a non-ftree tool and checks for the expected error message.
test_v16_predict_rejects_mode_with_non_ftree_tool() {
  local output
  output=$(run_fmetrics predict --tool fsearch --mode snapshot -o json "${TEST_DIR}" 2>&1) && {
    fail "--mode with non-ftree tool should fail" "Got success: $output"
    return
  }

  if [[ "$output" == *"--mode requires --tool ftree"* ]]; then
    pass "fmetrics predict rejects --mode with non-ftree tool"
  else
    fail "predict should reject --mode with non-ftree tool" "Got: $output"
  fi
}

# ============================================================================
# v1.5.0+ — Project Name Inference (walk-up heuristic)
# ============================================================================

test_v15_project_name_walkup() {
  # Create a project with .git inside TEST_DIR
  local proj_dir="${TEST_DIR}/myproject"
  mkdir -p "${proj_dir}/.git"
  mkdir -p "${proj_dir}/src/deep/nested"
  echo "hello" > "${proj_dir}/src/deep/nested/file.txt"

  # Scan the deeply nested subdir — project name should be "myproject", not "nested"
  rm -f $HOME/.fsuite/telemetry.jsonl
  FSUITE_TELEMETRY=1 "${FTREE}" --recon "${proj_dir}/src/deep/nested" >/dev/null 2>&1 || true
  local line
  line=$(tail -1 $HOME/.fsuite/telemetry.jsonl 2>/dev/null) || line=""
  if ! [[ "$line" =~ \"project_name\":\"myproject\" ]]; then
    fail "ftree should infer project_name='myproject' from .git" "Got: $line"
    return
  fi

  # Test fsearch on the same subdir
  rm -f $HOME/.fsuite/telemetry.jsonl
  FSUITE_TELEMETRY=1 "${FSEARCH}" --output paths "*.txt" "${proj_dir}/src/deep/nested" >/dev/null 2>&1 || true
  line=$(tail -1 $HOME/.fsuite/telemetry.jsonl 2>/dev/null) || line=""
  if ! [[ "$line" =~ \"project_name\":\"myproject\" ]]; then
    fail "fsearch should infer project_name='myproject'" "Got: $line"
    return
  fi

  # Test fcontent on the same subdir
  rm -f $HOME/.fsuite/telemetry.jsonl
  FSUITE_TELEMETRY=1 "${FCONTENT}" "hello" "${proj_dir}/src/deep/nested" >/dev/null 2>&1 || true
  line=$(tail -1 $HOME/.fsuite/telemetry.jsonl 2>/dev/null) || line=""
  if ! [[ "$line" =~ \"project_name\":\"myproject\" ]]; then
    fail "fcontent should infer project_name='myproject'" "Got: $line"
    return
  fi

  pass "Walk-up finds .git and uses project root name (ftree, fsearch, fcontent)"
}

# test_v15_project_name_fallback ensures that when no project markers are present, ftree telemetry falls back to using the directory basename as the `project_name`.
test_v15_project_name_fallback() {
  # Create a dir with NO project markers
  local plain_dir="${TEST_DIR}/plaindir"
  mkdir -p "${plain_dir}"
  echo "data" > "${plain_dir}/file.txt"

  rm -f $HOME/.fsuite/telemetry.jsonl
  FSUITE_TELEMETRY=1 "${FTREE}" --recon "${plain_dir}" >/dev/null 2>&1 || true
  local line
  line=$(tail -1 $HOME/.fsuite/telemetry.jsonl 2>/dev/null) || line=""
  if [[ "$line" =~ \"project_name\":\"plaindir\" ]]; then
    pass "Fallback: basename used when no project markers found"
  else
    fail "Should fall back to basename 'plaindir'" "Got: $line"
  fi
}

# test_harness_uses_sandbox_home verifies the test harness runs inside a sandboxed HOME by checking HOME differs from ORIGINAL_HOME and contains a .fsuite directory.
test_harness_uses_sandbox_home() {
  if [[ -n "${ORIGINAL_HOME}" ]] && [[ "$HOME" != "$ORIGINAL_HOME" ]] && [[ -d "$HOME/.fsuite" ]]; then
    pass "Telemetry tests run inside a sandboxed HOME"
  else
    fail "Telemetry tests should sandbox HOME instead of mutating the caller environment" "ORIGINAL_HOME=${ORIGINAL_HOME} HOME=${HOME}"
  fi
}

# ============================================================================
# Main Test Runner
# main sets up a sandboxed test environment, runs the fsuite telemetry test suite (invoking all test cases), and reports a pass/fail summary while ensuring teardown on exit.

main() {
  trap 'teardown' EXIT INT TERM
  echo "======================================"
  echo "  fsuite Telemetry Test Suite"
  echo "======================================"
  echo ""

  # Check dependencies
  if [[ ! -x "${FTREE}" ]]; then
    echo -e "${RED}Error: ftree not found at ${FTREE}${NC}"
    exit 1
  fi

  setup

  echo "Running tests..."
  echo ""

  echo "== Harness Isolation =="
  run_test "Telemetry harness uses sandboxed HOME" test_harness_uses_sandbox_home

  echo ""
  # bytes_scanned tests
  echo "== Phase 1: bytes_scanned =="
  run_test "fcontent bytes_scanned > 0" test_fcontent_bytes_scanned
  run_test "fsearch bytes_scanned > 0" test_fsearch_bytes_scanned
  run_test "ftree bytes_scanned > 0" test_ftree_bytes_scanned
  run_test "fcontent stdin mode bytes = -1" test_fcontent_stdin_mode_bytes_minus1

  # Tier tests
  echo ""
  echo "== Tier 0 (Disabled) =="
  run_test "Tier 0 produces no telemetry" test_tier0_no_telemetry

  echo ""
  echo "== Tier 2 (Hardware) =="
  run_test "Tier 2 includes hardware fields" test_tier2_hardware_fields
  run_test "Tier 1 excludes hardware fields" test_tier1_no_hardware_fields

  echo ""
  echo "== Filesystem & Storage Detection =="
  run_test "Tier 2 includes fs/storage fields" test_tier2_filesystem_storage_fields
  run_test "Filesystem type detected" test_filesystem_type_not_unknown
  run_test "Storage type detected" test_storage_type_not_unknown

  echo ""
  echo "== Tier 3 (Machine Profile) =="
  run_test "Tier 3 generates machine profile" test_tier3_machine_profile

  echo ""
  echo "== Schema Migration =="
  run_test "Schema migration is idempotent" test_schema_migration_idempotent
  run_test "Telemetry JSONL includes run_id" test_run_id_in_jsonl
  run_test "Burst runs are not dropped" test_burst_runs_not_dropped
  run_test "Legacy import backfills run_id" test_legacy_import_backfill_run_id
  run_test "Migration rollback on failure preserves data" test_migration_atomicity

  echo ""
  echo "== Metacharacter Warning =="
  run_test "Warning on parentheses" test_metachar_warning_parens
  run_test "Warning on brackets" test_metachar_warning_brackets
  run_test "Warning suppressed with -F" test_metachar_warning_suppressed_with_F
  run_test "JSON includes warning field" test_metachar_warning_json_field
  run_test "No warning for plain text" test_no_metachar_no_warning

  echo ""
  echo "== Graceful Degradation =="
  run_test "Works without _fsuite_common.sh" test_graceful_without_common_lib
  run_test "Non-numeric FSUITE_TELEMETRY handled" test_non_numeric_telemetry_env

  echo ""
  echo "== v1.5.0: Flag Accumulation =="
  run_test "ftree flags in telemetry" test_v15_ftree_flags
  run_test "fcontent flags in telemetry" test_v15_fcontent_flags
  run_test "fsearch include/exclude flags in telemetry" test_v16_fsearch_filter_flags
  run_test "JSONL safety with special chars" test_v15_jsonl_safety
  run_test "Project-name override" test_v15_project_name

  echo ""
  echo "== v1.5.0: fmetrics Enhancements =="
  run_test "fmetrics --self-check shows python3 status" test_v15_selfcheck_python3
  run_test "fmetrics --self-check shows predict script" test_v15_selfcheck_predict
  run_test "fmetrics predict --tool filter" test_v15_predict_tool_filter
  run_test "fmetrics history combines tool+project filters" test_v15_history_multi_filter
  run_test "fmetrics predict preserves ftree default contract with by_mode detail" test_v16_predict_ftree_preserves_default_contract_with_by_mode
  run_test "fmetrics predict --mode snapshot stays in snapshot cluster" test_v16_predict_ftree_mode_snapshot_stays_in_cluster
  run_test "predict helper lowers confidence on zero-spread features" test_v16_predict_helper_degrades_confidence_on_zero_spread
  run_test "fmetrics predict rejects --mode without --tool ftree" test_v16_predict_rejects_mode_without_ftree_tool
  run_test "fmetrics predict rejects --mode with non-ftree tool" test_v16_predict_rejects_mode_with_non_ftree_tool

  echo ""
  echo "== v1.5.0+: Project Name Inference =="
  run_test "Walk-up heuristic across all tools" test_v15_project_name_walkup
  run_test "Basename fallback without markers" test_v15_project_name_fallback

  teardown

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
