# fmetrics Learning Loop Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make fsuite telemetry automatically become model-aware command-chain recommendations without requiring the user or agent to remember manual `fmetrics import` and `fmetrics rebuild` calls.

**Architecture:** Keep SQLite as the local agent telemetry store. Add a safe `fmetrics refresh` primitive that imports JSONL, rebuilds derived analytics, and materializes recommendation rows under one refresh lock. Then layer status, cached recommendation listing, and optional user-level timer support on top of that primitive.

**Tech Stack:** Bash CLI, Python incremental JSONL importer, SQLite/WAL, Node MCP tests, systemd user timers as optional Linux automation.

---

## Research Validation

- SQLite/WAL: validated with Context7 SQLite docs and Firecrawl search against SQLite WAL docs. WAL improves reader/writer concurrency, but SQLite still has one writer at a time, so refresh must use a lock plus `busy_timeout`.
- SQLite transactions: current importer already uses `BEGIN IMMEDIATE`, which is appropriate for a known write transaction. Preserve that pattern.
- Scheduling: Firecrawl found freedesktop/systemd timer docs and Arch/SUSE timer guides. Use user-level `.service` plus `.timer`, `OnCalendar`, `Persistent=true`, and `RandomizedDelaySec` for optional automation.
- Node tests: Context7 Node.js docs validate `child_process.execFileSync`/`spawnSync` for deterministic CLI wrappers and `fs.rmSync(..., { recursive: true, force: true })` for fixture cleanup.

Primary references:

- https://www.sqlite.org/wal.html
- https://www.freedesktop.org/software/systemd/man/systemd.timer.html
- https://wiki.archlinux.org/title/Systemd/Timers
- https://github.com/nodejs/node/blob/main/doc/api/child_process.md
- https://github.com/nodejs/node/blob/main/doc/api/fs.md

---

## Current Starting Point

Relevant files:

- Modify: `fmetrics`
- Modify: `fmetrics-import.py` only if importer metadata needs extension
- Modify: `_fsuite_common.sh` only if shared refresh helpers are needed
- Modify: `mcp/index.js` for new fmetrics MCP actions
- Modify: `mcp/structured-parity.test.mjs`
- Create: `tests/test_fmetrics_learning_loop.sh`
- Modify: `tests/run_all_tests.sh`
- Modify: `README.md`
- Modify: `site/src/content/docs/commands/fmetrics.md`
- Modify: `site/src/content/docs/architecture/telemetry.md`

Known useful functions:

- `fmetrics:ensure_db`
- `fmetrics:cmd_import`
- `fmetrics:cmd_rebuild`
- `fmetrics:cmd_combos`
- `fmetrics:cmd_recommend`
- `fmetrics:ensure_analytics_populated`
- `fmetrics-import.py:starting_offset`
- `fmetrics-import.py:main`

Current commits to build on:

- `dacf5b7 feat(telemetry): attribute agents and score child chains`
- `7a53440 feat(fedit): add agent recovery hints to json errors`
- `1fc6e42 test: isolate fsuite harness telemetry state`

---

## Scope

Build this:

- `fmetrics refresh`: one safe command for import + rebuild + recommendation cache update.
- `fmetrics status`: machine-readable health/state of the telemetry learning loop.
- `fmetrics recommendations`: cached best-known next-step recommendations for a project/model/agent, not only one ad hoc prefix.
- `fmetrics install-timer --dry-run|--enable|--disable`: optional systemd user timer management.
- MCP parity for new fmetrics actions.
- Docs and tests.

Do not build this yet:

- ShieldCortex persistence bridge.
- Continuous daemon process.
- Remote sync.
- Training/fine-tuning pipeline.
- Complex ML. Start with deterministic scoring over telemetry + case impact.

---

## Design Details

### Refresh Lock

Add a lock helper in `fmetrics`:

```bash
with_refresh_lock() {
  local lock_dir="$FSUITE_DIR/fmetrics-refresh.lock"
  local waited=0
  while ! mkdir "$lock_dir" 2>/dev/null; do
    if (( waited >= 10 )); then
      emit_json_error "lock_timeout" "fmetrics refresh is already running"
      return 1
    fi
    sleep 1
    waited=$((waited + 1))
  done
  trap 'rm -rf "$lock_dir"' RETURN
  "$@"
}
```

If `flock` is available later, it can replace this, but `mkdir` works without adding a dependency.

### SQLite Busy Timeout

Add a wrapper for shell-side sqlite calls that need write/read consistency:

```bash
sqlite_cmd() {
  sqlite3 -cmd "PRAGMA busy_timeout=5000;" "$DB_FILE" "$@"
}
```

Use it for new refresh/status/cache code first. Do not rewrite all existing SQL in this sprint unless a test proves it is necessary.

### Recommendation Cache Tables

Add to `ensure_db`:

```sql
CREATE TABLE IF NOT EXISTS recommendation_snapshots_v1 (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  generated_at TEXT NOT NULL,
  project_name TEXT NOT NULL,
  model_id TEXT NOT NULL DEFAULT '*',
  agent_id TEXT NOT NULL DEFAULT '*',
  telemetry_rows INTEGER NOT NULL,
  run_facts INTEGER NOT NULL,
  combo_rows INTEGER NOT NULL,
  next_edges INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS recommendation_cache_v1 (
  snapshot_id INTEGER NOT NULL,
  project_name TEXT NOT NULL,
  model_id TEXT NOT NULL DEFAULT '*',
  agent_id TEXT NOT NULL DEFAULT '*',
  prefix_key TEXT NOT NULL,
  next_tool TEXT NOT NULL,
  resulting_combo TEXT NOT NULL,
  support_count INTEGER NOT NULL,
  clean_run_rate TEXT NOT NULL,
  fault_rate TEXT NOT NULL,
  avg_duration_ms INTEGER NOT NULL,
  confidence TEXT NOT NULL,
  telemetry_score INTEGER NOT NULL,
  case_impact_score INTEGER NOT NULL,
  score INTEGER NOT NULL,
  evidence_json TEXT NOT NULL DEFAULT '{}',
  because_json TEXT NOT NULL DEFAULT '[]',
  generated_at TEXT NOT NULL,
  PRIMARY KEY (project_name, model_id, agent_id, prefix_key, next_tool)
);

CREATE INDEX IF NOT EXISTS idx_recommendation_cache_project
  ON recommendation_cache_v1(project_name, score DESC);
```

Use `model_id='*'` and `agent_id='*'` for global recommendations in the first implementation. Add model-specific rows only after global rows are tested.

---

## Task 1: Add Learning Loop Tests First

**Files:**

- Create: `tests/test_fmetrics_learning_loop.sh`
- Modify: `tests/run_all_tests.sh`

**Step 1: Write failing refresh test**

Add a sandboxed test harness that creates a temporary `HOME`, writes telemetry JSONL rows for one run, then runs:

```bash
run_fmetrics refresh -o json
```

Expected assertions:

- JSON has `"subcommand":"refresh"`.
- `import.inserted >= 2`.
- `rebuild.analytics_dirty == 0`.
- recommendation cache row count is greater than 0.

**Step 2: Write failing idempotency test**

Run `fmetrics refresh -o json` twice against the same JSONL.

Expected:

- First run inserts rows.
- Second run inserts zero rows.
- Both runs exit 0.
- Recommendation cache row count stays stable.

**Step 3: Write failing status test**

Run:

```bash
run_fmetrics status -o json
```

Expected keys:

- `jsonl_path`
- `db_path`
- `telemetry_rows`
- `analytics_dirty`
- `last_import_at`
- `last_rebuilt_at`
- `recommendation_rows`
- `lock_state`

**Step 4: Write failing recommendations test**

Seed a run like:

```text
fsearch > fcontent > fmap
```

Run:

```bash
run_fmetrics recommendations --project LoopProj -o json
```

Expected:

- Top row recommends `fmap` after `fsearch,fcontent`.
- Row includes `score`, `confidence`, `evidence`, and `because`.

**Step 5: Register suite**

Add `test_fmetrics_learning_loop.sh` to `tests/run_all_tests.sh`.

**Step 6: Verify red**

Run:

```bash
bash tests/test_fmetrics_learning_loop.sh
```

Expected: FAIL because commands do not exist yet.

**Step 7: Commit**

```bash
git add tests/test_fmetrics_learning_loop.sh tests/run_all_tests.sh
git commit -m "test(fmetrics): define learning loop behavior"
```

---

## Task 2: Add Recommendation Cache Schema

**Files:**

- Modify: `fmetrics`
- Test: `tests/test_fmetrics_learning_loop.sh`

**Step 1: Extend `ensure_db`**

Add `recommendation_snapshots_v1` and `recommendation_cache_v1` tables.

**Step 2: Add schema self-check**

In the test suite, query `sqlite_master` after `fmetrics status -o json` or `fmetrics refresh -o json`.

Expected: both tables exist.

**Step 3: Run focused test**

```bash
bash tests/test_fmetrics_learning_loop.sh
```

Expected: still fails at missing commands/cache population, but schema assertions pass.

**Step 4: Commit**

```bash
git add fmetrics tests/test_fmetrics_learning_loop.sh
git commit -m "feat(fmetrics): add recommendation cache schema"
```

---

## Task 3: Implement `fmetrics refresh`

**Files:**

- Modify: `fmetrics`
- Test: `tests/test_fmetrics_learning_loop.sh`

**Step 1: Add command parser entry**

Add `refresh` to usage and dispatch.

**Step 2: Add lock wrapper**

Use a refresh lock so overlapping background/session refreshes do not fight over SQLite.

**Step 3: Implement refresh internals**

Refresh sequence:

1. `ensure_db`
2. run importer via existing import script
3. if inserted rows or dirty analytics, call `rebuild_analytics`
4. rebuild recommendation cache
5. update meta keys:
   - `last_import_at`
   - `last_refresh_at`
   - `last_recommendation_cache_at`

**Step 4: Emit JSON**

Shape:

```json
{
  "tool": "fmetrics",
  "version": "3.3.0",
  "subcommand": "refresh",
  "import": {"inserted": 3, "skipped": 0, "errors": 0},
  "rebuild": {"analytics_dirty": 0, "run_facts": 1, "combos": 3, "next_edges": 2},
  "recommendations": {"rows": 2, "generated_at": "..."},
  "lock": {"acquired": true}
}
```

**Step 5: Run focused test**

```bash
bash tests/test_fmetrics_learning_loop.sh
```

Expected: refresh and idempotency tests pass; status/recommendations may still fail.

**Step 6: Commit**

```bash
git add fmetrics tests/test_fmetrics_learning_loop.sh
git commit -m "feat(fmetrics): refresh telemetry analytics and recommendations"
```

---

## Task 4: Implement Recommendation Cache Builder and Reader

**Files:**

- Modify: `fmetrics`
- Test: `tests/test_fmetrics_learning_loop.sh`

**Step 1: Add cache builder function**

Create:

```bash
rebuild_recommendation_cache() { ... }
```

Source rows from `combo_next_stats_v1`, using existing scoring helpers:

- `combo_score`
- `combo_confidence`
- `case_impact_score`
- `recommend_because_json`

**Step 2: Add global cache rows**

Generate global rows with:

- `model_id='*'`
- `agent_id='*'`

**Step 3: Add optional model/agent filters**

Allow:

```bash
fmetrics recommendations --project fsuite --model codex-gpt-5.5 --agent codex-cli -o json
```

For this sprint, filters may fall back to global rows if no model-specific rows exist. Include `"fallback":"global"` in JSON.

**Step 4: Implement `fmetrics recommendations`**

Output:

```json
{
  "tool": "fmetrics",
  "subcommand": "recommendations",
  "project": "fsuite",
  "model": "*",
  "agent": "*",
  "generated_at": "...",
  "recommendations": [...]
}
```

**Step 5: Run focused test**

```bash
bash tests/test_fmetrics_learning_loop.sh
```

Expected: recommendations test passes.

**Step 6: Commit**

```bash
git add fmetrics tests/test_fmetrics_learning_loop.sh
git commit -m "feat(fmetrics): cache project recommendations"
```

---

## Task 5: Implement `fmetrics status`

**Files:**

- Modify: `fmetrics`
- Test: `tests/test_fmetrics_learning_loop.sh`

**Step 1: Add status command**

Add `status` to usage and dispatch.

**Step 2: Collect state**

Report:

- JSONL path, existence, size, mtime
- DB path, existence, size
- import cursor offset/size/device/inode
- telemetry row count
- run facts/counts
- analytics dirty/version
- last import/rebuild/refresh/cache timestamps
- recommendation cache row count
- lock state

**Step 3: Add stale indicators**

Add booleans:

- `jsonl_has_unimported_bytes`
- `analytics_stale`
- `recommendations_stale`

**Step 4: Run focused test**

```bash
bash tests/test_fmetrics_learning_loop.sh
```

Expected: status test passes.

**Step 5: Commit**

```bash
git add fmetrics tests/test_fmetrics_learning_loop.sh
git commit -m "feat(fmetrics): report learning loop status"
```

---

## Task 6: Add Safe Auto-Refresh Gate

**Files:**

- Modify: `fmetrics`
- Test: `tests/test_fmetrics_learning_loop.sh`

**Step 1: Add env controls**

Support:

- `FSUITE_METRICS_AUTO=0` disables auto-refresh.
- `FSUITE_METRICS_AUTO=1` enables foreground auto-refresh for read commands.
- `FSUITE_METRICS_AUTO_INTERVAL_SEC=900` throttle default.

**Step 2: Add `maybe_auto_refresh`**

Call from read-oriented commands:

- `stats`
- `history`
- `combos`
- `recommend`
- `recommendations`

Do not call it from `import`, `rebuild`, `refresh`, or `clean`.

**Step 3: Make auto-refresh conservative**

Only refresh when:

- JSONL exists and is larger/newer than imported cursor, or analytics dirty is 1.
- last auto refresh is older than interval.
- refresh lock is not held.

If lock is held, skip and add warning in JSON instead of blocking.

**Step 4: Add tests**

Test that:

- `FSUITE_METRICS_AUTO=1 fmetrics recommendations -o json` imports new JSONL data.
- `FSUITE_METRICS_AUTO=0` does not auto-import.
- lock-held state returns stale output with warning, not failure.

**Step 5: Commit**

```bash
git add fmetrics tests/test_fmetrics_learning_loop.sh
git commit -m "feat(fmetrics): auto-refresh stale telemetry reads"
```

---

## Task 7: Add Optional User Timer Commands

**Files:**

- Modify: `fmetrics`
- Test: `tests/test_fmetrics_learning_loop.sh`
- Docs: `README.md`, `site/src/content/docs/commands/fmetrics.md`

**Step 1: Add dry-run first**

Command:

```bash
fmetrics install-timer --dry-run -o json
```

Expected JSON:

- service path
- timer path
- service content
- timer content
- systemctl commands that would run

**Step 2: Add timer content**

Service:

```ini
[Unit]
Description=fsuite fmetrics refresh

[Service]
Type=oneshot
ExecStart=/absolute/path/to/fmetrics refresh -o json
```

Timer:

```ini
[Unit]
Description=Refresh fsuite fmetrics learning loop

[Timer]
OnCalendar=hourly
Persistent=true
RandomizedDelaySec=5m

[Install]
WantedBy=timers.target
```

**Step 3: Add enable/disable**

Commands:

```bash
fmetrics install-timer --enable
fmetrics install-timer --disable
```

Rules:

- If `systemctl --user` is unavailable, return structured error with manual instructions.
- Never require sudo.
- Do not auto-enable during normal install unless user explicitly requests it.

**Step 4: Add tests**

Test dry-run content only. Do not require systemd in CI/local tests.

**Step 5: Commit**

```bash
git add fmetrics tests/test_fmetrics_learning_loop.sh README.md site/src/content/docs/commands/fmetrics.md
git commit -m "feat(fmetrics): add optional refresh timer"
```

---

## Task 8: MCP Parity

**Files:**

- Modify: `mcp/index.js`
- Modify: `mcp/structured-parity.test.mjs`
- Test: `tests/test_mcp.sh`

**Step 1: Expose new actions**

Update the fmetrics MCP adapter to support:

- `refresh`
- `status`
- `recommendations`
- `install-timer` dry-run only, unless explicit arguments allow enable/disable.

**Step 2: Preserve structured content**

Make sure MCP responses expose the parsed JSON as `structuredContent`.

**Step 3: Add MCP tests**

Seed telemetry in a sandboxed HOME, call `fmetrics refresh`, then assert:

- `structuredContent.subcommand == "refresh"`
- recommendations rows exist
- status has `telemetry_rows`

**Step 4: Run MCP tests**

```bash
tmp_home=$(mktemp -d)
HOME="$tmp_home" bash tests/test_mcp.sh
rc=$?
rm -rf "$tmp_home"
exit $rc
```

Expected: pass.

**Step 5: Commit**

```bash
git add mcp/index.js mcp/structured-parity.test.mjs
git commit -m "feat(mcp): expose fmetrics learning loop actions"
```

---

## Task 9: Docs and Handoff

**Files:**

- Modify: `README.md`
- Modify: `site/src/content/docs/commands/fmetrics.md`
- Modify: `site/src/content/docs/architecture/telemetry.md`
- Modify: `docs/plans/2026-04-25-fmetrics-learning-loop.md` if implementation diverged

**Step 1: Document new workflow**

Add:

```bash
fmetrics refresh
fmetrics status -o json
fmetrics recommendations --project fsuite -o json
fmetrics install-timer --dry-run
```

**Step 2: Document env controls**

Add:

```bash
FSUITE_METRICS_AUTO=0
FSUITE_METRICS_AUTO=1
FSUITE_METRICS_AUTO_INTERVAL_SEC=900
```

**Step 3: Document operational doctrine**

Recommended agent default:

1. At session start: `fmetrics status -o json`
2. Before major repo recon: `fmetrics recommendations --project <project> -o json`
3. After meaningful tool use: `fmetrics refresh`
4. On machine setup: optional `fmetrics install-timer --enable`

**Step 4: Commit**

```bash
git add README.md site/src/content/docs/commands/fmetrics.md site/src/content/docs/architecture/telemetry.md docs/plans/2026-04-25-fmetrics-learning-loop.md
git commit -m "docs(fmetrics): document learning loop workflow"
```

---

## Final Verification

Run:

```bash
bash -n fmetrics tests/test_fmetrics_learning_loop.sh tests/run_all_tests.sh
python3 -m py_compile fmetrics-import.py
bash tests/test_fmetrics_learning_loop.sh
bash tests/test_telemetry.sh
bash tests/test_mcp.sh
bash tests/run_all_tests.sh
git diff --check
```

Expected:

- New learning-loop suite passes.
- Existing telemetry suite still passes.
- MCP structured parity passes.
- Full runner remains 21+ suites passing.
- `git diff --check` has no output and exit 0.

Manual live smoke:

```bash
FSUITE_MODEL_ID=codex-gpt-5.5 \
FSUITE_AGENT_ID=codex-cli \
FSUITE_SESSION_ID=learning-loop-smoke \
FSUITE_TELEMETRY=1 \
./fbash --command './fsearch -o paths "*.sh" tests | ./fcontent -o paths "run_test" | ./fmap -o json'

./fmetrics refresh -o json
./fmetrics recommendations --project fsuite -o json
./fmetrics recommend --after fsearch,fcontent --project fsuite -o json
```

Expected:

- `refresh` imports/rebuilds/cache-updates.
- `recommendations` includes fsuite rows.
- `recommend --after fsearch,fcontent` still recommends `fmap`.

---

## Risks and Guardrails

- Do not run imports from every fsuite tool directly; use `fmetrics refresh` plus throttled read-command auto-refresh.
- Do not require systemd for core behavior.
- Do not make timer install automatic during `install.sh` in this sprint.
- Do not remove existing `recommend` behavior. `recommendations` is additive.
- Keep tests sandboxed with temporary `HOME`.
- Keep live telemetry safe: no test should delete real `$HOME/.fsuite`.

---

## Suggested Commit Sequence

1. `test(fmetrics): define learning loop behavior`
2. `feat(fmetrics): add recommendation cache schema`
3. `feat(fmetrics): refresh telemetry analytics and recommendations`
4. `feat(fmetrics): cache project recommendations`
5. `feat(fmetrics): report learning loop status`
6. `feat(fmetrics): auto-refresh stale telemetry reads`
7. `feat(fmetrics): add optional refresh timer`
8. `feat(mcp): expose fmetrics learning loop actions`
9. `docs(fmetrics): document learning loop workflow`

---

## Open Questions For The Next Agent

- Should `fmetrics recommendations` be named `recommendations`, `advice`, or `plan`? The spec uses `recommendations` because it is explicit and matches the user language.
- Should model-specific cache rows be part of this sprint or deferred until global cache works? Recommendation: defer model-specific scoring rows until global cache is green.
- Should `fbash` trigger background refresh after fsuite child pipelines? Recommendation: defer. Start with `fmetrics` read-command auto-refresh and user timer.
