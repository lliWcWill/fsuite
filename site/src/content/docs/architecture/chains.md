---
title: Chain Combinations
description: Canonical fsuite tool chains — which sequences actually work for common tasks.
sidebar:
  order: 4
---

## The core chain

The default for "I need to understand and modify something in this repo."

<div class="fs-pipeline">
  <span class="fs-pn fs-pn-entry">ftree</span>
  <span class="fs-arr"></span>
  <span class="fs-pn">fs</span>
  <span class="fs-arr"></span>
  <span class="fs-pn">fmap</span>
  <span class="fs-arr"></span>
  <span class="fs-pn">fread</span>
  <span class="fs-arr"></span>
  <span class="fs-pn">fedit</span>
</div>

## Investigation chain

Spans multiple sessions or context windows. `fcase` brackets the work.

<div class="fs-pipeline">
  <span class="fs-pn fs-pn-entry">fcase init</span>
  <span class="fs-arr"></span>
  <span class="fs-pn">ftree</span>
  <span class="fs-arr"></span>
  <span class="fs-pn">fs</span>
  <span class="fs-arr"></span>
  <span class="fs-pn">fmap</span>
  <span class="fs-arr"></span>
  <span class="fs-pn">fread</span>
  <span class="fs-arr"></span>
  <span class="fs-pn">fcase note</span>
  <span class="fs-arr"></span>
  <span class="fs-pn">fedit</span>
  <span class="fs-arr"></span>
  <span class="fs-pn fs-pn-entry">fcase resolve</span>
</div>

## Debugging chain

`fcase` captures the hypothesis, the repro steps, and the fix — so if the fix fails, the next attempt starts with context.

<div class="fs-pipeline">
  <span class="fs-pn">fbash</span>
  <span class="fs-arr"></span>
  <span class="fs-pn">fs</span>
  <span class="fs-arr"></span>
  <span class="fs-pn">fmap</span>
  <span class="fs-arr"></span>
  <span class="fs-pn">fread</span>
  <span class="fs-arr"></span>
  <span class="fs-pn">fcase</span>
  <span class="fs-arr"></span>
  <span class="fs-pn">fedit</span>
  <span class="fs-arr"></span>
  <span class="fs-pn fs-pn-entry">fbash</span>
</div>

## Refactoring chain

The key move: use `fedit --symbol` for each symbol instead of doing a text-replace across files. Zero ambiguity.

<div class="fs-pipeline">
  <span class="fs-pn">fcontent</span>
  <span class="fs-arr"></span>
  <span class="fs-pn">fsearch</span>
  <span class="fs-arr"></span>
  <span class="fs-pn">fmap</span>
  <span class="fs-arr"></span>
  <span class="fs-pn fs-pn-entry">fedit --symbol</span>
</div>

## Binary investigation chain

When the target is a compiled binary, an obfuscated bundle, or anything text tools can't read.

<div class="fs-pipeline">
  <span class="fs-pn fs-pn-branch">fprobe strings</span>
  <span class="fs-arr"></span>
  <span class="fs-pn fs-pn-branch">fprobe scan</span>
  <span class="fs-arr"></span>
  <span class="fs-pn fs-pn-branch">fprobe window</span>
  <span class="fs-arr"></span>
  <span class="fs-pn fs-pn-branch">fprobe patch</span>
</div>

## fcase lifecycle

The investigation ledger isn't a chain — it's a state machine that wraps every other chain.

<div class="fs-fcase">
  <div class="fs-fcase-state"><b>init</b><span>open the seam</span></div>
  <span class="fs-arr"></span>
  <div class="fs-fcase-state"><b>note</b><span>capture evidence</span></div>
  <span class="fs-arr"></span>
  <div class="fs-fcase-state"><b>handoff</b><span>pass to next agent</span></div>
  <span class="fs-arr"></span>
  <div class="fs-fcase-state fs-fcase-end"><b>resolve</b><span>close + archive</span></div>
</div>

## Replay chain

Rerun a traced investigation step-by-step. Useful for post-mortems and regression tests.

```bash
freplay --session <id>
```

## Measurement chain

Ask the telemetry database what worked last time and what probably works next.

<div class="fs-pipeline">
  <span class="fs-pn">fmetrics import</span>
  <span class="fs-arr"></span>
  <span class="fs-pn">fmetrics stats</span>
  <span class="fs-arr"></span>
  <span class="fs-pn fs-pn-entry">fmetrics predict</span>
</div>
