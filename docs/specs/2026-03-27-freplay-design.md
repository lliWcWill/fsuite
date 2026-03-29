# freplay — Derivation Replay Ledger for fsuite

**Date:** 2026-03-27
**Status:** Approved for implementation
**Authors:** Player3 + Claude (co-pilot session)

---

## One-line definition

**`freplay` preserves the exact command path that produced an investigation outcome, so another agent can reproduce it without improvising.**

## Problem

`fcase` preserves investigation state: targets, evidence, hypotheses, next moves, handoffs. But it does not preserve the derivation path — the ordered sequence of commands that produced those conclusions. Another agent can see *what* was found but must improvise *how* to re-derive it.

## Design principles

1. **Record-first.** Explicit capture is the only source of truth in v1. No fuzzy reconstruction.
2. **Agent-first.** JSON core, pretty output is a courtesy.
3. **Trustworthy artifacts.** If a replay says "this is how we got here," that must be a recorded fact, not a guess.
4. **Same DB.** Replay is a child of case continuity. Storage follows domain truth, not CLI boundaries.
5. **Provenance per step.** Every step carries its origin: `recorded`, `imported`, or `inferred`.

## Non-goals (v1)

- Auto-reconstruct replays from telemetry (v2)
- Replay execution / re-running commands (v2+)
- General shell recording (never — fsuite commands only)
- Replacing fcase evidence or fmetrics telemetry

---

## Schema

All tables live in `~/.fsuite/fcase.db` alongside existing case tables.

### `replays`

```sql
CREATE TABLE IF NOT EXISTS replays (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  case_id INTEGER NOT NULL REFERENCES cases(id) ON DELETE CASCADE,
  label TEXT NOT NULL DEFAULT '',
  status TEXT NOT NULL DEFAULT 'draft'
    CHECK (status IN ('draft','canonical','archived')),
  origin TEXT NOT NULL DEFAULT 'recorded'
    CHECK (origin IN ('recorded','imported','inferred')),
  fsuite_version TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  actor TEXT NOT NULL DEFAULT '',
  parent_replay_id INTEGER REFERENCES replays(id) ON DELETE SET NULL,
  notes TEXT NOT NULL DEFAULT ''
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_replays_one_canonical_per_case
  ON replays(case_id) WHERE status = 'canonical';
```

### `replay_steps`

```sql
CREATE TABLE IF NOT EXISTS replay_steps (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  replay_id INTEGER NOT NULL REFERENCES replays(id) ON DELETE CASCADE,
  order_num INTEGER NOT NULL,
  tool TEXT NOT NULL,
  argv_json TEXT NOT NULL,
  cwd TEXT NOT NULL,
  mode TEXT NOT NULL CHECK (mode IN ('read_only','mutating','unknown')),
  purpose TEXT,
  provenance TEXT NOT NULL DEFAULT 'recorded'
    CHECK (provenance IN ('recorded','imported','inferred')),
  exit_code INTEGER NOT NULL,
  duration_ms INTEGER NOT NULL DEFAULT 0,
  started_at TEXT NOT NULL,
  telemetry_run_id TEXT,
  result_summary TEXT,
  error_excerpt TEXT,
  UNIQUE (replay_id, order_num)
);
```

### `replay_step_links`

```sql
CREATE TABLE IF NOT EXISTS replay_step_links (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  step_id INTEGER NOT NULL REFERENCES replay_steps(id) ON DELETE CASCADE,
  link_type TEXT NOT NULL
    CHECK (link_type IN ('evidence','target','hypothesis')),
  link_ref TEXT NOT NULL,
  UNIQUE (step_id, link_type, link_ref)
);
```

### Invariants

- **One canonical per case:** Enforced by partial unique index at DB level.
- **Step ordering:** `UNIQUE(replay_id, order_num)` prevents duplicate ordering.
- **Link uniqueness:** `UNIQUE(step_id, link_type, link_ref)` prevents duplicate links.
- **Enum enforcement:** CHECK constraints on `status`, `origin`, `mode`, `provenance`, `link_type`.
- **order_num allocation:** Computed inside a write transaction as `MAX(order_num)+1` to prevent races.
- **error_excerpt:** Bounded to 240 characters, populated only when `exit_code != 0`.
- **mode derivation:** Determined by tool + subcommand classification, never user-supplied.
- **link_ref validation:** The portion after `:` must be numeric in v1. Non-numeric values are rejected.
- **Excluded from recording:** v1 recording accepts fsuite commands except commands explicitly classified as non-lineage operational/meta tools. The concrete denylist is: `freplay` (recursive nonsense) and `fmetrics` (operational noise). This doctrine scales cleanly if additional meta-tools are added later.
- **show fallback:** "Newest draft" = highest `replays.id`. `list` output ordered by `id DESC` to match.
- **origin vs provenance:** `origin` on `replays` describes how the replay object was created. `provenance` on `replay_steps` describes how each step was obtained. In v1, both are always `recorded`. The columns exist for v2 when `imported`/`inferred` become reachable via reconstruction.
- **DB bootstrap:** `freplay` shares the DB bootstrap function with `fcase`. The shared function lives in a common DB module (extracted from fcase or sourced from `_fsuite_common.sh`). Replay tables are created at `user_version >= 2`. The migration checks `PRAGMA user_version` and only adds replay tables when upgrading from version 1. **`freplay` must not independently create a partial fcase.db schema; it must use the shared bootstrap/migration path as the single authority for schema creation and version upgrades.**

### Mode classification

| Tool | Default mode |
|------|-------------|
| `ftree` | `read_only` |
| `fsearch` | `read_only` |
| `fcontent` | `read_only` |
| `fmap` | `read_only` |
| `fread` | `read_only` |
| `fmetrics` | `read_only` |
| `fprobe` | `read_only` |
| `fcase status` | `read_only` |
| `fcase handoff` | `read_only` |
| `fcase export` | `read_only` |
| `fcase list` | `read_only` |
| `fcase init` | `mutating` |
| `fcase note` | `mutating` |
| `fcase next` | `mutating` |
| `fcase target add` | `mutating` |
| `fcase target import` | `mutating` |
| `fcase evidence` | `mutating` |
| `fcase evidence import` | `mutating` |
| `fcase hypothesis add` | `mutating` |
| `fcase hypothesis set` | `mutating` |
| `fcase reject` | `mutating` |
| `fedit` (no `--apply`) | `read_only` |
| `fedit --apply` | `mutating` |
| `freplay` | **excluded** — rejected by `record` |
| `fmetrics` | **excluded** — rejected by `record` |

### Tool-aware result_summary

| Tool | Summary format |
|------|---------------|
| `ftree` | `"snapshot: {entries} entries, {size}"` or `"tree: {dirs} dirs, {files} files"` |
| `fsearch` | `"{count} matches in {file_count} files"` |
| `fcontent` | `"{match_count} matches in {file_count} files"` |
| `fmap` | `"{symbol_count} symbols in {file_count} files"` |
| `fread` | `"{lines_emitted} lines from {path}"` |
| `fcase` | subcommand-dependent or null |
| `fedit` | `"dry-run: {diff_summary}"` or `"applied: {diff_summary}"` |
| `fmetrics` | `"{total_runs} runs imported"` or null |
| fallback | first 240 chars of stdout |

---

## CLI contract

```
freplay record <case-slug> [--purpose "..."] [--link <type:id>]... -- <fsuite-command...>
freplay show <case-slug> [--replay-id N] [-o pretty|json]
freplay list <case-slug> [-o pretty|json]
freplay export <case-slug> [--replay-id N] [-o json]
freplay verify <case-slug> [--replay-id N] [-o pretty|json]
freplay promote <case-slug> <replay-id>
freplay archive <case-slug> <replay-id>
freplay --version
freplay --help
freplay --self-check
```

### `record`

The core capture command. Wraps an fsuite tool invocation, executes it, and appends the result as a step to the active draft replay for that case.

- If no draft replay exists for the case, creates one automatically.
- Rejects non-fsuite commands with a clear error.
- `--purpose` is optional. Stored as-is when provided.
- `--link` is repeatable. Format: `<link_type>:<numeric_id>`.
- Captures: `argv_json`, `cwd`, derived `mode`, `exit_code`, `duration_ms`, `started_at`, `telemetry_run_id` (if available), `result_summary`, `error_excerpt` (failure-only).
- `order_num` allocated inside write transaction: `MAX(order_num)+1`.

```bash
freplay record nightfox-bridge -- ftree --snapshot -o json ~/Projects/nightfox
freplay record nightfox-bridge --purpose "map gateway symbols" -- fmap -o json src/gateway
freplay record nightfox-bridge --link evidence:71 -- fread src/auth.ts --symbol authenticate
```

### `show`

Displays a replay's steps. Defaults to canonical replay, falls back to newest draft.

- `--replay-id N` shows a specific replay.
- `-o json` emits structured step data.
- `-o pretty` emits human-readable step-by-step.

### `list`

Lists all replays for a case with id, status, origin, step count, created_at.

### `export`

Emits a portable `ReplayPack` JSON envelope. Defaults to canonical replay.

### `verify`

Validates a replay without executing anything:

- Referenced tool binary exists in PATH
- `cwd` directories still exist
- Path arguments still resolve (where applicable)
- Linked fcase references (`evidence`, `target`, `hypothesis`) still exist in their respective tables
- Mode classification still matches current rules

Reports pass/warn/fail per step.

### `promote`

Sets a replay to `canonical`. Demotes any existing canonical for that case to `archived`. Does not mutate steps.

### `archive`

Sets a replay to `archived`. Does not mutate steps.

---

## ReplayPack JSON (export schema)

```json
{
  "version": "1.0",
  "tool": "freplay",
  "case_slug": "nightfox-bridge",
  "case_goal": "Map OpenClaw gateway protocol into Nightfox dashboard",
  "replay_id": 1,
  "replay_status": "canonical",
  "replay_origin": "recorded",
  "fsuite_version": "2.1.2",
  "created_at": "2026-03-27T05:39:16Z",
  "actor": "player3vsgpt",
  "step_count": 5,
  "steps": [
    {
      "order": 1,
      "tool": "ftree",
      "argv": ["--snapshot", "-o", "json", "/home/user/Projects/nightfox"],
      "cwd": "/home/user",
      "mode": "read_only",
      "purpose": "repo orientation",
      "provenance": "recorded",
      "exit_code": 0,
      "duration_ms": 12764,
      "started_at": "2026-03-27T05:35:00Z",
      "result_summary": "snapshot: 755 entries, 170.1M dashboard app",
      "error_excerpt": null,
      "links": [
        {"type": "evidence", "ref": "70"}
      ]
    }
  ]
}
```

---

## Bootstrap and error behavior

- **`record`, `promote`, `archive`:** May call `ensure_db` to bootstrap tables if DB doesn't exist.
- **`show`, `list`, `export`, `verify`:** Fail cleanly with a precise message if no DB exists. Do not bootstrap.

---

## Acceptance criteria

1. `freplay record` captures exact command argv, cwd, timing, exit status, and derived mode for any fsuite command.
2. `freplay record` rejects non-fsuite commands.
3. Recorded steps are append-only within a replay. No mutation after capture.
4. `freplay export -o json` produces a self-sufficient ReplayPack that a cold-start agent can use to understand the derivation path without needing raw stdout/stderr blobs.
5. `freplay verify` validates paths and references without executing any commands.
6. At most one canonical replay per case, enforced at DB level.
7. Every step carries `provenance`. In v1, all recorded steps have `provenance: "recorded"`.
8. `mode` is derived from tool classification, never user-supplied.
9. `error_excerpt` is bounded to 240 characters and only populated on failure.
10. `result_summary` uses tool-aware extraction when available, falls back to bounded stdout.

---

## Future (v2+)

- `freplay build --from-case <slug>` — reconstruct replay from fcase events + fmetrics telemetry, marked as `origin: "inferred"`.
- `freplay run <slug> --read-only` — re-execute read-only steps with fresh data.
- Session mode: `freplay session start/run/stop` for reduced wrapper friction.
- `eval "$(freplay session env <slug>)"` for transparent recording.
- Hybrid provenance: `recorded` + `inferred` steps in same replay, clearly labeled.

---

## Implementation phases

### Phase 1: Foundation
1. Add replay tables to fcase `ensure_db` (migration-safe, check `user_version`)
2. Create `freplay` bash script with `_fsuite_common.sh`
3. Implement `record` — wrapper execution, capture, DB insert
4. Implement tool classification for `mode` derivation
5. Implement tool-aware `result_summary` extraction

### Phase 2: Read commands
6. Implement `show` (pretty + JSON)
7. Implement `list` (pretty + JSON)
8. Implement `export` (ReplayPack JSON)

### Phase 3: Lifecycle
9. Implement `promote` and `archive`
10. Enforce one-canonical invariant (already DB-level)

### Phase 4: Verification
11. Implement `verify` (path/tool/link validation, no execution)

### Phase 5: Testing
12. Full test suite: record flow, lifecycle, show/export, verify, schema integrity, edge cases
13. Wire into `tests/run_all_tests.sh` master runner

---

## Testing matrix

### Record flow
- Single step recorded correctly (all fields)
- Multiple steps with incrementing order_num
- Auto-create draft replay on first record
- Append to existing draft on subsequent records
- `--purpose` stored when provided, null when omitted
- `--link` creates entries in `replay_step_links`
- Non-fsuite command rejected with error
- `freplay` command rejected (no recursive recording)
- `fmetrics` command rejected (noise exclusion)
- `argv_json` is valid JSON array
- `cwd` captured as absolute path
- Mode correctly derived per classification table
- Exit code captured (both 0 and non-zero)
- `error_excerpt` populated only on failure, bounded to 240 chars
- `result_summary` uses tool-aware extraction

### Lifecycle
- `promote` sets canonical, demotes existing canonical to archived
- `promote` does not mutate steps
- Partial unique index prevents two canonical replays per case
- `archive` sets status without touching steps
- Draft stays open across multiple record calls
- `list` shows all replays with correct metadata

### Show / Export
- `show` defaults to canonical, falls back to newest draft
- `show --replay-id N` shows specific replay
- `show -o json` produces valid JSON
- `export` emits valid ReplayPack JSON
- `export` includes all steps with links resolved
- Empty replay exports cleanly

### Verify
- Pass for valid paths/tools
- Warn for missing cwd
- Fail for missing tool binary
- Does NOT execute any commands
- Checks link references exist in fcase tables
- `-o json` emits structured per-step results

### Schema integrity
- CHECK constraints reject invalid enum values
- UNIQUE constraints prevent duplicate order_num per replay
- UNIQUE constraints prevent duplicate links per step
- FK cascade: deleting case cascades to replays → steps → links
- FK cascade: deleting replay cascades to steps → links

### Edge cases
- Record against nonexistent case → clear error
- Record when no DB exists → ensure_db bootstraps
- Show/list/export/verify when no DB exists → clean failure message
- Very long stdout → result_summary bounded correctly
- Very long stderr → error_excerpt bounded correctly
- Concurrent record calls → order_num sequential via transaction
- Command that fails → step still recorded with exit_code + error_excerpt
- `--link` with non-numeric ref portion → rejected with clear error
- `show` with multiple drafts → returns highest id draft
- `list` output ordered by id DESC

### Utility commands
- `freplay --version` prints version
- `freplay --help` prints usage
- `freplay --self-check` verifies sqlite3 and fcase.db availability
