// End-to-end test for renderFbashResult via real MCP roundtrip.
// Exercises all six cases from fcase #359:
//   1. simple success (exit=0, stdout)
//   2. silent failure (exit!=0, no output)
//   3. mixed streams (stdout + stderr + non-zero exit)
//   4. background job
//   5. stderr-only error
//   6. truncation of long stdout

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

function stripAnsi(str) {
  return str.replace(/\x1b\[[0-9;]*m/g, "");
}

async function withClient(run, env = {}) {
  const transport = new StdioClientTransport({
    command: process.execPath,
    args: ["./index.js"],
    cwd: mcpDir,
    env: { ...process.env, ...env },
    stderr: "pipe",
  });
  const client = new Client({
    name: "fsuite-mcp-fbash-render-test",
    version: "0.0.0",
  });

  let stderr = "";
  transport.stderr?.on("data", (chunk) => { stderr += chunk.toString(); });

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

async function callFbash(args) {
  return withClient((client) => client.callTool({ name: "fbash", arguments: args }));
}

// ──────────────────────────────────────────────────────────────
// 1. Simple success
// ──────────────────────────────────────────────────────────────
test("fbash renderer: simple success shows fbash header, exit=0, stdout", async () => {
  const result = await callFbash({ command: "printf hello" });
  assert.ok(!result.isError, textContent(result));
  const text = textContent(result);
  const plain = stripAnsi(text);

  // Header zone
  assert.ok(plain.includes("fbash"), "header must contain 'fbash'");
  assert.ok(plain.includes("exit=0"), "success header must show exit=0");
  assert.match(plain, /\d+ms/, "header must include duration in ms");

  // Stdout zone
  assert.ok(plain.includes("hello"), "stdout 'hello' must appear in rendered text");

  // ANSI gold present (256-color fg 220 family: escape sequence w/ 38;2)
  assert.match(text, /\x1b\[38;2;255;215;0m/, "gold GOLD fg escape must appear for fbash header");

  // No stderr zone should be rendered
  assert.ok(!plain.toLowerCase().includes("stderr"), "no stderr label should appear on success");

  // Must not return structuredContent (renderer contract)
  assert.ok(!result.structuredContent, "rendered tools must NOT return structuredContent");
});

// ──────────────────────────────────────────────────────────────
// 2. Silent failure
// ──────────────────────────────────────────────────────────────
test("fbash renderer: silent failure shows red exit, (no output) marker, no stderr block", async () => {
  const result = await callFbash({ command: "false" });
  assert.ok(!result.isError, textContent(result));
  const text = textContent(result);
  const plain = stripAnsi(text);

  assert.ok(plain.includes("exit=1"), "failure header must show exit=1");
  assert.ok(plain.includes("(no output)"), "silent failure must show (no output) marker");
  assert.ok(!plain.toLowerCase().includes("stderr:"), "no stderr label when stderr is empty");

  // Red ANSI for exit code
  assert.match(text, /\x1b\[38;2;255;80;80m/, "red escape must appear for non-zero exit");
});

// ──────────────────────────────────────────────────────────────
// 3. Mixed streams
// ──────────────────────────────────────────────────────────────
test("fbash renderer: mixed stdout+stderr+exit=2 renders all three zones", async () => {
  const result = await callFbash({
    command: 'sh -c "echo OUT; echo ERR >&2; exit 2"',
  });
  assert.ok(!result.isError, textContent(result));
  const plain = stripAnsi(textContent(result));

  assert.ok(plain.includes("exit=2"), "header must show exit=2");
  assert.ok(plain.includes("OUT"), "stdout content must appear");
  assert.ok(plain.includes("ERR"), "stderr content must appear");
  assert.ok(plain.includes("stderr"), "stderr label must appear when stderr non-empty");
});

// ──────────────────────────────────────────────────────────────
// 4. Background job
// ──────────────────────────────────────────────────────────────
test("fbash renderer: background job shows [bg job ...] callout, no stdout/stderr blocks", async () => {
  const result = await callFbash({
    command: "sleep 0.5",
    background: true,
  });
  assert.ok(!result.isError, textContent(result));
  const plain = stripAnsi(textContent(result));

  assert.ok(plain.includes("bg job"), "background callout must appear");
  assert.match(plain, /fbash_\d+_\d+/, "background job id must appear");
  // No exit code in header for background start
  assert.ok(!plain.includes("exit="), "no exit= badge for backgrounded jobs");
  // Must not render a (silent success) marker
  assert.ok(!plain.includes("silent success"), "no silent-success marker for bg jobs");
});

// ──────────────────────────────────────────────────────────────
// 5. Stderr-only error
// ──────────────────────────────────────────────────────────────
test("fbash renderer: stderr-only error renders stderr block + red exit", async () => {
  const result = await callFbash({ command: "ls /nonexistent-path-xxxxxyz" });
  assert.ok(!result.isError, textContent(result));
  const plain = stripAnsi(textContent(result));

  assert.match(plain, /exit=[12]/, "non-zero exit must appear");
  assert.ok(plain.toLowerCase().includes("stderr"), "stderr label must appear");
  assert.ok(plain.includes("No such file") || plain.includes("cannot access"),
    "stderr body must mention the missing path");
});

// ──────────────────────────────────────────────────────────────
// 6. Long output truncation
// ──────────────────────────────────────────────────────────────
test("fbash renderer: long stdout is truncated with '... N more lines' trailer", async () => {
  const result = await callFbash({
    command: "seq 1 500",
    max_lines: 500,
  });
  assert.ok(!result.isError, textContent(result));
  const plain = stripAnsi(textContent(result));

  // Should include early lines
  assert.ok(plain.includes("\n  1\n") || plain.startsWith("  1\n") || plain.includes("  1"),
    "first line of seq must appear");
  // Truncation trailer
  assert.match(plain, /\.\.\. \d+ more lines/, "truncation trailer must appear for long stdout");
  // Should not actually contain all 500 lines — sample a very late number
  assert.ok(!plain.includes("\n  499\n"), "far-later line should have been truncated");
});

// ──────────────────────────────────────────────────────────────
// Bonus: fallback when JSON doesn't match fbash shape
// (tested indirectly by confirming header is always gold+bold)
// ──────────────────────────────────────────────────────────────
test("fbash renderer: header is always bold gold", async () => {
  const result = await callFbash({ command: "printf ok" });
  const text = textContent(result);
  // BOLD escape + 256-color gold = \x1b[1m followed by \x1b[38;2;255;215;0m (in either order)
  assert.match(text, /\x1b\[1m/, "bold escape must be in output");
  assert.match(text, /\x1b\[38;2;255;215;0m/, "gold fg escape must be in output");
});
