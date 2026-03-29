# fcase Lifecycle Upgrade — Close, Archive, Knowledge Base

> v1 design spec. Frozen 2026-03-29 by Claude + Codex + Player3.

## Problem

fcase has no way to close or resolve cases. Status is set to `open` on `init` and never changes.
Cases that are done stay open forever, cluttering `fcase list`. Agents that delete cases to "clean
up" cause hard data loss (IDs 10-12 were DELETEd, case rows gone, orphaned events survived by
accident). There is no knowledge base — resolved investigations with validated hypotheses and
evidence chains are not searchable or reusable.

## What This Adds

1. **Case lifecycle:** `open → resolved → archived` with mandatory conclusion summaries
2. **Filtered listing:** `fcase list` shows open only by default, with flags for broader views
3. **Safe deletion:** `fcase delete` exists but requires `--confirm`, does tombstone soft-delete
4. **Knowledge retrieval:** `fcase find` searches resolved/archived case conclusions and evidence

## Lifecycle State Machine

```
  open ──resolve──→ resolved ──archive──→ archived
    │                  │                      │
    │                  │                      │
    └──── delete ──────┴─── delete ───────────┘
          (soft, requires --confirm)
```

### `fcase resolve <slug> --summary "..."`

- Transitions status: `open → resolved`
- **Requires** `--summary` (the conclusion/knowledge — mandatory, not optional)
- Records a `case_resolved` event with the summary in payload_json
- Sets `updated_at` to now
- If case is already resolved or archived: error "case is not open"
- The summary is the knowledge artifact — it should capture what was learned, not just "done"

### `fcase archive <slug>`

- Transitions status: `resolved → archived`
- Records a `case_archived` event
- Sets `updated_at` to now
- If case is not resolved: error "only resolved cases can be archived"
- No additional metadata required — the resolve summary is the knowledge

### `fcase reopen <slug>`

- Transitions status: `resolved → open` OR `archived → open`
- Records a `case_reopened` event
- Sets `updated_at` to now
- Use case: new information invalidates the conclusion

### `fcase delete <slug> --confirm`

- **Requires** `--confirm` flag (no silent deletion)
- Does NOT delete the row. Sets `status = 'deleted'` and `deleted_at = now()`
- Records a `case_deleted` event
- Deleted cases are invisible to `list`, `status`, `find` by default
- Recoverable: `fcase reopen <slug>` can restore a deleted case
- Works from any status (open, resolved, archived)

## List Filtering

### `fcase list` (default)

Shows only `open` cases. Same output format as today.

### `fcase list --all`

Shows `open` + `resolved` + `archived`. Excludes deleted.

### `fcase list --resolved`

Shows only `resolved` cases.

### `fcase list --archived`

Shows only `archived` cases.

### `fcase list --deleted`

Shows only tombstoned cases (for recovery).

### `fcase list --status <value>`

Explicit filter: `open`, `resolved`, `archived`, `deleted`.

## Knowledge Retrieval: `fcase find`

### `fcase find <query>`

Searches across resolved and archived cases for knowledge reuse.

**Default search (shallow):** slug, goal, resolution summary only.
This is the knowledge base surface — "what do we know about X?"

**`--deep` flag:** also searches evidence notes, hypothesis text, and event payloads.
Use when looking for exact matches in the investigation trail — "has anyone seen this error before?"

- Returns matching cases ranked by relevance (summary matches > goal matches > note matches)
- Default: searches resolved + archived only (the knowledge base)
- `--all` flag: also searches open cases
- Tombstoned/deleted cases hidden by default (never appear in find unless `--deleted` flag)
- Output modes: `pretty` (default) and `json`

### Pretty output format

```
Found 3 cases matching "tool-call validation"

  [resolved] tool-call-validation (high)
    Goal: Investigate Ghost Claw tool-call validation failures
    Summary: Model leaks channel-format metadata into tool-call field.
             Fix: harden tool-name allowlist with alias normalization.
    Resolved: 2026-03-28

  [archived] openai-whisper-name-drift (normal)
    Goal: Fix openai-whisper-api vs openai_whisper_api name mismatch
    Summary: Provider adapter was not normalizing hyphens to underscores.
    Resolved: 2026-03-25, Archived: 2026-03-27
```

### JSON output format

```json
{
  "query": "tool-call validation",
  "results": [
    {
      "slug": "tool-call-validation",
      "status": "resolved",
      "priority": "high",
      "goal": "Investigate Ghost Claw tool-call validation failures",
      "summary": "Model leaks channel-format metadata...",
      "resolved_at": "2026-03-28T...",
      "match_fields": ["slug", "summary"]
    }
  ]
}
```

## Database Changes

### Alter `cases` table

Add columns:
- `resolution_summary TEXT DEFAULT ''` — resolve conclusion (the knowledge artifact)
- `resolved_at TEXT` — when resolved
- `archived_at TEXT` — when archived
- `deleted_at TEXT` — when soft-deleted (tombstone)

No schema migration needed — SQLite `ALTER TABLE ADD COLUMN` is safe for defaults.

### New event types

- `case_resolved` — payload: `{"summary": "...", "previous_status": "open"}`
- `case_archived` — payload: `{"previous_status": "resolved"}`
- `case_reopened` — payload: `{"previous_status": "resolved|archived|deleted"}`
- `case_deleted` — payload: `{"previous_status": "open|resolved|archived"}`

## MCP Registration Updates

Add new actions to the fcase MCP tool schema:
- `resolve` — requires slug + summary
- `archive` — requires slug
- `reopen` — requires slug
- `delete` — requires slug (+ confirm flag)
- `find` — requires query

Update the `action` enum in inputSchema:
```
z.enum(["init", "note", "status", "list", "next", "handoff", "export", "resolve", "archive", "reopen", "delete", "find"])
```

Add `summary` field to inputSchema (for resolve).
Add `query` field to inputSchema (for find).
Add `confirm` boolean field (for delete).
Add `deep` boolean field (for find --deep).
Add `filter` field for list filtering: `z.enum(["open", "resolved", "archived", "deleted", "all"]).optional()`.

## CLI Interface Updates

```
fcase resolve <slug> --summary "conclusion text"
fcase archive <slug>
fcase reopen <slug>
fcase delete <slug> --confirm
fcase find <query> [--deep] [--all] [--deleted] [-o pretty|json]
fcase list [--all|--resolved|--archived|--deleted|--status <value>]
```

## Safety Guarantees

1. **No hard deletes.** `fcase delete` is always a tombstone. The row stays in the DB.
2. **Mandatory summaries.** Can't close a case without capturing what was learned.
3. **Events are immutable.** Every lifecycle transition is recorded. Full audit trail.
4. **Deleted cases are recoverable.** `fcase reopen` works on deleted cases.
5. **Default list is clean.** Only open cases by default. Knowledge lives in `find`.

## Testing Strategy

- Unit tests for each lifecycle transition (resolve, archive, reopen, delete)
- Validation tests: can't resolve without summary, can't archive non-resolved, can't delete without --confirm
- Status filter tests for list
- find query tests: match by slug, goal, summary, evidence
- Tombstone tests: deleted cases invisible by default, recoverable via reopen
- Event audit trail tests: every transition records correct event type + payload

## v1 Non-Goals

- No auto-archive (time-based expiry)
- No case templates
- No cross-case linking (except through find)
- No export-to-obsidian integration (v2 candidate)
- No full-text search index (SQLite LIKE is sufficient for v1)
