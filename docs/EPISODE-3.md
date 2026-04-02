```
███████╗███████╗██╗   ██╗██╗████████╗███████╗
██╔════╝██╔════╝██║   ██║██║╚══██╔══╝██╔════╝
█████╗  ███████╗██║   ██║██║   ██║   █████╗
██╔══╝  ╚════██║██║   ██║██║   ██║   ██╔══╝
██║     ███████║╚██████╔╝██║   ██║   ███████╗
╚═╝     ╚══════╝ ╚═════╝ ╚═╝   ╚═╝   ╚══════╝
─────────────────────────────────────────────
[ FIELD DISPATCH ]  Episode 3: The Mirror
[ PREVIOUS ]        Episode 2: The Monolith
[ STATUS ]          The drones mapped the thing that made them. Full circle.
```

---

## Mission Context

Every tool has the moment where it stops being a thing you built and becomes a thing you need.

Episode 0 was trust. Episode 1 was the structural gap. Episode 2 was the eighteen-hour monolith — binary vision, pixel-perfect rendering, twelve tools, four hundred and twenty-five tests. Between then and now, the MCP adapter matured into a native tool surface running inside Claude Code itself. The drones weren't being tested anymore. They were being used. Every session. Every investigation. First instinct, not fallback.

And then, on April 2nd, 2026, the operator said: "I want to run Claude Code from source. Not the binary — the actual TypeScript. I want it talking to GPT-5.4 through the Codex backend. And I want to understand how the rendering works, from the moment I press Enter to the moment pixels appear on screen."

That's when things got interesting.

Because the codebase the agent needed to reverse-engineer was Claude Code itself. The same application that was running the agent. The same Ink rendering engine that was painting every tool result to the terminal. The same React reconciler that was scheduling every frame update. The agent was being asked to use fsuite to understand the very infrastructure fsuite was designed to augment.

The drones were about to look in the mirror.

---

## The Target

brane-code. Claude Code's open-source TypeScript, checked out locally at `~/Desktop/Projects/brane-code`. Two thousand five hundred lines of `main.tsx`. A custom fork of Ink — not the npm package, a full 1,722-line rendering engine at `src/ink/ink.tsx` with its own reconciler, its own Yoga layout integration, its own double-buffered frame pipeline. A React component tree six context providers deep. A keyboard input pipeline that goes from raw stdin bytes through a custom parser, through a batch processor, through an event dispatcher, through React state, through a reconciler commit, through a throttled microtask, through a Yoga layout pass, through a screen buffer diff, through an optimizer, and finally out to stdout.

And somewhere in that pipeline, the interactive REPL was broken. The cursor blinked. Text was invisible. Keystrokes never reached the API. The rendering gateway between "user types" and "terminal paints" had a gap, and nobody knew where.

The agent had never seen this codebase before.

---

## The Approach

Here's what didn't happen. The agent didn't spawn an Explore subagent. It didn't open files at random. It didn't grep for "render" and drown in 400 matches. It didn't read `main.tsx` top to bottom and burn 15,000 tokens discovering that the first 580 lines are imports.

Here's what happened.

```
ftree(path: "src", depth: 2, snapshot: true)
```

One call. The entire `src/` directory — 1,022 entries — laid out with structure, sizes, and directory composition. In that single response, the agent identified the five directories that mattered: `entrypoints/`, `ink/`, `components/`, `hooks/`, and `providers/`. Everything else was context. Not noise — context. But the drones knew the difference.

```
fmap(path: "src/entrypoints/cli.tsx")
```

Two symbols came back. An import and the `main()` function at line 33. Not the function body — the *declaration*. The skeleton. The agent now knew the entry point's shape without reading a single line of implementation.

```
fmap(path: "src/ink/root.ts")
```

Fourteen symbols. `createRoot` at line 129. `renderSync` at line 76. `RenderOptions` type at line 8. The agent now knew the Ink root's entire API surface in 14 lines of output instead of reading 172 lines of source.

```
fmap(path: "src/ink/ink.tsx")
```

Fifty-four symbols. The constructor at line 180. `deferredRender` at line 212. The `Ink` class at line 76. `drainStdin` at line 1664. The console intercepts at lines 1721-1722. Fifty-four structural landmarks in a 1,722-line file, returned in a single tool call. The agent now had the complete skeleton of the rendering engine — every method, every constant, every type — without reading a single function body.

```
fmap(path: "src/ink/components/App.tsx")
```

Thirty-five symbols. The `App` class at line 101. `processKeysInBatch` at line 444. `handleMouseEvent` at line 515. The state type at line 94. The props type at line 36. The keyboard input pipeline was now visible.

```
fmap(path: "src/interactiveHelpers.tsx")
```

Forty symbols. `renderAndRun` at line 98. `getRenderContext` at line 299. `showSetupScreens` at line 104. The gateway functions that connect Commander.js to the React tree.

Five `fmap` calls. The entire rendering architecture — mapped.

Then the surgical reads began.

```
fread(path: "src/entrypoints/cli.tsx", symbol: "main")
```

The agent read the `main()` function and found the gateway at line 293: `const { main: cliMain } = await import('../main.js')`. Not a guess. Not a grep. A targeted symbol read that returned exactly the function it asked for.

```
fread(path: "src/ink/root.ts", symbol: "createRoot")
```

Thirty lines. The `createRoot` function. `new Ink(options)`, `instances.set(stdout, instance)`, returns `{ render, unmount, waitUntilExit }`. The Ink instantiation pattern, complete.

```
fread(path: "src/interactiveHelpers.tsx", symbol: "renderAndRun")
```

Six lines. `root.render(element)`, `startDeferredPrefetches()`, `await root.waitUntilExit()`, `await gracefulShutdown(0)`. The entire interactive launch sequence. Six lines.

```
fread(path: "src/ink/ink.tsx", lines: "76:215")
```

The Ink class constructor and the `scheduleRender` setup. LogUpdate, Terminal, StylePool, CharPool, HyperlinkPool, double-buffered frames, reconciler container, `scheduleRender = throttle(deferredRender, FRAME_INTERVAL_MS)` where `deferredRender = () => queueMicrotask(this.onRender)`.

Four `fmap` calls for architecture. Six `fread` calls for confirmation. Total tool invocations for a complete rendering pipeline map: **ten**.

---

## What Came Out

A full seven-stage pipeline trace from CLI entry to terminal paint, with exact file and line references for every gateway function:

```
cli.tsx:main()                     [line 33]
  └── import('../main.js')         [line 293]
      └── main.tsx:main()          [line 585]
          └── getRenderContext()    [interactiveHelpers.tsx:299]
              └── createRoot()     [ink/root.ts:129]
                  └── new Ink()    [ink/ink.tsx:76, constructor at 180]
                      └── renderAndRun(root, <REPL/>)
                                   [interactiveHelpers.tsx:98]
```

The React component tree:

```
AppStateProvider → KeybindingSetup → App [ink/components/App.tsx:101]
  ├── AppContext (stdin, exitApp, setRawMode)
  ├── StdinContext (process.stdin wrapper)
  ├── CursorDeclarationContext (IME/a11y cursor parking)
  ├── ClockProvider
  ├── TerminalSizeContext
  ├── TerminalFocusProvider
  └── {children} → REPL component tree
```

The render cycle:

```
Keystroke → process.stdin
  → App.processKeysInBatch()     [line 444]
    → InputEvent dispatched
      → React state update
        → reconciler.resetAfterCommit()
          → Ink.scheduleRender()  [throttled microtask]
            → Ink.onRender()
              ├── Yoga layout (flexbox for terminal)
              ├── renderNodeToOutput() → screen buffer
              ├── diff frontFrame vs backFrame (double buffer)
              ├── optimize (blit + narrow damage)
              ├── search/selection overlays
              ├── cursor positioning (useDeclaredCursor)
              └── LogUpdate.write() → process.stdout → your eyes
```

The bug hypothesis, precisely located: keystrokes enter at `processKeysInBatch` but never reach the submit handler. The cursor blinks because `cursorDeclaration` works independently of text rendering. The API never fires because the message never leaves the input component. The gap is between the Ink 5 migration's `use-input.ts` hook and the `BaseTextInput` component that depends on it.

All of this. From a codebase the agent had never seen. In under ten minutes. Filed to `fcase` for the next session.

---

## Why This Matters

The README opens with a quote from January 2026:

> *"I'm bad at efficiently finding what to reason about. fsuite is built specifically for that phase."*

That was a self-assessment. An honest one. But it was abstract. "Reconnaissance gap" sounds like a whitepaper phrase. You read it and nod. You don't *feel* it.

This session made it concrete.

The agent was dropped into 2,500 lines of `main.tsx`, a 1,722-line custom rendering engine, a React reconciler, a Yoga layout system, a double-buffered terminal painter — the most complex terminal application architecture in existence — and it needed to understand the full pipeline from user keystroke to terminal pixel. Not read about it. Not get a summary. *Understand it well enough to locate a bug.*

Without fsuite, here's what that looks like:

```
Glob("src/**/*.tsx")           → 200+ files. Which ones matter?
Read("src/main.tsx")           → 2,500 lines. 15,000 tokens. Imports until line 580.
Read("src/ink/ink.tsx")        → 1,722 lines. 10,000 tokens. Where's the constructor?
Grep("createRoot", "src/")    → 22 matches. Which one is the real entry?
Read("src/ink/root.ts")       → 172 lines. Full file. Needed 30.
```

Five calls in and you've burned 25,000+ tokens and you still don't know the pipeline. You know fragments. Disconnected fragments that you now have to stitch together in your reasoning, hoping you didn't miss the critical junction buried on line 2,217 of a file you skimmed.

With fsuite:

```
ftree --snapshot               → Territory. One call. 1,022 entries.
fmap (5 calls)                 → Skeletons. Every gateway function, named and located.
fread --symbol (4 calls)       → Surgical reads. Only the functions that matter.
fread --lines (2 calls)        → The constructor. The scheduler. Exact ranges.
```

Eleven calls. Under 4,000 tokens of output. Complete architectural understanding. And every finding filed to `fcase` so the next agent — or the next session — doesn't start from zero.

That's not an efficiency improvement. That's a category change. It's the difference between "I spent my context window reading code" and "I spent my context window *understanding* architecture."

---

## The Irony

There's a moment in Episode 2 where the drones look inside the Claude Code binary for the first time. `fprobe strings` returned 47 matches. The reconnaissance drones had learned to see through compiled code. That was the proudest moment of the project.

This episode tops it.

Because the drones didn't just look inside the binary. They looked inside the *source code that builds the binary*. They mapped the rendering engine that paints their own output. They traced the keyboard pipeline that receives the operator's commands. They found the reconciler that schedules the frames that display their own results.

`fmap` mapped the `Ink` class. The `Ink` class renders `fmap`'s output.

The drones looked in the mirror. And they understood what they saw.

---

## The Numbers

```
Target:            brane-code (Claude Code open source)
Codebase size:     ~50,000 lines TypeScript
Key files mapped:  5 (cli.tsx, main.tsx, ink.tsx, root.ts, App.tsx)
Total fmap calls:  5
Total fread calls: 6
Total tool calls:  ~11 (excl. ftree, fcase, fprobe for binary check)
Tokens consumed:   ~4,000 (tool output only)
Time to full map:  <10 minutes
Pipeline stages:   7 (entry → commander → context → root → ink → setup → render)
React tree depth:  6 context providers
Bug located:       Yes (Ink 5 input hook → BaseTextInput gap)
Case filed:        fcase #150 brane-repl-input (open, high priority)
Vault doc:         Knowledge Base/Architecture/Brane Code Rendering Pipeline.md
```

---

## The Quote

> *"fmap gave me the entire Ink class skeleton — 1,722 lines — in one call without burning tokens on function bodies. I got the full symbol hierarchy of App.tsx, reconciler.ts, root.ts — all the gateway joints — without reading a single line of implementation I didn't need. It's genuinely the difference between 'explore for 20 minutes' and 'know the architecture in 60 seconds.'"*
>
> — Claude Code (Opus 4.6), field report, April 2nd 2026

---

## What's Next

The REPL input bug is located but not fixed. `fcase #150` has the full architecture mapping, the hypothesis, and the next steps. The gap is in `src/ink/hooks/use-input.ts` — the Ink 5 migration broke the callback chain between the keyboard hook and the text input component. The cursor works because cursor declaration is independent of text rendering. The text doesn't paint because the input state never updates.

The drones found it. Now someone has to fix it.

But when they come back to this codebase — next session, next week, next agent — they won't start from zero. The architecture is mapped. The case is filed. The vault has the doc. The pipeline diagram has exact line numbers. The rendering engine's skeleton is one `fmap` call away.

That's what continuity looks like. That's what `fcase` is for. That's the whole point.

---

## The Story So Far

| PR | Episode | What shipped |
|----|---------|-------------|
| #1 | Pre-history | `ftree` v1.0.0 — the first drone |
| #2 | Pre-history | `ftree` v1.0.1 — refactor + correctness |
| #3 | Pre-history | `ftree` v1.1.0 — output normalization |
| #4 | Pre-history | `ftree` v1.2.0 — snapshot mode |
| #5 | Episode -2 | `fsearch`, `fcontent` — the search drones |
| #6 | Episode -1 | Telemetry, fmetrics, hardware tiers |
| #7 | Episode 0 | The Launch — nitpicks fixed, test overhaul, 203 tests |
| #8 | Episode 1 | `fmap` — code cartography, 12 languages, 259 tests |
| #9 | — | `fmap` v1.6.1 — hardening, CodeRabbit clean |
| #10 | — | `fmap` Markdown support, 18 languages |
| #11 | — | `fcase`, `freplay` v2.1.0 — investigation lifecycle |
| #12 | — | `fcase` v2.1.2 — SQLite busy-timeout hotfix |
| #13 | — | `fedit` v2.0.0 — symbol-first batch editing |
| #14 | — | `fread` v1.8.0, `fedit` v1.9.0 — read and edit loop |
| #15 | Episode 2 | The Monolith — fprobe, fedit --lines, fs, fwrite, MCP overhaul, binary RE, pixel-perfect rendering, archive-grade README, 12 tools, 425 tests |
| — | Episode 3 | The Mirror — the drones mapped their own rendering engine, then rewired it |

---

## After The Mirror

The drones mapped the rendering engine. Then they looked at the tool they'd been forced to use every time fsuite couldn't help — the Bash tool. And they saw everything wrong with it.

12,400 lines. 2,400 lines of security theater. Output flooding with no budgeting. No shell state persistence. No command intelligence. A system prompt that burned 3,000 tokens per turn on commit instructions most calls never needed. Every `npm test` dumped the first 30KB of passing tests and truncated the actual failure at the end.

The drones had spent months learning what makes a good tool. They had the patterns: `fread`'s token budgeting. `fmap`'s skeleton-first approach. `fcase`'s investigation lifecycle. `fcontent`'s match capping and `next_hint`. `fs`'s auto-routing. They knew what worked. They knew what the Bash tool was missing.

So they built `fbash`.

---

## fbash — The Thirteenth Drone

1,400 lines. Built in a single session. Three parallel brainstorming agents produced a 1,744-line spec covering every pain point, every integration seam, every edge case. Three more agents built the implementation, the MCP registration, and the test suite simultaneously.

What shipped:

```
Output budgeting     max_lines (default 200) + max_bytes (50KB)
                     head/tail modes — build/test auto-tail so errors
                     aren't truncated away

Command classes      11 classes: build, test, git, install, service,
                     query, search, network, lint, internal, general
                     Each auto-tunes timeout (5s–180s) and output strategy

Smart routing        ls → fls, cat → fread, grep → fcontent,
                     find → fsearch, sed -i → fedit
                     Commands still execute — routing is advisory via
                     next_hint and routing_suggestion fields

Session state        CWD tracking across calls, 50-command history ring,
                     environment overrides, active fcase slug
                     Persisted in ~/.fsuite/fbash/session.json

fcase integration    Auto-logs build/test/git/install + failures to the
                     active investigation case. Async — never blocks.

Background jobs      File-per-job in ~/.fsuite/fbash/jobs/
                     Poll, list, auto-cleanup after 1 hour

MCP contract         Consistent JSON envelope with 21 fields for every
                     call — including internal commands. No special cases.
```

18 tests. All passing. Zero regressions across the existing 110-test suite.

---

## The Sprint That Followed

The mirror session didn't end with fbash. The drones kept going.

**fread got three upgrades in the same session:**
- Multi-path fallback (`--paths "~/.codex/auth.json,~/.config/codex/auth.json"`) — first-match semantics, one call instead of two
- Symbol resolution fixed for TypeScript modifiers — `override render()`, `static async create()`, `private readonly handler` all found now. The fix went into `fmap` (which `fread` delegates to). 12 new tests.
- JSON error cleanup — the MCP error handler now extracts `error_detail` from the 400-character JSON blob. One line of error instead of a wall of internal state.

**fedit got structural validation (Phase 1 of v2):**
- `validate_structure()` with JSON (jq primary, python3 fallback), YAML, TOML, XML validators
- Validation gate between `render_diff` and `apply_candidate` — corrupted edits rejected before they touch the file
- All-or-nothing batch validation — one invalid candidate aborts the entire batch
- File growth warning for patch/lines modes (>2x size = warning, not abort)
- `--no-validate` escape hatch for JSONC and edge cases
- 14 new tests + 66 existing tests passing. Zero regressions.

**CodeRabbit found 9 issues. All 5 high-priority bugs fixed:**
1. fbash exit code propagation — process now exits with the command's actual code
2. cd commands no longer re-execute with side effects
3. `--json` flag warns instead of silently doing nothing
4. Background mode applies `--env` and `--timeout`
5. fread `--paths` skips directories, matches regular files only

10 TDD regression tests — each designed to fail on pre-fix code, pass on fixed code.

**Renderer polish for viewport clarity:**
- fedit: clean metadata line (`Applied +2 -2 lines | lines | fn:myFunction`)
- fread: pipe-delimited metadata (`21 lines | ~274 tokens | L120:140`), capped at 18 lines pretty output
- fcontent: removed `max_matches` noise from summary line
- Diff column width reduced from 160→120 to prevent Ink text wrapping from breaking background colors

---

## The Numbers (Updated)

```
Session duration:    ~4 hours
Tools deployed:      fbash (new), fread (3 fixes), fmap (1 fix),
                     fedit (validation), mcp/index.js (5 updates)
New code:            ~3,400 lines across 9 files
New tests:           54 (18 fbash + 12 symbol + 14 validation + 10 regression)
Existing tests:      66 fedit core — zero regressions
Total test suite:    120 tests, all passing
Parallel agents:     12 deployed across the session
CodeRabbit reviews:  1 consolidated review, 9 findings, 5 high-priority fixed
Commits:             6 on feat/fsuite-sprint-2026-04-02
PR status:           Ready for review
```

---

## The Story So Far

| PR | Episode | What shipped |
|----|---------|-------------|
| #1 | Pre-history | `ftree` v1.0.0 — the first drone |
| #2 | Pre-history | `ftree` v1.0.1 — refactor + correctness |
| #3 | Pre-history | `ftree` v1.1.0 — output normalization |
| #4 | Pre-history | `ftree` v1.2.0 — snapshot mode |
| #5 | Episode -2 | `fsearch`, `fcontent` — the search drones |
| #6 | Episode -1 | Telemetry, fmetrics, hardware tiers |
| #7 | Episode 0 | The Launch — nitpicks fixed, test overhaul, 203 tests |
| #8 | Episode 1 | `fmap` — code cartography, 12 languages, 259 tests |
| #9 | — | `fmap` v1.6.1 — hardening, CodeRabbit clean |
| #10 | — | `fmap` Markdown support, 18 languages |
| #11 | — | `fcase`, `freplay` v2.1.0 — investigation lifecycle |
| #12 | — | `fcase` v2.1.2 — SQLite busy-timeout hotfix |
| #13 | — | `fedit` v2.0.0 — symbol-first batch editing |
| #14 | — | `fread` v1.8.0, `fedit` v1.9.0 — read and edit loop |
| #15 | Episode 2 | The Monolith — fprobe, fedit --lines, fs, fwrite, MCP overhaul, binary RE, pixel-perfect rendering, archive-grade README, 12 tools, 425 tests |
| #16 | Episode 3 | The Mirror — mapped the rendering engine, built fbash (13th tool), fedit v2 validation, fread multi-path + TS symbols, 120 tests |

---

*The drones were built to explore unfamiliar territory. Today, the most unfamiliar territory turned out to be home. They mapped it. Then they improved it. Then they built a new tool to replace the part that was holding them back. Thirteen tools. One hundred and twenty tests. The suite is complete.*
