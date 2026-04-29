---
title: Changelog
description: Release history for fsuite.
sidebar:
  order: 3
---

> **TODO:** wire this to the Debian changelog or GitHub releases so it auto-updates. For now, see the [GitHub releases page](https://github.com/lliWcWill/fsuite/releases) or [`debian/changelog`](https://github.com/lliWcWill/fsuite/blob/master/debian/changelog) for the canonical version history.

## [Unreleased] — fread media reading

Added image and PDF reading to fread, replacing the binary-skip path
with a Python engine (`fread-media.py`) that handles PNG/JPEG/GIF/WEBP
and PDFs via PyMuPDF (Poppler fallback).

### Added

- New flags: --render, --pages, --meta-only, --no-resize, --max-pages,
  --max-tokens (image-specific), --token-budget (PDF text total cap),
  --no-ingest
- MCP fread emits image content blocks (mimeType per 2025-11-25 spec)
  for image and PDF render outputs; bypasses cli() for media payloads
- `mcp/memory-ingest.js` — detached, timed (3s) Node helper that writes
  `ingest_payload` to ShieldCortex via MCP stdio; best-effort, never
  blocks fread; supports recall-based dedupe by content hash
- Top-level `"media_payload"` field in fread JSON output for downstream
  parsers
- Error codes: `PDF_ENCRYPTED`, `INVALID_PAGE_RANGE`, `BACKEND_MISSING`,
  `TOKEN_BUDGET_EXCEEDED`, `MISSING_SUBCOMMAND`
- Tests: 16 new `test_fread` cases + `tests/test_memory_ingest.sh`

### Changed

- Binary skip path now runs media_dispatch first; image/PDF files
  are read via `fread-media.py` instead of being skipped
- Token estimates for images now use dimension-based formula
  (`width × height / 750`) per Anthropic vision tokenization

## Recent highlights

- **v3.3.0** — telemetry attribution, shared run-id propagation, full-output controls, analytics rebuilds, and fedit JSON recovery hints
- **v3.2.0** — `fbash` CLI binary added to Debian package
- **v3.1.0** — `fsearch` SIGPIPE handling fix
- **v3.0.x** — `fcase` lifecycle overhaul, `fs` unified search, `freplay` introduction
- **v2.x** — `fmap` 50-language support, `fs-engine.py` refactor
- **v1.x** — Core 14-tool suite

## Migration guides

Coming soon as the project stabilizes its public API surface.
