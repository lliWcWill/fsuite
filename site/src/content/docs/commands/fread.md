---
title: 📖 fread
description: Budgeted reading with symbol + line-range resolution
sidebar:
  order: 7
---

## Budgeted reading with symbol + line-range resolution

`fread` is part of the fsuite toolkit — a set of fourteen CLI tools built for AI coding agents.

## Help output

The content below is the **live** `--help` output of `fread`, captured at build time from the tool binary itself. It cannot drift from the source — regenerating the docs regenerates this section.

```text
fread — budgeted file reading with line numbers, token estimates, and pipeline integration.

USAGE
  fread <file>                                   Read file (uncapped by default)
  fread <file> --symbol authenticate             Read one exact symbol block
  fread <dir> --symbol authenticate              Resolve one exact symbol within a directory scope
  fread <file> -r 120:220                        Line range
  fread <file> --head 50                         First N lines
  fread <file> --tail 30                         Last N lines
  fread <file> --around-line 150 -B 5 -A 10      Context around line
  fread <file> --around "pattern" -B 5 -A 10     Context around literal pattern
  fread --paths "~/.codex/auth.json,~/.config/codex/auth.json"   Try paths in order
  ... | fread --from-stdin --stdin-format=paths
  git diff | fread --from-stdin --stdin-format=unified-diff -B 3 -A 10

OPTIONS
  --paths P1,P2,...           Comma-separated file paths to try in order (first existing wins)
  -r, --lines START:END       Line range (1-based, inclusive)
  --head N                    Read first N lines
  --tail N                    Read last N lines
  --around-line N             Context around specific line number
  --around PATTERN            Context around first literal pattern match
  --all-matches               With --around: include all matches up to caps
  --symbol NAME               Read exactly one exact symbol match within file or directory scope
  -B, --before N              Lines before (default 5)
  -A, --after N               Lines after (default 10)
  --max-lines N               Cap total emitted lines (0/default = uncapped)
  --max-bytes N               Cap total emitted bytes (0/default = uncapped)
  --token-budget N            Cap by estimated tokens (conservative bytes/3)
  --no-truncate, --full       Disable line, byte, and token caps
  --max-files N               Cap files from stdin paths mode (default 10)
  --from-stdin                Read input from stdin
  --stdin-format FMT          Required with --from-stdin: paths|unified-diff
  --force-text                Read even if binary is detected
  -o, --output FMT            pretty (default), json, paths
  -q, --quiet                 Suppress pretty headers
  --project-name NAME         Override telemetry project name
  --self-check                Verify dependencies
  --install-hints             Print install commands
  --version                   Print version
  -h, --help                  Show help

NOTES
  Budget precedence: token_budget > max_bytes > max_lines
  --symbol is strict: exactly one exact symbol match succeeds; ambiguous or missing matches fail
  --stdin-format=unified-diff reads NEW-side hunk ranges from +++ path and @@ +start,count
```

## Media reading (images and PDFs)

`fread` now reads images (PNG/JPEG/GIF/WEBP) and PDFs natively. Previously these
file types were skipped as binary. The engine (`fread-media.py`) dispatches to
PyMuPDF when available and falls back to Poppler (`pdftotext` + `pdftoppm`)
automatically.

### New flags

| Flag | Applies to | Description |
|---|---|---|
| `--render` | PDF | Rasterize pages to JPEG instead of extracting text |
| `--pages X:Y` | PDF | 1-indexed inclusive page range (e.g. `1:3`) |
| `--meta-only` | PDF, image | Return only metadata; no content or base64 |
| `--no-resize` | Image | Emit raw base64; refuses if over token budget |
| `--max-pages N` | PDF render | Allow more than the default 10-page cap |
| `--max-tokens N` | Image | Token budget for resize loop (default 6000) |
| `--token-budget N` | PDF text | Total token cap for extracted text (default 25000) |
| `--no-ingest` | All media | Skip the post-call ShieldCortex memory ingest |

### Output modes

**Pretty mode** (default) shows a one-line summary; base64 is never dumped to the
terminal. Example: `screenshot.png — 1024x768 JPEG, ~4200 tokens`.

**JSON mode** (`-o json`) adds a top-level `media_payload` field alongside the
standard fread envelope. The field contains the verbatim engine output including
dimensions, page count, text, and (for images) base64 data.

For PDFs, **text extraction is the default** and is cheaper than rendering.
Rasterization is opt-in via `--render`.

### Token cost guidance

| Mode | Approximate tokens |
|---|---|
| Image (auto-resized) | ~6000 or under |
| Image (`--meta-only`) | < 100 |
| PDF text per page | ~200–500 |
| PDF page rendered | ~1500 |
| PDF (`--meta-only`) | < 100 |

### Backend selection

`fread-media.py` uses **PyMuPDF** when installed and falls back to
**Poppler** (`pdftotext` + `pdftoppm`). Override with the environment variable:

```bash
FREAD_MEDIA_FORCE_BACKEND=poppler fread report.pdf   # force Poppler
FREAD_MEDIA_FORCE_BACKEND=pymupdf fread report.pdf   # force PyMuPDF
```

Set to an unrecognized value (e.g. `banana`) to verify your config — the engine
errors with `BACKEND_MISSING`.

### Memory MCP integration

After every successful media read, `fread` spawns a detached Node helper
(`memory-ingest.js`) that writes a structured memory to ShieldCortex via MCP
stdio. The write is best-effort with a 3-second timeout; failures are logged to
`~/.cache/fsuite/memory-ingest.log` and never block the read result.

Disable via environment variable or flag:

```bash
FSUITE_MEMORY_INGEST=0 fread sensitive.png   # env opt-out
fread sensitive.png --no-ingest              # flag opt-out
```

### Encrypted PDFs

Encrypted PDFs surface as a `PDF_ENCRYPTED` error. The engine refuses to return
empty or partial results — it errors explicitly rather than silently returning
nothing. Password-protected PDFs are not currently supported.

### Examples

```bash
# PDF text extraction (default)
fread invoice.pdf

# PDF metadata only (page count, encryption flag)
fread invoice.pdf --meta-only

# Rasterize first two pages to JPEG
fread diagram.pdf --render --pages 1:2

# Image — auto-resize to token budget
fread screenshot.png

# Image — dimensions only, no base64
fread screenshot.png --meta-only

# Image — raw base64 (refuses if over budget)
fread huge.png --no-resize

# Force Poppler backend
FREAD_MEDIA_FORCE_BACKEND=poppler fread report.pdf

# Skip ShieldCortex memory ingest
FSUITE_MEMORY_INGEST=0 fread sensitive.png
```

## See also

- [fsuite mental model](/fsuite/getting-started/mental-model/) — how fread fits into the toolchain
- [Cheat sheet](/fsuite/reference/cheatsheet/) — one-line recipes for every tool
- [View source on GitHub](https://github.com/lliWcWill/fsuite/blob/master/fread)
