---
title: Mental Model
description: How the 14 fsuite tools fit together. The chain, the specialists, and the workflow discipline.
sidebar:
  order: 2
---

## The sensor metaphor

The filesystem is a cave. You don't know how deep it goes until you have the right tools to map it. Native CLI gives the agent a flashlight and an analog radio. fsuite hands it a fleet of reconnaissance drones with structured telemetry.

<div class="fs-sensor">
  <div class="fs-sensor-stage">
    <div class="fs-sensor-bg" aria-hidden="true"></div>
    <div class="fs-sensor-drone fs-sensor-d1" title="ftree">
      <span class="fs-sensor-name">ftree</span>
      <span class="fs-sensor-beam"></span>
    </div>
    <div class="fs-sensor-drone fs-sensor-d2" title="fsearch">
      <span class="fs-sensor-name">fsearch</span>
      <span class="fs-sensor-beam"></span>
    </div>
    <div class="fs-sensor-drone fs-sensor-d3" title="fcontent">
      <span class="fs-sensor-name">fcontent</span>
      <span class="fs-sensor-beam"></span>
    </div>
    <div class="fs-sensor-tree" aria-hidden="true">
      <span class="fs-sensor-trunk"></span>
      <span class="fs-sensor-branch fs-sensor-b1">src/</span>
      <span class="fs-sensor-branch fs-sensor-b2">lib/</span>
      <span class="fs-sensor-branch fs-sensor-b3">docs/</span>
      <span class="fs-sensor-branch fs-sensor-b4">tests/</span>
      <span class="fs-sensor-branch fs-sensor-b5">bin/</span>
    </div>
    <div class="fs-sensor-platform">
      <span>OPERATOR · TERMINAL · 03:14:22</span>
    </div>
  </div>
</div>

## The chain

The main fsuite workflow is a straight line from territory scout to surgical edit:

<div class="fs-pipeline-v2">
  <div class="fs-pipeline-row">
    <span class="fs-pn fs-pn-entry">fs</span>
    <span class="fs-arr"></span>
    <span class="fs-pn">ftree</span>
    <span class="fs-arr"></span>
    <span class="fs-pn fs-pn-bridge">fsearch │ fcontent</span>
    <span class="fs-arr"></span>
    <span class="fs-pn fs-pn-keystone">fmap</span>
    <span class="fs-arr"></span>
    <span class="fs-pn">fread</span>
    <span class="fs-arr"></span>
    <span class="fs-pn">fcase</span>
    <span class="fs-arr"></span>
    <span class="fs-pn">fedit</span>
  </div>
  <div class="fs-pipeline-undernote">
    <span>↑ <code>fs</code> is the front door — it auto-routes to <code>fsearch</code>+<code>fcontent</code> for you</span>
    <span>↑ <code>fmap</code> is the <b>keystone</b>. Symbol cartography is the gap native CLI does not fill.</span>
  </div>
</div>

### The keystone: why fmap matters

Native CLI gives the agent two ways to find code: name-match (`grep`/`find`) and full-file read (`cat`). Neither knows what a function is. So the agent burns tokens reading whole files just to locate a symbol that `fmap` could have pointed at directly.

`fmap` extracts the symbol skeleton — every function, class, import, and constant, with line numbers — across **50+ languages**. The agent sees the shape of the file before it spends a single token reading it. **That bridge from "I have a name" to "I know exactly which 14 lines to read" is the single biggest token-cost win in fsuite.**

### The supporting cast

Three specialists orbit the main chain:

- **`fls`** — Structured `ls` replacement with recon mode (per-dir sizes + counts)
- **`fwrite`** — Atomic file creation with safety nets
- **`fbash`** — Bash replacement with token-budgeting, command classification, session state
- **`fprobe`** — Binary / bundle inspection + patching when normal reads fail
- **`freplay`** — Derivation chain replay for deterministic reruns
- **`fmetrics`** — Telemetry + tool-chain prediction (learn what works, predict what's next)

## Default reflexes — translate native habits to fsuite

If your agent is already running it should learn this table by heart.

| Native habit | What it costs | fsuite equivalent | Why it's better |
|---|---|---|---|
| `grep -rn "foo"` | floods context, no caps | `fcontent "foo" -o json` | token-capped, ranked, structured |
| `find . -name "*.py"` | walks every dir | `fsearch '*.py' -o paths` | suppresses noise dirs, fd-aware |
| `cat src/auth.py` | dumps whole file | `fread src/auth.py --symbol authenticate` | reads exactly one function |
| `sed -i 's/x/y/' f` | unscoped, drift-prone | `fedit --symbol foo --replace x --with y` | symbol-scoped, dry-run by default |
| `ls -laR` | unbounded recursion | `ftree --recon` | per-dir sizes + counts, no flood |
| `bash -c '…'` | unbounded output | `fbash` | token-budgeted, classified, async |
| Re-discover repo every session | wastes context | `fcase init / handoff` | preserves state across agents |
| Read PDFs by hand | not a thing | `fread invoice.pdf` | first-class media reads |

## The discipline

1. **Scout once.** Run `ftree --snapshot` to establish territory. Don't rediscover the repo unless the target changes.
2. **Let `fs` route.** It auto-classifies your query and picks the right narrowing tool. One call beats three.
3. **Map before reading.** `fmap` extracts the symbol skeleton. You'll know what's there before you read a single line.
4. **Read exactly, never approximately.** `fread --symbol NAME` reads one function by name. `fread --lines 120:150` reads an exact range. Don't read whole files.
5. **Preserve investigation state.** Open `fcase init` at the start of non-trivial work. Close with `fcase resolve`. Check `fcase find` before starting new work — a past you may already have the answer.
6. **Edit surgically.** `fedit --lines` is the fastest mode when you have numbers from `fread`. `fedit --symbol` scopes by symbol without needing huge unique context strings.
7. **Never edit blind.** Always inspect context with `fread` before calling `fedit`.
8. **Measure.** `fmetrics` tells you which chains worked and predicts the best next step for any project.

## Why this order matters

Every tool in the chain is **bounded** — capped output, ranked results, structured JSON available. If you run them in order, each tool narrows the work for the next one, and by the time you reach `fedit` you are acting on an exact line range or exact symbol. Zero ambiguity. Zero failed context matches. Zero 10,000-line grep dumps.

If you skip the chain and reach for `fcontent` as your first search, you'll get what grep gives you — a flood — and you'll waste tokens re-narrowing by hand. That's the mistake the chain is built to prevent.
