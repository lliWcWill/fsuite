# fsuite

<p align="center">
  <img src="docs/fsuite-hero.jpeg" alt="fsuite - Filesystem Reconnaissance Drones" width="800">
</p>

<p align="center">
  <em>Deploy the drones. Map the terrain. Return with intel.</em>
</p>

---

**A three-tool filesystem reconnaissance kit for humans and AI agents.**

`fsuite` provides three composable CLI utilities that turn filesystem exploration into a clean, scriptable, agent-friendly pipeline:

| Tool | Purpose |
|------|---------|
| **`fsearch`** | Find files by name, extension, or glob pattern |
| **`fcontent`** | Search _inside_ files for text (powered by ripgrep) |
| **`ftree`** | Visualize directory structure with smart defaults and recon mode |

Each tool does one thing. They work independently or together for a complete **scout-then-search** workflow with zero glue code.

## Contents

- [Why This Exists](#why-this-exists-the-lightbulb-moment)
- [Quick Start](#quick-start)
- [Fast Paths](#fast-paths-copypaste)
- [Tools](#tools)
  - [fsearch](#fsearch--filename--path-search)
  - [fcontent](#fcontent--file-content-search)
  - [ftree](#ftree--directory-structure-visualization)
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

**The workflow shift — before and after:**

```
BEFORE fsuite:
  Spawn Explore agent -> 10-15 internal tool calls -> still blind on structure

AFTER fsuite:
  ftree --snapshot -o json  ->  fsearch -o paths  ->  fcontent -o json
  3-4 calls. Full understanding. ~70% fewer tool invocations.
```

The full unedited analysis is in **[AGENT-ANALYSIS.md](docs/AGENT-ANALYSIS.md)** — the raw self-assessment, exactly as Claude Code wrote it after studying and testing every tool in this repo.

That document is the pitch. Not because we wrote it, but because the agent did.

---

## Quick Start

```bash
# Clone and make executable
git clone https://github.com/lliWcWill/fsuite.git
cd fsuite
chmod +x fsearch fcontent ftree

# Find all .log files under /var/log
./fsearch '*.log' /var/log

# Search inside files for "ERROR"
./fcontent "ERROR" /var/log

# Scout a project: what's here?
./ftree --recon /project

# Show the directory tree (depth 3, smart defaults)
./ftree /project

# Combine: find logs, then grep inside them
./fsearch --output paths '*.log' /var/log | ./fcontent "ERROR"
```

---

## Fast Paths (copy/paste)

Three pipelines that cover 80% of what you'll ever need. Copy, paste, go.

### 1) New repo — instant context (best default)
```bash
ftree --snapshot -o json /project | jq .
```

### 2) Find candidates — search inside them (pipeline power)
```bash
fsearch -o paths '*.ts' /project/src | fcontent -o json "Auth" | jq .
```

### 3) Triage a big project safely (no floods)
```bash
ftree --recon -o json /project | jq '.entries | sort_by(-.size_bytes) | .[:10]'
```

> **Note:** `jq` is optional — used only in these examples for pretty-printing JSON. All tools output valid JSON natively with `-o json`.

---

## Tools

### `fsearch` &mdash; filename / path search

Searches for files by **name or glob pattern**. Automatically picks the fastest available backend (`fd` > `find`).

```
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

# Interactive mode (prompts for pattern and path)
fsearch -i
```

### `fcontent` &mdash; file content search

Searches **inside** files using `rg` (ripgrep). Accepts a directory _or_ a piped list of file paths from stdin.

```
fcontent [OPTIONS] <query> [path]
```

**Key features:**

- Directory mode: recursively searches a path
- Piped mode: reads file paths from stdin (pairs with `fsearch --output paths`)
- Three output formats: `pretty` (default), `paths` (matched files only), `json`
- Configurable match and file caps to prevent terminal floods
- Pass-through for extra `rg` flags via `--rg-args`

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

```
ftree [OPTIONS] [path]
```

**Key features:**

- Smart defaults: depth 3, 200-line cap, noise directories excluded (node_modules, .git, venv, etc.)
- Recon mode: per-directory item counts and sizes without full tree expansion
- Excluded-dir summaries in recon show what's hidden and how big it is
- `--include` promotes excluded dirs back to normal treatment
- Multiple `--ignore` flags accumulate (v1.0.1+): `-I 'docs' -I '*.md'` excludes both
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

---

## Output Formats

All three tools support three output modes via `--output` / `-o`:

| Mode | Description | Best for |
|------|-------------|----------|
| `pretty` | Human-readable header + formatted list | Terminal use, debugging |
| `paths` | One file path per line, no decoration | Piping, shell scripts |
| `json` | Compact JSON object with metadata | AI agents, tool integrations |

### JSON schema (`fsearch`)

```json
{
  "tool": "fsearch",
  "version": "1.0.0",
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
  "version": "1.0.0",
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
  "version": "1.2.0",
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
  "version": "1.2.0",
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
    {"name": "node_modules", "type": "directory", "items_total": 1847, "size_bytes": 207618048, "size_human": "198M", "excluded": true}
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

# Step 5: Search inside candidates (structured results)
fsearch --output paths '*.py' /project | fcontent --output json "import torch"
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
| `fsearch --max 10 '*.py' /project` | Limit pretty output to first 10 results |
| `fsearch --backend fd '*.rs' /src` | Force `fd` backend (faster, if installed) |
| `fsearch --backend find '*.c' /src` | Force POSIX `find` backend |
| `fsearch --self-check` | Show which backends are available |
| `fsearch --install-hints` | Print install commands for `fd` and `rg` |
| `fsearch --version` | Print version |
| `fsearch -i` | **Interactive** — prompts for pattern and path |

### `fcontent` — Search Inside Files

| Command | What it does |
|---------|-------------|
| `fcontent "ERROR" /var/log` | Search for `ERROR` inside all files under `/var/log` |
| `fcontent "TODO" /project` | Find every `TODO` in a project tree |
| `fcontent --output paths "ERROR" /var/log` | Print only the file paths that matched (one per line) |
| `fcontent --output json "ERROR" /var/log` | Structured JSON with `matches[]`, `matched_files[]`, counts |
| `fcontent --max-matches 20 "debug" /project` | Cap output to 20 match lines |
| `fcontent --rg-args "-i" "error" /var/log` | Case-insensitive search |
| `fcontent --rg-args "--hidden" "secret" ~` | Include hidden/dotfiles in search |
| `fcontent --rg-args "-i --hidden" "token" ~` | Case-insensitive + hidden files |
| `fcontent --rg-args "-w" "main" /project` | Whole-word match only |
| `fcontent --self-check` | Verify `rg` is installed |
| `fcontent --install-hints` | Print install command for `rg` |
| `fcontent --version` | Print version |

### `ftree` — Visualize Directory Structure

| Command | What it does |
|---------|-------------|
| `ftree /project` | Tree view, depth 3, default excludes, 200-line cap |
| `ftree --recon /project` | Recon: per-dir item counts and sizes |
| `ftree -L 5 /project/src` | Deeper tree (depth 5) of a subdirectory |
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
| `ftree -m 50 /project` | Cap pretty output at 50 lines |
| `ftree -m 0 /project` | Unlimited lines (may be large!) |
| `ftree --gitignore /project` | Also honor `.gitignore` rules (if tree supports it) |
| `ftree --self-check` | Verify tree is installed, check `--gitignore` support |
| `ftree --install-hints` | Print install command for tree |
| `ftree --version` | Print version |

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

### Headless / Agent Workflows

These are designed for AI agents, CI pipelines, cron jobs, and automation scripts. No TTY, no prompts, deterministic output.

| Workflow | Commands | Why |
|----------|----------|-----|
| **One-shot context** | `ftree --snapshot -o json /project` | Agent gets recon + tree in one call (v1.2.0+) |
| **Scout a project** | `ftree --recon -o json /project` | Agent gets per-dir item counts, sizes, and exclusion tags |
| **Structure overview** | `ftree -o json /project` | Agent gets depth-3 tree with truncation metadata |
| **Drill into subdirectory** | `ftree -L 5 -o json /project/src` | Agent zooms into a specific subtree |
| **Inventory a project** | `fsearch -o json '*.py' /project` | Agent gets structured file list with count |
| **Find + grep in one shot** | `fsearch -o paths '*.py' /project \| fcontent -o json "import"` | Agent gets structured match data in one pipeline |
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
| `--interactive` | `-i` | — | off |
| `--self-check` | — | — | — |
| `--install-hints` | — | — | — |

**`fcontent`**

| Flag | Short | Values | Default |
|------|-------|--------|---------|
| `--output` | `-o` | `pretty`, `paths`, `json` | `pretty` |
| `--max-matches` | — | any integer | `200` |
| `--max-files` | — | any integer | `2000` |
| `--rg-args` | — | quoted string of rg flags | none |
| `--self-check` | — | — | — |
| `--install-hints` | — | — | — |

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
| `--recon-depth` | — | any integer | `1` (`2` in snapshot) |
| `--hide-excluded` | — | — | off |
| `--dirs-only` | `-d` | — | off |
| `--sizes` | `-s` | — | off |
| `--gitignore` | — | — | off |
| `--full-paths` | `-f` | — | off |
| `--self-check` | — | — | — |
| `--install-hints` | — | — | — |

---

## Optional Dependencies

| Tool | Purpose | Install (Debian/Ubuntu) |
|------|---------|------------------------|
| `tree` | **Required** by `ftree` (tree mode) | `sudo apt install tree` |
| `fd` / `fdfind` | Faster filename search backend | `sudo apt install fd-find` |
| `rg` (ripgrep) | **Required** by `fcontent` | `sudo apt install ripgrep` |

All tools include built-in guidance:

```bash
fsearch --self-check       # Check what's available
fsearch --install-hints    # Print install commands
fcontent --self-check
fcontent --install-hints
ftree --self-check         # Verify tree + gitignore support
ftree --install-hints      # Print install command for tree
```

---

## Security Notes

- No tool stores passwords or credentials
- No tool writes to the filesystem or modifies files
- For scanning protected directories, authenticate first with `sudo -v` then run with `sudo`
- No auto-install behavior; `--install-hints` only _prints_ commands for you to run manually

---

## Installation

```bash
git clone https://github.com/lliWcWill/fsuite.git
cd fsuite
chmod +x fsearch fcontent ftree

# Optional: symlink into your PATH
sudo ln -s "$(pwd)/fsearch" /usr/local/bin/fsearch
sudo ln -s "$(pwd)/fcontent" /usr/local/bin/fcontent
sudo ln -s "$(pwd)/ftree" /usr/local/bin/ftree
```

---

## Changelog

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
