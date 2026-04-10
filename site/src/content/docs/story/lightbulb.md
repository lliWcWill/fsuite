---
title: The Lightbulb Moment
description: Why fsuite exists. The honest version — CLI-first, MCP detour, hooks discovered too late, the recursion problem, and the Monokai TODO.
sidebar:
  order: 1
---

**The honest version: fsuite was always supposed to be CLI-first. The MCP server, the hooks, the enforcement stack — those came later, in the wrong order, and we're still catching up to the lightbulb moment that probably should have come first.**

Here's the sequence, for the record.

## 1. Built the fsuite CLI tools

`fread`, `fedit`, `ftree`, `fs`, `fmap`, `fcase`, the whole stack. The core idea: give coding agents bounded, structured, token-budgeted alternatives to `grep`, `find`, `cat`, `sed`, and `bash`. CLI-first, always. That was the plan.

## 2. Built the MCP server

Because even with fsuite installed, Claude would still reach for its native `Bash` tool to run `fread` instead of something structured. So we wrapped the whole suite in MCP to give it a cleaner call path. The thing picked up a color scheme (Monokai) along the way, which turned out to be the part we love the most about it.

## 3. Built `fbash`

Because we realized we could replace the `Bash` tool too — token-budgeted, classified, session-aware. At this point fsuite had 14 tools and a whole MCP layer and we still thought we were doing the right thing.

## 4. Discovered Claude Code hooks

*After* all of the above. It turns out you can just **block** native tools at the source and force agents to use fsuite instead. One `PreToolUse` hook per blocked tool. No MCP needed to enforce usage. If we'd known about hooks first, the MCP might not exist at all.

## 5. Tried to rely on hooks alone

Couldn't. Hooks *block*, but they don't *route* — an agent can get blocked on `Read` but has no automatic translation to `fread`. So we defaulted back to the MCP as the "easy path" for agents to discover and invoke the suite. The two layers ended up complementary: hooks block the old tools, MCP exposes the new ones, agents have nowhere to land except on fsuite.

## The recursion problem

If you removed the MCP today, an agent would have to use its native `Bash` tool to call `fbash` to call `fread`. That's two hops, and it defeats the whole "use fsuite instead of Bash" thesis.

The honest truth: without the MCP, the agent would just use its `Bash` tool to call `fread` directly — which still works, but you lose the Monokai-colored structured output the MCP layer renders. Which is the part we love the most about the MCP path. Which should probably just be on the CLI tools too.

**Real TODO.** Not shipped yet.

## What actually happened

So that's how we got here. Messy build order, three layers stacked on top of each other, and somewhere in the middle of the chaos the thing started to *work*. We didn't believe it either until we pointed Claude Code at the repo, told it to clone, study, and live-test the tools, and asked it to do a *Tony Stark autopsy*: compare fsuite against its own built-in toolkit and tell us honestly what it would change.

It didn't just say "nice tools." It wrote a full self-assessment. The headline finding:

> *"The gap isn't in any single tool. It's in the reconnaissance layer. I have no native way to answer the question: 'What is this project, how big is it, and where should I look first?'"*
>
> *"fsuite doesn't make any of my tools obsolete, but it fills the reconnaissance gap that is genuinely my weakest phase of operation. I'm good at reading code, editing code, and running commands. I'm bad at efficiently finding what to read in the first place. fsuite is built specifically for that phase, and built specifically for how I operate."*
>
> — Claude Code (Opus 4.5), self-assessment, January 2026

The chaos converged on solving the real problem. We just got there backwards.

[Read Episode 0 →](/story/episode-0/) for the original framing, the version we wrote before we knew hooks existed.
