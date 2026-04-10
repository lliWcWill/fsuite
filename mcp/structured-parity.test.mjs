import test from "node:test";
import assert from "node:assert/strict";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, rmSync } from "node:fs";
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

async function withClient(run, env = {}) {
  const transport = new StdioClientTransport({
    command: process.execPath,
    args: ["./index.js"],
    cwd: mcpDir,
    env,
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

async function callToolWithEnv(name, args, env) {
  return withClient((client) => client.callTool({ name, arguments: args }), env);
}

// ─── Tools WITH renderers return pretty ANSI in content[text] ───
// With safeParse binary patch, rendered tools return BOTH pretty text AND
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
    assert.ok(!result.structuredContent, "rendered tools must NOT return structuredContent (early return blender)");
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
    assert.ok(!result.structuredContent, "rendered tools must NOT return structuredContent (early return blender)");
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
    assert.ok(!result.structuredContent, "rendered tools must NOT return structuredContent (early return blender)");
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
    assert.ok(!result.structuredContent, "rendered tools must NOT return structuredContent (early return blender)");
  } finally {
    rmSync(fixture, { recursive: true, force: true });
  }
});

// ─── Rendered tools: fprobe + fcase — pretty ANSI, no structuredContent ───

test("fprobe MCP returns pretty-rendered strings output", async () => {
  const fixture = makeFixture();
  try {
    const result = await callTool("fprobe", {
      action: "strings",
      file: join(fixture, "blob.bin"),
      filter: "agent",
    });

    assert.ok(!result.isError, textContent(result));
    assert.ok(!result.structuredContent, "rendered tools must NOT return structuredContent (early return blender)");
    const text = stripAnsi(textContent(result));
    assert.ok(text.includes("agent"), "fprobe strings output should contain the filter match");
  } finally {
    rmSync(fixture, { recursive: true, force: true });
  }
});

test("fprobe MCP patch dry-run renderer reports dry-run counts", async () => {
  const fixture = makeFixture();
  try {
    const patchFile = join(fixture, "patch-dry-run.bin");
    writeFileSync(patchFile, Buffer.from("hello world hello world", "utf-8"));

    const result = await callTool("fprobe", {
      action: "patch",
      file: patchFile,
      target: "hello",
      replacement: "HELLO",
      dry_run: true,
    });

    assert.ok(!result.isError, textContent(result));
    const text = stripAnsi(textContent(result));
    assert.ok(text.includes("Dry run 2 replacements"), `expected dry-run patch count in renderer, got: ${text}`);
    assert.equal(readFileSync(patchFile, "utf-8"), "hello world hello world", "dry-run should not modify the file");
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
    // Scan renderer produces pretty ANSI — check text content, not structuredContent
    const litText = stripAnsi(textContent(resultLiteral));
    assert.ok(litText.includes("2 matches"), "should find two literal \\x1b sequences");

    // Test 2: With decode_escapes: true, pattern "\\x1b" decodes to ESC byte (0x1b)
    // The file contains literal "\x1b" not the actual byte, so scan should NOT match
    const resultDecoded = await callTool("fprobe", {
      action: "scan",
      file: escapeFile,
      pattern: "\\x1b",
      decode_escapes: true,
    });

    assert.ok(!resultDecoded.isError, textContent(resultDecoded));
    const decText = stripAnsi(textContent(resultDecoded));
    assert.ok(decText.includes("0 matches"), "should NOT find ESC byte (0x1b) in literal \\x1b text");
  } finally {
    rmSync(fixture, { recursive: true, force: true });
  }
});

test("fprobe MCP scan renderer labels scan results correctly", async () => {
  const fixture = makeFixture();
  try {
    const scanFile = join(fixture, "scan.bin");
    writeFileSync(scanFile, Buffer.from("prefix_agent_suffix_agent", "utf-8"));

    const result = await callTool("fprobe", {
      action: "scan",
      file: scanFile,
      pattern: "agent",
    });

    assert.ok(!result.isError, textContent(result));
    const text = stripAnsi(textContent(result));
    assert.ok(text.includes("fprobe scan | 2 matches"), `expected scan header, got: ${text}`);

    const emptyResult = await callTool("fprobe", {
      action: "scan",
      file: scanFile,
      pattern: "missing",
    });

    assert.ok(!emptyResult.isError, textContent(emptyResult));
    const emptyText = stripAnsi(textContent(emptyResult));
    assert.ok(emptyText.includes("fprobe scan | 0 matches"), `expected empty scan header, got: ${emptyText}`);
  } finally {
    rmSync(fixture, { recursive: true, force: true });
  }
});

test("fprobe MCP decode_escapes patches high bytes as raw bytes", async () => {
  const fixture = makeFixture();
  try {
    const patchFile = join(fixture, "patch-high-byte.bin");
    writeFileSync(patchFile, Buffer.from([0x41, 0x80, 0x42]));

    const result = await callTool("fprobe", {
      action: "patch",
      file: patchFile,
      target: "\\x80",
      replacement: "\\u0081",
      decode_escapes: true,
    });

    assert.ok(!result.isError, `high-byte patch should not error: ${textContent(result)}`);
    const text = stripAnsi(textContent(result));
    assert.ok(text.includes("Patched 1 replacement"), `expected patched count in renderer, got: ${text}`);
    assert.deepEqual([...readFileSync(patchFile)], [0x41, 0x81, 0x42], "decoded escapes should patch raw bytes, not UTF-8 code points");
  } finally {
    rmSync(fixture, { recursive: true, force: true });
  }
});

test("fprobe patch mode with decode_escapes — control byte survives MCP path", async () => {
  const fixture = makeFixture();
  try {
    // Create binary with 5-byte target "ABCDE" followed by filler
    const patchFile = join(fixture, "patch-escape.bin");
    writeFileSync(patchFile, Buffer.from("ABCDE_padding_ABCDE"));

    // Test 1: Patch "ABCDE" with \u001b (ESC) + printable chars via decode_escapes
    // Replacement: "\\u001bXYZ!" decodes to ESC + "XYZ!" = 5 bytes, same as target
    // This proves the ACTUAL control byte (0x1b) survives MCP -> execFile -> CLI
    const result = await callTool("fprobe", {
      action: "patch",
      file: patchFile,
      target: "ABCDE",
      replacement: "\\u001bXYZ!",
      decode_escapes: true,
    });

    assert.ok(!result.isError, `patch with control byte should not error: ${textContent(result)}`);
    // Patch renderer produces pretty ANSI — check text for "Patched" or replacement count
    const patchText = stripAnsi(textContent(result));
    assert.ok(patchText.includes("replacement") || patchText.includes("Patched"), "should report at least 1 patch with ESC byte replacement");

    // Verify the file actually contains the ESC byte (0x1b)
    const patched = readFileSync(patchFile);
    assert.ok(patched.includes(0x1b), "patched file should contain ESC byte (0x1b)");

    // Test 2: Raw NUL bytes should survive the hex transport too.
    const nulFile = join(fixture, "nul-test.bin");
    writeFileSync(nulFile, Buffer.from([0x5a, 0x00, 0x5a]));
    const nulResult = await callTool("fprobe", {
      action: "patch",
      file: nulFile,
      target: "\\x00",
      replacement: "\\x01",
      decode_escapes: true,
    });

    assert.ok(!nulResult.isError, `patch with raw NUL should succeed via hex transport: ${textContent(nulResult)}`);
    const nulText = stripAnsi(textContent(nulResult));
    assert.ok(nulText.includes("Patched 1 replacement"), `expected patched count for NUL byte patch, got: ${nulText}`);
    assert.deepEqual([...readFileSync(nulFile)], [0x5a, 0x01, 0x5a], "decoded NUL should patch as raw byte, not be rejected");
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
    assert.ok(!editResult.structuredContent, "rendered tools must NOT return structuredContent (early return blender)");

    const writeResult = await callTool("fwrite", {
      path: join(fixture, "generated.txt"),
      content: "hello agent\n",
      apply: false,
    });

    assert.ok(!writeResult.isError, textContent(writeResult));
    const writeText = textContent(writeResult);
    assert.ok(writeText.length > 0, "fwrite should return non-empty content");
    assert.ok(!writeResult.structuredContent, "rendered tools must NOT return structuredContent (early return blender)");
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

test("fmetrics MCP preserves nested per-run fields in history", async () => {
  const fixture = makeFixture();
  try {
    const seedResult = await callTool("fcontent", {
      query: "agent",
      path: fixture,
      max_matches: 5,
    });
    assert.ok(!seedResult.isError, textContent(seedResult));

    const result = await callTool("fmetrics", {
      action: "history",
      limit: 5,
    });

    assert.ok(!result.isError, textContent(result));
    assert.ok(Array.isArray(result.structuredContent.runs), "fmetrics history should expose runs");
    assert.ok(result.structuredContent.runs.length > 0, "fmetrics history should contain at least one run");
    const run = result.structuredContent.runs[0];
    assert.equal(typeof run.tool, "string", "history run should preserve tool");
    assert.equal(typeof run.backend, "string", "history run should preserve backend");
    assert.equal(typeof run.duration_ms, "number", "history run should preserve duration_ms");
  } finally {
    rmSync(fixture, { recursive: true, force: true });
  }
});

test("fcase MCP preserves JSON envelopes for JSON-capable actions", async () => {
  const slug = `mcp-fcase-json-${Date.now()}`;
  const result = await callTool("fcase", {
    action: "init",
    slug,
    goal: "Verify JSON-capable fcase actions return structured data",
  });

  assert.ok(!result.isError, textContent(result));
  // fcase init returns single case view — renderer produces pretty ANSI with slug
  const caseText = stripAnsi(textContent(result));
  assert.ok(caseText.includes(slug), "fcase init output should contain the case slug");
});

test("fcase MCP list renders deleted cases", async () => {
  const caseDir = mkdtempSync(join(tmpdir(), "fsuite-mcp-fcase-"));
  const env = { FCASE_DIR: caseDir };
  const slug = `mcp-fcase-deleted-${Date.now()}`;
  try {
    const initResult = await callToolWithEnv("fcase", {
      action: "init",
      slug,
      goal: "Verify deleted cases remain visible in rendered list output",
    }, env);
    assert.ok(!initResult.isError, textContent(initResult));

    const deleteResult = await callToolWithEnv("fcase", {
      action: "delete",
      slug,
      reason: "test cleanup",
      confirm_delete: "DELETE",
    }, env);
    assert.ok(!deleteResult.isError, textContent(deleteResult));

    const deletedList = await callToolWithEnv("fcase", {
      action: "list",
      statuses: "deleted",
    }, env);
    assert.ok(!deletedList.isError, textContent(deletedList));
    const deletedText = stripAnsi(textContent(deletedList));
    assert.ok(deletedText.includes(slug), `deleted list should render deleted case row, got: ${deletedText}`);

    const allList = await callToolWithEnv("fcase", {
      action: "list",
      statuses: "all",
    }, env);
    assert.ok(!allList.isError, textContent(allList));
    const allText = stripAnsi(textContent(allList));
    assert.ok(allText.includes(slug), `all-status list should render deleted case row, got: ${allText}`);
  } finally {
    rmSync(caseDir, { recursive: true, force: true });
  }
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

test("fread MCP preserves paths entries that contain commas", async () => {
  const dir = mkdtempSync(join(tmpdir(), "fsuite-mcp-comma-"));
  const missingPath = join(dir, "missing.py");
  const commaPath = join(dir, "with,comma.py");
  writeFileSync(commaPath, "print('comma-path-ok')\n", "utf8");

  try {
    const result = await callTool("fread", {
      paths: [missingPath, commaPath],
      head: 1,
    });
    const plain = stripAnsi(textContent(result));

    assert.ok(!result.isError, plain);
    assert.ok(
      plain.includes("comma-path-ok"),
      `fread MCP should read the file selected from a comma-containing paths entry, got: ${plain}`,
    );
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("fbash pretty output does not color exit=null as an error", async () => {
  const result = await callTool("fbash", {
    command: "sleep 0.2",
    background: true,
  });

  const raw = textContent(result);
  const plain = stripAnsi(raw);

  assert.ok(!result.isError, plain);
  // A pending background job has exit_code=null in structured output. The
  // pretty renderer must NOT surface it as "exit=null" in red (or any color),
  // because null means "still running", not "failed". The fbash structured
  // renderer (fcase #359) hides the exit badge entirely for background starts
  // and emits a "[bg job <id> started · ...]" callout instead.
  assert.ok(
    /bg job\s+fbash_\d+_\d+/.test(plain),
    `expected bg job callout with background_job_id in pretty output, got: ${plain}`,
  );
  assert.ok(
    !plain.includes("exit=null"),
    `exit=null should never appear in plain text, got: ${plain}`,
  );
  assert.ok(
    !raw.includes("\x1b[38;2;220;90;90mexit=null"),
    `exit=null should not be rendered in red, got: ${JSON.stringify(raw)}`,
  );
});

test("fbash MCP error path falls back to parsed stderr when errors are empty", async () => {
  const result = await callTool("fbash", {
    command: "printf 'mcp-fbash-stderr\\n' >&2; exit 7",
  });

  const plain = stripAnsi(textContent(result));
  // PR #27 contract: fbash non-zero exit is a *command-level* failure, not a
  // *tool-level* failure. isError stays undefined/false so agents don't retry
  // the tool call. Instead, the pretty output must surface exit code + stderr
  // so the caller can see what went wrong.
  assert.ok(
    plain.includes("exit=7"),
    `expected exit=7 in fbash error output, got: ${plain}`,
  );
  assert.ok(
    plain.includes("mcp-fbash-stderr"),
    `expected fbash stderr to surface in MCP error text, got: ${plain}`,
  );
  assert.ok(
    !plain.includes("Command failed:"),
    `expected MCP error text to avoid generic execFile failure message, got: ${plain}`,
  );
});

// ─── colorPath: filename highlighting in renderer output ───

test("fread pretty output includes colored filename from path", async () => {
  const fixture = makeFixture();
  try {
    const result = await callTool("fread", {
      path: join(fixture, "src", "sample.py"),
      head: 5,
    });

    assert.ok(!result.isError, textContent(result));
    const raw = textContent(result);
    const plain = stripAnsi(raw);
    // The filename "sample.py" should appear in stripped output
    assert.ok(plain.includes("sample.py"), `fread output should include filename, got: ${plain.slice(0, 200)}`);
    // Verify ANSI is present (colorPath uses theme.path which adds escape codes)
    assert.ok(raw !== plain, "fread output should contain ANSI color codes");
  } finally {
    rmSync(fixture, { recursive: true, force: true });
  }
});

test("fedit pretty output includes colored filename from path", async () => {
  const fixture = makeFixture();
  try {
    const result = await callTool("fedit", {
      path: join(fixture, "src", "sample.py"),
        replace: "return f\"hello {name}\"",
        with_text: "return f\"hi {name}\"",
      apply: false,
    });

    assert.ok(!result.isError, textContent(result));
    const raw = textContent(result);
    const plain = stripAnsi(raw);
    assert.ok(plain.includes("sample.py"), `fedit output should include filename, got: ${plain.slice(0, 200)}`);
    assert.ok(raw !== plain, "fedit output should contain ANSI color codes");
  } finally {
    rmSync(fixture, { recursive: true, force: true });
  }
});
