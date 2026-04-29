<!-- README OVERHAUL — SECTION 04 -->
<!-- Quick Reference / Cheat Sheet, Output Formats, Testing, Changelog -->
<!-- Generated 2026-03-29 — v2.3.0; updated 2026-04-29 for v2.4.0 (media reading) -->
<!-- See ../../../README.md for the canonical published version -->
<!-- This draft is the source of truth for internal review and PR body assembly. -->
<!-- Note: PRs #27, #30, #33, #34, #37 (April 10–29) collapsed into the consolidated changelog under v2.3.x → v2.4.0 narrative. -->
<!-- See also: docs/EPISODE-3.md for narrative project history. -->

---

## Quick Reference / Cheat Sheet

Copy-paste ready. Every command runs headless (no prompts, no TTY needed) unless marked **Interactive**.

### `fs` — Unified Search Orchestrator

> MCP-only tool. Not available as a CLI binary. Call via the fsuite MCP server.

| Call | What it does |
|------|-------------|
| `fs "authenticate"` | Unified search — scouts structure, finds files, maps symbols, returns ranked results in one call |
| `fs "error handler" --scope /project/src` | Narrow the search surface to a subtree |
| `fs "class AuthHandler" --type symbol` | Bias toward symbol-name matches over text content |
| `fs "TODO" --type content` | Bias toward in-file text content matches |
| `fs "*.log" --type file` | File-name pattern search via orchestrator |
| `fs "def authenticate" -o json` | Structured JSON with ranked hits, tool breakdown, and confidence |

### `fprobe` — Binary Recon

| Command | What it does |
|---------|-------------|
| `fprobe strings /path/to/binary` | Extract printable strings from a binary file |
| `fprobe strings /path/to/binary --min-len 8` | Only strings of 8+ characters |
| `fprobe strings /path/to/binary --filter "http"` | Strings containing a literal substring |
| `fprobe scan /path/to/binary` | Full binary inventory: format, arch, size, section summary |
| `fprobe scan /path/to/binary -o json` | JSON envelope: format, arch, entropy, section table |
| `fprobe window /path/to/binary --offset 0x100 --size 256` | Read raw bytes from a specific offset |
| `fprobe window /path/to/binary --offset 0x100 --size 256 --hex` | Hex dump of the window |
| `fprobe window /path/to/binary --offset 0x100 --size 256 -o json` | JSON with hex, ascii, and offset metadata |
| `fprobe --self-check` | Verify `file`, `strings`, `xxd`/`od` availability |
| `fprobe --version` | Print version |

### `freplay` — Derivation Replay

| Command | What it does |
|---------|-------------|
| `freplay record --case auth-seam --note "Traced denial branch"` | Record a derivation step with a note |
| `freplay record --case auth-seam --cmd "fread /project/src/auth.py --around 'def authenticate'"` | Record a derivation step with the command that produced it |
| `freplay show auth-seam` | Show the full replay chain for a case in order |
| `freplay show auth-seam -o json` | Machine-readable replay chain with timestamps |
| `freplay list` | List all cases that have replay chains |
| `freplay list -o json` | JSON list of case slugs with step counts |
| `freplay --version` | Print version |

### `fsearch` — Find Files by Name

| Command | What it does |
|---------|-------------|
| `fsearch '*.log' /var/log` | Find all `.log` files under `/var/log` (pretty output) |
| `fsearch log /var/log` | Bare word `log` auto-expands to `*.log` |
| `fsearch .log /var/log` | Dotted `.log` also auto-expands to `*.log` |
| `fsearch 'upscale*' /home/user` | Files whose names start with `upscale` |
| `fsearch '*progress*' /home/user` | Files containing `progress` anywhere in the name |
| `fsearch '*error' /var/log` | Files whose names end with `error` |
| `fsearch --output paths '*.py' /project` | One path per line — ideal for piping |
| `fsearch --output json '*.conf' /etc` | Structured JSON with `total_found`, `results[]`, `backend` |
| `fsearch --include 'src' --exclude '*test*' '*.py' /project` | Scope to source, skip tests |
| `fsearch --exclude 'node_modules' --exclude '.git' '*.log' /repo` | Skip noisy dirs |
| `fsearch --max 10 '*.py' /project` | Limit to first 10 results |
| `fsearch --backend fd '*.rs' /src` | Force `fd` backend (faster, if installed) |
| `fsearch --self-check` | Show which backends are available |
| `fsearch -q '*.py' /project` | Quiet mode — exit code only |
| `fsearch -i` | **Interactive** — prompts for pattern and path |

### `fcontent` — Search Inside Files

| Command | What it does |
|---------|-------------|
| `fcontent "ERROR" /var/log` | Search for `ERROR` inside all files under `/var/log` |
| `fcontent "TODO" /project` | Find every `TODO` in a project tree |
| `fcontent --output paths "ERROR" /var/log` | Print only file paths that matched (one per line) |
| `fcontent --output json "ERROR" /var/log` | Structured JSON with `matches[]`, `matched_files[]`, counts |
| `fcontent -m 20 "debug" /project` | Cap output to 20 match lines |
| `fcontent -n 50 "debug" /project` | Cap to 50 files searched |
| `fcontent --rg-args "-i" "error" /var/log` | Case-insensitive search |
| `fcontent --rg-args "--hidden" "secret" ~` | Include hidden/dotfiles |
| `fcontent --rg-args "-w" "main" /project` | Whole-word match only |
| `fcontent --self-check` | Verify `rg` is installed |
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
| `ftree --snapshot /project` | Recon inventory + tree excerpt in one output |
| `ftree --snapshot -o json /project` | Snapshot JSON: combined recon + tree for agents |
| `ftree --recon --hide-excluded /project` | Clean recon, no excluded-dir summaries |
| `ftree --include .git /project` | Show `.git` even though it's in the default ignore list |
| `ftree -I 'docs\|*.md' /project` | Exclude additional patterns (appended to defaults) |
| `ftree --no-default-ignore /project` | Disable built-in ignore list entirely |
| `ftree --snapshot --no-lines -o json /project` | Snapshot JSON without `tree.lines` array |
| `ftree --self-check` | Verify tree is installed, check `--gitignore` support |

### `fmap` — Extract Code Structure

| Command | What it does |
|---------|-------------|
| `fmap /project` | Map all source files under `/project` (pretty output) |
| `fmap /project/src/auth.py` | Map a single file |
| `fmap -o json /project` | JSON output with symbol metadata |
| `fmap --name authenticate -o json /project` | Rank/filter by symbol name matches |
| `fmap -o paths /project` | File paths that contain symbols |
| `fmap -t function /project` | Show only function definitions |
| `fmap -t class /project` | Show only class definitions |
| `fmap --no-imports /project` | Skip import lines |
| `fmap -L bash /project/scripts` | Force language to Bash |
| `fmap -m 50 /project` | Cap shown symbols to 50 |
| `fmap -n 100 /project` | Cap files processed to 100 |
| `fmap --self-check` | Verify grep is available |
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
| `fread /project/src/auth.py --symbol authenticate -o json` | Read one exact symbol block from a file |
| `fread /project/src --symbol authenticate -o json` | Resolve and read one exact symbol from a directory scope |
| `fread /project/src/auth.py --all-matches --around "TODO"` | Read around every match until caps are hit |
| `fread /project/src/auth.py --max-lines 80 --max-bytes 12000` | Enforce hard output budgets |
| `fread /project/src/auth.py --token-budget 2000 -o json` | Cap by estimated token cost |
| `fsearch -o paths '*.py' /project \| fread --from-stdin --stdin-format=paths --max-files 5` | Read first 5 files from a pipeline |
| `git diff \| fread --from-stdin --stdin-format=unified-diff -B 3 -A 10` | Read context around changed hunks |
| `fread --self-check` | Verify dependencies (`sed`, `awk`, `grep`, `wc`, `od`, `perl`) |

### `fcase` — Preserve Investigation Continuity

| Command | What it does |
|---------|-------------|
| `fcase init auth-seam --goal "Trace authenticate flow"` | Create a new investigation case |
| `fcase list -o json` | List known cases for automation |
| `fcase status auth-seam -o json` | Read current case state |
| `fcase note auth-seam --body "Focused on denial branch"` | Append a note to the case history |
| `fcase target add auth-seam --path /project/src/auth.py --symbol authenticate --symbol-type function --state active` | Mark a file/symbol seam as active |
| `fcase evidence auth-seam --tool fread --path /project/src/auth.py --lines 40:72 --summary "..." --body "..."` | Store structured proof from a read |
| `fcase hypothesis add auth-seam --body "Cleanup bug in tool cancellation"` | Track an open hypothesis |
| `fcase reject auth-seam --hypothesis-id 1 --reason "Process survives normal completion too"` | Reject a hypothesis explicitly |
| `fmap -o json /project/src/auth.py \| fcase target import auth-seam` | Import mapped symbols as structured targets |
| `fread -o json /project/src/auth.py --around "def authenticate" -A 20 \| fcase evidence import auth-seam` | Import bounded reads as structured evidence |
| `fcase next auth-seam --body "Patch denial branch after reviewing symbol map"` | Update the next best move |
| `fcase handoff auth-seam -o json` | Emit a concise handoff packet for the next agent |
| `fcase export auth-seam -o json` | Export the full portable case envelope |
| `fcase --version` | Print version |

### `fedit` — Apply Surgical Patches

| Command | What it does |
|---------|-------------|
| `fedit /project/src/auth.py --replace 'old' --with 'new'` | Preview an exact replacement (dry-run by default) |
| `fedit /project/src/auth.py --replace 'old' --with 'new' --apply` | Apply the exact replacement |
| `fedit /project/src/auth.py --lines 71:73 --with "    return deny()\n"` | Replace a specific line range with new content |
| `fedit /project/src/auth.py --after 'def authenticate(user):' --content-file patch.txt` | Preview an insertion after an anchor |
| `fedit /project/src/auth.py --before 'return True' --stdin --apply` | Insert payload from stdin before an anchor |
| `fedit /project/src/auth.py --symbol authenticate --replace 'return False' --with 'return deny()'` | Scope the patch to one `fmap`-resolved symbol |
| `fedit /project/src/auth.py --function authenticate --replace 'return False' --with 'return deny()'` | Scope to a function without spelling `--symbol-type` |
| `fedit /project/src/auth.py --class AuthHandler --after 'self.ready = False' --with $'\n        self.ready = True'` | Target one class block |
| `printf '/project/a.py\n/project/b.py\n' \| fedit --targets-file - --targets-format paths --replace 'x = 1' --with 'x = 2'` | Preview a batch patch from stdin targets |
| `fedit --targets-file map.json --targets-format fmap-json --function authenticate --replace 'return False' --with 'return deny()' --apply` | Apply symbol-scoped edit across `fmap` JSON targets |
| `fedit /project/src/auth.py --expect 'def authenticate' --replace 'old' --with 'new'` | Require expected text before patching |
| `fedit /project/src/auth.py --expect-sha256 HASH --replace 'old' --with 'new' --apply` | Guard the write with a content hash |
| `fedit --create /project/src/new_file.py --content-file body.txt --apply` | Create a new file from payload |
| `fedit --replace-file /project/src/auth.py --content-file rewrite.txt --apply` | Replace an entire file from payload |
| `fedit --self-check` | Verify perl, diff, mktemp, and SHA tooling |

### `fwrite` — Write Files

> MCP-only tool. Not available as a CLI binary. Call via the fsuite MCP server. Writes or overwrites a file from a string payload. Use `fedit` for surgical patches; `fwrite` for complete file creation or full rewrites.

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

### Pipeline — Canonical Sequences

| Workflow | Command chain |
|----------|--------------|
| **Full scout** | `ftree --snapshot -o json /project` |
| **Find + map** | `fsearch -o paths '*.py' /project \| fmap -o json` |
| **Find + grep** | `fsearch -o paths '*.log' /var/log \| fcontent "ERROR"` |
| **Find + read** | `fsearch -o paths '*.py' /project \| fread --from-stdin --stdin-format=paths --max-files 5 -o json` |
| **Map + read** | `fmap --name authenticate -o json /project \| fread --symbol authenticate -o json` |
| **Binary recon** | `fprobe scan /binary && fprobe strings /binary --filter "http"` |
| **Investigation** | `fcase init seam --goal "..." && fmap -o json /path \| fcase target import seam && fcase handoff seam -o json` |
| **Batch patch** | `fsearch -o paths '*.py' /project \| fedit --targets-file - --targets-format paths --replace 'x' --with 'y' --apply` |
| **Git diff read** | `git diff \| fread --from-stdin --stdin-format=unified-diff -o json` |

---

## Output Formats

All fsuite CLI tools share the same three output modes: `pretty` (default, human-readable), `paths` (one path per line for piping), `json` (structured, always machine-parseable). Pass `-o json` to any tool.

### `fprobe scan` JSON schema

```json
{
  "tool": "fprobe",
  "version": "2.2.0",
  "mode": "scan",
  "path": "/path/to/binary",
  "format": "ELF 64-bit LSB executable",
  "arch": "x86-64",
  "size_bytes": 123456,
  "entropy": 5.91,
  "sections": [
    { "name": ".text",  "size_bytes": 65536, "offset": "0x400000" },
    { "name": ".data",  "size_bytes": 4096,  "offset": "0x500000" },
    { "name": ".rodata","size_bytes": 8192,  "offset": "0x510000" }
  ],
  "strings_count": 412,
  "truncated": false
}
```

### `fprobe strings` JSON schema

```json
{
  "tool": "fprobe",
  "version": "2.2.0",
  "mode": "strings",
  "path": "/path/to/binary",
  "min_len": 4,
  "filter": null,
  "total_found": 412,
  "strings": [
    { "offset": "0x1a30", "value": "https://api.example.com/v1" },
    { "offset": "0x1a58", "value": "Authorization: Bearer" }
  ],
  "truncated": false
}
```

### `fprobe window` JSON schema

```json
{
  "tool": "fprobe",
  "version": "2.2.0",
  "mode": "window",
  "path": "/path/to/binary",
  "offset": 256,
  "size": 64,
  "hex": "4d5a9000 03000000 04000000 ffff0000",
  "ascii": "MZ..............",
  "truncated": false
}
```

### `fs` (unified search) JSON schema

```json
{
  "tool": "fs",
  "version": "2.3.0",
  "query": "authenticate",
  "scope": "/project",
  "results": [
    {
      "rank": 1,
      "type": "symbol",
      "path": "/project/src/auth.py",
      "symbol": "authenticate",
      "symbol_type": "function",
      "line": 42,
      "confidence": 0.97
    },
    {
      "rank": 2,
      "type": "content",
      "path": "/project/tests/test_auth.py",
      "line": 18,
      "match": "def test_authenticate_rejects_expired():",
      "confidence": 0.81
    }
  ],
  "total": 2,
  "tools_used": ["fmap", "fcontent"],
  "truncated": false
}
```

### `freplay show` JSON schema

```json
{
  "tool": "freplay",
  "version": "2.3.0",
  "case": "auth-seam",
  "steps": [
    {
      "step": 1,
      "ts": "2026-03-29T14:02:11Z",
      "cmd": "fread /project/src/auth.py --around 'def authenticate' -A 20",
      "note": "Located denial branch at line 71"
    },
    {
      "step": 2,
      "ts": "2026-03-29T14:04:33Z",
      "cmd": "fedit /project/src/auth.py --lines 71:73 --with '    return deny()\\n' --apply",
      "note": "Patched denial path"
    }
  ],
  "total_steps": 2
}
```

---

## Testing

The full test harness lives in `tests/`. Run via the master runner:

```bash
./tests/run_all_tests.sh          # all suites
./tests/run_all_tests.sh --suite fprobe   # one suite only
./tests/run_all_tests.sh --verbose        # per-test output
```

### Test matrix (v2.4.0)

| Suite | File | Tests | Notes |
|-------|------|-------|-------|
| `fsearch` | `test_fsearch.sh` | 35 | Pattern normalization, backend fallback, output modes |
| `fcontent` | `test_fcontent.sh` | 30 | rg passthrough, pipeline, caps |
| `ftree` | `test_ftree.sh` | 48 | Recon, snapshot, JSON schema, depth |
| `fmap` | `test_fmap.sh` | 80 | 50 languages (v2.3.x expansion), dedup, imports, Markdown |
| `fread` | `test_fread.sh` | 84 | Range, head/tail, around, symbol, stdin, image/PDF media, budget skip, error contract |
| `memory-ingest` | `test_memory_ingest.sh` | 4 | ShieldCortex helper: empty/malformed payload, missing config, timeout |
| `fcase` | `test_fcase.sh` | 25 | Lifecycle, SQLite, import, handoff, busy-timeout |
| `fedit` | `test_fedit.sh` | 38 | Dry-run, apply, symbol scope, batch, line-range |
| `fmetrics` | `test_fmetrics.sh` | 20 | Import, stats, predict, clean, learning loop |
| `fprobe` | `test_fprobe.sh` | 25 | scan, strings, window, binary formats, self-check |
| `freplay` | `test_freplay.sh` | 14 | record, show, list, JSON schema |
| `fs` | `test_fs.sh` | 18 | Unified dispatch, ranking, scope, JSON output |
| `pipelines` | `test_pipelines.sh` | 22 | End-to-end cross-tool pipeline tests |
| `mcp_rendering` | `test_mcp_rendering.sh` | 16 | Pixel-perfect MCP display, dev mode, ANSI |
| `mcp_parity` | `mcp/structured-parity.test.mjs` | 45 | MCP envelope shape, schema flags, error path, media content blocks |
| `install` | `test_install.sh` | 12 | Installer, PATH, self-check, version |

**Total: ~516 tests across 16 suites.** All suites must pass green before any release.

Exit codes: `0` = all pass, `1` = failures (count printed), `2` = suite not found.

---

## Changelog

### v2.4.0 (2026-04-29)

`fread` ships first-class image and PDF reading. Auto-detects PNG/JPEG/GIF/WEBP and PDF inputs, routes through a Python media engine, emits proper MCP image content blocks per the 2025-11-25 spec. Plus consolidated April PR work: `fmap` 50-language support, `fbash` structured MCP renderer + async background jobs, CLI header bloat stripped (-50% line count), `fmetrics` learning-loop telemetry, `fprobe` binary-param escape decoding.

**`fread` media (PR #38):**
- **Images**: PNG/JPEG/GIF/WEBP with auto-resize loop targeting a token budget. Pillow primary, stdlib fallback.
- **PDFs**: Text extraction (default), page render mode (`--render --pages 1:5`, capped at 10 pages without `--max-pages`), metadata mode (`--meta-only`).
- **Backends**: PyMuPDF primary, Poppler fallback. Engine probes both at import time.
- **Memory ingest**: Successful media reads write a structured `ingest_payload` to ShieldCortex via a detached, best-effort spawn (3-second timeout, never blocks `fread`). Opt out via `FSUITE_MEMORY_INGEST=0` or `--no-ingest`.
- **New flags**: `--render`, `--pages`, `--meta-only`, `--no-resize`, `--max-pages`, `--max-tokens`, `--no-ingest`.

**MCP adapter:**
- New `formatExecError` helper extracted from `cli()` — error paths no longer respawn `fread` on failure (PR #38 round-2 fix).
- `fread` MCP schema exposes all 7 media flags. Agents drive image/PDF reading directly.
- Media files emit MCP `{type:"image", data, mimeType}` content blocks (top-level, not nested in text).

**Status contract fixes (`fread`):**
- Budget-blocked media now records `files[].status="budget_skipped"` (was incorrectly `read`); skips memory ingest.
- Engine errors (`BACKEND_MISSING`, `INVALID_PAGE_RANGE`, `PDF_ENCRYPTED`) now record `files[].status="media_error"` alongside `errors[]`.

**`fmap` (PR #27, #30):**
- Expanded from 18 → 50 languages. Test suite green across all.
- Async MCP background-job support for fmap on large repos.

**`fbash` (PR #27, #33):**
- Structured colored MCP renderer (matches fbash CLI output exactly).
- Background job support: `background:true`, `poll`, `list_jobs`. Token-budgeted output.

**`fmetrics` (PR #37):**
- Learning-loop telemetry. Combo recommendations, run-time prediction refinement, history queries by class/tool.

**`fprobe` (PR #24):**
- MCP layer now decodes escape sequences in binary `--pattern` and `--replacement` params. Lets agents target raw byte values without bash quoting headaches.

**CLI rendering (PR #34):**
- Header bloat stripped across all pretty renderers — ~50% line count reduction in MCP output, no semantic loss.

**Optional dependencies (new):**
- `python3-pil` (Pillow) — image read/resize
- `pymupdf` — primary PDF backend
- `poppler-utils` — PDF fallback (`pdftotext`, `pdftoppm`)

**Tests:**
- `test_fread.sh` expanded 42 → 84 (16 new media tests + budget skip + error contract regression test)
- `test_memory_ingest.sh` (4 tests) added for ShieldCortex helper
- `mcp/structured-parity.test.mjs` expanded to 45 (+ schema media flags + formatExecError envelope)

---

### v2.3.0 (2026-03-29)

`fs` unified search orchestrator ships. MCP rendering overhauled for pixel-perfect output. Review fixes applied across two rounds.

**New tools:**
- **`fs`**: Unified search orchestrator (MCP-only) — dispatches `ftree`, `fsearch`, `fmap`, and `fcontent` in one call; returns ranked, typed results with confidence scores and `tools_used` metadata
- **`freplay`**: Derivation replay — records investigation steps (command + note), shows ordered replay chains, supports `record|show|list` subcommands and JSON output

**Rendering and display:**
- **`fedit`**: Full display overhaul — pixel-perfect unified diff rendering in MCP context; line numbers preserved in preview; `--lines` mode (`--lines 71:73 --with "..."`) for direct line-range replacement without text anchors
- **MCP dev mode**: `FSUITE_DEV=1` env var enables verbose MCP trace output for server-side debugging without affecting client-facing JSON contracts
- **Pixel-perfect rendering**: All tools emit clean ANSI-free output in non-TTY/MCP contexts; pretty mode renders correctly in Claude Code tool output panels

**Review fixes (rounds 1 + 2):**
- `fread`: `--symbol` resolution now disambiguates same-name symbols across multiple files when scope is a directory
- `fedit`: `--lines` range validation rejects inverted ranges (`end < start`) with a clear error before any file mutation
- `fprobe`: `strings` mode defaults to `--min-len 4`; `window` mode validates offset + size does not exceed file size
- `fcase`: `next_move` update no longer clobbers evidence records added in the same session
- `fs`: Tie-breaking in ranking now favors `symbol` hits over `content` hits at equal confidence

**Tests:**
- `test_fs.sh` (18 tests), `test_freplay.sh` (14 tests), `test_mcp_rendering.sh` (16 tests) added
- Full suite: 14 suites, ~425 tests, all green

---

### v2.2.0 (2026-03-29)

`fprobe` binary recon and `fedit --lines` mode ship. MCP rendering stabilized at 10-tool baseline.

**New tools:**
- **`fprobe`**: Binary reconnaissance — `strings`, `scan`, and `window` subcommands; zero new dependencies (`file`, `strings`, `xxd`/`od`); structured JSON output with binary detection, entropy, section table, and offset-addressed windows
- 25-test suite `test_fprobe.sh` covering all three subcommands, format variants, and self-check

**New features:**
- **`fedit --lines`**: Line-range replacement mode — specify `--lines START:END --with "content"` to replace an exact line range without needing a text anchor; safe on files with duplicate anchor strings
- **MCP rendering**: `fread`, `fedit`, `fprobe` output renders correctly in Claude Code MCP tool panels — ANSI stripping in non-TTY, consistent line-number formatting, no bleed between tool outputs

**Tests:**
- Full suite: 10 suites, ~350 tests, all green

---

### v2.1.2

Hotfix for `fcase` SQLite busy-timeout regression introduced in v2.1.1.

- **fix(fcase):** preserve clean JSON/stdout contracts while enabling SQLite timeout behavior when the sqlite frontend supports it
- **fix(fcase):** avoid `PRAGMA busy_timeout=5000` result leakage in shim-based sqlite environments that printed `5000` ahead of JSON payloads
- **fix(fcase):** restore healthy `fcase` command behavior for `init`, `status`, `next`, `note`, `handoff`, `export`, and structured imports
- **test:** full suite restored green, including `25/25` `fcase` tests and `10/10` passing test suites overall

---

### v2.1.1

`fmap` adds Markdown as its 18th language. Headings, fences, frontmatter, and links are mapped with CommonMark-compliant rules.

- **feat(fmap):** Markdown language support (`.md`, `.markdown`, `.mdx`)
- **feat(fmap):** ATX headings h1–h6, Setext headings with paragraph accumulation, fenced code block suppression, YAML frontmatter suppression, inline links and reference link definitions
- **test:** 21 markdown-specific regression tests, 122 total tests passing

---

### v2.1.0

`fmap` expands to cover Kotlin and Android-lite (manifest + layout XML). `fcase` and `freplay` ship.

**New language and ecosystem coverage:**
- **`fmap`**: Kotlin symbol mapping for `.kt` and `.kts`
- **`fmap`**: Android-lite mapping for `AndroidManifest.xml` and `res/layout/*.xml`

**New tools:**
- **`fcase`**: Investigation lifecycle ledger — SQLite-backed, typed targets/evidence/hypotheses, explicit `fmap` and `fread` JSON imports, append-only history, handoff packets
- **`freplay`**: Derivation replay (initial version — `record` + `show` only; `list` added in v2.3.0)

**Packaging:** suite version unified at `2.1.0`

---

### v2.0.0

`fedit` grows into a symbol-first, preflighted batch editor. Suite gains the full scout-map-read-edit loop at project scale.

**New editing surface:**
- **`fedit`**: symbol shortcuts `--function`, `--class`, `--method`, `--import`, `--constant`, `--type`
- **`fedit`**: preflighted batch patching via `--targets-file` with `paths` or `fmap-json` target formats
- **`fedit`**: batch JSON envelope for headless agents, including per-target status and combined diffs

**Workflow hardening:**
- **`fsearch` / `fcontent`**: default-ignore steering for dependency/build trees
- **`fsuite`**: new suite-level guide command for first-contact workflow orientation
- **Packaging**: suite version unified at `2.0.0`

---

### v1.9.0

`fedit` introduced — suite becomes scout-map-read-edit-measure.

- **`fedit`**: preview-first surgical patching with exact replace, before/after anchors, and dry-run diffs by default
- **`fedit`**: preconditions (`--expect`, `--expect-sha256`), structured JSON error output, binary-target rejection
- **`fedit`**: `fmap`-driven `--symbol` / `--symbol-type` scoping
- **Tests**: dedicated `fedit` suite; 9 test suites total

---

### v1.8.0

`fread` introduced — suite becomes scout-map-read-measure.

- **`fread`**: budgeted file reading with range, head/tail, around-line, around-pattern, stdin path mode, and unified-diff mode
- **`fread`**: token estimation, binary detection, truncation `next_hint`, and structured JSON output
- **Tests**: 7 test suites total

---

### v1.7.0 and earlier

See `docs/ftree.md` and the `v1.6.x` entries below for full per-tool history.

---

### v1.6.1

Hardening and review fixes for `fmap`. No new features.

- `.h` header heuristic: dispatches to C++ when C++ constructs are detected
- Locale pinning: `LC_ALL=C` set at script top
- Performance: replaced O(n²) string concatenation in `extract_symbols` with temp file streaming
- JSON escape: handles `\b`, `\f`, and all control chars (U+0000–U+001F) via perl
- Safety: `--` before filenames in grep calls; missing-value checks on all option flags
- CodeRabbit review: **0 findings** on this release

---

### v1.6.0

**Introduces `fmap` — code cartography.** Fourth tool in the suite, completing the recon pipeline from "what's here" to "what's inside the code."

- **`fmap`**: 12 languages (Python, JavaScript, TypeScript, Rust, Go, Java, C, C++, Ruby, Lua, PHP, Bash/Shell)
- **`fmap`**: directory scan, single file, stdin pipe (`fsearch -o paths '*.py' | fmap -o json`)
- **`fmap`**: pretty, paths, JSON output — grep-only, zero new dependencies
- **Tests**: 6 suites, 259 tests total

---

### v1.5.0

Suite-wide enhancements: `duration_ms` in JSON output, smart project name inference, `--project-name` override, `--no-lines` for snapshot JSON, `--tool` flag for `fmetrics predict`, telemetry flag accumulation.

---

### ftree v1.2.0 — v1.0.1

See [docs/ftree.md](../ftree.md) for full version history and JSON schema notes.
