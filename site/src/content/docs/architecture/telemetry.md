---
title: Telemetry
description: Every fsuite tool emits a JSONL event. fmetrics ingests it. The toolchain learns.
sidebar:
  order: 3
---

<div class="fs-drone">
  <div class="fs-drone-head">
    <span class="fs-drone-call">TELEMETRY</span>
    <span class="fs-drone-tagline">The flight recorder · every tool call, timed, sized, attributed</span>
  </div>
  <div class="fs-drone-meta">
    <div><b>Storage</b><span>~/.fsuite/telemetry.jsonl</span></div>
    <div><b>Database</b><span>~/.fsuite/telemetry.db (SQLite)</span></div>
    <div><b>Privacy</b><span>local only · no upload</span></div>
    <div><b>Opt-out</b><span>FSUITE_TELEMETRY=0</span></div>
  </div>
</div>

## Why telemetry exists

`fmetrics` is the analytics layer that learns which tool combinations win. It can't learn anything without flight data. Every fsuite tool emits a JSONL event when it finishes — telemetry is what makes `fmetrics recommend --after ftree,fsearch` answer with evidence instead of a guess.

Without telemetry, you have 14 tools and no idea which order to call them in. With telemetry, the third tool an agent calls is statistically better than the first because `fmetrics` told it which patterns work on this machine, this project, this kind of query.

## What gets recorded

Every fsuite tool emits a JSONL telemetry event on completion. The event includes:

- **Identity:** tool name, arguments, exit code, duration
- **Output shape:** input size, output size, match count
- **Backend:** what executed (bash, mcp, etc.)
- **Caller attribution:** `model_id`, `agent_id`, `session_id`
- **Hardware:** cpu, memory snapshot

Events land in `~/.fsuite/telemetry.jsonl` by default. The format is one JSON object per line — append-only, easy to grep, easy to truncate.

## Caller attribution

fsuite records which model and which agent made each tool call so `fmetrics` can do LLM benchmarking and per-agent workflow analysis. Set these once in your agent wrapper or shell:

```bash
export FSUITE_MODEL_ID=codex-gpt-5.5
export FSUITE_AGENT_ID=codex-cli
export FSUITE_SESSION_ID=bench-042
```

If you don't set them, each tool tries common runtime environment hints and parent-process detection, then falls back to `unknown` for model/agent and an empty session.

`fbash` exports detected attribution to its child processes so pipelines preserve identity. For raw shell pipelines (no `fbash` in the chain), export the variables first when you need guaranteed shared attribution across every tool event.

## Import to SQLite

The JSONL is grep-friendly but slow for analytics. Promote to SQLite once and run real queries:

```bash
fmetrics import
```

This pulls the JSONL events into `~/.fsuite/telemetry.db` (SQLite) and indexes by tool, project, model, and session.

```bash
# Aggregate stats
fmetrics stats -o json

# Filter by caller identity
fmetrics history --model codex-gpt-5.5 --agent codex-cli -o json

# Predict the best next tool for a given project state
fmetrics predict /path/to/project

# Combo evidence — which 3-step chains actually win on this project
fmetrics combos --project fsuite -o json

# Recommend the strongest next step
fmetrics recommend --after ftree,fsearch --project fsuite
```

## Privacy

Telemetry is **local only**. Nothing is sent anywhere. You can delete `~/.fsuite/` at any time to wipe history.

Disable telemetry globally:

```bash
export FSUITE_TELEMETRY=0
```

When `FSUITE_TELEMETRY=0`, no events are written, no JSONL grows, no SQLite import works (because there's nothing to import). `fmetrics predict` still runs but has no learned data to draw on — it falls back to a default chain.

## Sanitization & safety

The flag-accumulation telemetry layer (Episode 0) sanitizes argument values through `tr -cd '[:alnum:] _./-'` before writing. This is a deliberate tradeoff:

- `--rg-args "-i --hidden"` is recorded as `--rg-args` (flag name only, value stripped)
- For analytics — knowing which features are used and how often — flag presence is enough
- For JSONL integrity — not corrupting the log when someone passes a brace or newline as an argument value — safety wins

Flag values aren't analytical signal; flag *presence* is. Sanitizing values protects the log without losing what `fmetrics` actually needs.

## Storage shape

```text
~/.fsuite/
├── telemetry.jsonl          ← append-only event log (raw)
├── telemetry.db             ← SQLite (built by fmetrics import)
├── fcase.db                 ← investigation continuity (separate schema)
└── memory-ingest.log        ← MCP memory-ingest debug log
```

Wipe `~/.fsuite/` to reset. The directory is recreated on the next tool run.

## Planned

- Per-session trace correlation across `fcase`, `freplay`, and ShieldCortex
- Model-aware combo scoring for benchmark comparisons across LLMs
- Per-machine prediction quality scoring (so the agent learns when to trust the prediction)

## Related

- [`fmetrics` reference](/fsuite/commands/fmetrics/) — every command for the analytics layer
- [`fcase` reference](/fsuite/commands/fcase/) — case storage that pairs with telemetry
- [Chain combinations](/fsuite/architecture/chains/) — combos `fmetrics` learns from
