---
title: 🌲 ftree
description: Territory scout — full tree + recon data in one call
sidebar:
  order: 2
---

## Territory scout — full tree + recon data in one call

`ftree` is part of the fsuite toolkit — a set of fourteen CLI tools built for AI coding agents.

<div class="fs-drone">
  <div class="fs-drone-head">
    <span class="fs-drone-call">ftree</span>
    <span class="fs-drone-tagline">Territory scout · directory recon · the first move</span>
  </div>
  <div class="fs-drone-meta">
    <div><b>Role</b><span class="role-recon">RECON</span></div>
    <div><b>Chain position</b><span>2 (scout)</span></div>
    <div><b>Pipe</b><span>not chainable (arg-based)</span></div>
    <div><b>Output</b><span>pretty · paths · json</span></div>
  </div>
</div>

`ftree` is the territory map. Before you guess at what's in a project, drop a tree-snapshot — see what dirs exist, what's loud (lots of files), what's lean, and where the surface area really is. The `--recon` mode adds per-directory item counts and sizes so you can prioritize where to dig.

Use it once at the start of every investigation. Use `--snapshot` when you want recon + a tree excerpt in one envelope.

## Canonical chains

`ftree` doesn't read from stdin — it's a chain start that gives context, not a middle filter. But it does emit machine-readable output via `-o paths` and `-o json` for downstream consumption.

```bash
# Default scout — 3-level tree, sensible excludes
ftree /project

# Recon mode — per-dir item counts + sizes
ftree --recon /project

# Snapshot — recon inventory + tree excerpt, agent-ready
ftree --snapshot -o json /project

# Deep dive into a specific subdir
ftree -L5 /project/src

# Full follow-up: scout, then map symbols of what looks promising
ftree --recon /project
fmap -o json /project/src/auth
```

## Help output

The content below is the **live** `--help` output of `ftree`, captured at build time from the tool binary itself. It cannot drift from the source — regenerating the docs regenerates this section.

```text
ftree — smart directory snapshot with recon mode (agent-friendly)

USAGE
  ftree [OPTIONS] [path]

QUICK EXAMPLES
  # Show tree of current directory (depth 3, default excludes)
  ftree

  # Recon: per-directory item counts and sizes
  ftree --recon /project

  # JSON output for agents
  ftree -o json /project

  # Flat file list (pipe-friendly)
  ftree -o paths /project

  # Drill into a subdirectory with deeper view
  ftree -L 5 /project/src

  # Include a normally-excluded directory
  ftree --include .git /project

  # Recon without excluded-directory summaries
  ftree --recon --hide-excluded /project

OPTIONS
  -o, --output pretty|paths|json
      pretty: human-friendly tree with header + truncation (default)
      paths:  flat file list, one per line (best for piping)
      json:   structured JSON (best for AI agents)

  -L, --depth N
      Max tree depth. Default: 3

  -m, --max-lines N
      Truncate pretty output at N lines (0 = unlimited). Default: 200
      Does not apply to paths or json output.

  -q, --quiet
      Suppress header line. Useful for piping/scripting.

  -F, --filelimit N
      Limit entries listed per directory. Default: 80
      tree may annotate directories when entries exceed this limit.

  -I, --ignore 'PATTERN'
      Additional pipe-separated patterns to exclude (appended to defaults).
      Always quote the value: ftree -I 'docs|*.md' /project

  --no-default-ignore
      Disable the built-in ignore list (node_modules, .git, venv, etc.).

  --include PATTERN
      Promote an excluded dir back to normal treatment (repeatable).
      Exact basename match: --include node_modules (not partial regex).

  -r, --recon
      Recon mode: shallow scan with per-directory item counts and sizes.
      Does not use tree(1) — uses find/du/stat directly.

  --recon-depth N
      How deep recon scans. Default: 1 (2 in snapshot mode). Deeper is expensive.

  --budget N
      Max wall-clock seconds for recon scans. Default: 30.
      Each du/find call has a 3-second per-call timeout.
      When budget is exceeded, remaining entries become stubs (items=-1, size=-1).
      JSON output includes "partial": true, "heavy": true on timed-out entries.

  --snapshot
      Snapshot mode: combines recon inventory and tree excerpt in one output.
      Default recon depth: 2. Not compatible with --recon or -o paths.

  --no-lines
      In snapshot JSON, omit the tree.lines array (keeps tree_json only).
      Only valid with --snapshot -o json.

  --project-name <name>
      Override project name in telemetry.

  --hide-excluded
      Suppress excluded-directory summaries from recon output.

  -d, --dirs-only
      Show only directories (applies to both tree and recon modes).

  -s, --sizes
      Show file/directory sizes in tree output.

  --gitignore
      Also honor .gitignore rules. Guarded: warns if tree version lacks support.

  -f, --full-paths
      Print full path prefix for each entry.

  --self-check
      Verify tree is installed and check --gitignore support.

  --install-hints
      Print install commands for tree.

  -h, --help
      Show this help and exit.

  --version
      Print version and exit.

DEFAULT IGNORE LIST
  node_modules|.git|venv|.venv|__pycache__|dist|build|.next|.cache|
  vendor|target|.gradle|.idea|.vscode|*.egg-info|.tox|.mypy_cache|
  .pytest_cache|.DS_Store|.terraform

  --ignore appends to defaults. --no-default-ignore disables them.
  --include removes exact tokens from the list.

EXIT CODES
  0  Success (even if empty tree / no results)
  2  Usage error (bad flags, missing args)
  3  Missing dependency (tree not installed)

RECON MODE
  Recon scans the target directory with find/du/stat instead of tree.
  For each entry: directories get an item count and size; files get size.
  Excluded directories (matching the ignore list) are shown separately,
  tagged [default-excluded], unless --hide-excluded is used.

  items_total: count of all entries (files + dirs) under a directory.

AGENT / HEADLESS USAGE
  ftree -o json /project             # structured tree JSON
  ftree --recon -o json /project     # per-dir inventory JSON
  ftree --snapshot -o json /project  # combined recon + tree in one call
  ftree -o paths /project            # flat file list for piping

  Agent drill-down workflow:
    1. ftree --snapshot /project         # one-shot: recon + tree
    2. ftree -L 5 /project/src           # zoom: deeper into src/
```

## See also

- [fsuite mental model](/fsuite/getting-started/mental-model/) — how ftree fits into the toolchain
- [Cheat sheet](/fsuite/reference/cheatsheet/) — one-line recipes for every tool
- [View source on GitHub](https://github.com/lliWcWill/fsuite/blob/master/ftree)
