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
