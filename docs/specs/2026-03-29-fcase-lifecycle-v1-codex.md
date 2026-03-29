# fcase Durable Lifecycle + Knowledge Search v1

## Summary

Turn fcase from an open-only continuity ledger into a durable case system with a real lifecycle and searchable knowledge retention.

This v1 adds:

- Durable case statuses: open, resolved, archived, deleted
- No hard-delete workflow in the tool surface; delete becomes a tombstoning soft delete
- Required resolution summaries so concluded cases become usable knowledge
- Agent-first fcase find backed by SQLite FTS for fast recall
- Read/write parity across CLI and MCP so agents can use the same lifecycle cleanly

## Public Interface Changes

### CLI

Add these subcommands to fcase:

- fcase resolve <slug> --summary <text> [-o pretty|json]
- fcase archive <slug> [-o pretty|json]
- fcase delete <slug> --reason <text> --confirm DELETE [-o pretty|json]
- fcase find <query> [--deep] [--status <csv|all>] [-o pretty|json]

Change existing list behavior:

- fcase list defaults to open cases only
- fcase list --status <csv|all> supports comma-separated statuses from open,resolved,archived,deleted or all
- fcase list --status all preserves the old "show everything" behavior

Lifecycle rules:

- resolve allowed only from open
- archive allowed only from resolved
- delete allowed from open, resolved, or archived; reject if already deleted
- resolve requires --summary
- delete requires both --reason and --confirm DELETE

find defaults:

- Default status scope: resolved,archived
- Tombstoned deleted cases are hidden by default
- --deep extends search beyond case-level fields

### MCP

Extend the existing fcase MCP tool rather than adding a second tool.

- Add actions: resolve, archive, delete, find
- Add structured fields instead of overloading body:
    - summary for resolve
    - reason and confirm_delete for delete
    - query, deep, and statuses for find
    - statuses for list
- Keep existing actions unchanged

### Read Model

Expand the case JSON returned by status/export/JSON list/JSON find to include:

- status
- resolution_summary
- resolved_at
- archived_at
- deleted_at
- delete_reason

status and export must still work for deleted cases when addressed by slug.

## Implementation Changes

### Schema + Migration

Add DB migration user_version=3 in _fsuite_db.sh.

Extend cases with:

- resolution_summary TEXT NOT NULL DEFAULT ''
- resolved_at TEXT
- archived_at TEXT
- deleted_at TEXT
- delete_reason TEXT NOT NULL DEFAULT ''

Use cases.status as the canonical lifecycle state with values:

- open
- resolved
- archived
- deleted

Do not move deleted cases to another table.

- Tombstoned rows stay in cases
- Related rows in targets, evidence, hypotheses, events, and case_sessions remain intact

Add performance indexes:

- cases(status, updated_at DESC)
- events(case_id, id DESC)
- evidence(case_id)
- hypotheses(case_id)
- targets(case_id)
- case_sessions(case_id, id DESC)

### Audit + Event Model

Use current-state columns for reads and append-only events for history.

Add lifecycle events:

- case_resolved
- case_archived
- case_deleted

Event payloads must include:

- prior_status
- summary for resolve
- reason for delete

Behavioral updates:

- resolve sets status='resolved', writes resolution_summary, stamps resolved_at, clears next_move, updates updated_at
- archive sets status='archived', stamps archived_at, updates updated_at
- delete sets status='deleted', stamps deleted_at, writes delete_reason, clears next_move, updates updated_at

No restore command in v1.
No hard delete command in v1.

### Knowledge Search

Add an FTS-backed search layer for fcase find.

Create one FTS4 table keyed by case_id with explicit searchable columns (FTS4 chosen for broader SQLite compatibility — system SQLite 3.46.1 does not compile FTS5):

- slug
- goal
- resolution_summary
- targets_text
- evidence_text
- hypotheses_text
- notes_text

Populate/search semantics:

- Shallow mode searches only slug, goal, resolution_summary
- --deep searches all columns
- targets_text aggregates target paths and symbols
- evidence_text aggregates evidence summaries and bodies
- hypotheses_text aggregates hypothesis bodies and reasons
- notes_text aggregates session summaries plus note/next/resolve/delete event text

Maintain FTS by explicit rebuild helpers called from every mutating fcase command that changes searchable text.

- Run a full initial rebuild during migration for existing cases

find -o json returns:

- query metadata
- effective statuses
- whether deep mode was used
- ordered case hits with case metadata, matched field labels, and short snippets

find -o pretty prints:

- one compact block per case with slug, status, priority, goal
- resolution summary when present
- 1-2 short search snippets

### Command and Read Updates

Update fcase usage/help, command dispatch, and JSON builders.

Specific behavior:

- status_json and export_json must emit lifecycle metadata
- list must filter before counting/rendering
- pretty list header should reflect the effective filter, not total DB row count
- find should rank exact slug hits highest, then resolution summary/goal hits, then deep-text hits

Update MCP registration in mcp/index.js to reflect the new action enum and structured fields.

## Test Plan

Add coverage in tests/test_fcase.sh and any MCP smoke coverage already used by the suite.

Required scenarios:

- Migration from existing v2 DB to v3 preserves current rows and fills defaults
- resolve fails without --summary
- resolve succeeds only from open
- archive succeeds only from resolved
- delete fails without --reason
- delete fails without --confirm DELETE
- delete tombstones the case row instead of removing it
- status and export still return deleted cases by slug
- list defaults to open only
- list --status all includes everything
- list with comma-separated statuses filters correctly
- find default scope is resolved,archived
- find shallow mode matches slug, goal, resolution_summary only
- find --deep matches targets, evidence, hypotheses, and note/session text
- deleted cases are excluded from find by default and returned only with explicit status filter
- lifecycle actions append the correct event payloads
- FTS rebuild stays in sync after init, note, next, target, evidence, hypothesis, resolve, archive, and delete
- MCP fcase accepts the new actions and argument shapes without breaking old ones

## Assumptions and Defaults

- resolve, not close, is the canonical verb in v1
- Archived cases are always resolved first; no direct open -> archived
- Deleted cases remain searchable only by explicit opt-in
- find is a knowledge-retrieval command first, so it defaults to resolved,archived rather than active open work
- Lifecycle metadata lives on cases; events provide history, not reconstruction
- No hard-delete path is exposed by fcase after this change
