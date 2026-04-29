---
title: Chain Combinations
description: Canonical fsuite tool chains — pipe contracts, MCP equivalents, and which sequences actually work.
sidebar:
  order: 4
---

## The pipe contract

fsuite tools communicate via two pipe-friendly output modes:

- **`-o paths`** — one file path per line (the pipe currency)
- **`-o json`** — structured data for programmatic decisions

The rule: **producers** output paths, **consumers** read paths from stdin.

### Producers (output file paths)

| Tool | Flag | What it produces |
|------|------|-----------------|
| `fsearch` | `-o paths` | File paths matching a glob/name pattern |
| `fcontent` | `-o paths` | File paths containing a literal string |

### Consumers (read paths from stdin)

| Tool | Stdin behavior | Notes |
|------|---------------|-------|
| `fcontent` | Reads paths, searches inside them | up to 2000 files |
| `fmap` | Reads paths, maps symbols | up to 2000 files |
| `fread` | `--from-stdin --stdin-format=paths` | up to `--max-files` |
| `fedit` | `--targets-file -` | batch patches |

### Non-pipe tools (arg-based)

`fread`, `fedit`, `ftree`, `fprobe`, `fcase`, `freplay`, `fmetrics` take arguments, not stdin pipe lists. They sit at chain endpoints, not in the middle.

<div class="fs-mcp-note">
  <h4>⚠ MCP CALLERS — SEQUENTIAL LIMIT</h4>
  <p>If you call fsuite tools <b>through the MCP server</b>, every call is <b>sequential</b>. The MCP protocol does not pipe — the agent constructs the chain by calling tools one at a time and reusing prior results.</p>
  <p><b>Escape hatch:</b> install fsuite as native Debian package or shell scripts and pipe directly. You can keep <code>fbash</code> as your MCP entry point and run real Unix pipes inside it: <code>fbash "fsearch -o paths '*.py' | fmap -o json"</code>. That unlocks combination calls instead of being trapped in sequential MCP.</p>
</div>

## Valid 2-command chains

| Chain | Purpose | Example |
|-------|---------|---------|
| `fsearch \| fcontent` | Find files by name, search inside | `fsearch -o paths '*.py' src \| fcontent "def authenticate"` |
| `fsearch \| fmap` | Find files, map symbols | `fsearch -o paths '*.rs' src \| fmap -o json` |
| `fcontent \| fmap` | Find files containing text, map symbols | `fcontent -o paths "TODO" src \| fmap -o json` |
| `fcontent \| fcontent` | Progressive narrowing | `fcontent -o paths "import" src \| fcontent "authenticate"` |

## Valid 3-command chains

<div class="fs-pipeline-v2">
  <div class="fs-pipeline-row">
    <span class="fs-pn">fsearch</span>
    <span class="fs-arr"></span>
    <span class="fs-pn">fcontent</span>
    <span class="fs-arr"></span>
    <span class="fs-pn fs-pn-keystone">fmap</span>
  </div>
  <div class="fs-pipeline-undernote">
    <span><code>fsearch -o paths '*.py' | fcontent -o paths "class" | fmap -o json</code></span>
  </div>
</div>

## Valid 4-command chains

```bash
fsearch -o paths '*.sh' \
  | fcontent -o paths "function" \
  | fmap -o json \
  | python3 -c "..."
```

Tested: produced 1956 symbols from the fsuite repo in one pipeline.

## Investigation patterns

### Pattern 1 — "What uses this function?"
```bash
fcontent -o paths "authenticate" src | fmap -o json
```

### Pattern 2 — "Find all Python tests and see what they test"
```bash
fsearch -o paths 'test_*.py' tests | fmap -o json
```

### Pattern 3 — "Which configs mention this key?"
```bash
fsearch -o paths '*.json' . | fcontent "api_key"
```

### Pattern 4 — Full investigation chain

<div class="fs-pipeline-v2">
  <div class="fs-pipeline-row">
    <span class="fs-pn fs-pn-entry">fcase init</span>
    <span class="fs-arr"></span>
    <span class="fs-pn">ftree</span>
    <span class="fs-arr"></span>
    <span class="fs-pn fs-pn-bridge">fsearch │ fcontent</span>
    <span class="fs-arr"></span>
    <span class="fs-pn fs-pn-keystone">fmap</span>
    <span class="fs-arr"></span>
    <span class="fs-pn">fread</span>
    <span class="fs-arr"></span>
    <span class="fs-pn">fedit</span>
    <span class="fs-arr"></span>
    <span class="fs-pn fs-pn-entry">fcase resolve</span>
  </div>
</div>

```bash
ftree --snapshot -o json /project
fsearch -o paths '*.rs' src | fcontent -o paths "pub fn" | fmap -o json
fread src/auth.rs --symbol authenticate
fcase init auth-fix --goal "Fix authenticate bypass"
fedit src/auth.rs --function authenticate --replace "return true" --with "return verify(token)"
fmetrics stats
```

### Pattern 5 — Binary recon
```bash
fprobe scan binary --pattern "renderTool" --context 300
fprobe window binary --offset 112730723 --before 50 --after 200
fprobe strings binary --filter "diffAdded"
```

## fcase lifecycle

<div class="fs-fcase">
  <div class="fs-fcase-state"><b>init</b><span>open the seam</span></div>
  <span class="fs-arr"></span>
  <div class="fs-fcase-state"><b>note</b><span>capture evidence</span></div>
  <span class="fs-arr"></span>
  <div class="fs-fcase-state"><b>handoff</b><span>pass to next agent</span></div>
  <span class="fs-arr"></span>
  <div class="fs-fcase-state fs-fcase-end"><b>resolve</b><span>close + archive</span></div>
</div>

## Invalid chains (and why)

| Chain | Why it fails |
|-------|-------------|
| `fread \| anything` | fread outputs file content, not paths |
| `fedit \| anything` | fedit outputs diffs, not paths |
| `ftree \| fcontent` | ftree outputs a tree, not paths |
| `fmap \| fread` | fmap outputs symbol data, not paths |
| `fprobe \| anything` | fprobe outputs JSON/text, not paths |
| `fcase \| anything` | fcase outputs investigation state, not paths |
