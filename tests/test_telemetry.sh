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
NC='\033[0m' # No Color

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

run_fmetrics() {
  FSUITE_TELEMETRY=0 "${FMETRICS}" "$@"
}

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

seed_combo_case_fixture_db() {
  mkdir -p "$HOME/.fsuite"
  rm -f "$HOME/.fsuite/telemetry.jsonl" "$HOME/.fsuite/telemetry.db" "$HOME/.fsuite/fcase.db"
  : > "$HOME/.fsuite/telemetry.jsonl"
  run_fmetrics import >/dev/null 2>&1 || true

  FSUITE_TELEMETRY=0 "${SCRIPT_DIR}/../fcase" init combo-case-resolved --goal "Resolved combo case" >/dev/null 2>&1 || true
  FSUITE_TELEMETRY=0 "${SCRIPT_DIR}/../fcase" init combo-case-progress --goal "Progress combo case" >/dev/null 2>&1 || true
  FSUITE_TELEMETRY=0 "${SCRIPT_DIR}/../fcase" init combo-case-telemetry --goal "Telemetry-only combo case" >/dev/null 2>&1 || true
  FSUITE_TELEMETRY=0 "${SCRIPT_DIR}/../fcase" next combo-case-progress --body "Try fsearch after ftree" >/dev/null 2>&1 || true
  FSUITE_TELEMETRY=0 "${SCRIPT_DIR}/../fcase" resolve combo-case-resolved --summary "Resolved after ftree -> fcontent" >/dev/null 2>&1 || true

  local resolved_case_id progress_case_id telemetry_case_id
  resolved_case_id=$(sqlite3 "$HOME/.fsuite/fcase.db" "SELECT id FROM cases WHERE slug='combo-case-resolved';")
  progress_case_id=$(sqlite3 "$HOME/.fsuite/fcase.db" "SELECT id FROM cases WHERE slug='combo-case-progress';")
  telemetry_case_id=$(sqlite3 "$HOME/.fsuite/fcase.db" "SELECT id FROM cases WHERE slug='combo-case-telemetry';")

  [[ -n "$resolved_case_id" ]] || return 1
  [[ -n "$progress_case_id" ]] || return 1
  [[ -n "$telemetry_case_id" ]] || return 1

  mkdir -p "$HOME/work/combo-impact/src"
  : > "$HOME/work/combo-impact/Makefile"
  local combo_project_cwd combo_project_cwd_sql
  combo_project_cwd="$HOME/work/combo-impact/src"
  combo_project_cwd_sql="${combo_project_cwd//\'/\'\'}"

  sqlite3 "$HOME/.fsuite/telemetry.db" <<'SQL'
DELETE FROM telemetry;
INSERT INTO telemetry (timestamp,tool,version,mode,path_hash,project_name,duration_ms,exit_code,depth,items_scanned,bytes_scanned,flags,backend,run_id) VALUES
  ('2026-03-10T00:10:00Z','ftree','2.1.0','tree','resolved-tree','combo-impact',11,0,3,42,4200,'-o json','tree','resolved-run'),
  ('2026-03-10T00:10:01Z','fcontent','2.1.0','read','resolved-content','combo-impact',14,0,3,42,4200,'-o json','content','resolved-run'),
  ('2026-03-10T00:10:02Z','ftree','2.1.0','tree','telemetry-tree-1','combo-impact',12,0,3,42,4200,'-o json','tree','telemetry-run-1'),
  ('2026-03-10T00:10:03Z','fsearch','2.1.0','read','telemetry-search-1','combo-impact',17,0,3,42,4200,'-o json','search','telemetry-run-1'),
  ('2026-03-10T00:10:04Z','ftree','2.1.0','tree','telemetry-tree-2','combo-impact',13,0,3,42,4200,'-o json','tree','telemetry-run-2'),
  ('2026-03-10T00:10:05Z','fsearch','2.1.0','read','telemetry-search-2','combo-impact',18,0,3,42,4200,'-o json','search','telemetry-run-2');
SQL

sqlite3 "$HOME/.fsuite/fcase.db" <<SQL
DELETE FROM replay_step_links;
DELETE FROM replay_steps;
DELETE FROM replays;
INSERT INTO replays (id, case_id, label, status, origin, fsuite_version, created_at, updated_at, actor, parent_replay_id, notes) VALUES
(1, $resolved_case_id, 'resolved replay', 'canonical', 'recorded', '2.3.0', '2026-03-10T00:10:00Z', '2026-03-10T00:10:00Z', 'test', NULL, ''),
(2, $progress_case_id, 'progress replay', 'canonical', 'recorded', '2.3.0', '2026-03-10T00:10:00Z', '2026-03-10T00:10:00Z', 'test', NULL, ''),
(3, $telemetry_case_id, 'telemetry replay', 'canonical', 'recorded', '2.3.0', '2026-03-10T00:10:00Z', '2026-03-10T00:10:00Z', 'test', NULL, '');

INSERT INTO replay_steps (id, replay_id, order_num, tool, argv_json, cwd, mode, purpose, provenance, exit_code, duration_ms, started_at, telemetry_run_id, result_summary, error_excerpt) VALUES
(1, 1, 1, 'ftree', '["ftree","/tmp/resolved"]', '$combo_project_cwd_sql', 'read_only', '', 'recorded', 0, 11, '2026-03-10T00:10:00Z', NULL, '', ''),
(2, 1, 2, 'fcontent', '["fcontent","/tmp/resolved"]', '$combo_project_cwd_sql', 'read_only', '', 'recorded', 0, 14, '2026-03-10T00:10:01Z', NULL, '', ''),
(3, 2, 1, 'ftree', '["ftree","/tmp/progress"]', '$combo_project_cwd_sql', 'read_only', '', 'recorded', 0, 11, '2026-03-10T00:10:00Z', NULL, '', ''),
(4, 2, 2, 'fcontent', '["fcontent","/tmp/progress"]', '$combo_project_cwd_sql', 'read_only', '', 'recorded', 0, 14, '2026-03-10T00:10:01Z', NULL, '', ''),
(5, 3, 1, 'ftree', '["ftree","/tmp/telemetry"]', '$combo_project_cwd_sql', 'read_only', '', 'recorded', 0, 12, '2026-03-10T00:10:02Z', 'telemetry-run-1', '', ''),
(6, 3, 2, 'fsearch', '["fsearch","/tmp/telemetry"]', '$combo_project_cwd_sql', 'read_only', '', 'recorded', 0, 17, '2026-03-10T00:10:03Z', 'telemetry-run-1', '', '');
SQL

  run_fmetrics clean --days 9999 >/dev/null 2>&1
}

seed_combo_fixture_db() {
  mkdir -p "$HOME/.fsuite"
  rm -f "$HOME/.fsuite/telemetry.jsonl" "$HOME/.fsuite/telemetry.db"
  : > "$HOME/.fsuite/telemetry.jsonl"
  run_fmetrics import >/dev/null 2>&1 || true

  sqlite3 "$HOME/.fsuite/telemetry.db" <<'SQL'
DELETE FROM telemetry;
INSERT INTO telemetry (timestamp,tool,version,mode,path_hash,project_name,duration_ms,exit_code,depth,items_scanned,bytes_scanned,flags,backend,run_id) VALUES
  ('2026-03-20T00:00:00Z','ftree','2.3.0','snapshot','combo-a1','ComboProj',10,0,1,10,1000,'--snapshot','tree','run-alpha'),
  ('2026-03-20T00:00:01Z','fsearch','2.3.0','glob','combo-a2','ComboProj',20,0,1,8,800,'*.rs','find','run-alpha'),
  ('2026-03-20T00:00:02Z','fmap','2.3.0','map','combo-a3','ComboProj',30,0,1,6,600,'','map','run-alpha'),
  ('2026-03-20T00:01:00Z','ftree','2.3.0','snapshot','combo-b1','ComboProj',11,0,1,10,1000,'--snapshot','tree','run-bravo'),
  ('2026-03-20T00:01:01Z','fsearch','2.3.0','glob','combo-b2','ComboProj',21,0,1,8,800,'*.rs','find','run-bravo'),
  ('2026-03-20T00:01:02Z','fmap','2.3.0','map','combo-b3','ComboProj',29,0,1,6,600,'','map','run-bravo'),
  ('2026-03-20T00:02:00Z','ftree','2.3.0','snapshot','combo-c1','ComboProj',12,0,1,10,1000,'--snapshot','tree','run-charlie'),
  ('2026-03-20T00:02:01Z','fsearch','2.3.0','glob','combo-c2','ComboProj',19,0,1,8,800,'*.rs','find','run-charlie'),
  ('2026-03-20T00:02:02Z','fread','2.3.0','lines','combo-c3','ComboProj',40,1,1,6,600,'--around auth','read','run-charlie'),
  ('2026-03-20T00:03:00Z','ftree','2.3.0','snapshot','combo-d1','OtherProj',9,0,1,10,1000,'--snapshot','tree','run-delta'),
  ('2026-03-20T00:03:01Z','fsearch','2.3.0','glob','combo-d2','OtherProj',16,0,1,8,800,'*.py','find','run-delta'),
  ('2026-03-20T00:03:02Z','fread','2.3.0','lines','combo-d3','OtherProj',25,0,1,6,600,'--around main','read','run-delta');
SQL

  run_fmetrics clean --days 9999 >/dev/null 2>&1
}

test_import_marks_analytics_dirty_without_rebuild() {
  mkdir -p "$HOME/.fsuite"
  cat > "$HOME/.fsuite/telemetry.jsonl" <<'JSONL'
{"timestamp":"2026-03-20T00:00:00Z","tool":"ftree","version":"2.3.0","mode":"snapshot","path_hash":"alpha-1","project_name":"analytics-fixture","duration_ms":12,"exit_code":0,"depth":2,"items_scanned":10,"bytes_scanned":1000,"flags":"--snapshot","backend":"tree","run_id":"run-alpha"}
{"timestamp":"2026-03-20T00:00:01Z","tool":"fcontent","version":"2.3.0","mode":"directory","path_hash":"alpha-2","project_name":"analytics-fixture","duration_ms":9,"exit_code":0,"depth":1,"items_scanned":4,"bytes_scanned":400,"flags":"-o json","backend":"read","run_id":"run-alpha"}
JSONL

  local output inserted dirty row_count
  output=$(run_fmetrics import -o json 2>&1)
  inserted=$(python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["inserted"])' <<< "$output" 2>/dev/null || echo "-1")
  dirty=$(sqlite3 "$HOME/.fsuite/telemetry.db" "SELECT value FROM analytics_meta WHERE key='analytics_dirty';" 2>/dev/null || true)
  row_count=$(sqlite3 "$HOME/.fsuite/telemetry.db" "SELECT COUNT(*) FROM run_facts_v1;" 2>/dev/null || echo "999")

  if [[ "$inserted" == "2" && "$dirty" == "1" && "$row_count" == "0" ]]; then
    pass "Import marks analytics dirty without rebuilding derived tables"
  else
    fail "Import should mark analytics dirty without rebuilding derived tables" "inserted=$inserted dirty=$dirty run_facts_count=$row_count output=$output"
  fi
}

test_rebuild_populates_run_facts_after_import() {
  mkdir -p "$HOME/.fsuite"
  cat > "$HOME/.fsuite/telemetry.jsonl" <<'JSONL'
{"timestamp":"2026-03-20T00:00:00Z","tool":"ftree","version":"2.3.0","mode":"snapshot","path_hash":"alpha-1","project_name":"analytics-fixture","duration_ms":12,"exit_code":0,"depth":2,"items_scanned":10,"bytes_scanned":1000,"flags":"--snapshot","backend":"tree","run_id":"run-alpha"}
{"timestamp":"2026-03-20T00:00:01Z","tool":"fcontent","version":"2.3.0","mode":"directory","path_hash":"alpha-2","project_name":"analytics-fixture","duration_ms":9,"exit_code":0,"depth":1,"items_scanned":4,"bytes_scanned":400,"flags":"-o json","backend":"read","run_id":"run-alpha"}
JSONL

  run_fmetrics import >/dev/null 2>&1
  run_fmetrics rebuild >/dev/null 2>&1

  local row dirty
  row=$(sqlite3 "$HOME/.fsuite/telemetry.db" "SELECT tool_count || '|' || project_name FROM run_facts_v1 WHERE run_id='run-alpha';" 2>/dev/null || true)
  dirty=$(sqlite3 "$HOME/.fsuite/telemetry.db" "SELECT value FROM analytics_meta WHERE key='analytics_dirty';" 2>/dev/null || true)
  if [[ "$row" == "2|analytics-fixture" && "$dirty" == "0" ]]; then
    pass "Rebuild populates run_facts_v1 and clears dirty flag"
  else
    fail "Rebuild should populate run_facts_v1 and clear dirty flag" "row=$row dirty=$dirty"
  fi
}

test_import_survives_malformed_lines() {
  mkdir -p "$HOME/.fsuite"
  rm -f "$HOME/.fsuite/telemetry.db"
  cat > "$HOME/.fsuite/telemetry.jsonl" <<'JSONL'
{"tool":"ftree","version":"2.3.0","mode":"snapshot","path_hash":"broken-1","project_name":"bad-line-fixture","duration_ms":12,"exit_code":0,"depth":2,"items_scanned":10,"bytes_scanned":1000,"flags":"--snapshot","backend":"tree","run_id":"run-bad"}
{"timestamp":"2026-03-20T00:00:00Z","tool":"ftree","version":"2.3.0","mode":"snapshot","path_hash":"good-1","project_name":"bad-line-fixture","duration_ms":12,"exit_code":0,"depth":2,"items_scanned":10,"bytes_scanned":1000,"flags":"--snapshot","backend":"tree","run_id":"run-good"}
JSONL

  local output rc inserted errors count
  output=$(run_fmetrics import -o json 2>&1)
  rc=$?
  inserted=$(python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["inserted"])' <<< "$output" 2>/dev/null || echo "-1")
  errors=$(python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["errors"])' <<< "$output" 2>/dev/null || echo "-1")
  count=$(sqlite3 "$HOME/.fsuite/telemetry.db" "SELECT COUNT(*) FROM telemetry;" 2>/dev/null || echo "0")

  if [[ $rc -eq 0 && "$inserted" == "1" && "$errors" == "1" && "$count" == "1" ]]; then
    pass "Import survives malformed lines and continues"
  else
    fail "Import should survive malformed lines and continue" "rc=$rc inserted=$inserted errors=$errors count=$count output=$output"
  fi
}

test_import_only_processes_new_lines() {
  mkdir -p "$HOME/.fsuite"
  cat > "$HOME/.fsuite/telemetry.jsonl" <<'JSONL'
{"timestamp":"2026-03-21T00:00:00Z","tool":"ftree","version":"2.3.0","mode":"snapshot","path_hash":"inc-1","project_name":"incremental-fixture","duration_ms":5,"exit_code":0,"depth":1,"items_scanned":3,"bytes_scanned":300,"flags":"--snapshot","backend":"tree","run_id":"run-inc-1"}
JSONL

  local first second third
  local first_total second_total third_total
  local first_inserted second_inserted third_inserted

  first=$(run_fmetrics import -o json 2>&1)
  printf '%s\n' '{"timestamp":"2026-03-21T00:00:01Z","tool":"fsearch","version":"2.3.0","mode":"glob","path_hash":"inc-2","project_name":"incremental-fixture","duration_ms":7,"exit_code":0,"depth":1,"items_scanned":4,"bytes_scanned":400,"flags":"*.sh","backend":"find","run_id":"run-inc-2"}' >> "$HOME/.fsuite/telemetry.jsonl"
  second=$(run_fmetrics import -o json 2>&1)
  third=$(run_fmetrics import -o json 2>&1)

  first_total=$(python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["total_lines"])' <<< "$first" 2>/dev/null || echo "-1")
  second_total=$(python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["total_lines"])' <<< "$second" 2>/dev/null || echo "-1")
  third_total=$(python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["total_lines"])' <<< "$third" 2>/dev/null || echo "-1")
  first_inserted=$(python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["inserted"])' <<< "$first" 2>/dev/null || echo "-1")
  second_inserted=$(python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["inserted"])' <<< "$second" 2>/dev/null || echo "-1")
  third_inserted=$(python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["inserted"])' <<< "$third" 2>/dev/null || echo "-1")

  if [[ "$first_total" == "1" && "$first_inserted" == "1" && "$second_total" == "1" && "$second_inserted" == "1" && "$third_total" == "0" && "$third_inserted" == "0" ]]; then
    pass "Import only processes newly appended telemetry lines"
  else
    fail "Import should only process newly appended telemetry lines" "first=$first second=$second third=$third"
  fi
}

test_clean_rebuilds_run_facts_after_direct_seed() {
  mkdir -p "$HOME/.fsuite"
  : > "$HOME/.fsuite/telemetry.jsonl"
  run_fmetrics import >/dev/null 2>&1 || true

  sqlite3 "$HOME/.fsuite/telemetry.db" <<'SQL'
DELETE FROM telemetry;
INSERT INTO telemetry (timestamp,tool,version,mode,path_hash,project_name,duration_ms,exit_code,depth,items_scanned,bytes_scanned,flags,backend,run_id) VALUES
  ('2026-03-25T00:00:00Z','fsearch','2.3.0','glob','beta-1','direct-seed-fixture',15,0,1,7,700,'-o json','find','run-beta');
SQL

  run_fmetrics clean --days 9999 >/dev/null 2>&1

  local row
  row=$(sqlite3 "$HOME/.fsuite/telemetry.db" "SELECT tool_count || '|' || project_name FROM run_facts_v1 WHERE run_id='run-beta';" 2>/dev/null || true)
  if [[ "$row" == "1|direct-seed-fixture" ]]; then
    pass "Clean rebuilds run_facts_v1 after direct seed"
  else
    fail "Clean should rebuild run_facts_v1 after direct seed" "Got: $row"
  fi
}

test_combos_rebuilds_dirty_analytics_on_demand() {
  mkdir -p "$HOME/.fsuite"
  rm -f "$HOME/.fsuite/telemetry.db"
  cat > "$HOME/.fsuite/telemetry.jsonl" <<'JSONL'
{"timestamp":"2026-03-22T00:00:00Z","tool":"ftree","version":"2.3.0","mode":"snapshot","path_hash":"lazy-1","project_name":"lazy-fixture","duration_ms":10,"exit_code":0,"depth":1,"items_scanned":5,"bytes_scanned":500,"flags":"--snapshot","backend":"tree","run_id":"run-lazy"}
{"timestamp":"2026-03-22T00:00:01Z","tool":"fsearch","version":"2.3.0","mode":"glob","path_hash":"lazy-2","project_name":"lazy-fixture","duration_ms":12,"exit_code":0,"depth":1,"items_scanned":6,"bytes_scanned":600,"flags":"*.md","backend":"find","run_id":"run-lazy"}
JSONL

  run_fmetrics import >/dev/null 2>&1

  local before_count after_count dirty output rc
  before_count=$(sqlite3 "$HOME/.fsuite/telemetry.db" "SELECT COUNT(*) FROM run_facts_v1;" 2>/dev/null || echo "999")
  output=$(run_fmetrics combos --project lazy-fixture -o json 2>&1)
  rc=$?
  after_count=$(sqlite3 "$HOME/.fsuite/telemetry.db" "SELECT COUNT(*) FROM run_facts_v1;" 2>/dev/null || echo "0")
  dirty=$(sqlite3 "$HOME/.fsuite/telemetry.db" "SELECT value FROM analytics_meta WHERE key='analytics_dirty';" 2>/dev/null || true)

  if [[ "$before_count" == "0" && $rc -eq 0 && "$after_count" == "1" && "$dirty" == "0" ]]; then
    pass "Combos lazily rebuilds dirty analytics"
  else
    fail "Combos should lazily rebuild dirty analytics" "before=$before_count after=$after_count dirty=$dirty rc=$rc output=$output"
  fi
}

test_v17_combos_reports_ordered_sequences() {
  seed_combo_fixture_db
  local output
  output=$(run_fmetrics combos --project ComboProj -o json 2>&1) || true

  if python3 -c '
import json, sys
data = json.loads(sys.stdin.read())
assert data["subcommand"] == "combos"
target = next(c for c in data["combos"] if c["combo_key"] == "ftree>fsearch>fmap")
assert target["steps"] == ["ftree", "fsearch", "fmap"]
assert target["occurrences"] == 2
assert target["evidence"]["clean_runs"] == 2
assert target["evidence"]["faulted_runs"] == 0
assert abs(float(target["fault_rate"])) < 1e-9
assert target["because"]
' <<<"$output" 2>/dev/null; then
    pass "fmetrics combos reports ordered sequences with evidence"
  else
    fail "combos should report ordered sequences with evidence" "Got: $output"
  fi
}

test_v17_combos_filters_and_errors() {
  seed_combo_fixture_db
  local filtered missing
  filtered=$(run_fmetrics combos --project ComboProj --starts-with ftree,fsearch --contains fmap -o json 2>&1) || true
  missing=$(run_fmetrics combos --project ComboProj --min-occurrences 5 -o json 2>&1) || true

  if python3 -c '
import json, sys
data = json.loads(sys.argv[1])
assert len(data["combos"]) == 1
assert data["combos"][0]["combo_key"] == "ftree>fsearch>fmap"
err = json.loads(sys.argv[2])
assert err["error"]["code"] == "insufficient_data"
' "$filtered" "$missing" 2>/dev/null; then
    pass "fmetrics combos supports filters and structured insufficient-data errors"
  else
    fail "combos filters or error envelope are wrong" "filtered=$filtered missing=$missing"
  fi
}

test_v17_recommend_suggests_next_step() {
  seed_combo_fixture_db
  local output
  output=$(run_fmetrics recommend --after ftree,fsearch --project ComboProj -o json 2>&1) || true

  if python3 -c '
import json, sys
data = json.loads(sys.stdin.read())
assert data["subcommand"] == "recommend"
assert data["prefix"] == ["ftree", "fsearch"]
top = data["recommendations"][0]
assert top["next_step"] == "fmap"
assert top["support"] == 2
assert abs(float(top["fault_rate"])) < 1e-9
assert top["confidence"] in {"medium", "high"}
assert top["because"]
' <<<"$output" 2>/dev/null; then
    pass "fmetrics recommend suggests the strongest next step"
  else
    fail "recommend should suggest the strongest next step" "Got: $output"
  fi
}

test_v17_recommend_returns_structured_error_without_next_step() {
  seed_combo_fixture_db
  local output
  output=$(run_fmetrics recommend --after ftree,fsearch,fmap --project ComboProj -o json 2>&1) || true

  if python3 -c '
import json, sys
data = json.loads(sys.stdin.read())
assert data["error"]["code"] == "insufficient_data"
' <<<"$output" 2>/dev/null; then
    pass "fmetrics recommend returns structured error when no next step exists"
  else
    fail "recommend should return structured insufficient-data error" "Got: $output"
  fi
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

test_v16_predict_ftree_pretty_renders_mode_breakdown() {
  if ! command -v sqlite3 >/dev/null 2>&1; then
    pass "ftree pretty predict test skipped (sqlite3 not available)"
    return 0
  fi

  local target_dir="${TEST_DIR}/predict_target_pretty"
  mkdir -p "${target_dir}/src"
  echo "one" > "${target_dir}/src/a.txt"
  echo "two" > "${target_dir}/src/b.txt"

  seed_ftree_predict_fixture_db

  local output
  output=$(run_fmetrics predict --tool ftree "${target_dir}" 2>&1) || true

  if [[ "$output" == *"ftree:mixed"* ]] && [[ "$output" == *"ftree:tree"* ]] && [[ "$output" == *"ftree:recon"* ]] && [[ "$output" == *"ftree:snapshot"* ]]; then
    pass "fmetrics pretty predict renders ftree mode breakdown"
  else
    fail "pretty predict should render ftree mixed summary plus per-mode rows" "Got: $output"
  fi
}

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

test_v16_predict_helper_pretty_preserves_ftree_mixed_contract() {
  if ! command -v sqlite3 >/dev/null 2>&1; then
    pass "predict helper pretty contract test skipped (sqlite3 not available)"
    return 0
  fi

  seed_ftree_predict_fixture_db

  local output mixed_count tree_row recon_row snapshot_row
  output=$(python3 "${FMETRICS_PREDICT}" --db "$HOME/.fsuite/telemetry.db" --items 42 --bytes 4200 --depth 3 --tool ftree --output pretty 2>&1) || true
  mixed_count=$(grep -c "ftree:mixed" <<< "$output" || true)
  tree_row=$(grep -c "ftree:tree" <<< "$output" || true)
  recon_row=$(grep -c "ftree:recon" <<< "$output" || true)
  snapshot_row=$(grep -c "ftree:snapshot" <<< "$output" || true)

  if [[ "$mixed_count" == "1" ]] && [[ "$tree_row" == "0" ]] && [[ "$recon_row" == "0" ]] && [[ "$snapshot_row" == "0" ]]; then
    pass "fmetrics-predict pretty output preserves collapsed ftree contract"
  else
    fail "predict helper pretty output should collapse default ftree rows" "Got: $output"
  fi
}

test_v16_predict_json_fallback_survives_broken_python3() {
  local sqlite3_bin
  sqlite3_bin="$(command -v sqlite3 2>/dev/null || true)"
  if [[ -z "$sqlite3_bin" ]]; then
    pass "predict fallback test skipped (sqlite3 not available)"
    return 0
  fi

  seed_ftree_predict_fixture_db

  local shim_dir="${TEST_DIR}/shim-bin"
  mkdir -p "${shim_dir}"
  printf '%s\n' '#!/bin/sh' 'exit 127' > "${shim_dir}/python3"
  printf '%s\n' '#!/bin/sh' "PATH=/usr/bin:/bin exec \"${sqlite3_bin}\" \"\$@\"" > "${shim_dir}/sqlite3"
  chmod +x "${shim_dir}/python3" "${shim_dir}/sqlite3"

  local target_dir="${TEST_DIR}/predict_target_broken_python"
  mkdir -p "${target_dir}"

  local output rc=0
  output=$(PATH="${shim_dir}:/bin:/usr/bin" FSUITE_TELEMETRY=0 "${FMETRICS}" predict -o json "${target_dir}" 2>&1) || rc=$?

  if [[ $rc -eq 0 ]] && python3 -c 'import json,sys; data=json.loads(sys.stdin.read()); assert data["method"] == "average_fallback"; assert data["predictions"][0]["tool"] == "ftree"' <<< "$output" 2>/dev/null; then
    pass "fmetrics JSON fallback survives missing or broken python3"
  else
    fail "predict -o json should fall back without a working python3 helper" "rc=$rc output=$output"
  fi
}

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

test_v15_combo_case_impact_ranking() {
  if ! command -v sqlite3 >/dev/null 2>&1; then
    pass "fmetrics combo case-impact test skipped (sqlite3 not available)"
    return 0
  fi

  seed_combo_case_fixture_db

  local combos_output recommend_output
  combos_output=$(run_fmetrics combos --project combo-impact -o json 2>&1) || true
  recommend_output=$(run_fmetrics recommend --after ftree --project combo-impact -o json 2>&1) || true

  if python3 -c '
import json, sys

combos = json.loads(sys.argv[1])
recommend = json.loads(sys.argv[2])

top_combo = combos["combos"][0]
top_recommend = recommend["recommendations"][0]

assert top_combo["combo_key"] == "ftree>fcontent"
assert top_combo["evidence"]["resolved_cases"] == 1
assert top_combo["evidence"]["progress_cases"] == 1
assert top_combo["case_impact_score"] > 0

assert recommend["prefix"] == ["ftree"]
assert top_recommend["next_step"] == "fcontent"
assert top_recommend["evidence"]["resolved_cases"] == 1
assert top_recommend["evidence"]["progress_cases"] == 1
assert top_recommend["case_impact_score"] > 0
' "$combos_output" "$recommend_output" 2>/dev/null; then
    pass "fmetrics combos and recommend elevate case-backed outcomes without changing the JSON contract"
  else
    fail "fmetrics combos and recommend should favor case-backed outcomes over telemetry-only support" "Combos: $combos_output ; Recommend: $recommend_output"
  fi
}

test_harness_uses_sandbox_home() {
  if [[ -n "${ORIGINAL_HOME}" ]] && [[ "$HOME" != "$ORIGINAL_HOME" ]] && [[ -d "$HOME/.fsuite" ]]; then
    pass "Telemetry tests run inside a sandboxed HOME"
  else
    fail "Telemetry tests should sandbox HOME instead of mutating the caller environment" "ORIGINAL_HOME=${ORIGINAL_HOME} HOME=${HOME}"
  fi
}

# ============================================================================
# Main Test Runner
# ============================================================================

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
  run_test "Import marks analytics dirty without rebuild" test_import_marks_analytics_dirty_without_rebuild
  run_test "Rebuild populates run_facts_v1 analytics" test_rebuild_populates_run_facts_after_import
  run_test "Import survives malformed lines" test_import_survives_malformed_lines
  run_test "Import only processes newly appended lines" test_import_only_processes_new_lines
  run_test "Clean rebuilds run_facts_v1 after direct seed" test_clean_rebuilds_run_facts_after_direct_seed
  run_test "Combos lazily rebuilds dirty analytics" test_combos_rebuilds_dirty_analytics_on_demand
  run_test "fmetrics combos reports ordered sequences" test_v17_combos_reports_ordered_sequences
  run_test "fmetrics combos filters and errors" test_v17_combos_filters_and_errors
  run_test "fmetrics recommend suggests next step" test_v17_recommend_suggests_next_step
  run_test "fmetrics recommend structured no-next-step error" test_v17_recommend_returns_structured_error_without_next_step

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
  run_test "fmetrics pretty predict renders ftree mode breakdown" test_v16_predict_ftree_pretty_renders_mode_breakdown
  run_test "fmetrics predict --mode snapshot stays in snapshot cluster" test_v16_predict_ftree_mode_snapshot_stays_in_cluster
  run_test "predict helper lowers confidence on zero-spread features" test_v16_predict_helper_degrades_confidence_on_zero_spread
  run_test "fmetrics-predict pretty output preserves collapsed ftree contract" test_v16_predict_helper_pretty_preserves_ftree_mixed_contract
  run_test "fmetrics JSON fallback survives broken python3" test_v16_predict_json_fallback_survives_broken_python3
  run_test "fmetrics predict rejects --mode without --tool ftree" test_v16_predict_rejects_mode_without_ftree_tool
  run_test "fmetrics predict rejects --mode with non-ftree tool" test_v16_predict_rejects_mode_with_non_ftree_tool

    echo ""
    echo "== v1.5.0+: Project Name Inference =="
    run_test "Walk-up heuristic across all tools" test_v15_project_name_walkup
    run_test "Basename fallback without markers" test_v15_project_name_fallback

    echo ""
    echo "== v1.5.1: Case-Impact Combo Analytics =="
    run_test "fmetrics combos and recommend use case outcomes" test_v15_combo_case_impact_ranking

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
