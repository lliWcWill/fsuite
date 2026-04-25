---
title: 📊 fmetrics
description: Telemetry analytics + tool-chain prediction
sidebar:
  order: 14
---

## Telemetry analytics + tool-chain prediction

`fmetrics` is part of the fsuite toolkit — a set of fourteen CLI tools built for AI coding agents.

## Help output

The content below is the **live** `--help` output of `fmetrics`, captured at build time from the tool binary itself. It cannot drift from the source — regenerating the docs regenerates this section.

```text
fmetrics — performance telemetry and analytics for fsuite

USAGE
  fmetrics <subcommand> [options]

  SUBCOMMANDS
    stats              Show dashboard of tool usage, runtimes, reliability
    history            Show recent runs (filterable)
combos             Show telemetry-backed combo patterns
recommend          Suggest the strongest next tool after a prefix
predict <path>     Estimate how long fsuite tools will take on <path>
import             Ingest new telemetry.jsonl rows into SQLite database
rebuild            Recompute derived analytics tables from imported telemetry
clean              Prune old telemetry data
profile            Show machine profile (Tier 3 telemetry)

OPTIONS (global)
  -o, --output       Output format: pretty (default) or json
  -h, --help         Show this help
  --version          Print version
  --self-check       Verify dependencies
  --install-hints    Print install commands for missing dependencies

    OPTIONS (history)
      --tool <name>      Filter by tool (ftree, fsearch, fcontent)
      --project <name>   Filter by project name
      --model <id>       Filter by model_id
      --agent <id>       Filter by agent_id
      --session <id>     Filter by session_id
      --limit <N>        Max rows (default 20)

  OPTIONS (combos)
    --project <name>           Filter by project name
    --starts-with <tool,...>   Require combo prefix
    --contains <tool>          Require a tool anywhere in the combo
    --min-occurrences <N>      Minimum occurrence count (default 1)

  OPTIONS (recommend)
    --after <tool,...>         Prefix to continue from
    --project <name>           Filter by project name
    --limit <N>                Max recommendations (default 20)

OPTIONS (predict)
  --tool <name>      Predict for specific tool only (ftree, fsearch, fcontent)
  --mode <name>      Restrict ftree predictions to tree, recon, or snapshot

OPTIONS (clean)
  --days <N>         Keep last N days (default 90)
  --dry-run          Preview what would be deleted

ENVIRONMENT
  FSUITE_TELEMETRY=0  Disable telemetry collection in fsuite tools
  FSUITE_MODEL_ID     Model identifier to store with telemetry
  FSUITE_AGENT_ID     Agent/runtime identifier to store with telemetry
  FSUITE_SESSION_ID   Session/thread identifier to store with telemetry

EXAMPLES
    fmetrics import              Import telemetry data into SQLite
fmetrics stats               Show usage dashboard
fmetrics stats -o json       Machine-readable stats
fmetrics history --tool ftree --limit 10
fmetrics history --model codex-gpt-5.5 --agent codex-cli -o json
fmetrics combos --project fsuite -o json
fmetrics recommend --after ftree,fsearch --project fsuite
fmetrics predict /project    Estimate runtimes for /project
fmetrics rebuild             Recompute combo/recommend analytics now
fmetrics predict --tool ftree --mode snapshot /project
fmetrics clean --days 30     Remove data older than 30 days
```

## See also

- [fsuite mental model](/fsuite/getting-started/mental-model/) — how fmetrics fits into the toolchain
- [Cheat sheet](/fsuite/reference/cheatsheet/) — one-line recipes for every tool
- [View source on GitHub](https://github.com/lliWcWill/fsuite/blob/master/fmetrics)
