---
title: ⏪ freplay
description: Derivation chain replay — rerun a traced investigation
sidebar:
  order: 12
---

## Derivation chain replay — rerun a traced investigation

`freplay` is part of the fsuite toolkit — a set of fourteen CLI tools built for AI coding agents.

<div class="fs-drone">
  <div class="fs-drone-head">
    <span class="fs-drone-call">freplay</span>
    <span class="fs-drone-tagline">Derivation chain replay · deterministic rerun</span>
  </div>
  <div class="fs-drone-meta">
    <div><b>Role</b><span class="role-state">REPLAY</span></div>
    <div><b>Chain position</b><span>specialist</span></div>
    <div><b>Pairs with</b><span>fcase</span></div>
    <div><b>Use for</b><span>post-mortems · regression</span></div>
  </div>
</div>

`freplay` records the exact tool-call sequence inside a case, so you can rerun the chain deterministically later. Useful for post-mortems ("how did the agent reach this conclusion?"), regression tests, and onboarding ("here's the exact recon path I took to find this bug").

It pairs with `fcase` — every replay step belongs to a case, and the recorded chain is part of the handoff envelope.

## Canonical chains

```bash
# Record a step under a case (with purpose annotation)
freplay record auth-seam --purpose "Traced denial branch" \
  -- fread /project/src/auth.py --around 'def auth'

# Record without purpose
freplay record auth-seam \
  -- fcontent -o paths "auth" /project/src

# Show the full chain
freplay show auth-seam
freplay show auth-seam -o json

# Show the recorded chain for a specific case
freplay list auth-seam -o json
```

## Help output

The content below is the **live** `--help` output of `freplay`, captured at build time from the tool binary itself. It cannot drift from the source — regenerating the docs regenerates this section.

```text
freplay — deterministic replay engine for fsuite investigation commands

USAGE
  freplay --help
  freplay --version
  freplay --self-check
  freplay record <case-slug> [--purpose "..."] [--link <type:id>]... [--replay-id N] [--new] -- <fsuite-command...>
  freplay show <case-slug> [--replay-id N] [-o pretty|json]
  freplay list <case-slug> [-o pretty|json]
  freplay export <case-slug> [--replay-id N] [-o json]
  freplay verify <case-slug> [--replay-id N] [-o pretty|json]
  freplay promote <case-slug> <replay-id>
  freplay archive <case-slug> <replay-id>

SUBCOMMANDS
  record     Run an fsuite command and record its invocation, output, and result
  show       Show a recorded replay (latest or by --replay-id)
  list       List all replays for a case
  export     Export a replay as JSON
  verify     Validate a replay without executing (check paths, tools, links)
  promote    Promote a replay to canonical status
  archive    Archive (soft-delete) a replay

OPTIONS
  --purpose  Human-readable purpose for this recording
  --link     Link this replay to a related entity (e.g. evidence:42)
  --replay-id  Select a specific replay by integer ID
  --new      Force creation of a new replay even if one exists for this command
  -o         Output format: pretty (default) or json

NOTES
  The following tools are excluded from recording:
    freplay, fmetrics
  fedit is classified read_only by default; mutating when --apply is present.
  verify exit codes: 0=pass, 1=warn, 2=fail.
```

## See also

- [fsuite mental model](/fsuite/getting-started/mental-model/) — how freplay fits into the toolchain
- [Cheat sheet](/fsuite/reference/cheatsheet/) — one-line recipes for every tool
- [View source on GitHub](https://github.com/lliWcWill/fsuite/blob/master/freplay)
