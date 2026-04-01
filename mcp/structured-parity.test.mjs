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

function stripAnsi(str) {
  return str.replace(/\x1b\[[0-9;]*m/g, "");
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

// ─── Tools WITH renderers return pretty ANSI in content[text] ───
// structuredContent is intentionally omitted to work around the
// Claude Code 2.1.88 outputSchema safeParse bug.

test("ftree MCP returns pretty-rendered content", async () => {
  const fixture = makeFixture();
  try {
    const result = await callTool("ftree", {
      path: fixture,
      snapshot: true,
      depth: 2,
    });

    assert.ok(!result.isError, textContent(result));
    const text = textContent(result);
    assert.ok(text.length > 0, "ftree should return non-empty content");
    assert.ok(!result.structuredContent, "rendered tools should not return structuredContent");
  } finally {
    rmSync(fixture, { recursive: true, force: true });
  }
});

test("fcontent MCP returns pretty-rendered content", async () => {
  const fixture = makeFixture();
  try {
    const result = await callTool("fcontent", {
      query: "agent",
      path: fixture,
      max_matches: 5,
    });

    assert.ok(!result.isError, textContent(result));
    const text = stripAnsi(textContent(result));
    assert.ok(text.includes("notes.md"), "fcontent should mention the matched file");
    assert.ok(!result.structuredContent, "rendered tools should not return structuredContent");
  } finally {
    rmSync(fixture, { recursive: true, force: true });
  }
});

test("fmap MCP returns pretty-rendered content", async () => {
  const fixture = makeFixture();
  try {
    const result = await callTool("fmap", {
      path: join(fixture, "src"),
    });

    assert.ok(!result.isError, textContent(result));
    const text = stripAnsi(textContent(result));
    assert.ok(text.includes("greet"), "fmap should mention the greet function");
    assert.ok(!result.structuredContent, "rendered tools should not return structuredContent");
  } finally {
    rmSync(fixture, { recursive: true, force: true });
  }
});

test("fread MCP returns pretty-rendered content", async () => {
  const fixture = makeFixture();
  try {
    const result = await callTool("fread", {
      path: join(fixture, "src", "sample.py"),
      head: 20,
    });

    assert.ok(!result.isError, textContent(result));
    const text = stripAnsi(textContent(result));
    assert.ok(text.includes("def greet"), "fread should contain the function definition");
    assert.ok(!result.structuredContent, "rendered tools should not return structuredContent");
  } finally {
    rmSync(fixture, { recursive: true, force: true });
  }
});

// ─── Tools WITHOUT renderers still return structuredContent ───

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

test("fprobe MCP decode_escapes decodes escape sequences", async () => {
  const fixture = makeFixture();
  try {
    // Create a fixture with literal escape sequence text (not an actual ESC byte)
    const escapeFile = join(fixture, "escapes.bin");
    writeFileSync(escapeFile, Buffer.from("\\x1b[31mRED\\x1b[0m", "utf-8"));

    // Test 1: With decode_escapes: false (default), search for literal "\x1b" (4 ASCII chars)
    const resultLiteral = await callTool("fprobe", {
      action: "scan",
      file: escapeFile,
      pattern: "\\x1b",
      decode_escapes: false,
    });

    assert.ok(!resultLiteral.isError, textContent(resultLiteral));
    assert.ok(Array.isArray(resultLiteral.structuredContent?.items), "should return items array");
    assert.equal(resultLiteral.structuredContent.items.length, 2, "should find two literal \\x1b sequences");

    // Test 2: With decode_escapes: true, pattern "\\x1b" decodes to ESC byte (0x1b)
    // The file contains literal "\x1b" not the actual byte, so scan should NOT match
    const resultDecoded = await callTool("fprobe", {
      action: "scan",
      file: escapeFile,
      pattern: "\\x1b",
      decode_escapes: true,
    });

    assert.ok(!resultDecoded.isError, textContent(resultDecoded));
    assert.ok(Array.isArray(resultDecoded.structuredContent?.items), "should return items array");
    assert.equal(resultDecoded.structuredContent.items.length, 0, "should NOT find ESC byte (0x1b) in literal \\x1b text");
  } finally {
    rmSync(fixture, { recursive: true, force: true });
  }
});

test("fprobe patch mode with decode_escapes \\uNNNN escape sequences", async () => {
  const fixture = makeFixture();
  try {
    // Create a binary fixture with literal "HELLO" (5 bytes)
    const patchFile = join(fixture, "patch-escape.bin");
    writeFileSync(patchFile, Buffer.from("HELLO"));

    // Test 1: Patch with \\uNNNN escapes that decode to same length as target
    // Target: "HELLO" (5 bytes)
    // Replacement: "\\u0048\\u0045\\u004c\\u004c\\u004f" → decodes to "HELLO" (5 bytes)
    // Same length, so patch should succeed
    const resultUnicode = await callTool("fprobe", {
      action: "patch",
      file: patchFile,
      target: "HELLO",
      replacement: "\\u0048\\u0045\\u004c\\u004c\\u004f",
      decode_escapes: true,
    });

    assert.ok(!resultUnicode.isError, `patch with \\uNNNN should not error: ${textContent(resultUnicode)}`);
    assert.ok(resultUnicode.structuredContent?.patched === 1, "should report 1 successful patch for \\uNNNN escapes");

    // Test 2: Patch with mismatched byte lengths should fail
    // Target: "XX" (2 bytes)
    // Replacement: "\\x41" → decodes to "A" (1 byte)
    // Different lengths, so patch should fail with length mismatch error
    const resultMismatch = await callTool("fprobe", {
      action: "patch",
      file: patchFile,
      target: "XX",
      replacement: "\\x41",
      decode_escapes: true,
    });

    assert.ok(resultMismatch.isError || textContent(resultMismatch).toLowerCase().includes("length"), 
      `patch with mismatched lengths should fail or report error: ${textContent(resultMismatch)}`);
  } finally {
    rmSync(fixture, { recursive: true, force: true });
  }
});

test("fedit and fwrite MCP return pretty-rendered content", async () => {
  const fixture = makeFixture();
  try {
    const editResult = await callTool("fedit", {
      path: join(fixture, "src", "sample.py"),
      replace: "return f\"hello {name}\"",
      with_text: "return f\"hi {name}\"",
      apply: false,
    });

    assert.ok(!editResult.isError, textContent(editResult));
    const editText = textContent(editResult);
    assert.ok(editText.length > 0, "fedit should return non-empty content");
    assert.ok(!editResult.structuredContent, "rendered tools should not return structuredContent");

    const writeResult = await callTool("fwrite", {
      path: join(fixture, "generated.txt"),
      content: "hello agent\n",
      apply: false,
    });

    assert.ok(!writeResult.isError, textContent(writeResult));
    const writeText = textContent(writeResult);
    assert.ok(writeText.length > 0, "fwrite should return non-empty content");
    assert.ok(!writeResult.structuredContent, "rendered tools should not return structuredContent");
  } finally {
    rmSync(fixture, { recursive: true, force: true });
  }
});

test("fmetrics MCP preserves stats JSON as structured content", async () => {
  const result = await callTool("fmetrics", {
    action: "stats",
  });

  assert.ok(!result.isError, textContent(result));
  assert.ok(result.structuredContent, "fmetrics should have structuredContent");
  // tool field is stripped by slimStructuredContent — check tools array instead
  assert.ok(Array.isArray(result.structuredContent.tools), "fmetrics stats should have tools array");
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
