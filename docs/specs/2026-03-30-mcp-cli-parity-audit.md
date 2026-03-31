# MCP And CLI Parity Audit

Date: 2026-03-30
Branch: `codex/mcp-cli-parity-audit`
Base: `codex/upstream-rollup-pr` at `20bed9e`
Live probe project: `/home/player2vscpu/Desktop/FAE-Knowledge-Base`

## Goal

fsuite is supposed to be agent-first tooling.

That means:

- the CLI stays the source of truth
- MCP should mirror the CLI instead of shrinking it
- JSON-capable tools should return machine-readable MCP results, not only ANSI text

## Current Status On This Branch

This branch closes the major parity gaps found in the initial audit.

- CLI exposes 11 operational tools:
  - `ftree`, `fsearch`, `fcontent`, `fmap`, `fread`, `fcase`, `fedit`, `fmetrics`, `freplay`, `fprobe`, `fs`
- MCP now exposes all 11 CLI tools plus one convenience wrapper:
  - `ftree`, `fsearch`, `fcontent`, `fmap`, `fread`, `fcase`, `fedit`, `fwrite`, `fmetrics`, `freplay`, `fprobe`, `fs`
- JSON-capable MCP tools now preserve structured results instead of discarding them.
- `freplay` is now registered in MCP.
- `fmetrics` now runs in JSON mode through MCP.
- `fcase` now returns structured JSON for the actions that already support JSON natively.

## Capability Matrix

| Tool | CLI | MCP | CLI JSON support | MCP structured result on this branch | Notes |
| --- | --- | --- | --- | --- | --- |
| `ftree` | Yes | Yes | Yes | Yes | Snapshot JSON preserved |
| `fsearch` | Yes | Yes | Yes | Yes | Already strong before this branch |
| `fcontent` | Yes | Yes | Yes | Yes | Match metadata preserved |
| `fmap` | Yes | Yes | Yes | Yes | Symbol maps preserved |
| `fread` | Yes | Yes | Yes | Yes | Chunk metadata preserved |
| `fcase` | Yes | Yes | Mixed by action | Yes for JSON-capable actions | `note` remains text-only because CLI does too |
| `fedit` | Yes | Yes | Yes | Yes | Dry-run/apply payload preserved |
| `fwrite` | No | Yes | N/A | Yes | MCP convenience wrapper over `fedit` |
| `fmetrics` | Yes | Yes | Yes | Yes | Stats/history/combo JSON now preserved |
| `freplay` | Yes | Yes | Mixed by action | Yes for JSON-capable actions | Newly exposed in MCP |
| `fprobe` | Yes | Yes | Yes | Yes | Top-level arrays normalized to `structuredContent.items` |
| `fs` | Yes | Yes | Yes | Yes | Already strong before this branch |

## What We Verified

### CLI proof points

- `ftree --snapshot -o json /home/player2vscpu/Desktop/FAE-Knowledge-Base`
  - Returns structured `snapshot.recon` and `snapshot.tree`.
- `fsuite`
  - Confirms the public CLI tool list includes `freplay`.
- `freplay --help`
  - Confirms `freplay` is a first-class CLI tool with `record`, `show`, `list`, `export`, `verify`, `promote`, and `archive`.

### MCP proof points

Live MCP tests now verify structured results for:

- `ftree`
- `fcontent`
- `fmap`
- `fread`
- `fprobe`
- `fedit`
- `fwrite`
- `fmetrics`
- `fcase` JSON-capable actions
- `freplay`
- `fs`
- `fsearch`

## What Changed

### 1. Generic MCP JSON preservation

The shared `cli()` helper now:

- detects valid JSON CLI output
- keeps human-readable `content`
- adds `structuredContent` whenever JSON is present

That means wrappers no longer fetch JSON and then throw it away.

### 2. `freplay` is now part of MCP

The missing CLI tool is now exposed through MCP with support for:

- `record`
- `show`
- `list`
- `export`
- `verify`
- `promote`
- `archive`

### 3. `fmetrics` now behaves like an agent tool

The MCP wrapper now runs `fmetrics` in JSON mode, so agents get structured telemetry output instead of scraping terminal dashboards.

### 4. `fcase` is more consistent for agents

For actions where the CLI already supports JSON, MCP now requests JSON and preserves the envelope as structured content.

`fcase note` stays text-only because the CLI action itself does not accept output flags.

### 5. `fprobe` array results are normalized

`fprobe` can emit top-level JSON arrays. MCP tool results behave more reliably when structured content is record-shaped, so top-level arrays are normalized as:

- `structuredContent.items = [...]`

The raw JSON still remains visible in text content when needed.

## Recommended Agent Path

With the current branch, the agent-first path is finally coherent:

1. Use `fs` or `fsearch` to narrow.
2. Use `ftree` for directory scouting.
3. Use `fmap` and `fread` for code understanding.
4. Use `fedit` or `fwrite` for changes.
5. Use `fcase` and `freplay` for continuity and replay.
6. Use `fmetrics` for telemetry-backed decisions.

That is one mental model across CLI and MCP instead of two competing products.

## Remaining Gaps Worth Considering

This branch fixes the core parity problem, but there are still improvements worth making:

- Add explicit output schemas for more tools instead of relying on generic structured content.
- Add prettier MCP renderers for `fmetrics` and `freplay` JSON modes so humans get richer summaries alongside the structured payload.
- Decide whether `fprobe` should keep the `items` normalization long-term or whether the MCP layer should gain first-class support for top-level arrays.
- Audit any future CLI JSON additions so MCP preserves them by default instead of requiring one-off patches.

## Verification On This Branch

Fresh MCP verification:

- `bash tests/test_mcp.sh`
  - `16/16` passing

Focused structured parity verification:

- `node --test mcp/structured-parity.test.mjs`
  - `9/9` passing

Regression verification:

- `node --test mcp/fcase-note.test.mjs mcp/fs-auto-intent.test.mjs`
  - `4/4` passing

Syntax verification:

- `node --check mcp/index.js`

## Bottom Line

Before this branch, MCP exposed only part of fsuite's agent value.

On this branch, MCP is much closer to what an agent-first wrapper should be:

- same core operational graph as the CLI
- structured JSON preserved across discovery, reading, editing, replay, and metrics
- missing `freplay` surface filled in
- lower learning curve for agents because the wrapper now respects the CLI contract instead of fighting it
