import test from "node:test";
import assert from "node:assert/strict";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";

import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";

const testFile = fileURLToPath(import.meta.url);
const mcpDir = dirname(testFile);

function textContent(result) {
  return result.content?.map((item) => item.text ?? "").join("\n") ?? "";
}

function makeFixture() {
  const dir = mkdtempSync(join(tmpdir(), "fsuite-mcp-structured-"));
  mkdirSync(join(dir, "src"));
  mkdirSync(join(dir, "docs"));
  writeFileSync(join(dir, "src", "sample.py"), "def greet(name):\n    return f\"hello {name}\"\n");
  writeFileSync(join(dir, "docs", "notes.md"), "# Notes\n\nagent first tooling\n");
  writeFileSync(join(dir, "blob.bin"), Buffer.from([0x00, 0x45, 0x4c, 0x46, 0x66, 0x61, 0x6b, 0x65, 0x61, 0x67, 0x65, 0x6e, 0x74, 0x00]));
  return dir;
}

async function withClient(run) {
  const transport = new StdioClientTransport({
    command: process.execPath,
    args: ["./index.js"],
    cwd: mcpDir,
    stderr: "pipe",
  });
  const client = new Client({
    name: "fsuite-mcp-structured-test",
    version: "0.0.0",
  });

  let stderr = "";
  transport.stderr?.on("data", (chunk) => {
    stderr += chunk.toString();
  });

  try {
    await client.connect(transport);
    await client.listTools();
    return await run(client);
  } catch (error) {
    if (stderr && error instanceof Error) {
      error.message += `\nserver stderr:\n${stderr}`;
    }
    throw error;
  } finally {
    await client.close();
  }
}

async function callTool(name, args) {
  return withClient((client) => client.callTool({ name, arguments: args }));
}

test("ftree MCP preserves snapshot JSON as structured content", async () => {
  const fixture = makeFixture();
  try {
    const result = await callTool("ftree", {
      path: fixture,
      snapshot: true,
      depth: 2,
    });

    assert.ok(!result.isError, textContent(result));
    assert.equal(result.structuredContent.tool, "ftree");
    assert.equal(result.structuredContent.snapshot.tree.path, fixture);
    assert.ok(Array.isArray(result.structuredContent.snapshot.tree.tree_json));
  } finally {
    rmSync(fixture, { recursive: true, force: true });
  }
});

test("fcontent MCP preserves JSON match metadata as structured content", async () => {
  const fixture = makeFixture();
  try {
    const result = await callTool("fcontent", {
      query: "agent",
      path: fixture,
      max_matches: 5,
    });

    assert.ok(!result.isError, textContent(result));
    assert.equal(result.structuredContent.tool, "fcontent");
    assert.deepEqual(result.structuredContent.matched_files, [join(fixture, "docs", "notes.md")]);
  } finally {
    rmSync(fixture, { recursive: true, force: true });
  }
});

test("fmap MCP preserves JSON symbol maps as structured content", async () => {
  const fixture = makeFixture();
  try {
    const result = await callTool("fmap", {
      path: join(fixture, "src"),
    });

    assert.ok(!result.isError, textContent(result));
    assert.equal(result.structuredContent.tool, "fmap");
    assert.equal(result.structuredContent.files[0].symbols[0].type, "function");
  } finally {
    rmSync(fixture, { recursive: true, force: true });
  }
});

test("fread MCP preserves JSON chunks as structured content", async () => {
  const fixture = makeFixture();
  try {
    const result = await callTool("fread", {
      path: join(fixture, "src", "sample.py"),
      head: 20,
    });

    assert.ok(!result.isError, textContent(result));
    assert.equal(result.structuredContent.tool, "fread");
    assert.match(result.structuredContent.chunks[0].content[0], /def greet/);
  } finally {
    rmSync(fixture, { recursive: true, force: true });
  }
});

test("fprobe MCP preserves JSON arrays as structured content", async () => {
  const fixture = makeFixture();
  try {
    const result = await callTool("fprobe", {
      action: "strings",
      file: join(fixture, "blob.bin"),
      filter: "agent",
    });

    assert.ok(!result.isError, textContent(result));
    assert.ok(Array.isArray(result.structuredContent.items));
    assert.equal(result.structuredContent.items[0].text, "ELFfakeagent");
  } finally {
    rmSync(fixture, { recursive: true, force: true });
  }
});

test("fedit and fwrite MCP preserve dry-run JSON as structured content", async () => {
  const fixture = makeFixture();
  try {
    const editResult = await callTool("fedit", {
      path: join(fixture, "src", "sample.py"),
      replace: "return f\"hello {name}\"",
      with_text: "return f\"hi {name}\"",
      apply: false,
    });

    assert.ok(!editResult.isError, textContent(editResult));
    assert.equal(editResult.structuredContent.tool, "fedit");
    assert.equal(editResult.structuredContent.dry_run, true);

    const writeResult = await callTool("fwrite", {
      path: join(fixture, "generated.txt"),
      content: "hello agent\n",
      apply: false,
    });

    assert.ok(!writeResult.isError, textContent(writeResult));
    assert.equal(writeResult.structuredContent.tool, "fedit");
    assert.equal(writeResult.structuredContent.dry_run, true);
  } finally {
    rmSync(fixture, { recursive: true, force: true });
  }
});

test("fmetrics MCP preserves stats JSON as structured content", async () => {
  const result = await callTool("fmetrics", {
    action: "stats",
  });

  assert.ok(!result.isError, textContent(result));
  assert.equal(result.structuredContent.tool, "fmetrics");
  assert.ok(Array.isArray(result.structuredContent.tools));
});

test("fcase MCP preserves JSON envelopes for JSON-capable actions", async () => {
  const slug = `mcp-fcase-json-${Date.now()}`;
  const result = await callTool("fcase", {
    action: "init",
    slug,
    goal: "Verify JSON-capable fcase actions return structured data",
  });

  assert.ok(!result.isError, textContent(result));
  assert.equal(result.structuredContent.case.slug, slug);
});

test("freplay MCP is available and preserves JSON list output", async () => {
  const slug = `mcp-freplay-${Date.now()}`;
  const initResult = await callTool("fcase", {
    action: "init",
    slug,
    goal: "Verify freplay MCP registration",
  });
  assert.ok(!initResult.isError, textContent(initResult));

  const result = await callTool("freplay", {
    action: "list",
    slug,
  });

  assert.ok(!result.isError, textContent(result));
  assert.ok(Array.isArray(result.structuredContent.replays));
});
