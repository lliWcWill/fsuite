# fsuite Agent Guide

Use `fsuite` for the suite-level mental model, then reach for the operational tools for filesystem reconnaissance, bounded reading, and surgical editing — before you open files blindly or burn tokens on broad exploration loops.

## Mental Model

```text
fsuite → fs / ftree / fls → fsearch | fcontent → fmap → fread → fcase → fedit / fwrite → fmetrics
Guide    Unified / Scout / LS   Narrowing            Bridge   Read     Preserve  Mutate           Measure
```

Specialist tools orbit the main stack:
- `fbash` — Bash replacement with token-budgeting, classification, and session state
- `fprobe` — Binary / bundle inspection + patching when normal reads fail
- `freplay` — Derivation chain replay for deterministic reruns

## Headless Defaults

- Prefer `-o json` for programmatic decisions
- Prefer `-o paths` when piping into another tool
- Prefer `pretty` only for human terminal output
- Results go to `stdout`. Errors go to `stderr`
- Use `-q` for existence checks and silent control flow

## Chain Combinations — the fbash unlock

When you call fsuite tools via MCP, **each tool call is sequential and independent**. There are no Unix pipes between them — you spawn each process, get the result, then spawn the next one. That works for one-off calls, but it's wasteful when the natural shape of your work is a pipeline.

**The unlock:** `fbash` is also an MCP tool. When you invoke it, you're back inside a real bash shell with all your local CLI tools on `PATH` (`fsearch`, `fcontent`, `fmap`, `fread`, etc., plus `jq`, `awk`, `grep`, `python3` — anything you have installed). Pipes work. Background jobs work. Process substitution works.

```bash
# CLI mode (terminal): native Unix pipes
fsearch -o paths '*.py' src | fcontent -o paths "def authenticate" | fmap -o json

# MCP mode without fbash: three sequential tool calls, no pipes between them
fsearch(query: "*.py")  →  fcontent(query: "def authenticate", path: <results>)  →  fmap(path: <results>)

# MCP mode WITH fbash: identical to CLI mode, one round trip
fbash(command: "fsearch -o paths '*.py' src | fcontent -o paths 'def authenticate' | fmap -o json")
```

**The pipe contract:** producers (`fsearch -o paths`, `fcontent -o paths`) emit file paths; consumers (`fcontent`, `fmap`) read paths from stdin. `fread`, `fedit`, `ftree`, `fprobe`, `fcase`, `freplay`, `fmetrics` are argument-based — they don't chain in a pipe but they compose fine sequentially.

**Rule of thumb:**
- Single tool call → call the MCP tool directly.
- Two or more producer/consumer steps, or you want `jq`/`awk`/`python3 -c` in the chain → wrap the whole thing in `fbash`.
- Long-running work → use `fbash(background: true)` and `fbash(poll: <job_id>)` so you don't block on tool output.

**fbash is the only bash you reach for.** Token-budgeted output (no 50k-line build log floods), command classification (build/test/git/etc.), session state across calls, fcase event integration, and `next_hint` suggestions when an fsuite tool would have been better.

## Recommended Workflow

```bash
# 0) Load the suite-level guide once
fsuite

# 1) Scout once — establish territory
ftree --snapshot -o json /project

# 2) One-shot search — auto-routes to the right tool
fs "authenticate" /project/src --scope '*.py'

# 3) Map structure before broad reads
fmap /project/src/auth.py -o json

# 4) Read exact context — symbol-scoped, not line-guessed
fread /project/src/auth.py --symbol authenticate

# 5) Preserve investigation state once the seam is known
fcase init auth-seam --goal "Trace authenticate flow"
fcase next auth-seam --body "Review denial branch before patching"

# 6) Edit surgically — line-range or symbol-scoped
fedit /project/src/auth.py --lines 120:124 --with-text "new code"

# 7) Measure and predict
fmetrics stats -o json
fmetrics predict /project
```

## Tool Reference (14 tools)

**Discovery & Navigation**

| Tool | One-liner | Canonical call |
|---|---|---|
| `fs` | Universal search orchestrator — auto-routes to fsearch/fcontent/fmap based on query intent | `fs "authenticate" --scope '*.py'` |
| `ftree` | Territory scout — full tree + recon data in one call. Replaces multiple Glob/LS rounds | `ftree --snapshot -o json /project` |
| `fls` | Structured directory listing with recon mode (sizes, types, flags) | `fls src/providers --mode recon` |
| `fsearch` | File / glob discovery. Pipe-friendly with `-o paths` | `fsearch '*.py' src -o paths` |
| `fcontent` | Bounded content search — token-capped ripgrep. Use AFTER narrowing, not first | `fcontent "authenticate" src/*.py` |

**Reading & Mapping**

| Tool | One-liner | Canonical call |
|---|---|---|
| `fmap` | Symbol cartography — functions, classes, imports, constants. 15+ languages. No native equivalent | `fmap src/auth.py` |
| `fread` | Budgeted reading with symbol resolution, line ranges, or context around matches. Never guess line numbers | `fread src/auth.py --symbol authenticate` |

**Editing & Writing**

| Tool | One-liner | Canonical call |
|---|---|---|
| `fedit` | Surgical edit — line-range, symbol-scoped, or anchor-based. Preconditions + structural validation | `fedit src/auth.py --lines 120:124 --with-text "new"` |
| `fwrite` | Atomic file creation. Standalone tool (not an fedit wrapper) — `--stdin`, `--from`, `--mkdir`, `--dry-run` | `fwrite src/new.ts --content "..."` |

**Shell & Binary**

| Tool | One-liner | Canonical call |
|---|---|---|
| `fbash` | Token-budgeted shell with classification, session state, background jobs, and fsuite-aware routing. **The MCP unlock for real Unix pipe chains** — call fsuite/local CLI tools through fbash to compose pipelines that raw MCP tool calls can't | `fbash "fsearch -o paths '*.py' \| fcontent -o paths 'def ' \| fmap -o json"` |
| `fprobe` | Binary / bundle inspection + in-place patching. Strings, scan, window, patch actions | `fprobe strings ./binary --pattern VERSION` |

**Investigation & Measurement**

| Tool | One-liner | Canonical call |
|---|---|---|
| `fcase` | Investigation continuity ledger — tracks findings, evidence, handoff state. Preserves work across context compaction and sessions | `fcase init auth-bug --goal "trace 401s"` |
| `freplay` | Derivation chain replay — rerun a traced investigation step-by-step | `freplay --session auth-bug` |
| `fmetrics` | Telemetry analytics + predictive tool-chain recommendations from past runs | `fmetrics predict /project` |

## Workflow Discipline

- Run `fsuite` once for the mental model — don't re-read it
- Run `ftree --snapshot` **once** to establish territory. Don't rediscover the repo unless the target changes
- Use `fs` as the default search entry point. Let it route
- Prefer `fmap` + `fread --symbol` before broad `fcontent`
- Use `fcontent` for exact-text confirmation AFTER narrowing, not as the first conceptual search
- Open `fcase init` at the start of any non-trivial investigation. Close with `fcase resolve`
- Always check `fcase find --status all --deep` before starting new work — past investigations may already have your answer
- Use `fread --symbol NAME` or `--lines START:END`. Don't read whole files
- Use `fedit --lines` when you have line numbers from fread. Fastest edit mode, zero ambiguity
- Use `fedit --function_name` when you want symbol-scoped edits without needing large unique context strings
- Never edit blind. Always inspect context with `fread` before calling `fedit`

## Output Formats

| Format | When to use |
|---|---|
| `-o pretty` (default) | Human terminal reading |
| `-o json` | Programmatic parsing, automation, chaining into jq |
| `-o paths` | Piping file lists into other tools |
| `-q` / `--quiet` | Existence checks and silent control flow (exit code only) |

## Further Reading

- [`README.md`](README.md) — full reference, tool-by-tool, with examples and chain combinations
- [`docs/EPISODE-0.md`](docs/EPISODE-0.md) through `EPISODE-3.md` — backstory of how fsuite came to be
- [`docs/internal/`](docs/internal/) — dev journal, design specs, plans (reference only, not user-facing)
