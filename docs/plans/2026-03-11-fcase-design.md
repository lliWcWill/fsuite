# fcase Design

**Date:** 2026-03-11

## Source Of Truth

This design supersedes the earlier March 9 `fcase` draft as the implementation kickoff source of truth.

The March 9 docs were directionally correct on the core shape:

- thin continuity ledger
- separate `~/.fsuite/fcase.db`
- normalized current-state tables plus append-only events
- narrow CLI
- explicit future import surfaces

This March 11 design keeps that core, but sharpens the product framing, the rollout discipline, and the read-model rules.

## Goal

Build `fcase` as the continuity and handoff layer for fsuite investigations.

`fsuite` already scouts, narrows, maps, and reads effectively through `ftree`, `fsearch`, `fmap`, and `fread`. The remaining gap is not discovery. The remaining gap is preserving investigation state across resets, resumptions, interruptions, and agent handoffs.

`fcase` fills that gap with a thin, structured case ledger.

## Product Positioning

`fcase` is:

- a continuity layer
- a handoff layer
- a structured case ledger

`fcase` is not:

- a search tool
- an orchestrator
- a transcript archive
- a graph engine
- a dashboard backend
- a giant ontology

It must never infer repo structure on its own. It consumes outputs from the rest of fsuite; it does not replace them.

## Problem

Current fsuite flow is strong at repo cognition but weak at investigation continuity.

Today an agent can:

- scout with `ftree`
- narrow with `fsearch`
- map with `fmap`
- extract proof with `fread`
- edit with `fedit`
- measure with `fmetrics`

What it cannot do cleanly is persist the live shape of an investigation without falling back to:

- ad hoc notes
- stale handoff docs
- long chat context
- noisy memory entries
- manual reconstruction after interruption

That creates repeated costs:

- duplicate recon after reset
- stale or contradictory state between agents
- weak handoffs
- no durable record of rejected hypotheses
- no structured evidence chain
- no compact “what matters now” state

## Opportunity

`fcase` turns fsuite from a strong repo-cognition toolkit into a true investigation workflow system.

The leverage point is not more reconnaissance. It is durable continuity:

- preserve investigation intent
- preserve ranked targets
- preserve evidence and reasoning state
- generate compact handoffs
- support future structured ingestion from tool outputs

## Canonical Workflow

```text
ftree -> fsearch -> fmap -> fread -> fcase -> fedit -> fmetrics
```

`fcase` begins once the seam is known and continuity becomes the bottleneck.

## Product Principles

### Thin over clever

Keep it explicit, durable, and small.

### Structured over narrative

Notes still matter, but typed targets, evidence, and hypotheses are first-class.

### Read current state fast

`status` and `handoff` must read current state directly, not reconstruct it from archaeology.

### Events for history, not reconstruction

Append-only events support audit and history. They are not the primary read model.

### Designed for future imports

The MVP must leave clean room for structured imports from `fread` and `fmap`.

## Users

### Primary user

An agent or power user actively investigating code, runtime incidents, regressions, behavior changes, or architecture questions.

### Secondary user

A follow-on agent inheriting an interrupted investigation and needing a clean, truthful handoff.

## Core Use Cases

### Start an investigation

Create a case, give it a slug and goal, open a session, and start accumulating state.

### Track what matters

Record the files and symbols that matter, along with rank, reason, and state.

### Preserve proof

Store structured evidence and excerpts so the next step is based on proof, not memory.

### Track reasoning state

Track hypotheses, advance or reject them, and keep the next best move current.

### Hand off cleanly

Another agent should be able to call `fcase handoff` or `fcase status` and immediately see what matters now.

## MVP Scope

### CLI Surface

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

### MVP Job

The MVP must:

- track the current investigation goal
- track the files and symbols that matter
- store structured evidence
- track open and rejected hypotheses
- store the next best move
- generate a handoff packet for another agent

## Architecture

### Recommended shape

Thin normalized ledger plus append-only event stream.

### Rejected alternatives

- event log only
- one JSON blob per case
- embedding `fcase` into `telemetry.db`

The reason is the same in each case: mutable investigation state and telemetry are different products with different trust and lifecycle boundaries.

## Storage

- dedicated SQLite database: `~/.fsuite/fcase.db`
- schema versioning via `PRAGMA user_version`
- `PRAGMA journal_mode=WAL`
- `PRAGMA foreign_keys=ON` on each connection

## Data Model

### `cases`

Current case-level state for fast reads.

- `id`
- `slug` unique
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

Structured list of files and symbols that matter.

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

Target state vocabulary in v0.1:

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

Implementation note:

- line fields should be nullable when absent
- do not use `0` sentinels for “not provided”

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

Implementation note:

- keep `confidence` contract explicit in CLI and JSON output
- do not hard-wire a misleading type choice too early

### `events`

Typed append-only ledger of notes and state transitions.

- `id`
- `case_id`
- `session_id`
- `event_type`
- `payload_json`
- `created_at`

Events support history and audit. They do not own the primary read model.

## Output Contracts

### `init -o json`

Returns:

- created case
- opened session
- creation event

### `status -o json`

Returns a stable read-model envelope with:

- `case`
- `active_session`
- `targets`
- `evidence`
- `hypotheses`
- `recent_events`

### `pretty`

Optimized for humans, especially `status` and `handoff`.

### `export`

Portable machine-readable full case envelope.

## Command Semantics

### `init`

Creates the case, opens the first session, writes a `case_init` event.

### `list`

Shows known cases.

### `status`

Reads current state from first-class tables, not by replaying the event stream.

### `note`

Adds a note event and updates case timestamps.

### `target add`

Creates a typed target record and a corresponding event.

### `evidence`

Creates an evidence record and a corresponding event.

### `hypothesis add` / `hypothesis set`

Creates or changes structured hypothesis state and appends corresponding events.

### `reject`

Convenience alias only. It must resolve to a typed state change:

- target -> `state=ruled_out`
- hypothesis -> `status=rejected`

If it cannot resolve cleanly, it must fail.

### `next`

Updates `cases.next_move`, updates timestamps, and appends a next-step event.

### `handoff`

Generates a concise read over the current case plus recent events.

### `export`

Emits the full portable case envelope.

## Validation Rules

### `evidence`

Manual entry requires exactly one body source:

- `--body`
- `--body-file`

`--lines` format:

- `start:end`
- 1-based
- inclusive
- positive integers only
- `start <= end`

If `--match-line` is provided, it must fall within that inclusive range.

### `reject`

- requires exactly one selector in v0.1
- selectors are ID-based only
- ambiguous or unresolvable input fails

## Structured Imports Roadmap

The MVP must be designed for structured imports even if every import command does not land in the first patch.

Planned surfaces:

- `fread -o json | fcase evidence import <slug>`
- `fmap -o json | fcase target import <slug>`
- later: `fedit -o json | fcase note import <slug>`

These remain explicit subcommands, not stdin magic.

## Success Metrics

### Functional

- an agent can resume a case without re-deriving the seam from scratch
- handoff contains current goal, key targets, evidence, hypotheses, and next move
- rejected hypotheses are preserved explicitly
- export produces a portable case envelope

### Behavioral

- less repeated recon after interruption
- faster handoffs between agents
- lower dependence on stale chat context and ad hoc markdown notes

## Risks

### Risk: platform sprawl

Mitigation:

- keep the command surface narrow
- refuse repo discovery behavior
- keep imports explicit

### Risk: mushy state

Mitigation:

- keep current state in normalized tables
- use events for history, not primary reconstruction

### Risk: schema churn when imports land

Mitigation:

- keep `payload_json` now
- keep typed targets and evidence now

## Rollout Recommendation

### Phase 1

Ship the thin ledger first:

- schema
- core commands
- notes / next / handoff / export
- typed targets / evidence / hypotheses / reject

### Phase 2

Add structured imports if they remain cheap:

- `evidence import`
- `target import`

## Recommendation

Yes: `fcase` is the right next moat to build now.

The suite can already scout, narrow, map, and read. The next leverage point is durable investigation continuity. Build `fcase` as a thin structured case ledger first, not a grand framework.
