---
title: 📝 fwrite
description: Atomic file creation
sidebar:
  order: 9
---

## Atomic file creation

`fwrite` is part of the fsuite toolkit — a set of fourteen CLI tools built for AI coding agents.

<div class="fs-drone">
  <div class="fs-drone-head">
    <span class="fs-drone-call">fwrite</span>
    <span class="fs-drone-tagline">Atomic file creation · MCP-only</span>
  </div>
  <div class="fs-drone-meta">
    <div><b>Role</b><span class="role-edit">CREATE</span></div>
    <div><b>Available</b><span>MCP only (no CLI)</span></div>
    <div><b>Use for</b><span>create or full rewrite</span></div>
    <div><b>Use fedit for</b><span>surgical changes</span></div>
  </div>
</div>

`fwrite` is the **MCP-only** atomic file creation tool. It writes or overwrites a file from a string payload. Not available as a CLI binary — agents call it directly through the fsuite MCP server.

**Decision rule:**
- Brand-new file → `fwrite`
- Replacing an entire file end-to-end → `fwrite`
- Any surgical change (line range, symbol, anchor) → `fedit`

`fedit` has analogous functionality (`fedit --create`, `fedit --replace-file`) for CLI users without MCP — but if you're already on the MCP transport, `fwrite` is one call instead of two flags.

## Usage notes

The block below is the script header from the `fwrite` source — usage, flags, and exit codes documented inline. (Unlike most fsuite tools, `fwrite`'s primary surface is the MCP tool definition, not a `--help` flag, so this section captures the script comments rather than runtime help text.)

```text
# modifications. This is the "create" counterpart to fedit's "modify."
#
# Usage:
#   fwrite <path> --content <text>           Create new file
#   fwrite <path> --content <text> --overwrite   Overwrite existing
#   fwrite <path> --stdin                    Read content from stdin
#   fwrite <path> --from <source>            Copy from source file
#
# Flags:
#   --content <text>    File content (required unless --stdin or --from)
#   --overwrite         Allow overwriting existing files (default: deny)
#   --stdin             Read content from stdin (for piping)
#   --from <path>       Copy content from another file
#   --mkdir             Create parent directories (default: true)
#   --no-mkdir          Don't create parent directories
#   --dry-run           Show what would happen without writing
#   --json              Output result as JSON
#   -q, --quiet         Suppress output, exit code only
#
# Exit codes:
#   0  Success
#   1  Missing arguments
#   2  File exists (no --overwrite)
#   3  Parent directory doesn't exist (--no-mkdir)
#   4  Write failed
#   5  Source file not found (--from)
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail
```

## See also

- [fsuite mental model](/fsuite/getting-started/mental-model/) — how fwrite fits into the toolchain
- [Cheat sheet](/fsuite/reference/cheatsheet/) — one-line recipes for every tool
- [View source on GitHub](https://github.com/lliWcWill/fsuite/blob/master/fwrite)
