# fsuite

<p align="center">
  <img src="docs/fsuite-hero.jpeg" alt="fsuite - Filesystem Reconnaissance Drones" width="800">
</p>

<p align="center">
  <em>Deploy the drones. Map the terrain. Return with intel.</em>
</p>

[![Release](https://img.shields.io/github/v/release/lliWcWill/fsuite?display_name=tag)](https://github.com/lliWcWill/fsuite/releases)
![Debian Package](https://img.shields.io/badge/deb-package%20available-A81D33)
![Shell](https://img.shields.io/badge/Shell-Bash-4EAA25?logo=gnubash&logoColor=white)
![JSON Output](https://img.shields.io/badge/output-json-0A7EA4)
![Platform](https://img.shields.io/badge/platform-linux%20%7C%20macOS-444)

---

**A suite-level guide plus seven operational tools for filesystem reconnaissance, patching, and analytics.**

`fsuite` provides one suite-level guide command plus seven operational tools that turn filesystem exploration into a clean, scriptable, agent-friendly pipeline:

| Tool | Purpose |
|------|---------|
| **`fsuite`** | Print the suite-level conceptual flow, tool roles, and headless usage guidance |
| **`fsearch`** | Find files by name, extension, or glob pattern |
| **`fcontent`** | Search _inside_ files for text (powered by ripgrep) |
| **`ftree`** | Visualize directory structure with smart defaults and recon mode |
| **`fmap`** | Extract structural skeleton from code (code cartography) |
| **`fread`** | Read files with budgets, ranges, context windows, and diff-aware input |
| **`fedit`** | Apply surgical text patches with dry-run diffs, preconditions, and symbol scoping |
| **`fmetrics`** | Analyze telemetry, history, and predicted runtime |

The first five operational tools are reconnaissance drones. `fedit` is the surgical patch arm. `fmetrics` is the flight recorder and analyst. Together they cover **scout -> find/search -> map -> read -> edit -> measure**. The `fsuite` command is the suite-level explainer that teaches that flow to humans and agents on first contact.

Works with **Claude Code**, **Codex**, **OpenCode**, and any shell-capable agent harness that can call local binaries.

| Install Path | Best For | Status |
|-------------|----------|--------|
| `./install.sh --user` | Fast local install without sudo | Recommended |
| Debian package | Linux release installs | Available |
| Source + manual symlink | Power users and repo hacking | Available |
| Homebrew tap | macOS-native package install | Roadmap |
| npm wrapper | Installer/distribution wrapper, not a rewrite | Roadmap |

## Contents

- [Why This Exists](#why-this-exists-the-lightbulb-moment)
- [Quick Start](#quick-start)
- [fsuite Help](#fsuite-help)
- [Fast Paths](#fast-paths-copypaste)
- [Tools](#tools)
  - [fsearch](#fsearch--filename--path-search)
  - [fcontent](#fcontent--file-content-search)
  - [ftree](#ftree--directory-structure-visualization)
  - [fmap](#fmap--code-cartography)
  - [fread](#fread--budgeted-file-reading)
  - [fedit](#fedit--surgical-patching)
  - [fmetrics](#fmetrics--telemetry-analytics)
- [Output Formats](#output-formats)
- [Agent / Headless Usage](#agent--headless-usage)
- [Cheat Sheet](#cheat-sheet)
- [Quick Reference — Flags](#quick-reference--flags)
- [Optional Dependencies](#optional-dependencies)
- [Security Notes](#security-notes)
- [Installation](#installation)
- [Changelog](#changelog)
- [License](#license)

---

## Why This Exists: The Lightbulb Moment

We shipped fsuite and thought it was done. Then we pointed Claude Code at the repo, told it to clone, study, and live-test the tools — and asked it to do a *Tony Stark autopsy*: compare fsuite against its own built-in toolkit and tell us honestly what it would change.

It didn't just say "nice tools." It wrote a full self-assessment. Unprompted conclusions. No instructions on what to find.

**The headline finding:**

> *"The gap isn't in any single tool. It's in the reconnaissance layer. I have no native way to answer the question: 'What is this project, how big is it, and where should I look first?'"*
>
> *"fsuite doesn't make any of my tools obsolete, but it fills the reconnaissance gap that is genuinely my weakest phase of operation. I'm good at reading code, editing code, and running commands. I'm bad at efficiently finding what to read in the first place. fsuite is built specifically for that phase, and built specifically for how I operate."*
>
> — Claude Code (Opus 4.5), self-assessment, January 2026

**What the agent said it would do:**

| Tool | Agent's Verdict |
|------|----------------|
| **ftree** | *"Net new capability. Nothing I have comes close."* — Replaces the Explore agent for structural recon. |
| **fsearch** | *"Augment. Use alongside Glob for discovery and pipeline scenarios."* — Pattern normalization + pipeline composability. |
| **fcontent** | *"Augment. Use for pipeline searches and scoped discovery."* — Piped mode + match caps designed for LLM context windows. |

That first round exposed the real missing step: after recon and search, the agent still had to spend extra calls just to read the right slice of a file. `fmap` and `fread` close that gap. `fedit` turns that bounded context into a safe patch surface. `fmetrics` closes the final loop by turning live usage into operational feedback instead of guesswork.

**The workflow shift — before and after:**

```text
BEFORE fsuite:
  Spawn Explore agent -> 10-15 internal tool calls -> still blind on structure

AFTER fsuite:
  ftree --snapshot -o json  ->  fsearch -o paths  ->  fmap -o json  ->  fread -o json  ->  fedit -o json
  5-6 calls. Structural context, bounded file reads, and previewable edits. Still dramatically fewer tool invocations.
```

And once those reads are happening in the real world:

```text
AFTER execution:
  ... -> fcontent -o json (only if exact text confirmation is needed) -> fedit -o json -> fmetrics import -> fmetrics stats / predict
  Search inside the narrowed set, patch surgically, then measure what actually happened and plan the next pass.
```

The full unedited analysis is in **[AGENT-ANALYSIS.md](AGENT-ANALYSIS.md)** — the raw self-assessment, exactly as Claude Code wrote it after studying and testing every tool in this repo.

That document is the pitch. Not because we wrote it, but because the agent did.

---

## Quick Start

```bash
# Clone and make executable
git clone https://github.com/lliWcWill/fsuite.git
cd fsuite

# Recommended: install into ~/.local/bin
./install.sh --user

# Suite-level guide
./fsuite

# Find all .log files under /var/log
./fsearch '*.log' /var/log

# Search inside files for "ERROR"
./fcontent "ERROR" /var/log

# Scout a project: what's here?
./ftree --recon /project

# Show the directory tree (depth 3, smart defaults)
./ftree /project

# Map code structure before opening files
./fmap -o json /project/src

# Read targeted context around a function or match
./fread /project/src/auth.py --around "def authenticate" -A 20

# Combine: find logs, then grep inside them
./fsearch --output paths '*.log' /var/log | ./fcontent "ERROR"

# Import telemetry and inspect runtime history
./fmetrics import && ./fmetrics stats
```

---

## fsuite Help

`fsuite` is now a real suite-level guide command. The operational work still happens through the seven underlying tools, but `fsuite` is the fastest way to load the mental model.

If your harness reads repo instructions automatically, use the bundled [AGENTS.md](AGENTS.md) as the suite-level operating guide.

If an agent only remembers one thing, it should remember this:

```text
fsuite -> ftree -> fsearch | fcontent -> fmap -> fread -> fedit -> fmetrics
Guide     Scout    Narrowing             Bridge   Read     Edit      Measure
```

The CLI equivalent is:

```bash
fsuite
```

### What Each Tool Is For

| Tool | Use it when you need to answer | Best output for agents |
|------|--------------------------------|------------------------|
| `ftree` | "What is in this project, how big is it, and where should I look first?" | `-o json` |
| `fsearch` | "Which files match this name, extension, or glob?" | `-o paths` or `-o json` |
| `fmap` | "What symbols exist in these source files?" | `-o json` |
| `fcontent` | "Which narrowed files contain this exact text?" | `-o json` or `-o paths` |
| `fread` | "Show me the exact lines around this function, match, or diff hunk." | `-o json` |
| `fedit` | "Preview and apply a surgical patch against the exact symbol or anchor I just inspected." | `-o json` |
| `fmetrics` | "What did these runs cost, and what will the next one cost?" | `stats -o json`, `predict` |

### Headless Contract

- Prefer `-o json` when the next step is programmatic decision-making.
- Prefer `-o paths` when the next step is piping into another fsuite tool.
- Prefer `pretty` only for human terminal use.
- Errors go to `stderr`. Results go to `stdout`.
- `-q` is for existence checks and silent control flow.
- Use `fsuite` for the suite-level mental model and each tool's `--help` for the full flag breakdown.

### Default Agent Workflow

```bash
# 0) Load the suite-level guide once
fsuite

# 1) Scout the target once
ftree --snapshot -o json /project

# 2) Narrow to candidate files
fsearch -o paths '*.py' /project/src

# 3) Map structure before broad reads
fsearch -o paths '*.py' /project/src | fmap -o json

# 4) Read the exact code neighborhood you care about
fread -o json /project/src/auth.py --around "def authenticate" -B 5 -A 20

# 5) Only if you still need exact text confirmation, search inside the narrowed set
fsearch -o paths '*.py' /project/src | fcontent -o json "authenticate"

# 6) Preview and then apply the patch
fedit -o json /project/src/auth.py --symbol authenticate --replace "return False" --with "return deny()"
fedit -o json /project/src/auth.py --symbol authenticate --replace "return False" --with "return deny()" --apply

# 7) Import telemetry and inspect the cost of what just happened
fmetrics import
fmetrics stats -o json
fmetrics predict /project
```

### Decision Rule for Agents

- Run `ftree` once to establish territory.
- Run one narrowing pass with `fsearch`.
- Prefer `fmap` + `fread` before broad `fcontent`.
- Use `fcontent` as exact-text confirmation after narrowing, not as the first conceptual repo search.
- Do not rediscover the repo twice unless the target changes or a contradiction appears.

| If you need... | Use... |
|----------------|--------|
| project shape, size, likely hotspots | `ftree` |
| candidate filenames | `fsearch` |
| structural skeleton without reading full files | `fmap` |
| content matches across files | `fcontent` |
| bounded context from a known file | `fread` |
| safe patch application against inspected context | `fedit` |
| runtime history or a preflight estimate | `fmetrics` |

---

## Language Support

`fsuite` works on any normal text file for `fsearch`, `fcontent`, `fread`, and plain `fedit`.
The table below tracks the **language-aware structural layer** in `fmap` and the **symbol-scoped** edit path that depends on it.

### Current Structural Support

| Language / ecosystem | `fmap` support | Symbol-scoped `fedit` | Notes |
|---|---:|---:|---|
| Python | Yes | Yes | Core AI / automation / backend |
| JavaScript | Yes | Yes | Web, Node, agent tooling |
| TypeScript | Yes | Yes | Web, agents, infrastructure tooling |
| Kotlin | Yes | Yes | Android / Kotlin-first mobile repos |
| Swift | Yes | Yes | Apple-native app analysis |
| Rust | Yes | Yes | Systems / infra / performance |
| Go | Yes | Yes | Services / CLIs / platform code |
| Java | Yes | Yes | Enterprise / Android-adjacent |
| C | Yes | Yes | Systems / embedded |
| C++ | Yes | Yes | Native / performance-heavy code |
| Ruby | Yes | Yes | Legacy web / scripting |
| Lua | Yes | Yes | Embedding / config / game tooling |
| PHP | Yes | Yes | Large real-world web footprint |
| Bash / Shell | Yes | Yes | DevOps / scripts / automation |
| Dockerfile | Yes | Yes | Container workflows |
| Makefile | Yes | Yes | Build systems |
| YAML | Yes | Yes | CI / config / infra manifests |

### Recommended Next Support (2026)

| Language / ecosystem | Why it matters | Priority | Notes |
|---|---|---:|---|
| C# | Large .NET / Unity / enterprise footprint | P0 | Strong cross-industry demand |
| Dart / Flutter | Cross-platform mobile codebases | P1 | Strong next mobile follow-up |
| HCL / Terraform | Infra / platform repo coverage | P1 | High-value for agent audits |
| Objective-C | Legacy Apple codebases | P1 | Useful after Swift |
| Mojo | Emerging AI / GPU language | P2 | Strategic watchlist |

### Ecosystem Bundles We Want

| Bundle | What it should cover |
|---|---|
| Apple-lite | Swift, `Package.swift`, `Info.plist`, later Objective-C |
| Android-lite | Kotlin, Gradle, Gradle Kotlin DSL, `AndroidManifest.xml`, resource/layout XML; narrow manifest/layout reconnaissance now lands in `fmap` |
| Python AI | Python plus better real-world recipes for PyTorch, JAX, NumPy, PyTensor |
| Infra | HCL / Terraform, Docker, CI config surfaces |
| Agent tooling | TypeScript / Python patterns for MCP, tool routing, workflow harnesses |

### Vote On Next Support

Open an issue or discussion with:

- the language or ecosystem you want
- 1-3 public repos we should test against
- the symbol types that matter most (`function`, `class`, `type`, `import`, `export`, `constant`)
- whether you care more about:
  - reading / mapping
  - editing
  - mobile app analysis
  - AI / ML codebases
  - infra / DevOps code

---

## Fast Paths (copy/paste)

Four workflows that cover the common cases without improvisation. Copy, paste, go.

### 1) New repo — instant context (best default)
```bash
ftree --snapshot -o json /project | jq .
```

### 2) Find candidates — search inside them (pipeline power)
```bash
fsearch -o paths '*.ts' /project/src | fcontent -o json "Auth" | jq .
```

### 3) Map structure, then read the exact neighborhood
```bash
fsearch -o paths '*.py' /project/src | fmap -o json | jq '.files[:5]'
fread /project/src/auth.py --around "def authenticate" -B 5 -A 20
```

### 4) Triage a big project safely (no floods)
```bash
ftree --recon -o json /project | jq '.entries | sort_by(-.size_bytes) | .[:10]'
```

> **Note:** `jq` is optional — used only in these examples for pretty-printing JSON. All tools output valid JSON natively with `-o json`.

---

## Tools

### `fsearch` &mdash; filename / path search

Searches for files by **name or glob pattern**. Automatically picks the fastest available backend (`fd` > `find`).

```bash
fsearch [OPTIONS] <pattern_or_ext> [path]
```

**Key features:**

- Glob-aware: `'upscale*'`, `'*progress*'`, `'*.log'`
- Smart pattern handling:
  - Wildcards are preserved (`*`/`?`).
  - Leading dot becomes an extension: `.log` -> `*.log`.
  - Dotted names are literal: `file.txt` -> `file.txt`.
  - Short lowercase tokens (<=4 chars, `^[a-z0-9]+$`, not purely numeric) become extensions:
    `py` -> `*.py`, `main` -> `*.main`.
  - Numeric-only tokens are treated literally (e.g. `123` stays `123`).
- Auto-selects `fd`/`fdfind` when available, falls back to POSIX `find`
- Interactive mode (prompts for missing args) or fully headless
- `--include/--exclude` support for post-search filtering, both repeatable and wildcard-aware
- Built-in low-signal directory suppression by default:
  - `node_modules`, `dist`, `build`, `.next`, `coverage`, `.git`, `vendor`, `target`
  - disable with `--no-default-ignore`
- Quiet mode (`-q`) for existence checks — exit 0 if found, 1 if not
- Three output formats: `pretty` (default), `paths` (one per line), `json`

**Examples:**

```bash
# Human-friendly output
fsearch '*.conf' /etc

# Agent-friendly: paths only
fsearch --output paths '*.py' /home/user/projects

# Agent-friendly: structured JSON
fsearch --output json '*token*' /home/user

# Force the fd backend
fsearch --backend fd '*.rs' /opt/src

# Monorepo noise reduction (skip generated dirs)
fsearch --exclude node_modules --exclude .git '*.py' /repo

# Focused scan with inclusion and exclusion
fsearch -I 'services/*' -x '*test*' '*.go' /project/src

# Interactive mode (prompts for pattern and path)
fsearch -i
```

### `fcontent` &mdash; file content search

Searches **inside** files using `rg` (ripgrep). Accepts a directory _or_ a piped list of file paths from stdin.

```bash
fcontent [OPTIONS] <query> [path]
```

**Key features:**

- Directory mode: recursively searches a path
- Piped mode: reads file paths from stdin (pairs with `fsearch --output paths`)
- Directory mode suppresses low-signal dependency/build trees by default:
  - `node_modules`, `dist`, `build`, `.next`, `coverage`, `.git`, `vendor`, `target`
  - disable with `--no-default-ignore`
- Three output formats: `pretty` (default), `paths` (matched files only), `json`
- Configurable match (`-m`) and file (`-n`) caps to prevent terminal floods
- Quiet mode (`-q`) for existence checks — exit 0 if found, 1 if not
- Pass-through for extra `rg` flags via `--rg-args`

**Operational note:** use `fcontent` after narrowing with `fsearch`/`fmap`/`fread`. It is an exact-text confirmation tool, not the best first-pass repo exploration step.

**Examples:**

```bash
# Search a directory
fcontent "database" /home/user/project

# Pipe from fsearch
fsearch --output paths '*.log' /var/log | fcontent "CRITICAL"

# JSON output for agent consumption
fcontent --output json "api_key" /home/user/project

# Case-insensitive search with hidden files
fcontent --rg-args "-i --hidden" "secret" /home/user
```

### `ftree` &mdash; directory structure visualization

Wraps `tree` with smart defaults, context-budget awareness, and a **recon mode** for scouting directories before committing context window to a full tree dump.

```bash
ftree [OPTIONS] [path]
```

**Key features:**

- Smart defaults: depth 3, 200-line cap, noise directories excluded (node_modules, .git, venv, etc.)
- Recon mode: per-directory item counts and sizes without full tree expansion
- Excluded-dir summaries in recon show what's hidden and how big it is
- `--include` promotes excluded dirs back to normal treatment
- Multiple `--ignore` flags accumulate (v1.0.1+): `-I 'docs' -I '*.md'` excludes both
- Quiet mode (`-q`) for silent operation — exit code only
- Three output formats: `pretty` (default), `paths` (flat file list), `json`
- Snapshot mode (`--snapshot`): combined recon + tree in one command (v1.2.0+)
- Truncation with overflow count and drill-down suggestion
- Clear error messages when flags are missing their required values

**Examples:**

```bash
# Default tree (depth 3, smart excludes, 200-line cap)
ftree /project

# Recon: scout per-directory sizes before committing context
ftree --recon /project

# JSON for agent consumption
ftree -o json /project

# Flat file list for piping
ftree -o paths /project

# Drill into a subdirectory
ftree -L 5 /project/src

# Include a normally-excluded directory
ftree --include .git /project

# Stack multiple ignore patterns (each -I adds to the list)
ftree -I 'docs' -I '*.md' /project

# Snapshot: recon + tree in one shot
ftree --snapshot /project

# Snapshot JSON for agents
ftree --snapshot -o json /project

# Recon without excluded-dir summaries
ftree --recon --hide-excluded /project

# Show sizes in tree output
ftree -s /project

# Directories only
ftree -d /project
```

See **[docs/ftree.md](docs/ftree.md)** for the full deep-dive: architecture, all flags, headless agent workflows, interactive human usage, and tandem usage with `fsearch`/`fcontent`.

### `fmap` &mdash; code cartography

Extracts the **structural skeleton** from source files — functions, classes, imports, types, exports, constants — without reading full file contents. Fills the gap between "found files" and "read full files."

```bash
fmap [OPTIONS] [path]
```

**Key features:**

- Zero dependencies beyond `grep` (uses `grep -n -E -I`)
- Three modes: directory (recursive), single file, piped file list from stdin
  - 17 languages / formats: Python, JavaScript, TypeScript, Kotlin, Swift, Rust, Go, Java, C, C++, Ruby, Lua, PHP, Bash, Dockerfile, Makefile, YAML
- Bash function detection: both `name() {` and `function name {` forms
- Shebang fallback for extensionless files (`#!/usr/bin/env bash`)
- Symbol type filtering (`-t function`, `-t class`, etc.)
- Import removal (`--no-imports`) with precedence rule (`-t import` overrides)
- Three output formats: `pretty` (default), `paths` (file list), `json`
- Symbol and file caps (`-m`, `-n`) with truncation indicators

**Examples:**

```bash
# Map a project directory
fmap /project

# Single file analysis
fmap /project/src/auth.py

# JSON output for agents
fmap -o json /project

# Pipeline: find Python files, extract structure
fsearch -o paths '*.py' /project | fmap -o json

# Functions only, no imports
fmap -t function --no-imports /project

# Force language detection
fmap -L bash /project/scripts/deploy

# Cap symbols for large projects
fmap -m 100 /project
```

### `fread` &mdash; budgeted file reading

Reads **just enough file content** for the next step in an investigation. It fills the gap after `fsearch`/`fmap`: once you know which file matters, `fread` lets you read a range, read around a line or literal pattern, cap by lines/bytes/tokens, or feed it paths/diffs from stdin.

```bash
fread [OPTIONS] <file>
```

**Key features:**

- Range reads (`-r 120:220`), head/tail, and context windows around a line or literal pattern
- Budget controls: `--max-lines`, `--max-bytes`, `--token-budget`
- Stdin modes:
  - `--stdin-format=paths` for `fsearch -> fread`
  - `--stdin-format=unified-diff` for `git diff -> fread`
- Binary detection with `--force-text` escape hatch
- `next_hint` output on truncation so agents can continue exactly where they stopped
- Three output formats: `pretty` (default), `paths`, `json`

**Examples:**

```bash
# Read a bounded file excerpt
fread /project/src/auth.py --head 80

# Read a precise range
fread /project/src/auth.py -r 120:220

# Read around a literal pattern
fread /project/src/auth.py --around "def authenticate" -B 5 -A 20

# Read around a changed hunk from git diff
git diff | fread --from-stdin --stdin-format=unified-diff -B 3 -A 10

# Pipe file paths from fsearch and cap how many get read
fsearch -o paths '*.py' /project | fread --from-stdin --stdin-format=paths --max-files 5 -o json
```

### `fedit` &mdash; surgical patching

Applies **preview-first text patches** after you have already narrowed the target with `fsearch`, `fread`, and `fmap`. It defaults to dry-run, emits a unified diff, and only mutates the file when `--apply` is present.

```bash
fedit [OPTIONS] <file>
```

**Key features:**

- Dry-run by default; `--apply` is required to write
- Exact replacement plus `--after` / `--before` anchor insertion
- Preconditions with `--expect` and `--expect-sha256`
- `--symbol` / `--symbol-type` scope a patch to one `fmap`-resolved symbol block
- Three output formats: `pretty` (default), `paths`, `json`

**Examples:**

```bash
# Preview a direct replacement
fedit /project/src/auth.py --replace 'return False' --with 'return deny()'

# Apply the replacement only inside one symbol
fedit /project/src/auth.py --symbol authenticate --symbol-type function \
  --replace 'return False' --with 'return deny()' --apply

# Insert after an anchor
fedit /project/src/auth.py --after 'def authenticate(user):' \
  --content-file patch.txt --apply
```

### `fmetrics` &mdash; telemetry analytics

Closes the loop after reconnaissance. `fmetrics` ingests local telemetry, shows dashboards and history, and predicts how long scans will take on a target before you launch them.

```bash
fmetrics <subcommand> [options]
```

**Key features:**

- `import` moves JSONL telemetry into SQLite
- `stats` shows usage, runtime, and reliability summaries
- `history` filters by tool and project
- `predict` estimates runtime from historical data
- `profile` exposes the Tier 3 machine profile

**Examples:**

```bash
# Import telemetry for analysis
fmetrics import

# See runtime and reliability dashboard
fmetrics stats

# Review recent ftree runs
fmetrics history --tool ftree --limit 10

# Estimate scan time before a large recon
fmetrics predict /project
```

---

## Output Formats

The six operational tools (`fsearch`, `fcontent`, `ftree`, `fmap`, `fread`, `fedit`) support three output modes via `--output` / `-o`:

| Mode | Description | Best for |
|------|-------------|----------|
| `pretty` | Human-readable header + formatted list | Terminal use, debugging |
| `paths` | One file path per line, no decoration | Piping, shell scripts |
| `json` | Compact JSON object with metadata | AI agents, tool integrations |

### JSON schema (`fsearch`)

```json
{
  "tool": "fsearch",
  "version": "2.0.0",
  "pattern": "*token*",
  "name_glob": "*token*",
  "path": "/home/user",
  "backend": "fd",
  "total_found": 12,
  "shown": 12,
  "results": ["/home/user/.config/token.json", "..."]
}
```

### JSON schema (`fcontent`)

```json
{
  "tool": "fcontent",
  "version": "2.0.0",
  "query": "ERROR",
  "mode": "directory",
  "path": "/var/log",
  "total_matched_files": 3,
  "shown_matches": 47,
  "matches": ["file.log:12:ERROR something failed", "..."],
  "matched_files": ["file.log", "..."]
}
```

### JSON schema (`ftree` — tree mode)

```json
{
  "tool": "ftree",
  "version": "2.0.0",
  "mode": "tree",
  "backend": "tree",
  "path": "/project",
  "depth": 3,
  "filelimit": 80,
  "ignored": "node_modules|.git|venv|...",
  "total_dirs": 12,
  "total_files": 47,
  "total_lines": 89,
  "shown_lines": 89,
  "truncated": false,
  "tree_json": [ "... native tree -J output ..." ]
}
```

### JSON schema (`ftree` — recon mode)

```json
{
  "tool": "ftree",
  "version": "2.0.0",
  "mode": "recon",
  "backend": "find/du/stat",
  "path": "/project",
  "recon_depth": 1,
  "total_entries": 8,
  "visible": 5,
  "excluded": 3,
  "entries": [
    {"name": "src", "type": "directory", "items_total": 234, "size_bytes": 1258291, "size_human": "1.2M", "excluded": false},
    {"name": "package.json", "type": "file", "size_bytes": 2355, "size_human": "2.3K", "excluded": false},
    {"name": "node_modules", "type": "directory", "items_total": 1847, "size_bytes": -1, "size_human": "?", "reason": "excluded", "excluded": true}
  ]
}
```

### JSON schema (`fmap`)

```json
{
  "tool": "fmap",
  "version": "2.0.0",
  "mode": "single_file",
  "path": "/project/src/auth.py",
  "total_files_scanned": 1,
  "total_files_with_symbols": 1,
  "total_symbols": 12,
  "shown_symbols": 12,
  "truncated": false,
  "languages": {"python": 1},
  "files": [
    {
      "path": "auth.py",
      "language": "python",
      "symbol_count": 12,
      "symbols": [
        {"line": 14, "type": "function", "indent": 0, "text": "def authenticate(user, token):"},
        {"line": 47, "type": "class", "indent": 0, "text": "class AuthError(Exception):"}
      ]
    }
  ]
}
```

### JSON schema (`fread`)

```json
{
  "tool": "fread",
  "version": "2.0.0",
  "mode": "around",
  "truncated": false,
  "truncation_reason": "none",
  "token_estimate": 148,
  "token_estimator": "bytes_div_3_conservative",
  "bytes_emitted": 444,
  "lines_emitted": 18,
  "max_lines": 200,
  "max_bytes": 50000,
  "token_budget": 0,
  "next_hint": null,
  "chunks": [
    {
      "path": "/project/src/auth.py",
      "start_line": 120,
      "end_line": 137,
      "match_line": 125,
      "content": ["120  ...", "125  def authenticate(user, token):", "137  ..."]
    }
  ],
  "files": [
    {
      "path": "/project/src/auth.py",
      "language": "python",
      "binary": false,
      "binary_state": "false",
      "file_size_bytes": 8124,
      "file_total_lines": 244,
      "status": "read"
    }
  ],
  "warnings": [],
  "errors": []
}
```

### JSON schema (`fmetrics stats`)

```json
{
  "tool": "fmetrics",
  "version": "2.0.0",
  "subcommand": "stats",
  "total_runs": 24,
  "db_path": "/home/user/.fsuite/telemetry.db",
  "db_size_bytes": 28672,
  "oldest_run": "2026-03-08T20:20:13Z",
  "newest_run": "2026-03-08T20:20:14Z",
  "tools": [
    {"name": "ftree", "runs": 8, "avg_ms": 6, "min_ms": 6, "max_ms": 7, "success_rate": 100.0}
  ],
  "top_projects": [
    {"name": "myproject", "runs": 12}
  ]
}
```

---

## Agent / Headless Usage

These tools are designed to be called programmatically by AI agents, automation scripts, or CI pipelines.

**Recommended drill-down workflow for agents:**

```bash
# Step 1: Scout — what's in this project?
ftree --recon -o json /project
# → per-dir item counts and sizes, agent picks targets programmatically

# Step 2: Structure — show me the tree
ftree /project
# → depth-3 tree, 200-line cap, noise excluded

# Step 3: Zoom — drill into interesting part
ftree -L 5 /project/src
# → deeper view of just src/

# Step 4: Find candidate files (deterministic, structured)
fsearch --output json '*.py' /project

# Step 5: Map code structure (structural skeleton)
fsearch --output paths '*.py' /project | fmap --output json
# → functions, classes, imports for each file

# Step 6: Search inside candidates (structured results)
fsearch --output paths '*.py' /project | fcontent --output json "import torch"

# Step 7: Read the exact code neighborhood
fread --output json /project/src/auth.py --around "def authenticate" -B 5 -A 20

# Step 8: Measure and plan the next pass
fmetrics import && fmetrics stats -o json
```

**The full pipeline:**

```text
ftree --snapshot → fsearch -o paths → fmap -o json → fread -o json → fcontent -o json → fmetrics
Scout            → Find              → Map          → Read          → Search            → Measure
```

**Why this matters:**

- `--output json` gives structured data an agent can parse without regex
- `--output paths` produces clean line-delimited output for piping
- No interactive prompts in headless mode (prompts only trigger when pattern is missing)
- Exit codes follow convention: `0` = success, `2` = usage error, `3` = missing dependency
- Errors go to stderr, results go to stdout

---

## Cheat Sheet

Copy-paste ready. Every command runs headless (no prompts, no TTY needed) unless marked **Interactive**.

### `fsearch` — Find Files by Name

| Command | What it does |
|---------|-------------|
| `fsearch '*.log' /var/log` | Find all `.log` files under `/var/log` (pretty output) |
| `fsearch log /var/log` | Same thing — bare word `log` auto-expands to `*.log` |
| `fsearch .log /var/log` | Same thing — dotted `.log` also auto-expands to `*.log` |
| `fsearch 'upscale*' /home/user` | Files whose names start with `upscale` |
| `fsearch '*progress*' /home/user` | Files containing `progress` anywhere in the name |
| `fsearch '*error' /var/log` | Files whose names end with `error` |
| `fsearch '*.??' /tmp` | Files with two-character extensions (`*.js`, `*.py`, etc.) |
| `fsearch --output paths '*.py' /project` | One path per line, no header — ideal for piping |
| `fsearch --output json '*.conf' /etc` | Structured JSON with `total_found`, `results[]`, `backend` |
| `fsearch --include 'src' --exclude '*test*' '*.py' /project` | Find `.py` files only under source paths, skipping tests |
| `fsearch --exclude 'node_modules' --exclude '.git' '*.log' /repo` | Scan logs while skipping noisy directories |
| `fsearch --max 10 '*.py' /project` | Limit pretty output to first 10 results |
| `fsearch --backend fd '*.rs' /src` | Force `fd` backend (faster, if installed) |
| `fsearch --backend find '*.c' /src` | Force POSIX `find` backend |
| `fsearch --self-check` | Show which backends are available |
| `fsearch --install-hints` | Print install commands for `fd` and `rg` |
| `fsearch --version` | Print version |
| `fsearch --project-name "MyApp" '*.py' /project` | Override project name in telemetry |
| `fsearch -q '*.py' /project` | Quiet mode — exit code only, no output |
| `fsearch -i` | **Interactive** — prompts for pattern and path |

### `fcontent` — Search Inside Files

| Command | What it does |
|---------|-------------|
| `fcontent "ERROR" /var/log` | Search for `ERROR` inside all files under `/var/log` |
| `fcontent "TODO" /project` | Find every `TODO` in a project tree |
| `fcontent --output paths "ERROR" /var/log` | Print only the file paths that matched (one per line) |
| `fcontent --output json "ERROR" /var/log` | Structured JSON with `matches[]`, `matched_files[]`, counts |
| `fcontent -m 20 "debug" /project` | Cap output to 20 match lines |
| `fcontent -n 50 "debug" /project` | Cap to 50 files searched |
| `fcontent --rg-args "-i" "error" /var/log` | Case-insensitive search |
| `fcontent --rg-args "--hidden" "secret" ~` | Include hidden/dotfiles in search |
| `fcontent --rg-args "-i --hidden" "token" ~` | Case-insensitive + hidden files |
| `fcontent --rg-args "-w" "main" /project` | Whole-word match only |
| `fcontent --self-check` | Verify `rg` is installed |
| `fcontent --install-hints` | Print install command for `rg` |
| `fcontent --version` | Print version |
| `fcontent --project-name "MyApp" "TODO" /project` | Override project name in telemetry |
| `fcontent -q "TODO" /project` | Quiet mode — exit code only (0=found, 1=not found) |

### `ftree` — Visualize Directory Structure

| Command | What it does |
|---------|-------------|
| `ftree /project` | Tree view, depth 3, default excludes, 200-line cap |
| `ftree --recon /project` | Recon: per-dir item counts and sizes |
| `ftree -L5 /project/src` | Deeper tree (depth 5) of a subdirectory |
| `ftree -o json /project` | Structured JSON tree with metadata envelope |
| `ftree -o paths /project` | Flat file list, one per line |
| `ftree --recon -o json /project` | Recon JSON: agent-parseable per-dir inventory |
| `ftree --snapshot /project` | Snapshot: recon inventory + tree excerpt in one output |
| `ftree --snapshot -o json /project` | Snapshot JSON: combined recon + tree for agents |
| `ftree --recon --hide-excluded /project` | Clean recon, no excluded-dir summaries |
| `ftree --include .git /project` | Show `.git` even though it's in the default ignore list |
| `ftree -I 'docs\|*.md' /project` | Exclude additional patterns (appended to defaults) |
| `ftree -I 'docs' -I '*.md' /project` | Same — multiple `-I` flags accumulate (v1.0.1+) |
| `ftree --no-default-ignore /project` | Disable built-in ignore list entirely |
| `ftree -d /project` | Directories only |
| `ftree -s /project` | Show file/dir sizes |
| `ftree -f /project` | Full absolute paths |
| `ftree -m50 /project` | Cap pretty output at 50 lines (combined flag) |
| `ftree -m 0 /project` | Unlimited lines (may be large!) |
| `ftree --gitignore /project` | Also honor `.gitignore` rules (if tree supports it) |
| `ftree --self-check` | Verify tree is installed, check `--gitignore` support |
| `ftree --install-hints` | Print install command for tree |
| `ftree --version` | Print version |
| `ftree --snapshot --no-lines -o json /project` | Snapshot JSON without tree.lines array |
| `ftree --project-name "MyApp" /project` | Override project name in telemetry |
| `ftree -q /project` | Quiet mode — exit code only |

### `fmap` — Extract Code Structure

| Command | What it does |
|---------|-------------|
| `fmap /project` | Map all source files under `/project` (pretty output) |
| `fmap /project/src/auth.py` | Map a single file |
| `fmap -o json /project` | JSON output with symbol metadata |
| `fmap -o paths /project` | File paths that contain symbols |
| `fmap -t function /project` | Show only function definitions |
| `fmap -t class /project` | Show only class definitions |
| `fmap --no-imports /project` | Skip import lines |
| `fmap -t import --no-imports /project` | Precedence: `-t import` overrides `--no-imports` |
| `fmap -L bash /project/scripts` | Force language to Bash |
| `fmap -m 50 /project` | Cap shown symbols to 50 |
| `fmap -n 100 /project` | Cap files processed to 100 |
| `fmap --no-default-ignore /project` | Include node_modules etc. |
| `fmap --self-check` | Verify grep is available |
| `fmap --version` | Print version |
| `fmap -q /project` | Quiet mode — no header |
| `fsearch -o paths '*.py' /project \| fmap -o json` | Pipeline: find then map |

### `fread` — Read Just Enough Context

| Command | What it does |
|---------|-------------|
| `fread /project/src/auth.py` | Read a file with default caps |
| `fread /project/src/auth.py -r 120:220` | Read a precise inclusive line range |
| `fread /project/src/auth.py --head 50` | Read the first 50 lines |
| `fread /project/src/auth.py --tail 40` | Read the last 40 lines |
| `fread /project/src/auth.py --around-line 150 -B 5 -A 15` | Read context around line 150 |
| `fread /project/src/auth.py --around "def authenticate" -B 5 -A 20` | Read around the first literal pattern match |
| `fread /project/src/auth.py --all-matches --around "TODO"` | Read around every match until caps are hit |
| `fread /project/src/auth.py --max-lines 80 --max-bytes 12000` | Enforce hard output budgets |
| `fread /project/src/auth.py --token-budget 2000 -o json` | Cap by estimated token cost |
| `fsearch -o paths '*.py' /project \| fread --from-stdin --stdin-format=paths --max-files 5` | Read the first 5 files from a pipeline |
| `git diff \| fread --from-stdin --stdin-format=unified-diff -B 3 -A 10` | Read context around changed hunks |
| `fread --self-check` | Verify dependencies (`sed`, `awk`, `grep`, `wc`, `od`, `perl`) |
| `fread --version` | Print version |

### `fedit` — Apply Surgical Patches

| Command | What it does |
|---------|-------------|
| `fedit /project/src/auth.py --replace 'old' --with 'new'` | Preview an exact replacement |
| `fedit /project/src/auth.py --replace 'old' --with 'new' --apply` | Apply the exact replacement |
| `fedit /project/src/auth.py --after 'def authenticate(user):' --content-file patch.txt` | Preview an insertion after an anchor |
| `fedit /project/src/auth.py --before 'return True' --stdin --apply` | Insert payload from stdin before an anchor |
| `fedit /project/src/auth.py --symbol authenticate --replace 'return False' --with 'return deny()'` | Scope the patch to one `fmap`-resolved symbol |
| `fedit /project/src/auth.py --function authenticate --replace 'return False' --with 'return deny()'` | Scope to a function without spelling `--symbol-type` |
| `fedit /project/src/auth.py --class AuthHandler --after 'self.ready = False' --with $'\n        self.ready = True'` | Target one class block with shortcut syntax |
| `printf '/project/a.py\n/project/b.py\n' \| fedit --targets-file - --targets-format paths --replace 'x = 1' --with 'x = 2'` | Preview a preflighted batch patch from stdin targets |
| `fedit --targets-file map.json --targets-format fmap-json --function authenticate --replace 'return False' --with 'return deny()' --apply` | Apply one symbol-scoped edit across `fmap` JSON targets |
| `fedit /project/src/auth.py --expect 'def authenticate' --replace 'old' --with 'new'` | Require expected text before patching |
| `fedit /project/src/auth.py --expect-sha256 HASH --replace 'old' --with 'new' --apply` | Guard the write with a content hash |
| `fedit --create /project/src/new_file.py --content-file body.txt --apply` | Create a new file from payload |
| `fedit --replace-file /project/src/auth.py --content-file rewrite.txt --apply` | Replace an entire file from payload |
| `fedit --self-check` | Verify perl, diff, mktemp, and SHA tooling |
| `fedit --version` | Print version |

### `fmetrics` — Analyze and Predict

| Command | What it does |
|---------|-------------|
| `fmetrics import` | Import `telemetry.jsonl` into SQLite |
| `fmetrics stats` | Show aggregate runtime and reliability dashboard |
| `fmetrics stats -o json` | Machine-readable stats for automation |
| `fmetrics history --tool ftree --limit 10` | Show recent runs for one tool |
| `fmetrics history --project MyApp` | Filter telemetry by project name |
| `fmetrics predict /project` | Estimate runtimes for the target path |
| `fmetrics predict --tool ftree /project` | Estimate a single tool only |
| `fmetrics profile` | Show Tier 3 machine profile |
| `fmetrics clean --days 30` | Prune old telemetry |
| `fmetrics --self-check` | Verify sqlite3, python3, and predict helper availability |

### Pipeline — Find Then Grep (the power move)

| Command | What it does |
|---------|-------------|
| `fsearch -o paths '*.log' /var/log \| fcontent "ERROR"` | Find logs, then search inside them for `ERROR` |
| `fsearch -o paths '*.py' /project \| fcontent "import torch"` | Which Python files import torch? |
| `fsearch -o paths '*.env' /home \| fcontent "API_KEY"` | Find `.env` files that mention `API_KEY` |
| `fsearch -o paths '*.yml' /etc \| fcontent "password"` | Audit YAML configs for hardcoded passwords |
| `fsearch -o paths '*.sh' /opt \| fcontent "rm -rf"` | Find shell scripts with dangerous deletes |
| `fsearch -o paths '*.js' /app \| fcontent "eval("` | Find JS files using `eval()` |
| `fsearch -o paths '*.py' /app \| fcontent --output json "def "` | JSON list of every function definition across all Python files |
| `fsearch -o paths '*.log' /var/log \| fcontent --output paths "CRITICAL"` | Just file paths of logs containing `CRITICAL` |
| `fsearch -o paths '*.conf' /etc \| fcontent --output json "listen"` | JSON: which config files have `listen` directives? |
| `fsearch -o paths '*.py' /project \| fread --from-stdin --stdin-format=paths --max-files 5 -o json` | Read bounded context from the first few matching files |

### Headless / Agent Workflows

These are designed for AI agents, CI pipelines, cron jobs, and automation scripts. No TTY, no prompts, deterministic output.

| Workflow | Commands | Why |
|----------|----------|-----|
| **One-shot context** | `ftree --snapshot -o json /project` | Agent gets recon + tree in one call (v1.2.0+) |
| **Scout a project** | `ftree --recon -o json /project` | Agent gets per-dir item counts, sizes, and exclusion tags |
| **Structure overview** | `ftree -o json /project` | Agent gets depth-3 tree with truncation metadata |
| **Drill into subdirectory** | `ftree -L 5 -o json /project/src` | Agent zooms into a specific subtree |
| **Inventory a project** | `fsearch -o json '*.py' /project` | Agent gets structured file list with count |
| **Map code structure** | `fmap -o json /project` | Agent gets functions, classes, imports per file |
| **Map specific files** | `fsearch -o paths '*.py' /project \| fmap -o json` | Pipeline: find then map structure |
| **Read targeted context** | `fread -o json /project/src/auth.py --around "def authenticate" -A 20` | Agent reads one function neighborhood without flooding context |
| **Preview a patch** | `fedit -o json /project/src/auth.py --symbol authenticate --replace "return False" --with "return deny()"` | Agent gets a structured diff before changing code |
| **Apply a patch** | `fedit -o json /project/src/auth.py --symbol authenticate --replace "return False" --with "return deny()" --apply` | Agent mutates only after it has inspected the diff |
| **Shortcut-scoped patch** | `fedit -o json /project/src/auth.py --function authenticate --replace "return False" --with "return deny()"` | Agent targets one function directly from the CLI |
| **Batch patch preview** | `printf 'a.py\nb.py\n' \| fedit -o json --targets-file - --targets-format paths --replace "x = 1" --with "x = 2"` | Agent previews a multi-file batch before writing |
| **Batch symbol patch** | `fedit -o json --targets-file map.json --targets-format fmap-json --function authenticate --replace "return False" --with "return deny()" --apply` | Agent applies one symbol-scoped patch across mapped files |
| **Read changed code** | `git diff \| fread --from-stdin --stdin-format=unified-diff -o json` | Agent turns a patch into contextual file reads |
| **Budgeted follow-up reads** | `fsearch -o paths '*.py' /project \| fread --from-stdin --stdin-format=paths --max-files 5 --token-budget 2000 -o json` | Agent keeps reading within a controlled context budget |
| **Functions only** | `fmap -t function -o json /project` | Agent gets only function definitions |
| **Find + grep in one shot** | `fsearch -o paths '*.py' /project \| fcontent -o json "import"` | Agent gets structured match data in one pipeline |
| **Predict before scanning** | `fmetrics predict /project` | Agent estimates cost before launching recon on a large target |
| **Count log files** | `fsearch -o json '*.log' /var/log \| jq .total_found` | Pull a single integer from JSON |
| **List matched files only** | `fsearch -o paths '*.cfg' /etc \| fcontent -o paths "deprecated"` | Clean file list, no noise, one per line |
| **Feed files to another tool** | `fsearch -o paths '*.py' /src \| xargs wc -l` | Line count of every Python file found |
| **Triage error logs** | `fsearch -o paths '*.log' /var/log \| fcontent -o json "FATAL"` | Agent parses `total_matched_files` to decide severity |
| **Security sweep** | `fsearch -o paths '*.env' / \| fcontent -o paths "SECRET"` | Find exposed secrets across the whole filesystem |
| **Dependency audit** | `fsearch -o paths 'requirements*.txt' /home \| fcontent "requests=="` | Which projects pin the `requests` library? |
| **Config drift check** | `fsearch -o paths '*.conf' /etc \| fcontent -o json "PermitRootLogin"` | Agent checks SSH config state across hosts |
| **Pre-deploy scan** | `fsearch -o paths '*.js' /app \| fcontent -o paths "console.log"` | Find leftover debug statements before shipping |
| **Dead code detection** | `fsearch -o paths '*.py' /src \| fcontent -o json "def unused_"` | Agent flags functions prefixed `unused_` |
| **Batch rename prep** | `fsearch -o paths '*_old*' /project` | List all `_old` files an agent should rename or delete |
| **Monitor new files** | `fsearch -o json '*.tmp' /var/tmp` | Agent checks `total_found` periodically to track tmp growth |
| **Multi-stage pipeline** | `fsearch -o paths '*.py' /src \| fcontent -o paths "class " \| xargs head -5` | Find Python files with classes, show first 5 lines of each |
| **Existence check** | `fsearch -q '*.lock' /project && echo "found"` | Quiet mode — check if lockfiles exist (exit code only) |
| **Grep check** | `fcontent -q "FIXME" /src \|\| echo "clean"` | Quiet mode — check if FIXME exists in codebase |

### Interactive / Human Shortcuts

| Command | What it does |
|---------|-------------|
| `fsearch -i` | Prompts for pattern and path interactively |
| `fsearch '*.log'` | Searches current directory (no path needed) |
| `fcontent "TODO"` | Searches current directory for `TODO` |
| `fsearch '*test*' .` | Find test files from here |
| `fcontent "FIXME" .` | Find `FIXME` comments from here |
| `fsearch '*.py' . \| less` | Page through results |
| `fcontent "error" /var/log 2>/dev/null` | Suppress permission warnings |
| `sudo fcontent "error" /var/log` | Search protected dirs (authenticate first with `sudo -v`) |

### Quick Reference — Flags

**`fsearch`**

| Flag | Short | Values | Default |
|------|-------|--------|---------|
| `--output` | `-o` | `pretty`, `paths`, `json` | `pretty` |
| `--backend` | `-b` | `auto`, `find`, `fd` | `auto` |
| `--max` | `-m` | any integer | `50` |
| `--include` | `-I` | any pattern (repeatable) | — |
| `--exclude` | `-x` | any pattern (repeatable) | — |
| `--quiet` | `-q` | — | off |
| `--project-name` | — | any string | auto-detected |
| `--interactive` | `-i` | — | off |
| `--self-check` | — | — | — |
| `--install-hints` | — | — | — |

> **Tip:** Numeric flags support combined syntax: `-m50` is equivalent to `-m 50`.

**`fcontent`**

| Flag | Short | Values | Default |
|------|-------|--------|---------|
| `--output` | `-o` | `pretty`, `paths`, `json` | `pretty` |
| `--max-matches` | `-m` | any integer | `200` |
| `--max-files` | `-n` | any integer | `2000` |
| `--quiet` | `-q` | — | off |
| `--project-name` | — | any string | auto-detected |
| `--rg-args` | — | quoted string of rg flags | none |
| `--self-check` | — | — | — |
| `--install-hints` | — | — | — |

> **Tip:** Numeric flags support combined syntax: `-m50` is equivalent to `-m 50`.

**`ftree`**

| Flag | Short | Values | Default |
|------|-------|--------|---------|
| `--output` | `-o` | `pretty`, `paths`, `json` | `pretty` |
| `--depth` | `-L` | any integer | `3` |
| `--max-lines` | `-m` | any integer (0 = unlimited) | `200` |
| `--filelimit` | `-F` | any integer | `80` |
| `--ignore` | `-I` | pipe-separated pattern | built-in list |
| `--no-default-ignore` | — | — | off |
| `--include` | — | pattern (repeatable) | — |
| `--recon` | `-r` | — | off |
| `--snapshot` | — | — | off |
| `--budget` | — | seconds (integer) | `30` |
| `--no-lines` | — | — | off |
| `--project-name` | — | any string | auto-detected |
| `--recon-depth` | — | any integer | `1` (`2` in snapshot) |
| `--hide-excluded` | — | — | off |
| `--dirs-only` | `-d` | — | off |
| `--sizes` | `-s` | — | off |
| `--quiet` | `-q` | — | off |
| `--gitignore` | — | — | off |
| `--full-paths` | `-f` | — | off |
| `--self-check` | — | — | — |
| `--install-hints` | — | — | — |

> **Tip:** Numeric flags support combined syntax: `-L5` is equivalent to `-L 5`.

**`fmap`**

| Flag | Short | Values | Default |
|------|-------|--------|---------|
| `--output` | `-o` | `pretty`, `paths`, `json` | `pretty` |
| `--max-symbols` | `-m` | any integer | `500` |
| `--max-files` | `-n` | any integer | `500` (dir) / `2000` (stdin) |
| `--lang` | `-L` | language name | auto-detect |
| `--type` | `-t` | `function`, `class`, `import`, `type`, `export`, `constant` | all |
| `--no-imports` | — | — | off |
| `--no-default-ignore` | — | — | off |
| `--quiet` | `-q` | — | off |
| `--project-name` | — | any string | auto-detected |
| `--self-check` | — | — | — |
| `--install-hints` | — | — | — |

> **Tip:** Numeric flags support combined syntax: `-m50` is equivalent to `-m 50`.

**`fedit`**

| Flag | Short | Values | Default |
|------|-------|--------|---------|
| `--output` | `-o` | `pretty`, `paths`, `json` | `pretty` |
| `--replace` | — | exact text block | — |
| `--with` | — | payload text | — |
| `--after` | — | exact anchor text | — |
| `--before` | — | exact anchor text | — |
| `--content-file` | — | readable file path | — |
| `--stdin` | — | — | off |
| `--expect` | — | exact text block | — |
| `--expect-sha256` | — | SHA-256 hex digest | — |
| `--symbol` | — | symbol name | — |
| `--symbol-type` | — | `function`, `class`, `import`, `type`, `export`, `constant` | any |
| `--function` | — | function name | — |
| `--class` | — | class name | — |
| `--method` | — | method/function name | — |
| `--import` | — | import text | — |
| `--constant` | — | constant name | — |
| `--type` | — | type name | — |
| `--fmap-json` | — | path to prior `fmap -o json` output | auto-run `fmap` |
| `--targets-file` | — | path list file or `-` for stdin | — |
| `--targets-format` | — | `paths`, `fmap-json` | — |
| `--allow-multiple` | — | — | off |
| `--apply` | — | — | off |
| `--dry-run` | — | — | on |
| `--create` | — | — | off |
| `--replace-file` | — | — | off |
| `--project-name` | — | any string | auto-detected |
| `--self-check` | — | — | — |
| `--install-hints` | — | — | — |

**`fread`**

| Flag | Short | Values | Default |
|------|-------|--------|---------|
| `--output` | `-o` | `pretty`, `paths`, `json` | `pretty` |
| `--lines` | `-r` | `START:END` | — |
| `--head` | — | any integer | — |
| `--tail` | — | any integer | — |
| `--around-line` | — | any integer | — |
| `--around` | — | literal pattern | — |
| `--all-matches` | — | — | off |
| `--before` | `-B` | any integer | `5` |
| `--after` | `-A` | any integer | `10` |
| `--max-lines` | — | any integer | `200` |
| `--max-bytes` | — | any integer | `50000` |
| `--token-budget` | — | any integer | off |
| `--max-files` | — | any integer | `10` |
| `--from-stdin` | — | — | off |
| `--stdin-format` | — | `paths`, `unified-diff` | required with `--from-stdin` |
| `--force-text` | — | — | off |
| `--quiet` | `-q` | — | off |
| `--project-name` | — | any string | auto-detected |
| `--self-check` | — | — | — |
| `--install-hints` | — | — | — |

> **Tip:** `fread` truncation reports a `next_hint` so agents can continue from the last emitted line without recalculating offsets.

**`fmetrics`**

| Subcommand | Key Flags | Description |
|------------|-----------|-------------|
| `import` | — | Ingest `telemetry.jsonl` into SQLite |
| `stats` | `-o json` | Usage dashboard (runtimes, reliability) |
| `history` | `--tool <name>`, `--limit N` (default 20), `--project <name>` | Recent runs, filterable |
| `predict <path>` | `--tool <name>` | Estimate runtime for a directory |
| `clean` | `--days N` (default 90), `--dry-run` | Prune old telemetry |
| `profile` | — | Show machine profile (Tier 3) |

| Flag | Values | Default |
|------|--------|---------|
| `--output` / `-o` | `pretty`, `json` | `pretty` |
| `--self-check` | — | — |
| `--install-hints` | — | — |

---

## Optional Dependencies

| Tool | Purpose | Install (Debian/Ubuntu) |
|------|---------|------------------------|
| `tree` | **Required** by `ftree` (tree mode) | `sudo apt install tree` |
| `fd` / `fdfind` | Faster filename search backend | `sudo apt install fd-find` |
| `rg` (ripgrep) | **Required** by `fcontent` | `sudo apt install ripgrep` |
| `perl` | **Required** by `fread` for JSON escaping and portable timing fallback | `sudo apt install perl` |
| `sqlite3` | Required by `fmetrics import/stats/history/clean` | `sudo apt install sqlite3` |

All tools include built-in guidance:

```bash
fsearch --self-check       # Check what's available
fsearch --install-hints    # Print install commands
fcontent --self-check
fcontent --install-hints
ftree --self-check         # Verify tree + gitignore support
ftree --install-hints      # Print install command for tree
fmap --self-check          # Verify grep is available
fmap --install-hints       # Print install command for grep
fread --self-check         # Verify sed/awk/grep/wc/od/perl
fread --install-hints      # Print install commands for core deps
fmetrics --self-check      # Verify sqlite3 + python3 helper chain
fmetrics --install-hints
```

---

## Telemetry

fsuite collects anonymous performance telemetry to help predict operation times and identify bottlenecks. **All data stays local** — nothing is transmitted anywhere.

### Telemetry Tiers

Control telemetry via the `FSUITE_TELEMETRY` environment variable:

| Tier | Description | Data Collected |
|------|-------------|----------------|
| `0` | Disabled | None |
| `1` | Basic (default) | Duration, items scanned, bytes scanned, exit code |
| `2` | Hardware | Tier 1 + CPU temp, disk temp, RAM usage, load average, filesystem type, storage type |
| `3` | Full | Tier 2 + machine profile (CPU model, cores, total RAM) |

**Tier 2 fields:**
- `filesystem_type`: ext4, ntfs, exfat, apfs, nfs, cifs, tmpfs, etc.
- `storage_type`: ssd, hdd, nvme, network, removable, tmpfs, etc.

### Examples

```bash
# Disable telemetry
FSUITE_TELEMETRY=0 ftree /project

# Enable hardware metrics
FSUITE_TELEMETRY=2 fcontent "TODO" /project

# Full telemetry with machine profile
FSUITE_TELEMETRY=3 fsearch "*.py" /project
```

### Data Storage

- **Telemetry log**: `~/.fsuite/telemetry.jsonl` (append-only JSONL)
- **SQLite database**: `~/.fsuite/telemetry.db` (after `fmetrics import`)
- **Machine profile**: `~/.fsuite/machine_profile.json` (Tier 3 only, regenerated daily)

### Using Telemetry

The `fmetrics` tool provides analytics on your telemetry data:

```bash
# Import telemetry into SQLite for analysis
fmetrics import

# View usage statistics
fmetrics stats

# View recent runs
fmetrics history --tool ftree --limit 10

# Predict runtime for a directory
fmetrics predict /project

# Predict for a specific tool only
fmetrics predict --tool ftree /project

# View machine profile
fmetrics profile

# Clean old data (keep last 30 days)
fmetrics clean --days 30
```

### Privacy

- **All data is local** — nothing is sent to any server
- **Paths are hashed** — the actual path `/home/user/secret-project` is stored as a 16-character SHA256 prefix
- **No file contents** — only metadata (counts, sizes, durations)
- **Easy to disable** — set `FSUITE_TELEMETRY=0` globally in your shell config

---

## Security Notes

- No tool stores passwords or credentials
- No tool writes to the filesystem or modifies files (except telemetry in `~/.fsuite/`)
- For scanning protected directories, authenticate first with `sudo -v` then run with `sudo`
- No auto-install behavior; `--install-hints` only _prints_ commands for you to run manually

---

## Installation

### Run from source

```bash
git clone https://github.com/lliWcWill/fsuite.git
cd fsuite
chmod +x install.sh
./install.sh --user
```

This installs into `~/.local/bin` and `~/.local/share/fsuite`.

### Alternate: source install with a custom prefix

```bash
./install.sh --prefix /opt/fsuite
```

### Alternate: manual symlink install

```bash
chmod +x fsearch fcontent ftree fmap fread fedit fmetrics

sudo ln -s "$(pwd)/fsearch" /usr/local/bin/fsearch
sudo ln -s "$(pwd)/fcontent" /usr/local/bin/fcontent
sudo ln -s "$(pwd)/ftree" /usr/local/bin/ftree
sudo ln -s "$(pwd)/fmap" /usr/local/bin/fmap
sudo ln -s "$(pwd)/fread" /usr/local/bin/fread
sudo ln -s "$(pwd)/fedit" /usr/local/bin/fedit
sudo ln -s "$(pwd)/fmetrics" /usr/local/bin/fmetrics
```

### Build the Debian package

```bash
sudo apt install build-essential debhelper dpkg-dev
dpkg-buildpackage -us -uc -b
ls -lh ../fsuite_*_all.deb
```

### Install the Debian package locally

```bash
sudo dpkg -i ../fsuite_*_all.deb
ftree --version
fread --version
fedit --version
fmetrics --version
```

### Agent adoption

For harnesses that read repo instructions, point them at [AGENTS.md](AGENTS.md). For everyone else, the `fsuite Help` section above is the suite-level contract and each tool's `--help` remains the detailed interface.

---

## Changelog

### v2.0.0

`fedit` grows from a single-file patch tool into a symbol-first, preflighted batch editor. This release adds the structural editing surface that turns the suite into scout-map-read-edit at project scale.

**New editing surface:**
- **`fedit`**: symbol shortcuts `--function`, `--class`, `--method`, `--import`, `--constant`, and `--type`
- **`fedit`**: preflighted batch patching via `--targets-file` with `paths` or `fmap-json` target formats
- **`fedit`**: batch JSON envelope for headless agents, including per-target status and combined diffs

**Workflow hardening:**
- **`fsearch` / `fcontent`**: default-ignore steering for dependency/build trees so agent discovery stays focused on real project files
- **Docs**: README and AGENTS guidance now frame `fcontent` as a confirmation tool and `fedit` as part of the structural edit loop
- **`fsuite`**: new suite-level guide command that prints the conceptual flow, tool roles, and headless usage contract on first contact
- **Packaging**: suite version unified at `2.0.0`, including the new `fsuite` command, helper scripts, and Debian release assets

### v1.9.0

The missing modification step is now part of the suite. `fedit` turns `fsuite` from scout-map-read-measure into scout-map-read-edit-measure, and the entire release is unified at `1.9.0`.

**New tool:**
- **`fedit`**: preview-first surgical patching with exact replace, before/after anchors, and dry-run diffs by default
- **`fedit`**: preconditions (`--expect`, `--expect-sha256`), structured JSON error output, and binary-target rejection for safe headless use
- **`fedit`**: `fmap`-driven `--symbol` / `--symbol-type` scoping so agents patch one symbol block instead of guessing with raw text alone

**Release hardening:**
- **Packaging**: Debian package and installer now install `fedit`
- **Tests**: dedicated `fedit` suite added and wired into the master runner; full suite now runs across 9 test suites
- **Docs**: README promoted from a six-tool recon kit to the seven-tool inspect/edit loop

### v1.8.0

The missing read step is now part of the suite. `fread` turns `fsuite` from scout-and-map into scout-map-read-measure, and the entire release is unified at `1.8.0`.
- **`fread`**: budgeted file reading with range, head/tail, around-line, around-pattern, stdin path mode, and unified-diff mode
- **`fread`**: token estimation, binary detection, truncation `next_hint`, and structured JSON output for agents

**Release hardening:**
- **Packaging**: Debian package now installs `fread`
- **Telemetry**: `fread` uses portable millisecond timestamp fallback for macOS/BSD as well as GNU/Linux
- **Tests**: dedicated `fread` suite added and wired into the master runner; full suite now runs across 7 test suites
- **Docs**: README promoted from a four-tool view to the full six-tool suite

### v1.7.0

Unified version bump. All tools now at 1.7.0. Seven bug fixes, new features, 281 tests.

**Bug fixes:**
- **ftree**: recon path identity at depth > 1 — positional `rel_path` replaces `basename`, JSON includes both `name` and `path` fields
- **ftree**: timeout detection fixed — structured output protocol (`value|flag`) replaces broken subshell variable propagation
- **ftree**: `total_size_bytes` preserves `-1` sentinel for unknown sizes (was coerced to `0`)
- **telemetry**: `run_id`-based dedup replaces timestamp-based `UNIQUE` constraint — burst runs no longer silently dropped
- **telemetry**: atomic DB migration with `.bail on` + `BEGIN IMMEDIATE` + rollback safety
- **fsearch**: bounded memory — `head -n` before `mapfile` + `|| true` guards under `pipefail`
- **fcontent**: `-q` exit code 1 on no match (matches documented contract)

**New features:**
- `fsearch`: `-I/--include` and `-x/--exclude` repeatable path filters with wildcard matching
- `fcontent`: path deduplication in output — first match shows full path, subsequent show basename

### v1.6.2

Production-grade path filtering for `fsearch`:

- Added `-I/--include` and `-x/--exclude` repeatable filters with wildcard-aware pattern matching.
- Added filter-aware filtering pipeline: include checks run first (OR across includes), then exclude checks remove matches (OR across excludes).
- Recorded include/exclude flags in telemetry for `fsearch`.
- Documentation updates for `fsearch` include/exclude workflows (monorepo and test-scope triage).

### v1.6.1

Hardening and review fixes for `fmap`. No new features — all changes improve robustness, safety, and correctness.

- **`.h` header heuristic**: `.h` files now dispatch to C++ when C++ constructs are detected (class, template, namespace, `std::`), otherwise fall back to C
- **Locale pinning**: `LC_ALL=C` set at script top so grep/regex character classes behave consistently across environments
- **Performance**: replaced O(n²) string concatenation in `extract_symbols` with temp file streaming
- **JSON escape**: handles `\b`, `\f`, and all control chars (U+0000–U+001F) via perl
- **Safety**: `--` before filenames in grep calls; missing-value checks on all option flags (`-o`, `-m`, `-n`, `-L`, `-t`)
- **Java regex**: access modifier now optional — captures package-private methods
- **Paths output**: respects `--max-symbols` cap (was previously uncapped)
- **Tests**: `_validate_lang_json` passes variables as argv (no shell interpolation); `run_test` reports crashes with exit code; truncated field uses canonical JSON booleans
- **Docs**: fenced code blocks annotated with language specifiers (MD040); TESTING.md language list expanded to all 12; TEST_QUICKSTART.md total updated to 259
- CodeRabbit review: **0 findings** on this release

### v1.6.0

**Introduces `fmap` — code cartography.** The fourth tool in the suite, completing the recon pipeline from "what's here" to "what's inside the code."

```text
ftree --snapshot → fsearch -o paths → fmap -o json → fcontent
Scout            → Find              → Map           → Search
```

**New tool: `fmap`**
- Extract structural skeletons (functions, classes, imports, types, exports, constants) from source files
- **12 languages**: Python, JavaScript, TypeScript, Rust, Go, Java, C, C++, Ruby, Lua, PHP, Bash/Shell
- **3 modes**: directory scan, single file, stdin pipe (`fsearch -o paths '*.py' | fmap -o json`)
- **3 output formats**: pretty, paths, JSON — same as every other fsuite tool
- **grep-only** — zero new dependencies, uses `grep -n -E -I` for extraction
- Line-level dedup prevents multi-regex overlap false positives
- Shebang detection for extensionless files (`#!/usr/bin/env bash`)
- Default ignore list matches ftree (node_modules, .git, venv, etc.)
- Filters: `-t function`, `-t class`, `--no-imports`, `-L bash`
- Caps: `-m` (max symbols), `-n` (max files)
- Telemetry integration (tool=fmap, backend=grep)

**Suite-wide changes:**
- All tools bumped to v1.6.0 (unified suite versioning)
- Debian packaging updated (fsuite_1.6.0-1_all.deb includes fmap)
- 58-test suite for fmap (per-language exact parsing for all 12 languages, dedup regression tests)
- Full test suite: 6 suites, 259 tests
- CodeRabbit review: 8 findings addressed (Go regex false positives, paths output cap, exit code handling, telemetry test isolation)

### v1.5.0

New features across all tools:

- **`duration_ms`** (ftree): JSON output now includes wall-clock milliseconds for recon, tree, and snapshot modes (snapshot also has nested recon `duration_ms`)
- **Smart project name inference** (all 3 tools): Walk-up heuristic finds `.git`, `package.json`, etc. to auto-detect the project name from any subdirectory
- **`--project-name <name>`** (all 3 tools): Override project name in telemetry records
- **`--no-lines`** (ftree): Omit the `lines` array from snapshot JSON output (only valid with `--snapshot -o json`)
- **`--tool <name>`** (fmetrics predict): Predict for a specific tool only (`ftree`, `fsearch`, `fcontent`)
- **Recon reason field** (ftree): Entries with `size_bytes: -1` now include a `reason` field (`excluded`, `budget_exceeded`, `timeout`, `stat_failed`)
- **Telemetry flag accumulation**: All flags passed to tools are now recorded in telemetry (previously only mode + output format)
- **JSONL safety**: Telemetry flags are sanitized to prevent invalid JSON in telemetry.jsonl
- **fmetrics `--self-check` enhancement**: Reports python3, predict script, and k-NN availability separately
- **fcontent stdin project inference**: When piped file paths, infers project from first file's directory (walks up to find .git, package.json, etc.)
- **Packaging fix**: `fmetrics-predict.py` installs to `/usr/share/fsuite/` with multi-path resolution

### ftree v1.2.0

New mode: `--snapshot` — combined recon + tree in one invocation.

- `--snapshot` produces a single artifact with both inventory (recon) and structure (tree)
- Pretty output: sectioned `== Recon ==` and `== Tree ==` blocks
- JSON output: envelope with embedded recon and tree objects (plus `lines` array on tree)
- Default recon depth in snapshot: 2 (standalone recon stays 1)
- Mutually exclusive with `--recon` and `-o paths`

See [docs/ftree.md](docs/ftree.md) for full JSON schema and snapshot mode details.

### ftree v1.1.0

Clear all deferred items from v1.0.1. Intentional observable output changes; JSON schema unchanged (no new fields, only value changes).

- Error/warning messages now prefixed `ftree:` (was `Error:` / `Warning:`)
- `human_size()` rounds to nearest instead of truncating (e.g. 1536 bytes → `1.5K`)
- Pretty headers and JSON `path` always use absolute path (logical, preserves symlinks)
- Drill-down path is shell-quoted (`printf %q`) for copy-paste safety
- Robust report line detection (backward scan, dual-anchor regex)
- Graceful `? directories, ? files` when count parsing fails
- Tree mode requires directory target (was: degenerate output for files)
- `--self-check` exits 3 when tree is missing (was: always 0)
- `count_items_total()` strips `wc -l` whitespace (portability)
- Removed `sort -z` from recon find pipeline (portability)
- Recon sort uses alphabetical name tiebreak for size ties (determinism)

See [docs/ftree.md](docs/ftree.md) for the full version history and JSON schema notes.

### ftree v1.0.1

Internal refactor + correctness fixes. No observable output changes except version field.
See [docs/ftree.md](docs/ftree.md) for details.

---

## License

MIT
