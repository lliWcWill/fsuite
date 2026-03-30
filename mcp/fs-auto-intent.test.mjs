import test from "node:test";
import assert from "node:assert/strict";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";

const testFile = fileURLToPath(import.meta.url);
const mcpDir = dirname(testFile);
const repoRoot = resolve(mcpDir, "..");

async function callFs(args) {
  const transport = new StdioClientTransport({
    command: process.execPath,
    args: ["./index.js"],
    cwd: mcpDir,
    stderr: "pipe",
  });
  const client = new Client({
    name: "fsuite-mcp-test",
    version: "0.0.0",
  });

  let stderr = "";
  transport.stderr?.on("data", (chunk) => {
    stderr += chunk.toString();
  });

  try {
    await client.connect(transport);
    await client.listTools();
    return await client.callTool({ name: "fs", arguments: args });
  } catch (error) {
    if (stderr && error instanceof Error) {
      error.message += `\nserver stderr:\n${stderr}`;
    }
    throw error;
  } finally {
    await client.close();
  }
}

test("fs MCP auto intent resolves ambiguous multi-word content queries", async () => {
  const result = await callFs({
    query: "navigation handoff",
    path: repoRoot,
    intent: "auto",
  });

  assert.ok(!result.isError);
  assert.equal(result.structuredContent.intent, "auto");
  assert.equal(result.structuredContent.resolved_intent, "content");
});

test("fs MCP auto intent resolves scoped single-word content queries", async () => {
  const result = await callFs({
    query: "MCP",
    path: repoRoot,
    scope: "*.md",
    intent: "auto",
  });

  assert.ok(!result.isError);
  assert.equal(result.structuredContent.intent, "auto");
  assert.equal(result.structuredContent.resolved_intent, "content");
});
