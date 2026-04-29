---
title: 💻 fbash
description: Token-budgeted shell execution with classification and session state
sidebar:
  order: 10
---

## Token-budgeted shell execution with classification and session state

`fbash` is part of the fsuite toolkit — a set of fourteen CLI tools built for AI coding agents.

<div class="fs-drone">
  <div class="fs-drone-head">
    <span class="fs-drone-call">fbash</span>
    <span class="fs-drone-tagline">Token-budgeted shell · classification · session state · MCP escape hatch</span>
  </div>
  <div class="fs-drone-meta">
    <div><b>Role</b><span class="role-edit">EXEC</span></div>
    <div><b>Chain position</b><span>specialist</span></div>
    <div><b>MCP advantage</b><span>shells out to all CLI tools</span></div>
    <div><b>Output</b><span>budgeted · classified</span></div>
  </div>
</div>

`fbash` is `bash` with the same agent-aware budget discipline as the rest of fsuite. Output is capped, classified (stdout vs stderr vs status), and the working directory + fcase/session state persist between calls. Note: exported environment variables do **not** persist across `fbash` invocations — each call starts a fresh shell with `cd` restored.

**The MCP escape hatch.** If you're calling fsuite tools through the MCP server, every call is sequential — MCP doesn't pipe. But `fbash` runs a real shell, which means real Unix pipes work inside it. Wrap your chain in one `fbash` call and get full pipeline speed back, even from MCP-only agents.

## Canonical chains

```bash
# Run a real Unix pipe from inside MCP — the escape hatch
fbash "fsearch -o paths '*.py' src | fmap -o json"

# Triple-chain inside one fbash call
fbash "fsearch -o paths '*.py' src \
       | fcontent -o paths 'class' \
       | fmap -o json"

# Stateful session — cd persists to the next call (env vars do not)
fbash "cd /project"
fbash "pwd"   # → /project (cd was preserved)

# Long-running with cap
fbash "find / -name '*.log' 2>/dev/null"   # output capped automatically
```

## Help output

The content below is the **live** `--help` output of `fbash`, captured at build time from the tool binary itself. It cannot drift from the source — regenerating the docs regenerates this section.

```text
fbash — token-budgeted shell execution for fsuite

USAGE
  fbash --command '<cmd>' [options]
  fbash '<cmd>' [options]

OPTIONS
  --command <cmd>       Bash command to execute (or pass as positional arg)
  --max-lines <n>       Cap stdout to n lines (default: 200)
  --max-bytes <n>       Cap stdout to n bytes (default: 51200)
  --json                Parse command output as JSON
  --cwd <path>          Working directory (overrides session CWD)
  --timeout <secs>      Timeout in seconds (auto-tuned by class if omitted)
  --env <KEY=VALUE>     Environment override (repeatable)
  --filter <regex>      Regex filter for output lines
  --quiet               Suppress stdout/stderr, return exit code + metadata
  --tag <label>         Label for fcase event logging
  --background          Run in background, return job_id
  --tail                Keep tail instead of head when truncating
  -o, --output <fmt>    Output format: pretty (default) or json
  --history             Show command history from session
  --version             Show version
  -h, --help            Show this help

INTERNAL COMMANDS
  __fbash_history       Return command history
  __fbash_session       Return full session state
  __fbash_reset         Clear session state
  __fbash_poll <id>     Check background job status
  __fbash_jobs          List background jobs
  __fbash_set_case <s>  Set active fcase slug
  __fbash_clear_case    Clear active fcase

EXAMPLES
  fbash --command 'git status'
  fbash --command 'npm test' --tail --max-lines 100
  fbash --command 'find . -name "*.ts"' -o json
  fbash --command 'npm run build' --background
  fbash --command '__fbash_poll fbash_1712035200_12345'
```

## See also

- [fsuite mental model](/fsuite/getting-started/mental-model/) — how fbash fits into the toolchain
- [Cheat sheet](/fsuite/reference/cheatsheet/) — one-line recipes for every tool
- [View source on GitHub](https://github.com/lliWcWill/fsuite/blob/master/fbash)
