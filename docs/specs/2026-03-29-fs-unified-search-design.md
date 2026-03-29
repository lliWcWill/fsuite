# fs — Unified Search Orchestrator

> v1 design spec. Frozen 2026-03-29 by Claude + Codex + Player3.

## Problem

fsuite has strong search primitives (fsearch for files, fcontent for content, fmap for symbols).
But agents face **dispatch friction**: every search requires the agent to decide which tool to call,
format the right flags, and often chain 2-3 calls to get an actionable answer. That decision tax
burns tokens, adds latency, and creates hesitation.

`fs` absorbs the "which tool do I call?" decision. One tool, one call, bounded auto-enrichment.

## What fs Is

An **agent-first reconnaissance orchestrator**. A thin routing layer over existing fsuite primitives
that classifies search intent, selects the optimal chain, executes it within hard budgets, and
returns a ranked, enriched result with an explicit next-step recommendation.

## What fs Is NOT

- Not a replacement for fsearch/fcontent/fmap (primitives stay registered in MCP alongside fs)
- Not a semantic search engine (no embeddings, no NLP, no query expansion)
- Not a compound query language (no `"X in *.py"` parsing)
- Not a new search backend (fs calls existing tools, it doesn't reimplement them)

## Architecture

```
                  MCP client (Claude Code / agent)
                           |
                  MCP: fs tool registration
                    (thin, calls fs -o json)
                           |
                     fs  (bash shim)
                           |
                   fs-engine.py
                  (routing / chaining / budgeting / ranking)
                           |
              +------+------+------+------+
              |      |      |      |      |
           fsearch fcontent  fmap  fread  ftree
```

### File Layout

| File | Role |
|------|------|
| `fs` | Bash entrypoint. Parses args, calls `fs-engine.py`, formats output. |
| `fs-engine.py` | Core logic: intent classification, chain execution, budget enforcement, result ranking, JSON output. |
| `mcp/index.js` | Thin MCP registration. Calls `fs -o json`. Renders result. |

### Engine Contract

Both CLI and MCP use the same engine. Input is JSON on stdin or CLI args. Output is JSON on stdout.
This eliminates CLI/MCP drift by construction.

```
CLI:  fs "authenticate" --scope "*.py" --path /repo
      → internally: echo '{"query":"authenticate","scope":"*.py","path":"/repo"}' | python3 fs-engine.py

MCP:  fs(query: "authenticate", scope: "*.py", path: "/repo")
      → internally: execFile("fs", ["-o", "json", "authenticate", "--scope", "*.py", "--path", "/repo"])
```

## API

### Input

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `query` | string | yes | — | The search intent: glob, literal string, identifier, filename |
| `path` | string | no | `.` | Search root directory |
| `scope` | string | no | — | Glob filter to narrow file set before searching (e.g. `"*.py"`, `"*.rs"`) |
| `intent` | enum | no | `auto` | `auto \| file \| content \| symbol` |

### Output

```json
{
"query": "authenticate",
"path": "/repo",
"scope": "*.py",
"intent": "auto",
"resolved_intent": "content",
"route_reason": "single lowercase word, ambiguous — scope present so fsearch narrows first",
"route_confidence": "low",
"selected_chain": ["fsearch", "fcontent"],
"hits": [
  {
    "file": "/repo/src/auth.py",
    "matches": [
      { "line": 42, "text": "def authenticate(token, secret):" },
      { "line": 87, "text": "    return authenticate(refresh_token, key)" }
    ],
    "match_count": 2
  }
],
"truncated": false,
"budget": {
  "candidate_files": 12,
  "enriched_files": 0,
  "time_ms": 184
},
"next_hint": {
  "tool": "fread",
  "args": { "path": "/repo/src/auth.py", "around": "authenticate" }
}
}
```
### Output Field Contracts

| Field | Always present | Description |
|-------|---------------|-------------|
| `query` | yes | Echo of input query |
| `path` | yes | Echo of resolved search root |
| `scope` | if provided | Echo of scope filter |
| `intent` | yes | Echo of input intent |
| `resolved_intent` | yes | What the router actually chose: `file \| content \| symbol` |
| `route_reason` | yes | Human-readable explanation of why the router chose this chain |
| `route_confidence` | yes | `high \| medium \| low` (see contract below) |
| `selected_chain` | yes | Ordered list of fsuite tools executed |
| `hits` | yes | Array of result objects (shape varies by resolved_intent) |
| `truncated` | yes | Whether results were capped by budget |
| `budget` | yes | Execution stats: candidate_files, enriched_files, time_ms |
| `next_hint` | yes (nullable) | Recommended follow-up tool call, or null if results are complete |

## Routing Rules

### Intent Classification (deterministic heuristics)

| Signal | Resolved Intent | Confidence | Chain |
|--------|----------------|------------|-------|
| Has glob chars (`*`, `?`) | `file` | high | fsearch |
| Bare extension (`.py`, `log`, `.rs`) | `file` | high | fsearch |
| Looks like a filename (`auth.py`, `Makefile`, `package.json`) | `file` | high | fsearch |
| camelCase token (`renderTool`, `htmlToAnsi`) | `symbol` | high | fcontent → fmap |
| PascalCase token (`McpServer`, `AuthError`) | `symbol` | high | fcontent → fmap |
| snake_case token (`verify_token`, `parse_args`) | `symbol` | high | fcontent → fmap |
| SCREAMING_CASE (`DIFF_COLORS`, `MAX_FILES`) | `symbol` | medium | fcontent → fmap |
| Multi-word phrase (`error loading config`) | `content` | high | fcontent |
| Quoted or contains spaces | `content` | high | fcontent |
| Single lowercase word (`authenticate`, `render`) | `content` | low | fcontent |

### Scope Interaction

When `scope` is provided, fsearch runs first to narrow the file set, then the resolved intent chain
runs against only those files.

| Scope present? | Resolved intent | Actual chain |
|----------------|----------------|--------------|
| no | `file` | fsearch |
| no | `content` | fcontent |
| no | `symbol` | fcontent → fmap |
| yes | `file` | fsearch with scope as glob, query filters within results |
| yes | `content` | fsearch → fcontent (scoped) |
| yes | `symbol` | fsearch → fcontent → fmap (scoped) |

### Explicit Intent Override

When `intent` is not `auto`, skip classification entirely. Run the chain for that intent directly.
`route_reason` says `"explicit intent=<value>"`. `route_confidence` is always `high`.

## Fanout Budget (v1 Hard Caps)

| Stage | Cap | On exceed |
|-------|-----|-----------|
| Candidate files from search | 50 | Truncate to top 50 by relevance, set `truncated: true` |
| Files sent to fmap enrichment | 15 | Take top 15 by match density |
| Total wall time | 10s | Abort enrichment, return search-only results |
| Symbols per file (fmap) | 100 | fmap's own truncation applies |

**Graceful degradation:** If enrichment budget is exceeded, the response downgrades to search-only
results with `truncated: true`. `next_hint` points to a manual fmap call on the top candidates.
The agent always gets something useful, never a timeout error.

## route_confidence Contract

Coarse, mechanical, three values. No opaque math.

| Condition | Value |
|-----------|-------|
| Explicit `intent` override | `high` |
| Clear heuristic signal (glob, extension, strong case pattern) | `high` |
| Moderate signal (single identifier, no scope) | `medium` |
| Ambiguous (single common word, no case signal, no scope) | `low` |

Agents can use `route_confidence: "low"` as a signal to override with explicit `intent` on retry.

## next_hint Logic

| Resolved intent | next_hint |
|----------------|-----------|
| `file` (no scope) | `fcontent` on first hit (agent probably wants to search inside) |
| `file` (with scope) | `fread` on first hit |
| `content` | `fread(path, around: "<query>")` on top match |
| `symbol` | `fread(path, symbol: "<top_symbol>")` on top-ranked symbol |
| Any, zero hits | `null` |

## Hit Shapes

### file intent hits

```json
{
  "file": "/repo/src/auth.py",
  "size_bytes": 4200,
  "modified": "2026-03-29T12:00:00Z"
}
```

### content intent hits

```json
{
  "file": "/repo/src/auth.py",
  "matches": [
    { "line": 42, "text": "def authenticate(token, secret):" },
    { "line": 87, "text": "    return authenticate(refresh_token, key)" }
  ],
  "match_count": 2
}
```

### symbol intent hits

```json
{
  "file": "/repo/src/auth.py",
  "matches": [
    { "line": 42, "text": "def authenticate(token, secret):", "type": "definition" }
  ],
  "symbols": ["authenticate", "verify_token", "AuthError"],
  "match_count": 1
}
```

## MCP Registration

fs is registered as a new tool alongside all existing primitives. Existing tools are NOT removed.

**structuredContent + outputSchema:** Binary analysis of Claude Code v2.1.87 confirms the client
fully supports `structuredContent` with `outputSchema` validation. Observed behavior (v2.1.87,
not an SDK guarantee): if a tool declares `outputSchema` but omits `structuredContent`, Claude
Code throws an error. The client propagates structured data
through `mcpMeta` for typed rendering. Since the fs engine already outputs JSON, we return both
`content` (human-readable text summary) and `structuredContent` (the full JSON result) from v1.

```javascript
server.registerTool("fs", {
  description: "Unified search orchestrator. One call to find files, content, or symbols. " +
    "Auto-classifies query intent and chains the right fsuite tools. " +
    "Returns ranked hits with enrichment and a recommended next step.",
  inputSchema: z.object({
    query: z.string().describe("Search intent: glob, literal string, or identifier"),
    path: z.string().optional().describe("Search root directory (default: cwd)"),
    scope: z.string().optional().describe("Glob filter to narrow file set, e.g. '*.py'"),
    intent: z.enum(["auto", "file", "content", "symbol"]).optional()
      .describe("Override auto-classification. Default: auto"),
  }),
  outputSchema: z.object({
    query: z.string(),
    path: z.string(),
    scope: z.string().optional(),
    intent: z.enum(["auto", "file", "content", "symbol"]),
    resolved_intent: z.enum(["file", "content", "symbol"]),
    route_reason: z.string(),
    route_confidence: z.enum(["high", "medium", "low"]),
    selected_chain: z.array(z.string()),
    hits: z.array(z.object({}).passthrough()),
    truncated: z.boolean(),
    budget: z.object({
      candidate_files: z.number(),
      enriched_files: z.number(),
      time_ms: z.number(),
    }),
    next_hint: z.object({
      tool: z.string(),
      args: z.object({}).passthrough(),
    }).nullable(),
  }),
}, async ({ query, path, scope, intent }) => {
  // fs bypasses cli() because cli() wraps in { content } and we need raw JSON
  // for structuredContent. Use run() + resolveTool() directly (same primitives cli() uses).
  const args = ["-o", "json", query];
  if (path) args.push("--path", path);
  if (scope) args.push("--scope", scope);
  if (intent) args.push("--intent", intent);
  const { stdout } = await run(resolveTool("fs"), args, EXEC_OPTS);
  const parsed = JSON.parse(stdout);
  const chain = parsed.selected_chain?.join(" → ") || "?";
  const hitCount = parsed.hits?.length || 0;
  const summary = `${parsed.resolved_intent} (${parsed.route_confidence}) via ${chain}\n` +
    `  ${parsed.route_reason}\n` +
    `  ${hitCount} hits, ${parsed.budget?.time_ms || 0}ms`;
  return {
    content: [{ type: "text", text: summary }],
    structuredContent: parsed,
  };
});
```

## CLI Interface

```
fs [OPTIONS] <query> [path]

OPTIONS
  -s, --scope GLOB     Glob filter for file narrowing (e.g. "*.py")
  -i, --intent MODE    Override: auto|file|content|symbol (default: auto)
  -o, --output MODE    pretty|json (default: pretty for tty, json for pipe)
  -p, --path PATH      Search root (default: .). Overrides positional [path].
  --max-candidates N   Override candidate file cap (default: 50)
  --max-enrich N       Override enrichment file cap (default: 15)
  --timeout N          Override wall time cap in seconds (default: 10)
  -h, --help           Show help
  --version            Show version

EXAMPLES
  fs "authenticate"                    # auto-route, search cwd
  fs "*.py" /repo                      # file intent (glob detected)
  fs "renderTool" --scope "*.js"       # symbol in JS files
  fs "error loading" --intent content  # explicit content search
  fs "TODO" --scope "*.rs" -o json     # JSON output, scoped to Rust
```

## v1 Non-Goals

- No compound query language (`"X in *.py"` — use the `scope` field)
- No `terrain` intent (no clean deterministic chain behind it)
- No embeddings or semantic search
- No opaque confidence math
- No replacement of primitive MCP tools
- No interactive mode
- No caching layer

## v1.1 Candidates (post-ship evaluation)

- `terrain` intent if a clean ftree + fsearch chain emerges
- Result caching for repeated queries within a session
- `--deep` flag for unbounded enrichment (agent explicitly opts in)
- Compound query sugar in CLI (`fs "authenticate in *.py"`)
- Parallel execution of chain stages where possible

## Testing Strategy

- Unit tests for intent classification (heuristic rules, edge cases)
- Unit tests for scope interaction (with/without scope x each intent)
- Integration tests for each chain (file, content, symbol, scoped variants)
- Budget enforcement tests (verify truncation at caps)
- Graceful degradation tests (timeout simulation, empty results)
- CLI parity tests (verify CLI and MCP produce identical JSON for same input)

## Dependencies

- Python 3.8+ (engine)
- fsearch, fcontent, fmap (must be in PATH or resolved via FSUITE_SRC_DIR)
- Existing fsuite telemetry integration
