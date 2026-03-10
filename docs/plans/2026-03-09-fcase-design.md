# fcase Design

**Date:** 2026-03-09

## Goal

Define `fcase` as the next moat for `fsuite`: a thin continuity and handoff ledger for investigations that lands after the current trust and symbol ergonomics sprint.

## Positioning

`fcase` is not the next patch in the active sprint. The current sequence remains:

1. finish `fmetrics` trust and prediction hardening
2. land symbol ergonomics in `fmap` and `fread`
3. then start `fcase`

The positioning line for the product is:

> `fcase` is the continuity layer that starts after the suite can already scout, narrow, map, and read reliably.

## Canonical Workflow

```text
ftree -> fsearch -> fmap -> fread -> fcase -> fedit -> fmetrics
```

`fcase` does not replace reconnaissance. It preserves what the investigation learned once the seam is known.

## Purpose

`fcase` is a thin continuity and handoff ledger for investigations.

Its core job is to:

- track what the agent is trying to solve
- track which files and symbols matter
- store structured evidence
- track open and rejected hypotheses
- record the next best move
- generate clean handoff state for another agent

## Non-goals

`fcase` is explicitly not:

- a search tool
- an orchestrator
- a transcript archive
- a graph engine
- a dashboard backend
- a giant ontology

It should never try to infer repo structure on its own. It should consume outputs from `ftree`, `fsearch`, `fmap`, and `fread`, not replace them.

## Architecture

The recommended shape is a thin normalized ledger plus an append-only event stream.

Rejected alternatives:

- event log only: too mushy for `status` and `handoff`
- one JSON blob per case: flexible early, weak for filtering, ranking, and structured imports
- embedding cases into `telemetry.db`: rejected because telemetry and mutable investigation state have different lifecycles and trust boundaries

### Storage

- separate SQLite database: `~/.fsuite/fcase.db`
- schema versioning via `PRAGMA user_version`
- `PRAGMA journal_mode=WAL`
- `PRAGMA foreign_keys=ON` on each connection

This keeps mutable case state isolated from append-only runtime telemetry.

## Schema

### `cases`

Current case-level state for fast reads.

- `id`
- `slug` UNIQUE
- `goal`
- `status`
- `priority`
- `next_move`
- `created_at`
- `updated_at`

### `case_sessions`

Lightweight session boundaries for resumptions and handoffs.

- `id`
- `case_id`
- `started_at`
- `ended_at`
- `actor`
- `summary`

### `targets`

Structured list of files and symbols that matter to the investigation.

- `id`
- `case_id`
- `path`
- `symbol`
- `symbol_type`
- `rank`
- `reason`
- `state`
- `created_at`
- `updated_at`

Target state vocabulary is fixed in v0.1:

- `candidate`
- `active`
- `validated`
- `ruled_out`

### `evidence`

Structured facts captured from tool output or manual entry.

- `id`
- `case_id`
- `tool`
- `path`
- `symbol`
- `line_start`
- `line_end`
- `match_line`
- `summary`
- `body`
- `payload_json`
- `fingerprint`
- `created_at`

### `hypotheses`

Tracked explanations and their current state.

- `id`
- `case_id`
- `body`
- `status`
- `confidence`
- `reason`
- `created_at`
- `updated_at`

Recommended status vocabulary:

- `open`
- `active`
- `validated`
- `rejected`

### `events`

Typed append-only ledger of state transitions and notes.

- `id`
- `case_id`
- `session_id`
- `event_type`
- `payload_json`
- `created_at`

The event stream records:

- notes
- target adds and state changes
- evidence adds and imports
- hypothesis adds and transitions
- next-step updates
- handoff snapshots

## Command Surface

The v0.1 CLI should stay intentionally narrow:

- `fcase init <slug> --goal ... [--priority ...] [-o pretty|json]`
- `fcase list [-o pretty|json]`
- `fcase status <slug> [-o pretty|json]`
- `fcase note <slug> --body ...`
- `fcase target add <slug> --path ... [--symbol ... --symbol-type ... --rank ... --reason ... --state ...]`
- `fcase evidence <slug> --tool ... [--path ... --symbol ... --lines <start:end> --match-line ... --summary ...] (--body ... | --body-file <path>)`
- `fcase hypothesis add <slug> --body ... [--confidence ...]`
- `fcase hypothesis set <slug> --id ... --status ... [--reason ... --confidence ...]`
- `fcase reject <slug> (--target-id <id> | --hypothesis-id <id>) [--reason ...]`
- `fcase next <slug> --body ... [-o pretty|json]`
- `fcase handoff <slug> [-o pretty|json]`
- `fcase export <slug> [-o json]`

### Command semantics

- `init` creates the case and opens the first session
- `status` reads primarily from first-class tables, not by replaying the full event log
- `note` appends an event and updates case timestamps
- `target add`, `evidence`, `hypothesis add`, `hypothesis set`, `reject`, and `next` update structured state and append an event
- `handoff` is a formatted read over current state plus recent events
- `export` emits a portable JSON envelope for the full case

### `reject`

`reject` is a convenience alias, not a separate data model.

In v0.1, selector semantics are explicit and ID-based only:

- `--target-id <id>`
- `--hypothesis-id <id>`

It must resolve cleanly to a typed state change:

- target -> `state=ruled_out`
- hypothesis -> `status=rejected`

If the input cannot be resolved to a typed state transition, the command must fail rather than creating fuzzy state.

### Output contract

- `pretty` for human-centric status and handoff views
- `json` for automation and export

#### `init -o json`

`init` should return the created state in an explicit envelope:

```json
{
  "case": {
    "slug": "auth-bug",
    "goal": "Find auth failure root cause",
    "status": "open",
    "priority": "high",
    "next_move": "",
    "created_at": "2026-03-09T12:00:00Z",
    "updated_at": "2026-03-09T12:00:00Z"
  },
  "session": {
    "id": 1,
    "actor": "codex",
    "started_at": "2026-03-09T12:00:00Z",
    "ended_at": null,
    "summary": ""
  },
  "event": {
    "event_type": "case_init",
    "created_at": "2026-03-09T12:00:00Z"
  }
}
```

#### `status -o json`

`status` should return a stable read-model envelope:

```json
{
  "case": {
    "slug": "auth-bug",
    "goal": "Find auth failure root cause",
    "status": "open",
    "priority": "high",
    "next_move": "Inspect refresh-token branch in auth.py",
    "created_at": "2026-03-09T12:00:00Z",
    "updated_at": "2026-03-09T12:05:00Z"
  },
  "active_session": {
    "id": 1,
    "actor": "codex",
    "started_at": "2026-03-09T12:00:00Z",
    "ended_at": null,
    "summary": ""
  },
  "targets": [],
  "evidence": [],
  "hypotheses": [],
  "recent_events": []
}
```

The `case` object is the authoritative current state. `recent_events` provides history context, not reconstruction authority.

### Evidence payload rules

Manual evidence entry requires exactly one body source:

- `--body <text>`
- `--body-file <path>`

`evidence import` is the future explicit stdin path for structured JSON ingestion.

`--lines` format is `start:end`:

- 1-based
- inclusive
- positive integers only
- `start <= end`

If `--match-line` is provided alongside `--lines`, it must fall within that inclusive range.

## Structured Imports

The schema and CLI should leave room for structured ingestion from tool outputs now, even if all imports do not land in the first patch.

Planned import surfaces:

- `fread -o json | fcase evidence import <slug>`
- `fmap -o json | fcase target import <slug>`
- later: `fedit -o json | fcase note import <slug>`

Imports should be explicit subcommands, not autodetected stdin magic.

## Why Now

`fsuite` already knows how to scout, narrow, map, and read. The remaining gap is investigation continuity across resets, resumptions, and handoffs.

That is the specific gap `fcase` fills.

## Testing Strategy

Add a dedicated shell test suite for `fcase` and wire it into the master runner.

The first test pass should cover:

- DB bootstrap and schema creation
- `init`, `list`, and `status`
- `note` and `next`
- `target add` with explicit states
- `evidence` with line metadata
- `hypothesis add` and `hypothesis set`
- `reject` as a typed alias
- `handoff` output in pretty and JSON
- `export` JSON envelope correctness
- invalid transitions and missing cases

Tests must sandbox `HOME` so `~/.fsuite/fcase.db` is always isolated.

## Risks And Mitigations

### Risk: premature sprawl

If `fcase` starts absorbing search, orchestration, or transcript behavior, it becomes a vague platform instead of a sharp tool.

Mitigation:

- keep the command surface narrow
- reject inferred repo discovery behavior
- keep imports explicit and typed

### Risk: slow status reconstruction

An event-only model would make `status` and `handoff` expensive and messy.

Mitigation:

- keep current state in normalized tables
- use the event ledger for history, not primary reconstruction

### Risk: schema churn when imports land

If manual notes are the only first-class storage in v0.1, import support later may force rewrites.

Mitigation:

- keep `payload_json` fields now
- keep typed evidence/target tables now

## Recommendation

Ship `fcase` first as a thin ledger with schema and CLI designed for structured imports. If imports remain cheap during implementation, they can land in v0.1. Otherwise they become the first follow-on patch after the base continuity layer ships.
