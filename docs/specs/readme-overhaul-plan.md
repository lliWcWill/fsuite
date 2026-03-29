# README Overhaul Plan

> Generated 2026-03-29 by planning agent. Target: archive-grade documentation.
> Current: 1951 lines. Target: ~2850 lines (46% expansion).

## New Sections Required

1. **fprobe** (~80 lines) — binary recon tool docs
2. **freplay** (~120 lines) — derivation replay docs
3. **Chain Combination Guide** (~250 lines) — THE centerpiece, compatibility matrix
4. **MCP Adapter Layer** (~120 lines) — setup, rendering, registered tools
5. **Binary Patching** (~60 lines) — fpatch-claude-mcp
6. **Dev Mode** (~40 lines) — source resolution, fast iteration
7. **Rendering Architecture** (~80 lines) — Monokai colors, diff backgrounds

## Sections to Update

- Tool table: 8 → 10 tools + fpatch
- fedit: add --lines mode documentation
- Cheat sheet: add fprobe, freplay, fedit --lines, fpatch entries
- Quick reference flags: add new tools
- Output formats: add JSON schemas for new tools
- Installation: add MCP setup
- Changelog: add v2.2.0 entry
- TESTING.md cross-reference

## Gotchas Flagged

1. fedit CLI defaults to dry-run, MCP defaults to apply=true — MUST document
2. fwrite is MCP-only virtual tool — NOT a CLI command
3. Changelog says v2.1.2 latest but source is v2.3.0
4. AGENTS.md companion update needed (separate task)

## Implementation Phases

Phase 1: Structural (tool table, TOC, flow diagrams)
Phase 2: New tool docs (fprobe, freplay, fedit --lines)
Phase 3: Chain Combination Guide
Phase 4: MCP + rendering docs
Phase 5: Cascading updates (cheat sheet, flags, schemas)
Phase 6: Cross-reference verification

## Chain Combination Data

Already saved at: docs/specs/chain-combinations.md (validated via live pipe tests)
