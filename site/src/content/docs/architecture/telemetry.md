---
title: Telemetry
description: How fsuite records tool usage in JSONL + SQLite for analytics, prediction, and replay.
sidebar:
  order: 3
---

## What gets recorded

Every fsuite tool emits a JSONL telemetry event on completion. The event includes:

- Tool name, arguments, exit code, duration
- Input size, output size, match count
- Backend used (bash, mcp, etc.)
- Caller attribution: `model_id`, `agent_id`, and `session_id`
- Hardware snapshot (cpu, memory)

Events land in `~/.fsuite/telemetry.jsonl` by default.

## Caller attribution

fsuite records the model and agent behind each tool call for LLM benchmarking and workflow analysis. Set these once in the agent wrapper or shell:

```bash
export FSUITE_MODEL_ID=codex-gpt-5.5
export FSUITE_AGENT_ID=codex-cli
export FSUITE_SESSION_ID=bench-042
```

If those variables are not set, tools try common runtime environment and parent-process hints, then fall back to `unknown` for model/agent and an empty session. `fbash` exports detected attribution to child fsuite commands so pipelines preserve caller identity. For direct shell pipelines, export the variables first when you need guaranteed shared attribution across every tool event.

## Import to SQLite

```bash
fmetrics import
```

This pulls the JSONL events into `~/.fsuite/telemetry.db` (SQLite) for fast query. From there:

```bash
# Summary stats
fmetrics stats -o json

# Filter by caller identity
fmetrics history --model codex-gpt-5.5 --agent codex-cli -o json

# Predict the best next tool for a given project state
fmetrics predict /path/to/project
```

## Privacy

Telemetry is **local only**. Nothing is sent anywhere. You can delete `~/.fsuite/` at any time to wipe history.

Disable telemetry globally by setting:

```bash
export FSUITE_TELEMETRY=0
```

## Planned

- Per-session trace correlation across fcase, freplay, and ShieldCortex
- Model-aware combo scoring for benchmark comparisons
