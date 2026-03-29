# fcase Lifecycle Upgrade Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add resolve/archive/delete lifecycle, filtered listing, and knowledge search (`fcase find`) to the fcase investigation ledger.

**Architecture:** All changes are in the existing `fcase` bash script (SQLite ALTER TABLE for new columns, new `cmd_*` functions for each subcommand, updated `cmd_list` with status filters). MCP registration gets expanded action enum + new fields. TDD with `tests/test_fcase_lifecycle.sh`.

**Tech Stack:** Bash, SQLite3, existing `_fsuite_db.sh` shared module, Zod (MCP schema)

**Spec:** `docs/specs/2026-03-29-fcase-lifecycle-design.md`

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `fcase` | Modify | Add cmd_resolve, cmd_archive, cmd_reopen, cmd_delete, cmd_find. Update cmd_list with filters. Update ensure_db with ALTER TABLE. Update main dispatch. |
| `mcp/index.js` | Modify | Expand fcase action enum, add summary/query/confirm/deep/filter fields |
| `tests/test_fcase_lifecycle.sh` | Create | TDD tests for all lifecycle transitions, guards, find, list filters |
| `tests/run_all_tests.sh` | Modify | Add fcase lifecycle test suite block |

---

### Task 1: Schema Migration + resolve command (TDD)

**Files:**
- Create: `tests/test_fcase_lifecycle.sh`
- Modify: `fcase`

The foundation — ALTER TABLE to add new columns, then the `resolve` command with mandatory summary.

- [ ] **Step 1: Write test harness + resolve tests**

```bash
#!/usr/bin/env bash
# tests/test_fcase_lifecycle.sh — TDD tests for fcase lifecycle upgrade
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
FCASE="$REPO_DIR/fcase"

# Use an isolated test DB
export FCASE_TEST_DB=""
PASS=0; FAIL=0; TOTAL=0

setup_test_db() {
  FCASE_TEST_DB=$(mktemp)
  rm -f "$FCASE_TEST_DB"  # fcase will create it
  # Override DB path — fcase reads FCASE_DIR from env or defaults to ~/.fsuite
  export FSUITE_DIR=$(mktemp -d)
  export DB_FILE="$FSUITE_DIR/fcase.db"
  # Create a symlink so fcase finds the DB at its expected path
  mkdir -p "$FSUITE_DIR"
}

teardown_test_db() {
  rm -rf "${FSUITE_DIR:-}" 2>/dev/null || true
}

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  TOTAL=$((TOTAL + 1))
  if [[ "$expected" == "$actual" ]]; then
    PASS=$((PASS + 1))
    echo -e "  \033[0;32m✓\033[0m $label"
  else
    FAIL=$((FAIL + 1))
    echo -e "  \033[0;31m✗\033[0m $label"
    echo "    expected: $expected"
    echo "    actual:   $actual"
  fi
}

assert_contains() {
  local label="$1" haystack="$2" needle="$3"
  TOTAL=$((TOTAL + 1))
  if [[ "$haystack" == *"$needle"* ]]; then
    PASS=$((PASS + 1))
    echo -e "  \033[0;32m✓\033[0m $label"
  else
    FAIL=$((FAIL + 1))
    echo -e "  \033[0;31m✗\033[0m $label"
    echo "    expected to contain: $needle"
    echo "    actual: ${haystack:0:200}"
  fi
}

assert_not_contains() {
  local label="$1" haystack="$2" needle="$3"
  TOTAL=$((TOTAL + 1))
  if [[ "$haystack" != *"$needle"* ]]; then
    PASS=$((PASS + 1))
echo -e "  \033[0;32m✓\033[0m $label"
  else
    FAIL=$((FAIL + 1))
    echo -e "  \033[0;31m✗\033[0m $label"
  fi
}

trap teardown_test_db EXIT

echo ""
echo "═══════════════════════════════════════════"
echo " fcase lifecycle test suite"
echo "═══════════════════════════════════════════"

# ── Section 1: Resolve ──────────────────────────────────────────
echo ""
echo "── Section 1: Resolve ──"

setup_test_db

# Create a test case
"$FCASE" init test-resolve --goal "Test resolve" -o json >/dev/null 2>&1

# Resolve without summary should fail
result=$("$FCASE" resolve test-resolve 2>&1 || true)
assert_contains "resolve without summary fails" "$result" "requires --summary"

# Resolve with summary should succeed
result=$("$FCASE" resolve test-resolve --summary "Root cause was X. Fix was Y." -o json 2>&1)
assert_contains "resolve succeeds with summary" "$result" "resolved"

# Status should show resolved
status=$("$FCASE" status test-resolve -o json 2>&1)
assert_contains "status shows resolved" "$status" "resolved"

# Resolve an already resolved case should fail
result=$("$FCASE" resolve test-resolve --summary "again" 2>&1 || true)
assert_contains "double resolve fails" "$result" "not open"

# Summary should be stored
assert_contains "summary stored in status" "$status" "Root cause was X"

teardown_test_db
```

- [ ] **Step 2: Run tests — they should fail (resolve command doesn't exist)**

Run: `bash tests/test_fcase_lifecycle.sh`
Expected: FAIL — "unknown or unimplemented subcommand: resolve"

- [ ] **Step 3: Add schema migration to ensure_db**

In `fcase`, find the `ensure_db()` function. After the existing CREATE TABLE statements and before the function closes, add:

```bash
# Lifecycle columns (idempotent — ALTER TABLE ADD COLUMN is a no-op if column exists)
db_exec <<'SQL' 2>/dev/null || true
ALTER TABLE cases ADD COLUMN summary TEXT DEFAULT '';
SQL
db_exec <<'SQL' 2>/dev/null || true
ALTER TABLE cases ADD COLUMN resolved_at TEXT;
SQL
db_exec <<'SQL' 2>/dev/null || true
ALTER TABLE cases ADD COLUMN archived_at TEXT;
SQL
db_exec <<'SQL' 2>/dev/null || true
ALTER TABLE cases ADD COLUMN deleted_at TEXT;
SQL
```

The `2>/dev/null || true` makes these idempotent — SQLite errors if the column already exists, which is fine.

- [ ] **Step 4: Implement cmd_resolve**

Add this function to `fcase` (before the `main()` function):

```bash
cmd_resolve() {
  local slug="${1:-}"
  shift || true
  [[ -n "$slug" ]] || die "resolve requires <slug>"

  local summary="" output="$DEFAULT_OUTPUT"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --summary) summary="${2:-}"; shift 2 ;;
      -o|--output) output="${2:-}"; shift 2 ;;
      *) die "Unknown option for resolve: $1" ;;
    esac
  done
  [[ -n "$summary" ]] || die "resolve requires --summary"
  [[ "$output" == "pretty" || "$output" == "json" ]] || die "Invalid --output: $output"

  ensure_db
  local case_id now escaped_summary escaped_slug current_status
  case_id="$(case_exists_or_die "$slug")"
  current_status="$(db_query <<<"SELECT status FROM cases WHERE id = $case_id;")"
  [[ "$current_status" == "open" ]] || die "case '$slug' is not open (status: $current_status)"

  now="$(now_utc)"
  escaped_summary="$(sql_quote "$summary")"
  escaped_slug="$(sql_quote "$slug")"

  local session_id
  session_id="$(latest_session_id_for_case "$case_id")"

  if ! db_exec <<SQL
PRAGMA foreign_keys=ON;
BEGIN IMMEDIATE;
UPDATE cases SET status = 'resolved', summary = ${escaped_summary}, resolved_at = $(sql_quote "$now"), updated_at = $(sql_quote "$now") WHERE id = $case_id;
INSERT INTO events (case_id, session_id, event_type, payload_json, created_at)
VALUES ($case_id, ${session_id:-NULL}, 'case_resolved', json_object('summary', ${escaped_summary}, 'previous_status', 'open'), $(sql_quote "$now"));
COMMIT;
SQL
  then
    die "failed to resolve case"
  fi

  if [[ "$output" == "json" ]]; then
    db_query <<SQL
SELECT json_object('slug', slug, 'status', status, 'summary', summary, 'resolved_at', resolved_at) FROM cases WHERE id = $case_id;
SQL
  else
    echo "Case '$slug' resolved."
    echo "Summary: $summary"
  fi
}
```

- [ ] **Step 5: Add resolve to main dispatch**

In the `main()` function's case statement, add before the `*) die` fallback:

```bash
resolve)
  shift
  cmd_resolve "$@"
  ;;
```

- [ ] **Step 6: Run tests — all resolve tests should pass**

Run: `bash tests/test_fcase_lifecycle.sh`
Expected: All Section 1 tests PASS

- [ ] **Step 7: Commit**

```bash
git add fcase tests/test_fcase_lifecycle.sh
git commit -m "feat(fcase): resolve command with mandatory summary + schema migration

ALTER TABLE adds summary, resolved_at, archived_at, deleted_at columns.
resolve transitions open → resolved, requires --summary, records
case_resolved event. TDD tests verify guards and state transitions."
```

---

### Task 2: Archive + Reopen commands

**Files:**
- Modify: `fcase`
- Modify: `tests/test_fcase_lifecycle.sh`

- [ ] **Step 1: Add archive + reopen tests**

Append to `tests/test_fcase_lifecycle.sh`:

```bash
# ── Section 2: Archive + Reopen ─────────────────────────────────
echo ""
echo "── Section 2: Archive + Reopen ──"

setup_test_db

# Create + resolve a case
"$FCASE" init test-archive --goal "Test archive" -o json >/dev/null 2>&1
"$FCASE" resolve test-archive --summary "Conclusion" -o json >/dev/null 2>&1

# Archive open case should fail (must be resolved first)
"$FCASE" init test-archive-open --goal "Still open" -o json >/dev/null 2>&1
result=$("$FCASE" archive test-archive-open 2>&1 || true)
assert_contains "archive open case fails" "$result" "only resolved"

# Archive resolved case should succeed
result=$("$FCASE" archive test-archive -o json 2>&1)
assert_contains "archive succeeds" "$result" "archived"

# Status should show archived
status=$("$FCASE" status test-archive -o json 2>&1)
assert_contains "status shows archived" "$status" "archived"

# Reopen archived case
result=$("$FCASE" reopen test-archive -o json 2>&1)
assert_contains "reopen succeeds" "$result" "open"

# Re-resolve and verify
"$FCASE" resolve test-archive --summary "New conclusion after reopen" -o json >/dev/null 2>&1
status=$("$FCASE" status test-archive -o json 2>&1)
assert_contains "re-resolved after reopen" "$status" "resolved"

teardown_test_db
```

- [ ] **Step 2: Run tests — archive/reopen tests fail**

Run: `bash tests/test_fcase_lifecycle.sh`
Expected: Section 1 PASS, Section 2 FAIL

- [ ] **Step 3: Implement cmd_archive**

```bash
cmd_archive() {
  local slug="${1:-}"
  shift || true
  [[ -n "$slug" ]] || die "archive requires <slug>"

  local output="$DEFAULT_OUTPUT"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -o|--output) output="${2:-}"; shift 2 ;;
      *) die "Unknown option for archive: $1" ;;
    esac
  done

  ensure_db
  local case_id now current_status
  case_id="$(case_exists_or_die "$slug")"
  current_status="$(db_query <<<"SELECT status FROM cases WHERE id = $case_id;")"
  [[ "$current_status" == "resolved" ]] || die "only resolved cases can be archived (status: $current_status)"

  now="$(now_utc)"
  local session_id
  session_id="$(latest_session_id_for_case "$case_id")"

  if ! db_exec <<SQL
PRAGMA foreign_keys=ON;
BEGIN IMMEDIATE;
UPDATE cases SET status = 'archived', archived_at = $(sql_quote "$now"), updated_at = $(sql_quote "$now") WHERE id = $case_id;
INSERT INTO events (case_id, session_id, event_type, payload_json, created_at)
VALUES ($case_id, ${session_id:-NULL}, 'case_archived', json_object('previous_status', 'resolved'), $(sql_quote "$now"));
COMMIT;
SQL
  then
    die "failed to archive case"
  fi

  if [[ "$output" == "json" ]]; then
    db_query <<SQL
SELECT json_object('slug', slug, 'status', status, 'archived_at', archived_at) FROM cases WHERE id = $case_id;
SQL
  else
    echo "Case '$slug' archived."
  fi
}
```

- [ ] **Step 4: Implement cmd_reopen**

```bash
cmd_reopen() {
  local slug="${1:-}"
  shift || true
  [[ -n "$slug" ]] || die "reopen requires <slug>"

  local output="$DEFAULT_OUTPUT"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -o|--output) output="${2:-}"; shift 2 ;;
      *) die "Unknown option for reopen: $1" ;;
    esac
  done

  ensure_db
  local case_id now current_status
  case_id="$(case_exists_or_die "$slug")"
  current_status="$(db_query <<<"SELECT status FROM cases WHERE id = $case_id;")"
  [[ "$current_status" != "open" ]] || die "case '$slug' is already open"

  now="$(now_utc)"
  local session_id
  session_id="$(latest_session_id_for_case "$case_id")"

  if ! db_exec <<SQL
PRAGMA foreign_keys=ON;
BEGIN IMMEDIATE;
UPDATE cases SET status = 'open', updated_at = $(sql_quote "$now") WHERE id = $case_id;
INSERT INTO events (case_id, session_id, event_type, payload_json, created_at)
VALUES ($case_id, ${session_id:-NULL}, 'case_reopened', json_object('previous_status', $(sql_quote "$current_status")), $(sql_quote "$now"));
COMMIT;
SQL
  then
    die "failed to reopen case"
  fi

  if [[ "$output" == "json" ]]; then
    db_query <<SQL
SELECT json_object('slug', slug, 'status', status) FROM cases WHERE id = $case_id;
SQL
  else
    echo "Case '$slug' reopened."
  fi
}
```

- [ ] **Step 5: Add archive + reopen to main dispatch**

```bash
archive)
  shift
  cmd_archive "$@"
  ;;
reopen)
  shift
  cmd_reopen "$@"
  ;;
```

- [ ] **Step 6: Run tests — all should pass**

Run: `bash tests/test_fcase_lifecycle.sh`
Expected: Sections 1 + 2 all PASS

- [ ] **Step 7: Commit**

```bash
git add fcase tests/test_fcase_lifecycle.sh
git commit -m "feat(fcase): archive + reopen commands with lifecycle guards

archive requires resolved status. reopen works from resolved/archived/
deleted. Both record events with previous_status in payload."
```

---

### Task 3: Tombstone delete with --confirm

**Files:**
- Modify: `fcase`
- Modify: `tests/test_fcase_lifecycle.sh`

- [ ] **Step 1: Add delete tests**

```bash
# ── Section 3: Tombstone Delete ─────────────────────────────────
echo ""
echo "── Section 3: Tombstone Delete ──"

setup_test_db

"$FCASE" init test-delete --goal "Test delete" -o json >/dev/null 2>&1

# Delete without --confirm should fail
result=$("$FCASE" delete test-delete 2>&1 || true)
assert_contains "delete without confirm fails" "$result" "requires --confirm"

# Delete with --confirm should succeed (tombstone)
result=$("$FCASE" delete test-delete --confirm -o json 2>&1)
assert_contains "delete with confirm succeeds" "$result" "deleted"

# Default list should NOT show deleted case
list_output=$("$FCASE" list -o json 2>&1)
assert_not_contains "deleted case hidden from default list" "$list_output" "test-delete"

# List --deleted should show it
list_deleted=$("$FCASE" list --deleted -o json 2>&1)
assert_contains "deleted case visible with --deleted flag" "$list_deleted" "test-delete"

# Reopen should recover deleted case
result=$("$FCASE" reopen test-delete -o json 2>&1)
assert_contains "reopen recovers deleted case" "$result" "open"

# After reopen, should appear in default list again
list_output=$("$FCASE" list -o json 2>&1)
assert_contains "reopened case back in default list" "$list_output" "test-delete"

teardown_test_db
```

- [ ] **Step 2: Implement cmd_delete**

```bash
cmd_delete() {
  local slug="${1:-}"
  shift || true
  [[ -n "$slug" ]] || die "delete requires <slug>"

  local confirm=false output="$DEFAULT_OUTPUT"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --confirm) confirm=true; shift ;;
      -o|--output) output="${2:-}"; shift 2 ;;
      *) die "Unknown option for delete: $1" ;;
    esac
  done
  [[ "$confirm" == "true" ]] || die "delete requires --confirm (this is a destructive operation)"

  ensure_db
  local case_id now current_status
  case_id="$(case_exists_or_die "$slug")"
  current_status="$(db_query <<<"SELECT status FROM cases WHERE id = $case_id;")"
  [[ "$current_status" != "deleted" ]] || die "case '$slug' is already deleted"

  now="$(now_utc)"
  local session_id
  session_id="$(latest_session_id_for_case "$case_id")"

  if ! db_exec <<SQL
PRAGMA foreign_keys=ON;
BEGIN IMMEDIATE;
UPDATE cases SET status = 'deleted', deleted_at = $(sql_quote "$now"), updated_at = $(sql_quote "$now") WHERE id = $case_id;
INSERT INTO events (case_id, session_id, event_type, payload_json, created_at)
VALUES ($case_id, ${session_id:-NULL}, 'case_deleted', json_object('previous_status', $(sql_quote "$current_status")), $(sql_quote "$now"));
COMMIT;
SQL
  then
    die "failed to delete case"
  fi

  if [[ "$output" == "json" ]]; then
    db_query <<SQL
SELECT json_object('slug', slug, 'status', status, 'deleted_at', deleted_at) FROM cases WHERE id = $case_id;
SQL
  else
    echo "Case '$slug' tombstoned (soft-deleted). Use 'fcase reopen $slug' to recover."
  fi
}
```

- [ ] **Step 3: Update cmd_list to filter by status**

Replace the existing `cmd_list` function. Add `--all`, `--resolved`, `--archived`, `--deleted`, `--status` flags. Default shows only `open` cases.

The key change in the SQL: add `WHERE status = 'open'` by default, or adjust based on filter flag.

In the argument parsing section of `cmd_list`, add:

```bash
local filter="open"
# in the case statement:
--all) filter="all"; shift ;;
--resolved) filter="resolved"; shift ;;
--archived) filter="archived"; shift ;;
--deleted) filter="deleted"; shift ;;
--status) filter="${2:-}"; shift 2 ;;
```

Then in the SQL, change `FROM cases` to:
```sql
-- NOTE: production code uses sql_quote() for safe parameterization
FROM cases WHERE status = '${filter}'
```
For `--all`, use `WHERE status != 'deleted'` (exclude only tombstoned).

- [ ] **Step 4: Add delete to main dispatch**

```bash
delete)
  shift
  cmd_delete "$@"
  ;;
```

- [ ] **Step 5: Run tests — all should pass**

Run: `bash tests/test_fcase_lifecycle.sh`
Expected: Sections 1 + 2 + 3 all PASS

- [ ] **Step 6: Commit**

```bash
git add fcase tests/test_fcase_lifecycle.sh
git commit -m "feat(fcase): tombstone delete + filtered list

delete requires --confirm, sets status='deleted' + deleted_at. No hard
deletes. list defaults to open-only, supports --all/--resolved/--archived/
--deleted/--status filters. Deleted cases recoverable via reopen."
```

---

### Task 4: Knowledge search — fcase find

**Files:**
- Modify: `fcase`
- Modify: `tests/test_fcase_lifecycle.sh`

- [ ] **Step 1: Add find tests**

```bash
# ── Section 4: Knowledge Search (find) ──────────────────────────
echo ""
echo "── Section 4: Knowledge Search ──"

setup_test_db

# Create and resolve cases with known content
"$FCASE" init auth-fix --goal "Fix auth token validation" -o json >/dev/null 2>&1
"$FCASE" resolve auth-fix --summary "Model leaked channel metadata into tool-call field. Hardened allowlist." -o json >/dev/null 2>&1

"$FCASE" init proxy-bug --goal "Fix yt-dlp proxy 407 errors" -o json >/dev/null 2>&1
"$FCASE" resolve proxy-bug --summary "Proxy retry was infinite loop. Added max retries." -o json >/dev/null 2>&1
"$FCASE" archive proxy-bug -o json >/dev/null 2>&1

"$FCASE" init still-open --goal "This is still open" -o json >/dev/null 2>&1

# Find by slug match
result=$("$FCASE" find "auth" -o json 2>&1)
assert_contains "find matches slug" "$result" "auth-fix"

# Find by summary match
result=$("$FCASE" find "channel metadata" -o json 2>&1)
assert_contains "find matches summary" "$result" "auth-fix"

# Find by goal match
result=$("$FCASE" find "proxy 407" -o json 2>&1)
assert_contains "find matches goal" "$result" "proxy-bug"

# Find excludes open cases by default
result=$("$FCASE" find "still open" -o json 2>&1)
assert_not_contains "find excludes open by default" "$result" "still-open"

# Find --all includes open cases
result=$("$FCASE" find "still open" --all -o json 2>&1)
assert_contains "find --all includes open" "$result" "still-open"

# Find includes both resolved and archived
result=$("$FCASE" find "proxy" -o json 2>&1)
assert_contains "find includes archived" "$result" "proxy-bug"

teardown_test_db
```

- [ ] **Step 2: Implement cmd_find**

```bash
cmd_find() {
  local query="${1:-}"
  shift || true
  [[ -n "$query" ]] || die "find requires <query>"

  local deep=false include_all=false include_deleted=false output="$DEFAULT_OUTPUT"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --deep) deep=true; shift ;;
      --all) include_all=true; shift ;;
      --deleted) include_deleted=true; shift ;;
      -o|--output) output="${2:-}"; shift 2 ;;
      *) die "Unknown option for find: $1" ;;
    esac
  done

  ensure_db
  local escaped_query status_filter
  escaped_query="$(sql_quote "%${query}%")"

  # Default: resolved + archived. --all adds open. --deleted adds deleted.
  if [[ "$include_all" == "true" && "$include_deleted" == "true" ]]; then
    status_filter="1=1"
  elif [[ "$include_all" == "true" ]]; then
    status_filter="c.status != 'deleted'"
  elif [[ "$include_deleted" == "true" ]]; then
    status_filter="c.status IN ('resolved', 'archived', 'deleted')"
  else
    status_filter="c.status IN ('resolved', 'archived')"
  fi

  if [[ "$output" == "json" ]]; then
    if [[ "$deep" == "true" ]]; then
      # Deep: also search evidence body and hypothesis body
      db_query <<SQL
SELECT json_object('query', ${escaped_query}, 'results',
  COALESCE((SELECT json_group_array(json_object(
    'slug', c.slug, 'status', c.status, 'priority', c.priority,
    'goal', c.goal, 'summary', c.summary,
    'resolved_at', c.resolved_at, 'archived_at', c.archived_at
  )) FROM cases c
  LEFT JOIN evidence e ON e.case_id = c.id
  LEFT JOIN hypotheses h ON h.case_id = c.id
  WHERE ${status_filter}
    AND (c.slug LIKE ${escaped_query}
      OR c.goal LIKE ${escaped_query}
      OR c.summary LIKE ${escaped_query}
      OR e.body LIKE ${escaped_query}
      OR e.summary LIKE ${escaped_query}
      OR h.body LIKE ${escaped_query})
  GROUP BY c.id
  ORDER BY
    CASE WHEN c.summary LIKE ${escaped_query} THEN 0 ELSE 1 END,
    CASE WHEN c.goal LIKE ${escaped_query} THEN 0 ELSE 1 END,
    c.updated_at DESC
  ), json('[]'))
);
SQL
    else
      # Shallow: slug, goal, summary only
      db_query <<SQL
SELECT json_object('query', ${escaped_query}, 'results',
  COALESCE((SELECT json_group_array(json_object(
    'slug', c.slug, 'status', c.status, 'priority', c.priority,
    'goal', c.goal, 'summary', c.summary,
    'resolved_at', c.resolved_at, 'archived_at', c.archived_at
  )) FROM cases c
  WHERE ${status_filter}
    AND (c.slug LIKE ${escaped_query}
      OR c.goal LIKE ${escaped_query}
      OR c.summary LIKE ${escaped_query})
  ORDER BY
    CASE WHEN c.summary LIKE ${escaped_query} THEN 0 ELSE 1 END,
    CASE WHEN c.goal LIKE ${escaped_query} THEN 0 ELSE 1 END,
    c.updated_at DESC
  ), json('[]'))
);
SQL
    fi
  else
    # Pretty output
    local results
    results=$(db_query <<SQL
SELECT c.slug, c.status, c.priority, c.goal, c.summary, c.resolved_at
FROM cases c
WHERE ${status_filter}
  AND (c.slug LIKE ${escaped_query}
    OR c.goal LIKE ${escaped_query}
    OR c.summary LIKE ${escaped_query})
ORDER BY
  CASE WHEN c.summary LIKE ${escaped_query} THEN 0 ELSE 1 END,
  c.updated_at DESC;
SQL
    )
    if [[ -z "$results" ]]; then
      echo "No cases found matching '$query'"
    else
      local count
      count=$(echo "$results" | wc -l)
      echo "Found $count case(s) matching '$query'"
      echo ""
      echo "$results" | while IFS='|' read -r rslug rstatus rpriority rgoal rsummary rresolved; do
        echo "  [$rstatus] $rslug ($rpriority)"
        echo "    Goal: $rgoal"
        [[ -n "$rsummary" ]] && echo "    Summary: $rsummary"
        [[ -n "$rresolved" ]] && echo "    Resolved: $rresolved"
        echo ""
      done
    fi
  fi
}
```

- [ ] **Step 3: Add find to main dispatch**

```bash
find)
  shift
  cmd_find "$@"
  ;;
```

- [ ] **Step 4: Run tests — all should pass**

Run: `bash tests/test_fcase_lifecycle.sh`
Expected: Sections 1-4 all PASS

- [ ] **Step 5: Commit**

```bash
git add fcase tests/test_fcase_lifecycle.sh
git commit -m "feat(fcase): knowledge search with fcase find

Searches slug, goal, summary by default (shallow). --deep adds evidence
and hypothesis body search. Default scope: resolved + archived. --all
includes open. --deleted includes tombstoned. Ranked: summary > goal."
```

---

### Task 5: MCP Registration Update

**Files:**
- Modify: `mcp/index.js`

- [ ] **Step 1: Update fcase MCP registration**

In `mcp/index.js`, find the fcase registration (line ~780-804). Update:

1. Expand the action enum:
```javascript
action: z.enum(["init", "note", "status", "list", "next", "handoff", "export",
  "resolve", "archive", "reopen", "delete", "find"]).describe("Case action"),
```

2. Add new fields to inputSchema:
```javascript
summary: z.string().optional().describe("Resolution summary (required for resolve)"),
query: z.string().optional().describe("Search query (for find)"),
confirm: z.boolean().optional().describe("Confirm destructive operation (required for delete)"),
deep: z.boolean().optional().describe("Deep search including evidence/hypotheses (for find)"),
filter: z.enum(["open", "resolved", "archived", "deleted", "all"]).optional()
  .describe("Status filter for list (default: open)"),
```

3. Update the handler to pass new args:
```javascript
async ({ action, slug, goal, body, priority, summary, query, confirm, deep, filter }) => {
  const args = [action];
  if (action === "find" && query) {
    args.push(query);
  } else if (slug) {
    args.push(slug);
  }
  if (goal) args.push("--goal", goal);
  if (body) args.push("--body", body);
  if (priority) args.push("--priority", priority);
  if (summary) args.push("--summary", summary);
  if (confirm) args.push("--confirm");
  if (deep) args.push("--deep");
  if (filter === "all") args.push("--all");
  else if (filter && filter !== "open") args.push(`--${filter}`);
  args.push("-o", "pretty");
  return cli("fcase", args);
}
```

- [ ] **Step 2: Verify MCP server starts**

Run: `cd mcp && node -e "import('./index.js').then(() => console.log('OK')).catch(e => { console.error(e); process.exit(1) })"`
Expected: `OK`

- [ ] **Step 3: Commit**

```bash
git add mcp/index.js
git commit -m "feat(fcase): MCP registration for resolve/archive/reopen/delete/find

Expanded action enum, added summary/query/confirm/deep/filter fields.
Handler maps new fields to CLI flags."
```

---

### Task 6: Test Runner Integration + Final Validation

**Files:**
- Modify: `tests/run_all_tests.sh`

- [ ] **Step 1: Add fcase lifecycle tests to run_all_tests.sh**

Add after existing fcase test block (or at the end before the summary):

```bash
# ── fcase lifecycle ────────────────────────────────────────────
run_test_suite "${SCRIPT_DIR}/test_fcase_lifecycle.sh" "fcase lifecycle"
```

- [ ] **Step 2: Run full fcase lifecycle test suite**

Run: `bash tests/test_fcase_lifecycle.sh`
Expected: All sections pass

- [ ] **Step 3: Run fmetrics import**

Run: `bash fmetrics import`
Expected: Records imported

- [ ] **Step 4: Commit**

```bash
git add tests/run_all_tests.sh
git commit -m "chore: add fcase lifecycle tests to master test runner"
```
