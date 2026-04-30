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

  fread <image>                                  Read image with auto-resize (PNG/JPEG/GIF/WEBP)
  fread <pdf>                                    Extract PDF text (default mode)
  fread <pdf> --render --pages 1:5               Rasterize PDF pages to images
  fread <pdf> --meta-only                        PDF metadata only

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

MEDIA OPTIONS (image + PDF reading)
  --render                    PDF: render pages as images instead of extracting text
  --pages START:END           PDF: page range (1-based, inclusive)
  --meta-only                 Return metadata only (no body / base64)
  --no-resize                 Image: emit raw base64 without auto-resize
  --max-pages N               PDF render: raise 10-page cap
  --max-tokens N              Image: resize-loop token budget (default 6000)
  --no-ingest                 Skip ShieldCortex memory ingest for this read

NOTES
  Budget precedence: token_budget > max_bytes > max_lines
  --symbol is strict: exactly one exact symbol match succeeds; ambiguous or missing matches fail
  --stdin-format=unified-diff reads NEW-side hunk ranges from +++ path and @@ +start,count
```

## See also

- [fsuite mental model](/fsuite/getting-started/mental-model/) — how fread fits into the toolchain
- [Cheat sheet](/fsuite/reference/cheatsheet/) — one-line recipes for every tool
- [View source on GitHub](https://github.com/lliWcWill/fsuite/blob/master/fread)
