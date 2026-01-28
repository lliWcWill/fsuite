# Headless Hardening: Making `fcontent` Reliable in Non-Interactive Shells

**Date:** 2026-01-27
**Scope:** `fcontent` v1.0.0
**Environment:** Debian 12 (kernel 6.1.0-42), Bash 5.2, ripgrep 13.0.0

---

## Background

`fsuite` ships two composable CLI tools — `fsearch` (find files by name) and `fcontent` (search inside files via ripgrep). Both were designed from the start to support headless use: an AI agent or CI pipeline calls them with `--output json` or `--output paths` and parses the result programmatically.

The initial implementation worked perfectly in a regular terminal session. When we ran the tools headless — from a subprocess spawned by an automation harness, with no TTY attached — `fcontent` broke in three distinct ways. All three bugs were silent in interactive shells and only surfaced under non-interactive execution.

This document captures what went wrong, what we learned from researching the underlying Bash behavior, and what we changed.

---

## Bug 1: Stdin Detection Assumed "No TTY = Piped Data"

### What happened

`fcontent` supports two input modes:

1. **Directory mode:** `fcontent "query" /some/path` — searches recursively under a path.
2. **Piped mode:** `fsearch --output paths '*.log' /var/log | fcontent "query"` — reads file paths from stdin.

The original detection logic was:

```bash
FILES_FROM_STDIN=0
if ! [ -t 0 ]; then
  FILES_FROM_STDIN=1
fi
```

This checks whether file descriptor 0 (stdin) is connected to a terminal. In a normal interactive shell, running `fcontent "query" /some/path` has stdin attached to the terminal, so `[ -t 0 ]` is true and the script correctly uses directory mode.

In a headless environment (subprocess, cron, CI runner, automation harness), stdin is **never** a terminal — it's `/dev/null` or a pipe from the parent process. So `! [ -t 0 ]` is always true, even when the user explicitly passed a directory path as an argument. The script would enter piped mode, try to read file paths from the empty stdin, and immediately die:

```
Error: No file paths received on stdin.
```

### What we learned

`[ -t 0 ]` is a TTY check, not a "is data being piped" check. These are different things:

| Condition | `[ -t 0 ]` | Actual stdin state |
|-----------|-----------|-------------------|
| Interactive terminal, no pipe | true | Terminal |
| Interactive terminal, with pipe | false | Pipe with data |
| Headless, no pipe | false | `/dev/null` or closed fd |
| Headless, with pipe | false | Pipe with data |

The last two rows are indistinguishable via `[ -t 0 ]` alone.

### What we changed

The fix prioritizes explicit user intent. If the user provided a path argument (positional or `--path`), directory mode wins regardless of stdin state:

```bash
EXPLICIT_PATH=0
if [[ -n "${POSITIONAL[1]:-}" ]] || [[ "$SEARCH_PATH" != "$DEFAULT_PATH" ]]; then
  EXPLICIT_PATH=1
fi

FILES_FROM_STDIN=0
if (( EXPLICIT_PATH == 0 )) && ! [ -t 0 ]; then
  FILES_FROM_STDIN=1
fi
```

Now piped mode only activates when no explicit path was given **and** stdin is not a terminal. This covers the intended use case (`fsearch | fcontent "query"`) without breaking direct invocation in headless environments.

---

## Bug 2: `rg --files-from` Doesn't Exist in ripgrep 13.x

### What happened

The piped mode used ripgrep's `--files-from` flag to pass a list of file paths:

```bash
rg --files-from "$TMP_LIST" -- "$QUERY"
```

This flag does not exist in ripgrep 13.0.0 (the version packaged in Debian 12). It was introduced in a later release. The error:

```
error: Found argument '--files-from' which wasn't expected, or isn't valid in this context
```

### What we learned

`rg --version` on Debian 12 stable reports `ripgrep 13.0.0`. The `--files-from` flag is not available. The ripgrep docs recommend `--files` for listing indexed files, but that's a different feature entirely. For feeding an explicit file list, the portable approach is `xargs`.

### What we changed

Replaced all `--files-from` calls with `xargs -d '\n' -a`:

```bash
# Before (broken on rg 13.x)
rg --files-from "$TMP_LIST" -- "$QUERY"

# After (portable)
xargs -d '\n' -a "$TMP_LIST" rg -- "$QUERY"
```

`-d '\n'` sets the delimiter to newline (handles paths with spaces). `-a "$TMP_LIST"` reads arguments from the file instead of stdin (so rg's own stdin isn't consumed). Both are GNU coreutils extensions, but that's fine — this tool targets Linux.

---

## Bug 3: EXIT Trap Leaked a Non-Zero Exit Code

### What happened

Every output mode produced correct results, but the script's exit code was `1` instead of `0`. An agent checking `$?` after calling `fcontent` would interpret this as a failure.

### What we learned

The script registers a cleanup trap:

```bash
TMP_LIST=""
cleanup() {
  [[ -n "$TMP_LIST" && -f "$TMP_LIST" ]] && rm -f "$TMP_LIST"
}
trap cleanup EXIT
```

In directory mode, `TMP_LIST` is never assigned (it stays empty). When the script exits, the trap fires and evaluates:

```bash
[[ -n "" && -f "" ]] && rm -f ""
```

`[[ -n "" ]]` is false, so the `&&` short-circuits. The compound command's exit status is `1` (the failing test). Because this is the **last command executed in the trap**, and the trap is the **last thing the shell runs before exiting**, that `1` becomes the script's exit code.

This is a well-documented Bash pitfall. Under `set -e`, the behavior gets even more convoluted — the rules for which failures trigger immediate exit change depending on context (subshell, trap, conditional, process substitution). Greg's Wiki [BashFAQ/105](https://mywiki.wooledge.org/BashFAQ/105) covers this extensively. The short version: **never let a trap's last command be a conditional that might fail**.

### What we changed

```bash
cleanup() {
  [[ -n "$TMP_LIST" && -f "$TMP_LIST" ]] && rm -f "$TMP_LIST" || true
}
```

The `|| true` ensures the function always returns `0`, regardless of whether the conditional matched.

---

## Bonus: Process Substitution and `set -e` — What We Investigated but Didn't Need to Fix

During debugging, we also researched the interaction between `set -euo pipefail`, `mapfile`, and process substitution (`< <(...)`). This turned out not to be the root cause, but the findings are worth recording.

### Process substitution exit codes are invisible to the parent shell

```bash
set -euo pipefail
mapfile -t arr < <(some_failing_command)
echo "This still runs — the failure was silently discarded"
```

The process substitution `<(...)` runs asynchronously in a subshell. Its exit code is **not** propagated to the parent shell. `mapfile` itself succeeds (it just reads whatever data arrived), so `set -e` never triggers.

### `pipefail` only applies to actual pipelines

`set -o pipefail` changes exit-code behavior for `cmd1 | cmd2` pipelines. It has **no effect** on process substitutions. They are fundamentally different execution models.

### `head` can cause SIGPIPE in pipelines under `pipefail`

When `rg` produces output and `head -n N` closes its read end after N lines, `rg` receives SIGPIPE. Under `pipefail`, this makes the pipeline return non-zero. We added `|| true` to these pipelines as a safety measure:

```bash
mapfile -t LINES < <(rg ... | head -n "$MAX" || true)
```

### References

- [BashFAQ/105 — Why doesn't set -e do what I expected?](https://mywiki.wooledge.org/BashFAQ/105)
- [ProcessSubstitution — Greg's Wiki](https://mywiki.wooledge.org/ProcessSubstitution)
- [Capturing process substitution exit code in Bash](https://www.alikov.com/blog/2022-01-18-process-substitution-exit-code/)
- [Bash errexit and command substitution](https://samanpavel.medium.com/bash-errexit-and-command-substitution-32edaeaae36d)

---

## Test Matrix (Post-Fix)

All tests run headless (non-TTY subprocess), all returned `EXIT_CODE=0`.

| Test | Mode | Result |
|------|------|--------|
| `fsearch '*.py' /path` | pretty | 1796 files found |
| `fsearch --output json '*.sh' /path` | json | Valid JSON, 13 results |
| `fsearch --output paths '*.json' /path` | paths | 9 paths, one per line |
| `fsearch --self-check` | — | Reports fd missing, rg present |
| `fcontent "import" /path` | directory, pretty | 3 files, 21 matches |
| `fcontent --output json "def " /path` | directory, json | Valid JSON, 17 matches |
| `fcontent --output paths "import" /path` | directory, paths | 3 unique file paths |
| `fcontent --self-check` | — | Reports rg present |
| `fsearch \| fcontent` (pretty) | piped, pretty | 2 files, 2 matches |
| `fsearch \| fcontent` (json) | piped, json | Valid JSON, 2 matches |
| `fsearch \| fcontent` (paths) | piped, paths | 2 unique file paths |

---

## Takeaway

If your CLI tool will be used by agents, CI, or any non-interactive context:

1. **Don't use `[ -t 0 ]` as your only stdin-detection heuristic.** Combine it with explicit argument checks.
2. **Don't assume the latest version of your dependencies.** Check what ships with your target distro's stable repos. Debian 12 ships `rg 13.0.0`.
3. **Audit your EXIT traps.** A conditional with no fallback in a trap can silently set the script's exit code to `1`.
4. **Test headless from the start.** Run your tool from `bash -c`, a subprocess, or a pipe with no TTY. Bugs that are invisible interactively will surface immediately.
