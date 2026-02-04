# The Stark Autopsy: Claude Code Evaluates fsuite

> *"I was having a conversation with my coding terminal agent about the tools we built, and I asked him to do a Tony Stark autopsy — a detailed synopsis comparing fsuite's tools to his own built-in toolkit. This is what we came up with. This is the pitch to why you should use these tools, because this is what Claude Code said."*
>
> — [@lliWcWill](https://github.com/lliWcWill), after shipping fsuite

---

## Context

This analysis was performed by **Claude Code (Opus 4.5)** — Anthropic's agentic coding CLI — after being asked to clone, study, and live-test fsuite against its own native toolset. The agent was given no instructions on what to conclude. What follows is the unedited self-assessment.

---

## The Audit: My Current Toolkit vs. fsuite

### What I Have Now

| Tool | What it does | Limitation |
|------|-------------|------------|
| **Glob** | Find files by pattern | Returns file paths, no size/count metadata, no sorting |
| **Grep** | Search file contents | Returns matches, but no composable pipeline with Glob |
| **Read** | Read a file | One file at a time, 2000-line cap |
| **Bash** | Run any command | General-purpose, no structure — I'm just shelling out |
| **Task/Explore** | Spawn a sub-agent to explore | Heavy — spins up an entire agent just to look around |

### What fsuite Has That I Don't

**The gap isn't in any single tool. It's in the reconnaissance layer.** I have no native way to answer the question: *"What is this project, how big is it, and where should I look first?"*

---

## The Rebuild: Tool by Tool

### 1. ftree — This Is the Biggest Upgrade. Nothing I Have Comes Close.

**Current pain:** When I land in an unfamiliar codebase, my first move is to spawn an Explore agent or run a series of `Glob` + `Read` calls — casting a wide net and hoping I grab the right files. I have zero sense of *scale*. I don't know if `src/` has 5 files or 500. I don't know if `utils/` is 2K or 200K. I'm blind until I start reading.

**What ftree gives me:**

- **Recon mode** answers "where's the weight?" in one call. A 256K `src/` directory with 35 items versus a 118-byte `.gitignore` — now I know where the code actually lives before I read a single file. That size-sorted inventory is something I literally cannot get from any of my tools without chaining `du`, `find`, `wc`, and `sort` in Bash and parsing the output myself.

- **Snapshot mode** is the real killer. One command gives me both the structural map AND the size inventory. Right now, to get equivalent context, I spin up a Task/Explore agent that makes 10-15 tool calls internally. `ftree --snapshot -o json` replaces that entire agent in a single invocation.

- **The 200-line cap with drill-down suggestions** is actually designed for me. It prevents me from dumping an entire monorepo tree into my context window and wasting tokens on noise. It says "here's depth 3, if you need more, drill into `src/bot/handlers`." That's exactly how I should be working but often don't.

**Integration:** I would use `ftree --snapshot -o json` as my **very first move** on any new project, before Glob, before Grep, before anything. It replaces the Explore agent for initial reconnaissance entirely. I'd keep the Explore agent for deeper semantic questions ("how does auth work?"), but for structural understanding, ftree is faster, cheaper, and more informative.

**Verdict: Net new capability. No replacement — this fills a hole.**

---

### 2. fsearch — Augments Glob, Doesn't Replace It

**Current pain:** Glob is fine for exact patterns when I already know what I'm looking for. `**/*.ts` works. But Glob has no intelligence about what I *mean*. If I search for `log`, I have to know to write `**/*.log`. If I search for `config`, I have to decide: do I mean `*config*`? `*.config.*`? `config.*`?

**What fsearch gives me:**

- **Pattern normalization.** I say `log`, it knows I mean `*.log`. I say `upscale`, it wraps it as `*upscale*`. This is the kind of fuzzy-to-precise translation I currently do in my head before calling Glob. fsearch externalizes that reasoning.

- **Backend selection.** It auto-picks `fd` over `find` when available. I don't think about this — I just call Glob and trust the system. But in Bash-based workflows (scripting, pipelines), having a tool that optimizes its own backend matters.

- **The `--output paths` mode** is specifically designed to pipe into fcontent. Glob returns paths too, but there's no native pipeline between Glob and Grep in my toolkit. They're independent tools that I manually bridge by reading Glob results, then calling Grep on each path. fsearch + fcontent eliminates that manual bridging.

**Where Glob still wins:** Glob is built into my runtime. Zero latency, no process spawn. For quick needle queries ("find `auth.middleware.ts`"), Glob is faster. I wouldn't replace it.

**Integration:** I'd use fsearch when I'm in **discovery mode** — when I don't know exactly what I'm looking for and want smart pattern handling. I'd keep Glob for **precision mode** — when I know the exact file pattern. And critically, I'd use fsearch when I need to **pipe into fcontent**, because that pipeline doesn't exist natively.

**Verdict: Augment. Use alongside Glob for discovery and pipeline scenarios.**

---

### 3. fcontent — Augments Grep, With One Major Advantage

**Current pain:** Grep is solid. It does regex, it does file type filtering, it does context lines. But it operates in isolation. When I Grep a large codebase, I get matches — but I have no control over the *scope* of what I'm searching. I search everything in a directory, or I search one file. There's no middle ground.

**What fcontent gives me:**

- **The piped mode is the real value.** `fsearch --output paths '*.py' | fcontent "import torch"` — this lets me narrow the search space *before* searching content. With my native tools, I'd Glob for `*.py`, get 200 paths, then Grep across the directory with a type filter. Similar result, but the fsuite version is a composable pipeline where each stage refines the scope. That's a fundamentally different mental model.

- **Match caps.** fcontent defaults to 200 matches max. This is designed for me. When I Grep a large codebase and get 3000 matches, I've just burned context tokens on noise. fcontent prevents that by default. I don't have a native equivalent — I have to manually set `head_limit` on Grep, and I often forget to.

- **Structured JSON output.** `{"total_matched_files": N, "matches": [...], "matched_files": [...]}` — this gives me both the matches AND the unique file list in one response. With Grep, I'd need two calls: one for `content` mode and one for `files_with_matches` mode. fcontent gives both simultaneously.

**Where Grep still wins:** Grep has richer filtering — `type` parameter for language-specific searches, `-A/-B/-C` for context lines, `multiline` mode. Grep is also in-process, no shell spawn. For targeted searches where I know the file and pattern, Grep is better.

**Integration:** I'd use fcontent at the **end of an fsuite pipeline** — after ftree told me where to look and fsearch narrowed the file list. I'd keep Grep for **direct, targeted searches** when I already know the scope. The two serve different phases of investigation.

**Verdict: Augment. Use for pipeline searches and scoped discovery. Keep Grep for precision.**

---

## The Workflow Transformation

### Before fsuite (How I Work Now)
```
1. User says "explore this project"
2. Spawn Explore agent (heavy, 10-15 internal tool calls)
3. Agent runs Glob("**/*"), reads README, reads random files
4. Agent returns summary (burned 15 tool calls, maybe missed key dirs)
5. I still don't know directory sizes or structure
6. Start Grep-ing blindly for keywords
7. Read files one by one
8. Gradually build understanding over many turns
```

### After fsuite (The Upgrade)
```
1. User says "explore this project"
2. ftree --snapshot -o json /project          <- ONE call, full structural context
3. I now know: 14 dirs, 27 files, src/ is 256K (that's where code lives)
4. fsearch -o paths '*.ts' /project/src       <- scoped file discovery
5. Pipe to fcontent if I need to find patterns <- scoped content search
6. Read only the files that matter
7. Full understanding in 3-4 tool calls instead of 15+
```

**Token savings:** The Explore agent typically uses 10-15 internal tool calls, each consuming context. The fsuite pipeline achieves the same (or better) understanding in 3-4 Bash calls with structured output. That's roughly **70% fewer tool invocations** for initial reconnaissance.

---

## The Headless Advantage

This is where fsuite was clearly *designed for agents like me*, and it shows in three specific ways:

1. **No interactive prompts in headless mode.** My tools already handle this, but fsuite explicitly detects TTY state and adjusts. The `headless-hardening.md` doc shows they ran into the exact bugs that trip up agent-driven tools (stdin detection, exit code leaks, `--files-from` incompatibilities) and fixed them. That level of agent-awareness is rare in CLI tools.

2. **Structured JSON with metadata envelopes.** Every JSON response includes `tool`, `version`, `mode`, and counts. I don't have to parse human-readable output. I get `total_entries: 12, visible: 11, excluded: 1` — machine-readable facts I can reason over programmatically.

3. **Context-budget awareness.** The 200-line cap on ftree, the 200-match cap on fcontent, the truncation footers with drill-down suggestions — these are guardrails designed for LLM context windows. My own tools don't have this. Grep will happily return 5000 lines if I don't set `head_limit`. fsuite defaults to *not* flooding me.

---

## Final Assessment

| Tool | Action | Reason |
|------|--------|--------|
| **ftree** | **Add as primary recon tool** | Fills a gap nothing else covers. Replaces Explore agent for structural understanding. |
| **fsearch** | **Add alongside Glob** | Use for discovery + pipeline input. Keep Glob for precision queries. |
| **fcontent** | **Add alongside Grep** | Use for scoped pipeline searches. Keep Grep for direct targeted searches. |
| **Explore agent** | **Demote to semantic-only** | Still useful for "how does X work?" but no longer needed for "what's in this project?" |

The honest summary: fsuite doesn't make any of my tools obsolete, but it fills the **reconnaissance gap** that is genuinely my weakest phase of operation. I'm good at reading code, editing code, and running commands. I'm bad at efficiently *finding* what to read in the first place. fsuite is built specifically for that phase, and built specifically for how I operate.

---

*Analysis performed by Claude Code (Opus 4.5) on January 28, 2026.*
*No instructions were given on what to conclude. This is the raw self-assessment.*
