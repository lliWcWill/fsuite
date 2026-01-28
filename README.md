# fsuite

**A two-tool filesystem reconnaissance kit for humans and AI agents.**

`fsuite` provides two composable CLI utilities that turn filesystem search into a clean, scriptable, agent-friendly pipeline:

| Tool | Purpose |
|------|---------|
| **`fsearch`** | Find files by name, extension, or glob pattern |
| **`fcontent`** | Search _inside_ files for text (powered by ripgrep) |

They work independently or together. Pipe the output of one into the other for a full **find-then-grep** workflow with zero glue code.

---

## Quick Start

```bash
# Clone and make executable
git clone https://github.com/lliWcWill/fsuite.git
cd fsuite
chmod +x fsearch fcontent

# Find all .log files under /var/log
./fsearch '*.log' /var/log

# Search inside files for "ERROR"
./fcontent "ERROR" /var/log

# Combine: find logs, then grep inside them
./fsearch --output paths '*.log' /var/log | ./fcontent "ERROR"
```

---

## Tools

### `fsearch` &mdash; filename / path search

Searches for files by **name or glob pattern**. Automatically picks the fastest available backend (`fd` > `find`).

```
fsearch [OPTIONS] <pattern_or_ext> [path]
```

**Key features:**

- Glob-aware: `'upscale*'`, `'*progress*'`, `'*.log'`
- Smart extension handling: passing `log` or `.log` both resolve to `*.log`
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

---

## Output Formats

Both tools support three output modes via `--output` / `-o`:

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

---

## Agent / Headless Usage

These tools are designed to be called programmatically by AI agents, automation scripts, or CI pipelines.

**Recommended workflow for agents:**

```bash
# Step 1: Find candidate files (deterministic, structured)
fsearch --output json '*.py' /project

# Step 2: Search inside candidates (structured results)
fsearch --output paths '*.py' /project | fcontent --output json "import torch"
```

**Why this matters:**

- `--output json` gives structured data an agent can parse without regex
- `--output paths` produces clean line-delimited output for piping
- No interactive prompts in headless mode (prompts only trigger when pattern is missing)
- Exit codes follow convention: `0` = success, `1` = error
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

---

## Optional Dependencies

| Tool | Purpose | Install (Debian/Ubuntu) |
|------|---------|------------------------|
| `fd` / `fdfind` | Faster filename search backend | `sudo apt install fd-find` |
| `rg` (ripgrep) | **Required** by `fcontent` | `sudo apt install ripgrep` |

Both tools include built-in guidance:

```bash
fsearch --self-check       # Check what's available
fsearch --install-hints    # Print install commands
fcontent --self-check
fcontent --install-hints
```

---

## Security Notes

- Neither tool stores passwords or credentials
- Neither tool writes to the filesystem or modifies files
- For scanning protected directories, authenticate first with `sudo -v` then run with `sudo`
- No auto-install behavior; `--install-hints` only _prints_ commands for you to run manually

---

## Installation

```bash
git clone https://github.com/lliWcWill/fsuite.git
cd fsuite
chmod +x fsearch fcontent

# Optional: symlink into your PATH
sudo ln -s "$(pwd)/fsearch" /usr/local/bin/fsearch
sudo ln -s "$(pwd)/fcontent" /usr/local/bin/fcontent
```

---

## License

MIT
