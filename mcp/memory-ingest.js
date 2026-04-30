#!/usr/bin/env node
// memory-ingest.js — Phase 4: MCP stdio client that writes fread ingest_payload to ShieldCortex.
// Invoked detached by fread bash: node mcp/memory-ingest.js < payload.json
// All output goes to stderr (parent redirects to ~/.cache/fsuite/memory-ingest.log).

import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";
import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

// ── Logging ────────────────────────────────────────────────────────────────
const PREFIX = "[memory-ingest]";
const log = (level, msg) =>
  process.stderr.write(`${new Date().toISOString()} ${PREFIX} ${level}: ${msg}\n`);

// ── Read + validate payload from stdin ────────────────────────────────────
async function readStdin() {
  return new Promise((resolve, reject) => {
    const chunks = [];
    process.stdin.on("data", (c) => chunks.push(c));
    process.stdin.on("end", () => resolve(Buffer.concat(chunks).toString("utf8")));
    process.stdin.on("error", reject);
  });
}

function parsePayload(raw) {
  const trimmed = raw.trim();
  if (!trimmed) throw new Error("invalid payload");
  let p;
  try { p = JSON.parse(trimmed); } catch { throw new Error("invalid payload"); }
  const { title, category, content, tags } = p;
  if (!title || !category || !content || !Array.isArray(tags) || !tags.length)
    throw new Error("invalid payload");
  return p;
}

// ── Resolve ShieldCortex command ──────────────────────────────────────────
function resolveFromMcpServersConfig(path) {
  const cfg = JSON.parse(readFileSync(path, "utf8"));
  const servers = cfg?.mcpServers || {};
  const nameRe = /^(memory|shieldcortex|shield.cortex)$/i;
  for (const [key, val] of Object.entries(servers)) {
    if (nameRe.test(key) && val?.command) {
      const extraArgs = Array.isArray(val.args) ? val.args : [];
      return { cmd: val.command, args: extraArgs };
    }
  }
  return null;
}

function resolveCmd() {
  // 1. Explicit env override
  const envCmd = process.env.FSUITE_SHIELDCORTEX_CMD;
  if (envCmd && envCmd.trim()) {
    const parts = envCmd.trim().split(/\s+/);
    return { cmd: parts[0], args: parts.slice(1) };
  }

  // 2. which shieldcortex-mcp
  const which = spawnSync("which", ["shieldcortex-mcp"], { encoding: "utf8" });
  const whichOut = (which.stdout || "").trim();
  if (whichOut) return { cmd: whichOut, args: [] };

  // 3. Claude MCP config locations → mcpServers entry
  for (const cfgPath of [
    join(homedir(), ".claude", "mcp.json"),
    join(homedir(), ".claude.json"),
  ]) {
    try {
      const resolved = resolveFromMcpServersConfig(cfgPath);
      if (resolved) return resolved;
    } catch { /* not present or malformed */ }
  }

  // 4. ~/.codex/config.toml — tiny regex extractor
  try {
    const toml = readFileSync(join(homedir(), ".codex", "config.toml"), "utf8");
    // Match [mcp_servers.<name>] sections where name matches
    const sectionRe = /^\[mcp_servers\.([^\]]+)\]/gm;
    const nameRe = /^(memory|shieldcortex|shield.cortex)$/i;
    let m;
      while ((m = sectionRe.exec(toml)) !== null) {
        // Strip surrounding quotes from quoted TOML keys, e.g. ["shield.cortex"]
        const key = m[1].replace(/^["']|["']$/g, "");
        if (!nameRe.test(key)) continue;
      // Grab the block after the section header until the next [
      const block = toml.slice(m.index + m[0].length).split(/^\[/m)[0];
      const cmdMatch = block.match(/^command\s*=\s*"([^"]+)"/m);
if (cmdMatch) {
  const argsRegex = /args\s*=\s*\[([^\]]*)\]/m;
  const am = block.match(argsRegex);
  let args = [];
  if (am) {
    // Parse args with quote-awareness instead of naive split
    const argsStr = am[1];
    const tokens = [];
    let current = '';
    let inQuote = false;
    let quoteChar = '';
    let escaped = false;
    for (let i = 0; i < argsStr.length; i++) {
      const c = argsStr[i];
      if (escaped) {
        current += c;
        escaped = false;
      } else if (c === '\\') {
        escaped = true;
      } else if (!inQuote && (c === '"' || c === "'")) {
        inQuote = true;
        quoteChar = c;
      } else if (inQuote && c === quoteChar) {
        inQuote = false;
        quoteChar = '';
      } else if (!inQuote && c === ',') {
        if (current.trim()) tokens.push(current.trim());
        current = '';
      } else {
        current += c;
      }
    }
    if (current.trim()) tokens.push(current.trim());
    args = tokens.map(s => s.replace(/^["']|["']$/g, '')).filter(Boolean);
  }
  return { cmd: cmdMatch[1], args };
}
    }
  } catch { /* not present */ }

  return null;
}

// ── Core ingest ──────────────────────────────────────────────────────────
let activeClient = null;

async function doIngest(payload) {
  const resolved = resolveCmd();
  if (!resolved) {
    log("warn", "unreachable: no command configured");
    return;
  }

  const transport = new StdioClientTransport({ command: resolved.cmd, args: resolved.args });
  const client = new Client({ name: "fsuite-memory-ingest", version: "1.0.0" });
  activeClient = client;

  try {
    await client.connect(transport);

    // Extract hash tag and SHA256 for dedupe
    const hashTag = (payload.tags || []).find((t) => /^hash:[a-f0-9]{1,}$/i.test(t)) || null;
    const sha256Match = (payload.content || "").match(/SHA256:\s+([a-f0-9]{64})/i);
    const sha256 = sha256Match ? sha256Match[1] : null;

    // Dedupe via recall
    if (hashTag) {
      let recalled = null;
      try {
        recalled = await client.callTool({
          name: "recall",
          arguments: {
            mode: "search",
            query: payload.title,
            tags: [hashTag],
            limit: 1,
            ...(process.env.FSUITE_PROJECT_NAME ? { project: process.env.FSUITE_PROJECT_NAME } : {}),
            ...(payload.source !== undefined ? { source: payload.source } : {}),
          },
        });
      } catch { /* recall failure is non-fatal — fall through to write */ }

      if (recalled) {
        // The result is a CallToolResult — content is an array of { type, text } blocks
        const text = (recalled.content || [])
          .filter((c) => c.type === "text")
          .map((c) => c.text)
          .join("\n");
        // Hit if any returned memory body contains the full SHA256
        if (sha256 && text.includes(sha256)) {
          log("warn", `dedupe-hit: skipping ${payload.title}`);
          return;
        }
      }
    }

    // Write via remember
    await client.callTool({ name: "remember", arguments: payload });
    log("info", `wrote: ${payload.title}`);
  } finally {
    activeClient = null;
    await client.close().catch(() => {});
  }
}

// ── Entry point ───────────────────────────────────────────────────────────
(async () => {
  let payload;
  try {
    const raw = await readStdin();
    payload = parsePayload(raw);
  } catch (err) {
    log("error", err.message || "invalid payload");
    process.exit(1);
  }

  try {
    await Promise.race([
      doIngest(payload),
      new Promise((_, reject) =>
        setTimeout(() => reject(new Error("timeout")), 3000)
      ),
    ]);
    process.exit(0);
  } catch (err) {
    if (activeClient) {
      try { await activeClient.close(); } catch {}
      activeClient = null;
    }
    const msg = err?.message || String(err);
    log(msg === "timeout" ? "warn" : "error", msg);
    process.exit(1);
  }
})();
