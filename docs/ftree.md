# ftree — Directory Structure and Recon Tool

**Version:** 1.0.1
**Part of:** [fsuite](../README.md)
**Requires:** `tree` (for tree mode), `find`/`du`/`stat` (for recon mode)

---

## What ftree Does

ftree produces a **context-budget-aware directory snapshot**. It wraps `tree(1)` with smart defaults and adds a recon mode that uses `find`/`du`/`stat` directly for per-directory inventory without full tree expansion.

It speaks two dialects:

- **Headless / agent mode**: stable JSON output, deterministic ordering, parseable metadata. Designed for AI agents, CI pipelines, and automation scripts.
- **Human mode**: readable pretty output with headers, truncation, drill-down hints, and size summaries.

---

## Architecture

ftree has two independent modes, each with three output formats:

```
ftree
  |
  +-- tree mode (default)     wraps tree(1)
  |     +-- pretty            header + tree body + truncation footer
  |     +-- paths             flat file list via tree -fi
  |     +-- json              metadata envelope + tree -J output
  |
  +-- recon mode (--recon)    uses find/du/stat directly
        +-- pretty            header + sorted inventory table
        +-- paths             flat entry list
        +-- json              metadata envelope + entries array
```

### Internal structure (v1.0.1)

The script is organized into:

1. **Helpers** — `die()`, `has()`, `json_escape()`, `human_size()`, `name_matches_ignore()`
2. **Extracted utilities** (v1.0.1) — `tree_supports_gitignore()`, `du_bytes()`, `count_items_total()`, `stat_bytes()`
3. **Arg parsing** — validates all flags, accumulates `--ignore`, guards missing values
4. **Ignore pattern builder** — `build_ignore()` combines defaults + user patterns, removes `--include` entries
5. **Recon mode** — `run_recon()` with `render_recon_pretty()`, `render_recon_json()`, `render_recon_paths()`
6. **Tree mode** (v1.0.1 refactor) — `tree_build_args()`, `tree_capture_body_and_counts()`, `run_tree_pretty()`, `run_tree_paths()`, `run_tree_json()`

---

## Modes

### Tree mode (default)

Runs `tree(1)` with smart defaults:

- Depth 3 (configurable via `-L`)
- 200-line cap on pretty output (configurable via `-m`)
- 80-entry filelimit per directory (configurable via `-F`)
- Noise directories excluded by default (node_modules, .git, venv, __pycache__, etc.)
- Directories sorted first (`--dirsfirst`)
- No color codes (`-n`) for clean piping

### Recon mode (`--recon`)

Does **not** use `tree(1)`. Scans the target directory with `find`/`du`/`stat`:

- Lists immediate children (or deeper with `--recon-depth`)
- For each directory: item count (`find | wc -l`) and total size (`du -sb`)
- For each file: size (`stat`)
- Entries sorted by size descending within each group (dirs, files, excluded)
- Excluded entries shown separately, tagged `[default-excluded]`

Recon is the "scout" step: cheap, fast, tells you where the mass is before you commit context to a full tree.

---

## Cheat Sheet

Every command runs headless (no prompts, no TTY needed).

### Basic usage

| Command | What it does |
|---------|-------------|
| `ftree /project` | Tree view, depth 3, default excludes, 200-line cap |
| `ftree --recon /project` | Recon: per-dir item counts and sizes |
| `ftree -L 5 /project/src` | Deeper tree (depth 5) into a subdirectory |
| `ftree -L 1 /project` | Shallow tree (depth 1) — just top-level entries |

### Output formats

| Command | What it does |
|---------|-------------|
| `ftree /project` | Pretty output (default) — human-readable with header |
| `ftree -o json /project` | Structured JSON tree with metadata envelope |
| `ftree -o paths /project` | Flat file list, one per line — pipe-friendly |
| `ftree --recon -o json /project` | Recon JSON: per-dir inventory for agents |
| `ftree --recon -o paths /project` | Recon paths: entry names, one per line |

### Ignore and include

| Command | What it does |
|---------|-------------|
| `ftree -I 'docs\|*.md' /project` | Exclude additional patterns (pipe-separated, appended to defaults) |
| `ftree -I 'docs' -I '*.md' /project` | Same — multiple `-I` flags accumulate (v1.0.1+) |
| `ftree --include .git /project` | Show `.git` even though it's in the default ignore list |
| `ftree --include node_modules /project` | Show `node_modules` (exact basename match) |
| `ftree --no-default-ignore /project` | Disable the entire built-in ignore list |
| `ftree --no-default-ignore -I 'tmp' /project` | No defaults, only exclude `tmp` |

### Display options

| Command | What it does |
|---------|-------------|
| `ftree -d /project` | Directories only |
| `ftree -s /project` | Show file/dir sizes in tree output |
| `ftree -f /project` | Full absolute paths for each entry |
| `ftree -m 50 /project` | Cap pretty output at 50 lines |
| `ftree -m 0 /project` | Unlimited lines (may be large) |
| `ftree --gitignore /project` | Also honor `.gitignore` rules (requires tree >= 1.8.0) |

### Recon options

| Command | What it does |
|---------|-------------|
| `ftree --recon /project` | Recon: depth 1 (immediate children) |
| `ftree --recon --recon-depth 2 /project` | Recon: scan 2 levels deep |
| `ftree --recon --hide-excluded /project` | Suppress excluded-dir summaries |
| `ftree --recon -d /project` | Recon: directories only (skip files) |

### Diagnostics

| Command | What it does |
|---------|-------------|
| `ftree --self-check` | Verify tree is installed, check `--gitignore` support |
| `ftree --install-hints` | Print install command for tree |
| `ftree --version` | Print version (`ftree 1.0.1`) |

---

## Headless Agent Workflows

ftree is designed for AI agents, CI pipelines, and automation scripts. No TTY, no prompts, deterministic output.

### The drill-down workflow

This is the recommended pattern for an agent exploring an unknown project:

```bash
# Step 1: Scout — what's here, how big is it?
ftree --recon -o json /project
# Agent reads: per-dir item counts, sizes, exclusion tags
# Decision: which dirs are worth expanding?

# Step 2: Structure — show me the shape
ftree -o json /project
# Agent reads: depth-3 tree, dir/file counts, truncation status
# Decision: where should I drill deeper?

# Step 3: Zoom — expand an interesting subtree
ftree -L 5 -o json /project/src
# Agent reads: deeper view of just src/

# Step 4: Find specific files
fsearch -o json '*.py' /project/src

# Step 5: Search inside those files
fsearch -o paths '*.py' /project/src | fcontent -o json "def main"
```

### Agent-specific patterns

| Pattern | Command | Why |
|---------|---------|-----|
| **Project triage** | `ftree --recon -o json /project` | Size + counts tell agent where mass is |
| **Structure overview** | `ftree -o json /project` | Agent gets tree + truncation metadata |
| **Deep dive** | `ftree -L 6 -o json /project/src` | Agent zooms into heavy subtree |
| **Flat inventory** | `ftree -o paths /project` | One path per line, easy to iterate |
| **Size audit** | `ftree --recon -o json /project \| jq '.entries[] \| select(.size_bytes > 1000000)'` | Find dirs > 1MB |
| **Exclude noise** | `ftree -I 'test\|docs\|*.md' -o json /project` | Skip test/docs for code-only view |
| **Include hidden** | `ftree --include .git -o json /project` | See .git in tree for repo analysis |
| **Context-safe** | `ftree -m 100 -o json /project` | Cap to 100 lines, stay in budget |
| **Dirs-only map** | `ftree -d -o json /project` | Just the directory skeleton |

### JSON output contracts

Tree mode JSON:

```json
{
  "tool": "ftree",
  "version": "1.0.1",
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

Recon mode JSON:

```json
{
  "tool": "ftree",
  "version": "1.0.1",
  "mode": "recon",
  "backend": "find/du/stat",
  "path": "/project",
  "recon_depth": 1,
  "total_entries": 8,
  "visible": 5,
  "excluded": 3,
  "entries": [
    {
      "name": "src",
      "type": "directory",
      "items_total": 234,
      "size_bytes": 1258291,
      "size_human": "1.2M",
      "excluded": false
    },
    {
      "name": "package.json",
      "type": "file",
      "size_bytes": 2355,
      "size_human": "2.3K",
      "excluded": false
    },
    {
      "name": "node_modules",
      "type": "directory",
      "items_total": 1847,
      "size_bytes": 207618048,
      "size_human": "198M",
      "excluded": true
    }
  ]
}
```

### Key JSON fields for agents

| Field | Type | Meaning |
|-------|------|---------|
| `total_dirs` / `total_files` | int | Counts from tree's report line |
| `total_lines` | int | Total content lines (excluding report) |
| `shown_lines` | int | Lines after truncation cap |
| `truncated` | bool | Whether output was capped by `--max-lines` |
| `tree_json` | array | Native `tree -J` output (nested directory structure) |
| `entries[].items_total` | int | Count of all entries under a directory (-1 if unreadable) |
| `entries[].size_bytes` | int | Size in bytes (-1 if unreadable) |
| `entries[].excluded` | bool | Whether the entry matched the ignore pattern |

---

## Interactive Human Usage

ftree's default pretty output is designed for terminal use. No flags needed for common cases.

### Quick exploration

```bash
# What's in this project?
ftree

# What's in this project? (scout first)
ftree --recon

# How deep is src/?
ftree -L 6 src

# What's eating disk space?
ftree --recon -s

# Show me everything (no ignore list)
ftree --no-default-ignore -L 1
```

### Reading the pretty output

**Tree mode header:**

```
Tree(/project, depth=3, filelimit=80)
  ⎿ 12 directories, 47 files (showing 89 of 89 lines)
```

Tells you: path, depth, filelimit, dir/file counts, and how many lines are shown vs total.

**Truncation footer** (when output exceeds `--max-lines`):

```
     ... 34 more lines not shown
     Drill deeper: ftree -L 5 /project
```

Copy-paste the suggested command to see more.

**Recon mode header:**

```
Recon(/project, depth=1)
  ⎿ 8 entries (5 visible, 3 default-excluded)
```

Tells you: path, recon depth, total entries, visible vs excluded breakdown.

---

## Using ftree with fsearch and fcontent

The three fsuite tools compose into a **scout-then-search** pipeline:

### Pattern 1: Recon, then tree, then search

```bash
# 1. Scout: where's the mass?
ftree --recon /project
# Output tells you: src/ has 234 items and 1.2M

# 2. Structure: what's the shape of src/?
ftree -L 5 /project/src

# 3. Find: which files match?
fsearch '*.py' /project/src

# 4. Grep: what's inside?
fsearch -o paths '*.py' /project/src | fcontent "class "
```

### Pattern 2: Tree paths as input to content search

```bash
# Get all file paths from tree, search inside them
ftree -o paths /project | fcontent "TODO"
```

### Pattern 3: Agent pipeline (fully structured)

```bash
# Agent gets structured inventory
ftree --recon -o json /project > /tmp/recon.json

# Agent gets structured tree
ftree -o json /project > /tmp/tree.json

# Agent searches inside files
fsearch -o paths '*.py' /project | fcontent -o json "import torch" > /tmp/imports.json
```

### Pattern 4: Size-aware search targeting

```bash
# Scout sizes first
ftree --recon /project
# See that src/ is 1.2M, tests/ is 500K, docs/ is 50K

# Only search the heavy directory
fsearch -o paths '*.py' /project/src | fcontent "database"
```

---

## Default Ignore List

The following patterns are excluded by default:

```
node_modules  .git       venv         .venv       __pycache__
dist          build      .next        .cache      vendor
target        .gradle    .idea        .vscode     *.egg-info
.tox          .mypy_cache .pytest_cache .DS_Store  .terraform
```

- `--ignore` / `-I` appends additional patterns to this list
- Multiple `-I` flags accumulate: `-I 'docs' -I '*.md'` excludes both
- `--no-default-ignore` disables the entire built-in list
- `--include` removes exact tokens from the list (basename match)

---

## Exit Codes

| Code | Meaning |
|------|---------|
| `0` | Success (even if empty tree or no results) |
| `2` | Usage error (bad flags, missing args, missing flag values) |
| `3` | Missing dependency (tree not installed) |

---

## Version History

### v1.0.1

**Internal refactor + correctness fixes. No observable output changes except version field.**

Bug fixes:
- Multiple `--ignore` / `-I` flags now accumulate (was silently overwriting)
- Missing flag values (e.g. `ftree -L` with no number) now die with clear `"Error: Missing value for --flag"` messages instead of confusing errors

Refactors:
- `build_ignore()` replaced sed-based token removal with exact-match array loop
- Extracted `tree_supports_gitignore()` helper (was inline 4+ times)
- Extracted `du_bytes()`, `count_items_total()`, `stat_bytes()` helpers from `run_recon()`
- Split `run_tree()` (~180 lines) into focused functions: `tree_build_args()`, `tree_capture_body_and_counts()`, `run_tree_pretty()`, `run_tree_paths()`, `run_tree_json()`
- JSON tree mode now runs `tree` 2 times instead of 3

### v1.0.0

Initial release. Tree mode, recon mode, three output formats, smart defaults.

---

## Dependencies

| Tool | Required by | Install (Debian/Ubuntu) |
|------|-------------|------------------------|
| `tree` | tree mode | `sudo apt install tree` |
| `find` | recon mode | Pre-installed (coreutils) |
| `du` | recon mode | Pre-installed (coreutils) |
| `stat` | recon mode | Pre-installed (coreutils) |

```bash
# Check what's available
ftree --self-check

# Print install commands
ftree --install-hints
```
