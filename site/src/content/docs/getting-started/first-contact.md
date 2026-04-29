---
title: First Contact
description: The first ten minutes with fsuite — what to run, what to notice, and what to do next.
sidebar:
  order: 3
---

<div class="fs-drone">
  <div class="fs-drone-head">
    <span class="fs-drone-call">FIRST CONTACT</span>
    <span class="fs-drone-tagline">Ten minutes from install to "I get it"</span>
  </div>
  <div class="fs-drone-meta">
    <div><b>Prereq</b><span>fsuite installed</span></div>
    <div><b>Time</b><span>~10 min</span></div>
    <div><b>Output</b><span>working mental model</span></div>
    <div><b>Next</b><span>real investigation</span></div>
  </div>
</div>

You've just installed fsuite. Here's the shortest path to understanding what it actually does. Run these in order on any project you have on disk.

## 1. Load the mental model

```bash
fsuite
```

`fsuite` itself is the suite-level guide. It prints the chain, the discipline, and the tool list in one shot. Read it once. This is the same content you'll find on the [Mental Model](/fsuite/getting-started/mental-model/) page — same source, different surface.

## 2. Scout any project

```bash
cd /path/to/any/project
ftree --snapshot -o json .
```

`ftree` returns the full tree AND recon data (sizes, types, flags) in one call. Note how it caps output automatically — no 10,000-line floods. The `--snapshot` mode is what you want for an agent's "first look" because it gets the recon inventory plus the tree excerpt in a single envelope.

<div class="fs-term">
  <div class="fs-term-bar"><b>ftree --snapshot</b> · recon + tree in one call <span class="fs-term-cost">410ms</span></div>
<pre><span class="tk-tool">ftree</span>(<span class="tk-str">"."</span> | mode: <span class="tk-str">"snapshot"</span>)
  <span class="tk-arrow">└─</span> Snapshot(./, depth=3)
     <span class="tk-num">12</span> directories, <span class="tk-num">87</span> files
<span class="tk-mut">·</span>
     src/                       —    <span class="tk-num">42</span> files
     tests/                     —    <span class="tk-num">12</span> files
     docs/                      —    <span class="tk-num">8</span> files
     node_modules/              —    <span class="tk-mut">[excluded]</span>
     dist/                      —    <span class="tk-mut">[excluded]</span>
<span class="tk-mut">·</span>
     <span class="tk-cyan">next</span> <span class="tk-arrow">→</span> fsearch <span class="tk-com">// narrow files</span>  |  fcontent <span class="tk-com">// narrow content</span>
<span class="tk-mut">·</span></pre>
</div>

## 3. Run a one-shot search

```bash
fs "TODO" --scope '*.py'
```

`fs` auto-classifies your query. Given a string + glob scope, it routes to content search. Given a path glob, it routes to file search. Given a code identifier, it routes to symbol search. **One call instead of three.**

The `next_hint` line at the bottom of every `fs` response tells you the strongest follow-up. **Take the hint** — it's drawn from `fmetrics` combo data.

## 4. Map a file before reading it

```bash
fmap src/some_file.py
```

`fmap` lists the symbol skeleton — functions, classes, imports, constants — with line numbers. You'll know the structure before opening the file. For a 600-line module, this is ~50 lines of output instead of 600. **That's the keystone — see the [Mental Model](/fsuite/getting-started/mental-model/) for why.**

## 5. Read exactly one function

```bash
fread src/some_file.py --symbol name_of_function
```

`fread` reads exactly the function you asked for. Not the file. Not a guess. The function. If the symbol is ambiguous (multiple matches), `fread` errors explicitly — it doesn't pick one for you.

When you don't know the symbol name yet but have a line number from `fmap`:

```bash
fread src/some_file.py -r 120:150
```

## 6. Open a case

```bash
fcase init first-contact --goal "Explore fsuite on this project"
fcase note first-contact --body "Scouted, mapped, read one function"
fcase resolve first-contact --summary "Got the vibe. Moving on."
```

`fcase` preserves investigation state across sessions. Your notes survive context compaction and you can re-load them with `fcase list` next time. This is the most underrated tool in the suite — when an agent comes back tomorrow, `fcase` is what makes it pick up where you left off instead of starting over.

## What you should notice

| Signal | Why it matters |
|--------|---------------|
| Every output is **capped** | No flood, ever. The agent's context window stays clean. |
| `-o json` works on every tool | Programmatic parsing is first-class, not an afterthought. |
| `-q` exists for silent existence checks | Useful in shell scripts and conditional chains. |
| Several commands return `next_hint` | The toolchain tells you what to call next. **Take the hint.** |
| `fmap` and `fread --symbol` are not in any other CLI | This is the gap fsuite was built to fill. |

## What to do next

- [Read the mental model](/fsuite/getting-started/mental-model/) — the discipline that makes the chain work
- [Browse the cheat sheet](/fsuite/reference/cheatsheet/) — every command, every flag, ready to copy-paste
- [Browse the command reference](/fsuite/commands/fs/) — one page per tool, with live `--help` output
- [Read Episode 0](/fsuite/story/episode-0/) — how fsuite came to be and what it was trying to fix
- [Set up MCP + hooks](/fsuite/architecture/) — make fsuite the default for your Claude Code agents
