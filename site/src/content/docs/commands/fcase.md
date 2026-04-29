---
title: 📋 fcase
description: Investigation continuity ledger
sidebar:
  order: 11
---

## Investigation continuity ledger

`fcase` is part of the fsuite toolkit — a set of fourteen CLI tools built for AI coding agents.

<div class="fs-drone">
  <div class="fs-drone-head">
    <span class="fs-drone-call">fcase</span>
    <span class="fs-drone-tagline">Investigation continuity ledger · cross-session state machine</span>
  </div>
  <div class="fs-drone-meta">
    <div><b>Role</b><span class="role-state">STATE</span></div>
    <div><b>Chain position</b><span>wraps every chain</span></div>
    <div><b>Lifecycle</b><span>init → note → handoff → resolve</span></div>
    <div><b>Storage</b><span>~/.fsuite/fcase.db</span></div>
  </div>
</div>

`fcase` is the investigation ledger. Every non-trivial debug, refactor, or recon ends with the agent saying "ok now what" — `fcase` answers that question across sessions. Open a case at the start, drop notes and evidence as you go, hand off cleanly to the next agent (or the next you).

It's the *continuity* tool. Without it, every new session starts from zero. With it, the next agent reads the case envelope and knows exactly where the trail left off.

## Canonical chains

```bash
# Open a case
fcase init auth-seam --goal "Trace authenticate flow"

# List active cases
fcase list -o json

# Append a note
fcase note auth-seam --body "Focused on the denial branch"

# Add a target seam
fcase target add auth-seam \
  --path /project/src/auth.py --symbol authenticate \
  --symbol-type function --state active

# Import targets from fmap
fmap -o json /project | fcase target import auth-seam

# Import evidence from fread
fread -o json /project/src/auth.py --around "def auth" -A 20 \
  | fcase evidence import auth-seam

# Track and reject hypotheses
fcase hypothesis add auth-seam --body "Cleanup bug in cancellation"
fcase reject auth-seam --hypothesis-id 1 --reason "Verified safe"

# Hand off to the next agent
fcase next auth-seam --body "Patch denial branch next"
fcase handoff auth-seam -o json
```

## Help output

The content below is the **live** `--help` output of `fcase`, captured at build time from the tool binary itself. It cannot drift from the source — regenerating the docs regenerates this section.

```text
fcase — continuity and handoff ledger for fsuite investigations

USAGE
  fcase --help
  fcase --version
  fcase init <slug> --goal ... [--priority ...] [-o pretty|json]
  fcase list [--status <csv|all>] [--include-shadow] [-o pretty|json]
  fcase status <slug> [-o pretty|json]
  fcase find <query> [--deep] [--status <csv|all>] [--include-shadow] [-o pretty|json]
  fcase note <slug> --body ...
  fcase next <slug> --body ... [-o pretty|json]
  fcase handoff <slug> [-o pretty|json]
  fcase export <slug> -o json
  fcase target add <slug> --path ... [--symbol ... --symbol-type ... --rank ... --reason ... --state ...]
  fcase target import <slug> [-o pretty|json] [--input <path|- >]
  fcase evidence <slug> --tool ... [--path ... --symbol ... --lines <start:end> --match-line ... --summary ...] (--body ... | --body-file <path>)
  fcase evidence import <slug> [-o pretty|json] [--input <path|- >]
  fcase hypothesis add <slug> --body ... [--confidence ...]
  fcase hypothesis set <slug> --id ... --status ... [--reason ... --confidence ...]
  fcase reject <slug> (--target-id <id> | --hypothesis-id <id>) [--reason ...]
  fcase resolve <slug> --summary ... [-o pretty|json]
  fcase archive <slug> [-o pretty|json]
  fcase delete <slug> --reason ... --confirm DELETE [-o pretty|json]

DESCRIPTION
  fcase preserves investigation state once the seam is known:
    init         Create a case and open a session
    list         Show cases (default: open only; shadow/session cases hidden unless --include-shadow)
    find         Search resolved/archived cases via FTS (--deep for full text; shadow/session cases hidden unless --include-shadow)
    status       Show current case state
    note         Append a note to a case
    next         Update the next best move
    handoff      Generate a concise handoff packet
    export       Export the full case envelope
    resolve      Mark case as resolved (requires --summary)
    archive      Archive a resolved case
    delete       Tombstone a case (requires --reason and --confirm DELETE)
    target import    Import structured targets from fmap JSON
    evidence import  Import structured evidence from fread JSON
```

## See also

- [fsuite mental model](/fsuite/getting-started/mental-model/) — how fcase fits into the toolchain
- [Cheat sheet](/fsuite/reference/cheatsheet/) — one-line recipes for every tool
- [View source on GitHub](https://github.com/lliWcWill/fsuite/blob/master/fcase)
