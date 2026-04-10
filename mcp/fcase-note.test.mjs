import test from "node:test";
import assert from "node:assert/strict";
import { dirname } from "node:path";
import { fileURLToPath } from "node:url";

import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";

const testFile = fileURLToPath(import.meta.url);
const mcpDir = dirname(testFile);

function textContent(result) {
  return result.content?.map((item) => item.text ?? "").join("\n") ?? "";
}

async function callTool(name, args) {
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
    return await client.callTool({ name, arguments: args });
  } catch (error) {
    if (stderr && error instanceof Error) {
      error.message += `\nserver stderr:\n${stderr}`;
    }
    throw error;
  } finally {
    await client.close();
  }
}

test("fcase MCP note succeeds without appending unsupported output flags", async () => {
  const slug = `mcp-note-${Date.now()}`;
  const initResult = await callTool("fcase", {
    action: "init",
    slug,
    goal: "Verify MCP note wrapper behavior",
  });
  assert.ok(!initResult.isError, textContent(initResult));

  const noteResult = await callTool("fcase", {
    action: "note",
    slug,
    body: "wrapper should not append output flags here",
  });

  assert.ok(!noteResult.isError, textContent(noteResult));
  const noteText = textContent(noteResult);
  assert.match(noteText, /Note saved/);
  assert.match(noteText, new RegExp(slug));
});

test("fcase MCP export uses the CLI's required json output mode", async () => {
  const slug = `mcp-export-${Date.now()}`;
  const initResult = await callTool("fcase", {
    action: "init",
    slug,
    goal: "Verify MCP export wrapper behavior",
  });
  assert.ok(!initResult.isError, textContent(initResult));

  const exportResult = await callTool("fcase", {
    action: "export",
    slug,
  });

  assert.ok(!exportResult.isError, textContent(exportResult));
  const payload = JSON.parse(textContent(exportResult));
  assert.equal(payload.case.slug, slug);
  assert.ok(Array.isArray(payload.events));
});
