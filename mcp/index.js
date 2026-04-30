#!/usr/bin/env node
// fsuite-mcp — Thin MCP adapter for fsuite CLI tools
// Makes ftree, fmap, fread, fcontent, fsearch, fedit, fwrite, fcase show up
// as native tool calls alongside Read, Edit, Grep in Claude/Codex.
//
// Architecture: The bash tools do all real work. This is a stateless dispatcher.
// Security: Uses execFile (not exec) — arguments are array elements, never shell strings.
// SDK: @modelcontextprotocol/sdk v1.28.0 — McpServer + registerTool (latest API)

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { writeFile as fsWriteFile, mkdtemp, unlink, rmdir } from "node:fs/promises";
import { dirname, join } from "node:path";
import { pathToFileURL } from "node:url";
import { tmpdir } from "node:os";
import hljs from "highlight.js";
import { buildFcontentArgs } from "./fcontent-args.js";

// ─── ANSI helpers ────────────────────────────────────────────────
const RESET = "\x1b[0m";
const DIM   = "\x1b[2m";
const UNDIM = "\x1b[22m";
const BOLD  = "\x1b[1m";

const fg = (r, g, b) => `\x1b[38;2;${r};${g};${b}m`;
const bg = (r, g, b) => `\x1b[48;2;${r};${g};${b}m`;

// ─── Claude Code exact Monokai scope colors ──────────────────────
const SCOPE_COLORS = {
  keyword:              fg(249, 38, 114),
  storage:              fg(102, 217, 239),
  built_in:             fg(166, 226, 46),
  type:                 fg(166, 226, 46),
  literal:              fg(190, 132, 255),
  number:               fg(190, 132, 255),
  string:               fg(230, 219, 116),
  title:                fg(166, 226, 46),
  "title.function":     fg(166, 226, 46),
  "title.class":        fg(166, 226, 46),
  params:               fg(253, 151, 31),
  comment:              fg(117, 113, 94),
  meta:                 fg(117, 113, 94),
  attr:                 fg(166, 226, 46),
  attribute:            fg(166, 226, 46),
  variable:             fg(255, 255, 255),
  "variable.language":  fg(255, 255, 255),
  property:             fg(255, 255, 255),
  operator:             fg(249, 38, 114),
  punctuation:          fg(248, 248, 242),
  symbol:               fg(190, 132, 255),
  regexp:               fg(230, 219, 116),
  subst:                fg(248, 248, 242),
};

const DIFF_COLORS = {
  addBg:         bg(2, 40, 0),
  removeBg:      bg(61, 1, 0),
  addGutterFg:   fg(80, 200, 80),
  removeGutterFg:fg(220, 90, 90),
  normalFg:      fg(248, 248, 242),
};

// Theme for non-diff output (metadata, warnings, etc.)
const theme = {
  meta:    (s) => `${DIM}${s}${UNDIM}`,
  warn:    (s) => `${fg(255, 200, 50)}${s}${RESET}`,
  error:   (s) => `${fg(255, 80, 80)}${s}${RESET}`,
  ok:      (s) => `${fg(80, 200, 80)}${s}${RESET}`,
  dryrun:  (s) => `${fg(255, 200, 50)}${s}${RESET}`,
  lineNum: (s) => `${DIM}${s}${UNDIM}`,
  path:    (s) => `${fg(102, 217, 239)}${s}${RESET}`,
  symbol:  (s) => `${fg(102, 217, 239)}${s}${RESET}`,
};

// Highlight the filename in a path — directory stays dim, filename gets color
function colorPath(fullPath) {
  if (!fullPath) return "";
  const p = shortPath(fullPath);
  const slash = p.lastIndexOf("/");
  if (slash === -1) return theme.path(p);
  return `${DIM}${p.slice(0, slash + 1)}${UNDIM}${theme.path(p.slice(slash + 1))}`;
}

// Map hljs CSS class → ANSI color
const HLJS_CLASS_TO_ANSI = {
  "hljs-keyword":    fg(249, 38, 114),
  "hljs-built_in":   fg(166, 226, 46),
  "hljs-type":       fg(166, 226, 46),
  "hljs-literal":    fg(190, 132, 255),
  "hljs-number":     fg(190, 132, 255),
  "hljs-string":     fg(230, 219, 116),
  "hljs-title":      fg(166, 226, 46),
  "hljs-title.function": fg(166, 226, 46),
  "hljs-title.class": fg(166, 226, 46),
  "hljs-params":     fg(253, 151, 31),
  "hljs-comment":    fg(117, 113, 94),
  "hljs-meta":       fg(117, 113, 94),
  "hljs-attr":       fg(166, 226, 46),
  "hljs-attribute":  fg(166, 226, 46),
  "hljs-variable":   fg(255, 255, 255),
  "hljs-variable.language": fg(255, 255, 255),
  "hljs-variable.constant_": fg(255, 255, 255),
  "hljs-property":   fg(255, 255, 255),
  "hljs-operator":   fg(249, 38, 114),
  "hljs-punctuation": fg(248, 248, 242),
  "hljs-symbol":     fg(190, 132, 255),
  "hljs-regexp":     fg(230, 219, 116),
  "hljs-subst":      fg(248, 248, 242),
  "hljs-selector-tag": fg(249, 38, 114),
  "hljs-selector-class": fg(166, 226, 46),
  "hljs-name":       fg(249, 38, 114),
  "hljs-function":   fg(166, 226, 46),
  // Markdown scopes
  "hljs-section":    fg(102, 217, 239) + "\x1b[1m",  // bold cyan — headings
  "hljs-strong":     fg(253, 151, 31) + "\x1b[1m",   // bold orange — **bold**
  "hljs-emphasis":   fg(230, 219, 116) + "\x1b[3m",  // italic yellow — *italic*
  "hljs-bullet":     fg(249, 38, 114),                // pink — list markers
  "hljs-quote":      fg(117, 113, 94) + "\x1b[3m",   // italic dim — blockquotes
  "hljs-code":       fg(166, 226, 46),                // green — inline code / fenced
  "hljs-link":       fg(102, 217, 239) + "\x1b[4m",  // underlined cyan — URLs
};

// Convert hljs HTML output to ANSI-colored string
function htmlToAnsi(html) {
  const defaultFg = fg(248, 248, 242);
  return html
    // Replace <span class="hljs-xxx"> with ANSI color
    .replace(/<span class="([^"]+)">/g, (_, cls) => {
      // Try exact match, then first class
      return HLJS_CLASS_TO_ANSI[cls] || HLJS_CLASS_TO_ANSI[cls.split(" ")[0]] || defaultFg;
    })
    // Replace </span> with reset + default fg
    .replace(/<\/span>/g, RESET + defaultFg)
    // Unescape HTML entities
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&#x27;/g, "'")
    .replace(/&#39;/g, "'");
}

function highlightLine(code, lang) {
  if (!lang) return fg(248, 248, 242) + code;
  try {
    const result = hljs.highlight(code, { language: lang, ignoreIllegals: true });
    return fg(248, 248, 242) + htmlToAnsi(result.value) + RESET;
  } catch {
    return fg(248, 248, 242) + code;
  }
}

function visibleLength(str) {
  return str.replace(/\x1b\[[0-9;]*m/g, "").length;
}

// Truncate a rendered output string to maxVisible lines.
// Returns the truncated string with a dim "... N more lines" trailer when capped.
function truncateOutput(text, maxVisible) {
  const lines = text.split("\n");
  // Trailing newline produces an empty last element — don't count it
  const trailingNewline = lines.length > 0 && lines[lines.length - 1] === "";
  const contentLines = trailingNewline ? lines.slice(0, -1) : lines;
  if (contentLines.length <= maxVisible) return text;
  const hidden = contentLines.length - maxVisible;
  const visible = contentLines.slice(0, maxVisible);
  visible.push(`${DIM}  ... ${hidden} more lines${RESET}`);
  return visible.join("\n") + "\n";
}
// Detect language from file path extension
function detectLang(filePath) {
  if (!filePath) return "";
  const ext = filePath.split(".").pop()?.toLowerCase();
  if (ext && hljs.getLanguage(ext)) return ext;
  const map = { rs: "rust", py: "python", js: "javascript", ts: "typescript",
    sh: "bash", kt: "kotlin", rb: "ruby", yml: "yaml", md: "markdown",
    h: "c", hpp: "cpp", cxx: "cpp" };
  return map[ext] || ext || "";
}

function shellSegments(command) {
  const input = String(command || "");
  const segments = [];
  let segment = "";
  let quote = "";

  for (let i = 0; i < input.length; i += 1) {
    const ch = input[i];
    if (quote) {
      segment += ch;
      if (quote === "'" && ch === "'") {
        quote = "";
      } else if (quote === '"') {
        if (ch === "\\" && i + 1 < input.length) {
          i += 1;
          segment += input[i];
        } else if (ch === '"') {
          quote = "";
        }
      }
      continue;
    }

    if (ch === "'" || ch === '"') {
      quote = ch;
      segment += ch;
    } else if (ch === "\\") {
      segment += ch;
      if (i + 1 < input.length) {
        i += 1;
        segment += input[i];
      }
    } else if (ch === "\n" || ch === ";" || ch === "|" || ch === "&" || ch === "(" || ch === ")") {
      segments.push(segment);
      segment = "";
    } else {
      segment += ch;
    }
  }

  segments.push(segment);
  return segments;
}

function shellSegmentTokens(segment) {
  const input = String(segment || "");
  const tokens = [];
  let token = "";
  let quote = "";

  const pushToken = () => {
    if (token) {
      tokens.push(token);
      token = "";
    }
  };

  for (let i = 0; i < input.length; i += 1) {
    const ch = input[i];
    if (quote) {
      if (quote === "'" && ch === "'") {
        quote = "";
        continue;
      }
      if (quote === '"') {
        if (ch === '"') {
          quote = "";
          continue;
        }
        if (ch === "\\" && i + 1 < input.length) {
          i += 1;
          token += input[i];
          continue;
        }
      }
      token += ch;
      continue;
    }

    if (ch === "'" || ch === '"') {
      quote = ch;
    } else if (ch === "\\") {
      if (i + 1 < input.length) {
        i += 1;
        token += input[i];
      }
    } else if (/\s/.test(ch)) {
      pushToken();
    } else if (ch === "<" || ch === ">") {
      pushToken();
      tokens.push(ch);
    } else {
      token += ch;
    }
  }

  pushToken();
  return tokens;
}

function stripLeadingTabs(value) {
  return String(value || "").replace(/^\t+/, "");
}

function extractHeredocDelimiters(line) {
  const input = String(line || "");
  const delimiters = [];
  let quote = "";

  for (let i = 0; i < input.length; i += 1) {
    const ch = input[i];
    if (quote) {
      if (quote === "'" && ch === "'") {
        quote = "";
      } else if (quote === '"') {
        if (ch === "\\" && i + 1 < input.length) {
          i += 1;
        } else if (ch === '"') {
          quote = "";
        }
      }
      continue;
    }

    if (ch === "'" || ch === '"') {
      quote = ch;
      continue;
    }
    if (ch === "\\") {
      if (i + 1 < input.length) i += 1;
      continue;
    }
    if (ch !== "<" || input[i - 1] === "<" || input[i + 1] !== "<" || input[i + 2] === "<") continue;

    i += 2;
    let stripTabs = false;
    if (input[i] === "-") {
      stripTabs = true;
      i += 1;
    }
    while (i < input.length && /\s/.test(input[i])) i += 1;

    let delimiter = "";
    let wordQuote = "";
    for (; i < input.length; i += 1) {
      const wordChar = input[i];
      if (wordQuote) {
        if (wordQuote === "'" && wordChar === "'") {
          wordQuote = "";
          continue;
        }
        if (wordQuote === '"') {
          if (wordChar === '"') {
            wordQuote = "";
            continue;
          }
          if (wordChar === "\\" && i + 1 < input.length) {
            i += 1;
            delimiter += input[i];
            continue;
          }
        }
        delimiter += wordChar;
        continue;
      }

      if (wordChar === "'" || wordChar === '"') {
        wordQuote = wordChar;
      } else if (wordChar === "\\") {
        if (i + 1 < input.length) {
          i += 1;
          delimiter += input[i];
        }
      } else if (/\s/.test(wordChar) || [";", "|", "&", "(", ")", "<", ">"].includes(wordChar)) {
        break;
      } else {
        delimiter += wordChar;
      }
    }

    if (delimiter) delimiters.push({ delimiter, stripTabs });
  }

  return delimiters;
}

function stripHeredocBodies(command) {
  const lines = String(command || "").split("\n");
  const pending = [];
  const kept = [];

  for (const line of lines) {
    if (pending.length > 0) {
      const current = pending[0];
      const compareLine = current.stripTabs ? stripLeadingTabs(line) : line;
      if (compareLine === current.delimiter) pending.shift();
      continue;
    }

    kept.push(line);
    pending.push(...extractHeredocDelimiters(line));
  }

  return kept.join("\n");
}

function commandInvokesTool(command, tool) {
  for (const segment of shellSegments(stripHeredocBodies(command))) {
    let skipRedirectionTarget = false;
    let skipTimeoutArg = false;
    for (const token of shellSegmentTokens(segment)) {
      if (!token) continue;
      if (skipRedirectionTarget) {
        skipRedirectionTarget = false;
        continue;
      }
      if (token === "<" || token === ">") {
        skipRedirectionTarget = true;
        continue;
      }
      if (/^[A-Za-z_][A-Za-z0-9_]*=/.test(token)) continue;
      const base = token.split("/").pop();
      if (["env", "command", "builtin", "exec", "time"].includes(base)) continue;
      if (base === "timeout") {
        skipTimeoutArg = true;
        continue;
      }
      if (skipTimeoutArg) {
        if (token.startsWith("-")) continue;
        skipTimeoutArg = false;
        continue;
      }
      if (base === tool) return true;
      break;
    }
  }
  return false;
}

const run = promisify(execFile);
function readTimeoutMs(name, defaultMs) {
  const raw = process.env[name];
  if (raw === undefined || raw === "") return defaultMs;
  const parsed = Number.parseInt(raw, 10);
  if (!Number.isFinite(parsed) || parsed < 0) return defaultMs;
  return parsed;
}

const TOOL_TIMEOUT = readTimeoutMs("FSUITE_MCP_TOOL_TIMEOUT_MS", 30_000);
// fbash owns command timeouts itself. A zero execFile timeout prevents the MCP
// wrapper from killing long foreground calls or background job startup/polls.
const FBASH_TOOL_TIMEOUT = readTimeoutMs("FSUITE_MCP_FBASH_TIMEOUT_MS", 0);
const MAX_BUFFER = 1024 * 1024 * 5; // 5MB

// Resolve tools from source tree (sibling of mcp/).
// Since mcp/index.js is always run from the source tree, prefer source tools
// over installed PATH versions — enables fast iteration without reinstalling.
// Set FSUITE_USE_PATH=1 to force PATH resolution (e.g. in production).
const FSUITE_SRC_DIR = process.env.FSUITE_USE_PATH
  ? null
  : join(dirname(new URL(import.meta.url).pathname), "..");

function resolveTool(name) {
  if (FSUITE_SRC_DIR) return join(FSUITE_SRC_DIR, name);
  return name; // resolve from PATH
}

// FSUITE_TELEMETRY=3: full telemetry (timing, args, results) for fmetrics import
const EXEC_ENV = { ...process.env, FSUITE_TELEMETRY: "3" };

function execOptsFor(tool) {
  return {
    timeout: tool === "fbash" ? FBASH_TOOL_TIMEOUT : TOOL_TIMEOUT,
    maxBuffer: MAX_BUFFER,
    env: EXEC_ENV,
  };
}

// ─── Per-tool color palette (256-color ANSI for Claude Code tool headers) ────
// Binary patch v2 passes _.annotations?.title through as-is.
// We embed the ANSI color in the title so Claude Code renders it.
const TOOL_PALETTE = {
  fread: 46, ftree: 46, freplay: 46,           // neon green — read/scout
  fedit: 208, fwrite: 208,                      // orange — mutation
  fcontent: 27, fsearch: 27, fs: 27,            // royal blue — search
  fmap: 129, fcase: 129,                        // dark violet — structure/knowledge
  fprobe: 196, fmetrics: 196,                   // pure red — diagnostic/recon
  fbash: 220,                                    // gold — shell execution
};
function coloredTitle(name) {
  const c = TOOL_PALETTE[name];
  return c ? `\x1b[1;38;5;${c}m${name}\x1b[m` : name;
}
// (theme defined above with ANSI helpers)

// ─── Path shortener ──────────────────────────────────────────────
function shortPath(fullPath) {
  if (!fullPath) return "";
  const home = process.env.HOME || (process.env.USER ? "/home/" + process.env.USER : null);
  const cwd = process.cwd();

  // If inside cwd, show relative
  if (fullPath.startsWith(cwd + "/")) {
    return fullPath.slice(cwd.length + 1);
  }
  // If under home, show ~/...
  if (home && fullPath.startsWith(home + "/")) {
    return "~/" + fullPath.slice(home.length + 1);
  }
  return fullPath;
}

// ─── Diff renderer (Claude Code exact — hljs + Monokai + truecolor bg) ─
function colorizeDiff(diff, filePath) {
  if (!diff) return "";
  // MCP runs as stdio subprocess — stdout.columns is undefined (piped).
  // Try stderr (may still be a TTY), env var, or fall back conservatively.
  // 120 is safer than 160 — avoids Ink text wrapping that breaks backgrounds.
  const cols = process.stderr.columns || parseInt(process.env.COLUMNS, 10) || 120;
  const lang = detectLang(filePath || "");

  let oldLine = 0, newLine = 0;
  const diffLines = diff.split("\n");

  // Find max line number for gutter width
  let maxLn = 0;
  for (const line of diffLines) {
    const m = line.match(/@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@/);
    if (m) {
      maxLn = Math.max(maxLn,
        parseInt(m[1]) + parseInt(m[2] || "1"),
        parseInt(m[3]) + parseInt(m[4] || "1"));
    }
  }
  const gutterW = Math.max(3, String(maxLn).length);
  const codeW = cols - gutterW - 3; // gutter + space + marker + space

  return diffLines.map(line => {
    if (line.startsWith("+++") || line.startsWith("---")) return "";

    if (line.startsWith("@@")) {
      const m = line.match(/@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@/);
      if (m) { oldLine = parseInt(m[1]); newLine = parseInt(m[2]); }
      return ""; // skip hunk headers — the line numbers tell the story
    }

    const marker = line[0]; // +, -, or space
    const code = line.substring(1);

    if (marker === "+") {
      // ADDED: syntax highlighted + dark green bg + full width padding
      const hl = highlightLine(code, lang);
      const num = String(newLine++).padStart(gutterW);
      const gutter = `${DIFF_COLORS.addBg}${DIFF_COLORS.addGutterFg} ${num} +`;
      // Re-inject bg after every hljs RESET so background persists across tokens
      const hlBg = hl.replace(/\x1b\[0m/g, `${RESET}${DIFF_COLORS.addBg}`);
      const vis = gutterW + 3 + visibleLength(code);
      const pad = " ".repeat(Math.max(0, cols - vis));
      return `${gutter}${DIFF_COLORS.addBg}${hlBg}${DIFF_COLORS.addBg}${pad}${RESET}`;
    }
    if (marker === "-") {
      // REMOVED: NO syntax highlight, plain white, dimmed, dark red bg, full width
      const num = String(oldLine++).padStart(gutterW);
      const gutter = `${DIFF_COLORS.removeBg}${DIFF_COLORS.removeGutterFg} ${num} -`;
      const content = `${DIFF_COLORS.removeBg}${DIFF_COLORS.normalFg}${code}`;
      const vis = gutterW + 3 + code.length;
      const pad = " ".repeat(Math.max(0, cols - vis));
      return `${DIM}${gutter}${content}${DIFF_COLORS.removeBg}${pad}${UNDIM}${RESET}`;
    }
    // CONTEXT: syntax highlighted, dimmed gutter, no bg
    const hl = highlightLine(code, lang);
    const num = String(newLine).padStart(gutterW);
    oldLine++; newLine++;
    return `${DIM} ${num}  ${UNDIM}${hl}${RESET}`;
  }).filter(l => l !== "").join("\n");
}

// ─── Pretty renderers (ANSI, no markdown) ────────────────────────

function renderFeditResult(jsonStr) {
  try {
    const d = JSON.parse(jsonStr);
    if (!d.tool || (d.tool !== "fedit" && d.tool !== "fwrite")) return null;

    const mode = d.mode === "create" ? "create" : d.mode === "replace_file" ? "replace" : "patch";

    // Count diff lines for summary
    let added = 0, removed = 0;
    if (d.diff) {
      for (const line of d.diff.split("\n")) {
        if (line.startsWith("+") && !line.startsWith("+++")) added++;
        if (line.startsWith("-") && !line.startsWith("---")) removed++;
      }
    }

    // Build clean metadata line like fmap's "27 symbols | typescript"
    // Shows operation summary: "Applied +2 -2 lines | replace | function_name"
    const parts = [];
    if (d.applied) {
      parts.push(theme.ok("Applied"));
    } else {
      parts.push(theme.dryrun("Dry-run"));
    }
    if (added > 0) parts.push(theme.ok(`+${added}`));
    if (removed > 0) parts.push(theme.error(`-${removed}`));
    if (added > 0 || removed > 0) parts.push("lines");
    if (!d.preconditions_ok) parts.push(theme.error("PRECONDITION FAILED"));

    // Add operation context on same line (mode, anchors used)
    const ctx = [];
    if (d.mode && d.mode !== "patch") ctx.push(d.mode);
    if (d.function_name) ctx.push(`fn:${d.function_name}`);
    else if (d.lines_start) ctx.push(`L${d.lines_start}:${d.lines_end || ""}`);
    if (ctx.length) parts.push(theme.meta("| " + ctx.join(" | ")));

    let out = colorPath(d.path) + " " + parts.join(" ") + "\n";
    if (d.error_code) {
      out += theme.error(`Error: ${d.error_code}`) + ` \u2014 ${d.error_detail}\n`;
      return out;
    }

    if (d.diff) {
      const MAX_DIFF_LINES = 30;
      if ((mode === "create" || mode === "replace") && added > MAX_DIFF_LINES) {
        const diffLines = d.diff.split("\n").filter(l => !l.startsWith("---") && !l.startsWith("+++"));
        const preview = diffLines.slice(0, 8);
        const tail = diffLines.slice(-3);
        out += colorizeDiff(preview.join("\n"), d.path) + "\n";
        out += theme.meta(`  ... ${added - 11} more lines ...`) + "\n";
        out += colorizeDiff(tail.join("\n"), d.path) + "\n";
      } else {
        out += colorizeDiff(d.diff, d.path) + "\n";
      }
    }

    // Warnings
    if (d.warnings && Array.isArray(d.warnings) && d.warnings.length > 0) {
      out += "\n";
      for (const warning of d.warnings) {
        out += theme.warn(`⚠ Warning: ${warning}`) + "\n";
      }
    }

    return out;
  } catch {
    // Non-JSON output (shell error, binary crash). Return a plain-text fallback
    // so cli() never falls through to the raw JSON dump path for fedit/fwrite calls.
    const preview = (jsonStr || "").slice(0, 200).replace(/\n/g, " ").trim();
    return `${theme.error("fedit: unexpected output")} \u2014 ${preview || "(empty)"}\n`;
  }
}

function renderFreadResult(jsonStr, ctx = {}) {
  try {
    const d = JSON.parse(jsonStr);
    if (!d.tool || d.tool !== "fread") return null;

    // Clean metadata line with dividers: "21 lines | ~274 tokens | L120:140"
    const metaParts = [`${d.lines_emitted} lines`, `~${d.token_estimate} tokens`];
    if (d.symbol_resolution) {
      metaParts.push(`L${d.symbol_resolution.line_start}-${d.symbol_resolution.line_end}`);
    } else if (d.chunks?.[0]?.start_line) {
      metaParts.push(`L${d.chunks[0].start_line}:${d.chunks[0].end_line}`);
    }
    if (d.truncated) metaParts.push(theme.warn("truncated"));
    const filePath = d.symbol_resolution?.path || d.files?.[0]?.path || d.path || "";
    let out = colorPath(filePath) + " " + theme.meta(metaParts.join(" | ")) + "\n";

    for (const w of (d.warnings || [])) {
      out += `   ${theme.warn("\u26a0 " + w)}\n`;
    }
    for (const e of (d.errors || [])) {
      out += `   ${theme.error("\u2716 " + e)}\n`;
    }
    for (const f of (d.files || [])) {
      if (f.status && f.status !== "read") {
        out += `   ${theme.warn(shortPath(f.path) + ": " + f.status)}\n`;
      }
    }

    const lang = detectLang(d.symbol_resolution?.path || d.files?.[0]?.path || "");

    // MCP fread should mirror CLI fread: uncapped unless the caller asks for a cap.
    const MAX_PRETTY_LINES = (ctx.full || ctx.maxLines === undefined || ctx.maxLines === 0)
      ? Number.POSITIVE_INFINITY
      : ctx.maxLines;
    let lineCount = 0;
    let totalLines = 0;
    for (const chunk of (d.chunks || [])) {
      totalLines += chunk.content?.length || 0;
    }

    for (const chunk of (d.chunks || [])) {
      for (const rawLine of chunk.content) {
        if (lineCount >= MAX_PRETTY_LINES) {
          const remaining = totalLines - MAX_PRETTY_LINES;
          out += `${DIM}  ... ${remaining} more lines${RESET}` + "\n";
          lineCount = -1; // sentinel to break outer loop
          break;
        }
        const m = rawLine.match(/^(\d+)(\s{2,})(.*)/);
        if (m) {
          const ln = `${DIM} ${m[1].padStart(4)} ${UNDIM}`;
          const hl = highlightLine(m[3], lang);
          out += `${ln}${hl}${RESET}\n`;
        } else {
          out += rawLine + "\n";
        }
        lineCount++;
      }
      if (lineCount === -1) break;
    }

    if (d.next_hint) out += theme.meta(`next: ${d.next_hint}`) + "\n";
    return out;
  } catch {
    return null;
  }
}

function renderFmapResult(jsonStr) {
  try {
    const d = JSON.parse(jsonStr);
    if (!d.tool || d.tool !== "fmap") return null;

    let meta = `${d.total_symbols} symbols`;
    if (d.files?.[0]?.language) meta += ` | ${d.files[0].language}`;
    if (d.shown_symbols < d.total_symbols) meta += ` ${theme.warn(`(${d.shown_symbols}/${d.total_symbols} shown)`)}`;
    let out = theme.meta(meta) + "\n";

    for (const file of (d.files || [])) {
      const lang = detectLang(file.path || "");
      for (const sym of file.symbols) {
        const text = sym.text.trim().substring(0, 65);
        const typeColor = sym.type === "function" ? fg(166, 226, 46) :
                          sym.type === "class" ? fg(253, 151, 31) :
                          sym.type === "import" ? fg(117, 113, 94) :
                          sym.type === "constant" ? fg(190, 132, 255) :
                          fg(248, 248, 242);
        const hl = highlightLine(text, lang);
        out += `  ${DIM}${String(sym.line).padStart(4)}${UNDIM}  ${typeColor}${sym.type.padEnd(9)}${RESET} ${hl}${RESET}\n`;
      }
    }

    return out;
  } catch {
    return null;
  }
}

function renderFcontentResult(jsonStr) {
  try {
    const d = JSON.parse(jsonStr);
    if (!d.tool || d.tool !== "fcontent") return null;

    const query = d.query || "";

    if (d.shown_matches === 0) {
      return theme.meta("no matches") + "\n";
    }
    // Clean summary: just files + matches count (no max_matches noise)
// Clean summary: just files + matches count (no max_matches noise)
let out = theme.meta(`${d.total_matched_files} files, ${d.shown_matches} matches`) + "\n";

const MAX_CONTENT_LINES = 20;
let contentLineCount = 0;
const totalMatches = (d.matches || []).length;

for (const m of (d.matches || [])) {
if (contentLineCount >= MAX_CONTENT_LINES) {
const remaining = totalMatches - contentLineCount;
out += `${DIM}  ... ${remaining} more lines${RESET}` + "\n";
break;
}
// Parse "filepath:linenum:content"
const firstColon = m.indexOf(":");
const secondColon = firstColon > -1 ? m.indexOf(":", firstColon + 1) : -1;
if (secondColon > -1) {
const filePath = m.substring(0, firstColon);
const lineNum = m.substring(firstColon + 1, secondColon);
const content = m.substring(secondColon + 1);

// Detect language + syntax highlight
const ext = filePath.split(".").pop() || "";
const lang = detectLang(ext);
let colored = lang ? highlightLine(content, lang) : content;

// Bold the queried string inside highlighted output
if (query) colored = boldMatchInAnsi(colored, query);

out += `  ${theme.path(shortPath(filePath) + ":" + lineNum)} ${colored}\n`;
} else {
out += `  ${m}\n`;
}
contentLineCount++;
}
return out;
} catch {
  return null;
}
}

// Bold a literal query match inside an ANSI-colored string
function boldMatchInAnsi(ansiStr, query) {
  const raw = ansiStr.replace(/\x1b\[[0-9;]*m/g, "");
  const matchIdx = raw.indexOf(query);
  if (matchIdx === -1) return ansiStr;

  let rawPos = 0, i = 0, result = "";
  let boldStart = false, boldEnd = false;

  while (i < ansiStr.length) {
    // Pass through ANSI escapes without counting
    if (ansiStr[i] === "\x1b") {
      let j = i + 1;
      while (j < ansiStr.length && ansiStr[j] !== "m") j++;
      result += ansiStr.substring(i, j + 1);
      i = j + 1;
      continue;
    }
    if (rawPos === matchIdx && !boldStart) {
      result += BOLD;
      boldStart = true;
    }
    if (rawPos === matchIdx + query.length && !boldEnd) {
      result += "\x1b[22m"; // unbold
      boldEnd = true;
    }
    result += ansiStr[i];
    rawPos++;
    i++;
  }
  if (boldStart && !boldEnd) result += "\x1b[22m";
  return result;
}
function renderFtreeResult(jsonStr) {
  try {
    const d = JSON.parse(jsonStr);
    if (!d.tool || (d.tool !== "ftree" && d.tool !== "fls")) return null;

    const recon = d.snapshot?.recon;
    const path = recon?.path || "";

    let out = "";
    if (recon) {
      out += theme.meta(`${recon.total_entries} entries | depth ${recon.recon_depth}`) + "\n";
    }

    const tree = d.snapshot?.tree;
    if (tree?.lines) {
      out += tree.lines.join("\n") + "\n";
    }
    return out;
  } catch {
    // fls outputs pre-rendered text (not JSON) — pass through as-is
    return jsonStr || null;
  }
}

// Extension → color for ls-style file listing
const EXT_COLORS = {
  js: fg(230, 219, 116),   // yellow
  ts: fg(102, 217, 239),   // cyan
  py: fg(166, 226, 46),    // green
  rs: fg(253, 151, 31),    // orange
  go: fg(102, 217, 239),   // cyan
  rb: fg(249, 38, 114),    // pink
  sh: fg(166, 226, 46),    // green
  bash: fg(166, 226, 46),  // green
  json: fg(230, 219, 116), // yellow
  toml: fg(230, 219, 116), // yellow
  yaml: fg(230, 219, 116), // yellow
  yml: fg(230, 219, 116),  // yellow
  md: fg(102, 217, 239),   // cyan (matches heading color)
  css: fg(102, 217, 239),  // cyan
  html: fg(249, 38, 114),  // pink
  c: fg(102, 217, 239),    // cyan
  cpp: fg(102, 217, 239),  // cyan
  h: fg(190, 132, 255),    // purple
  java: fg(253, 151, 31),  // orange
  kt: fg(190, 132, 255),   // purple
  swift: fg(253, 151, 31), // orange
  txt: fg(200, 200, 200),  // gray
};

function colorByExt(filename) {
  const ext = filename.split(".").pop()?.toLowerCase() || "";
  return EXT_COLORS[ext] || fg(248, 248, 242);
}

function renderFsearchStructured(d) {
  if (!d || d.tool !== "fsearch") return null;

  const lines = [];
  const countLabel = d.count_mode === "lower_bound" ? `${d.total_found}+` : `${d.total_found}`;
  const summary = d.has_more
    ? `${d.shown}/${countLabel} results shown (more available)`
    : `${d.total_found} results found`;
  lines.push(theme.meta(summary));

  const hits = (d.hits && d.hits.length > 0)
    ? d.hits
    : (d.results || []).map((path) => ({ path, kind: "file", matched_on: "name" }));

  for (const hit of hits) {
    const fullPath = hit.path;
    const short = shortPath(fullPath);
    const filename = short.split("/").pop() || short;
    const dir = short.substring(0, short.length - filename.length);
    const suffix = hit.kind === "dir" ? "/" : "";
    const matchNote = hit.matched_on && hit.matched_on !== "name"
      ? `${DIM} (${hit.matched_on})${RESET}`
      : "";

    if (hit.kind === "dir") {
      lines.push(`  ${theme.path(short)}${suffix}${matchNote}`);
    } else {
      const color = colorByExt(filename);
      lines.push(`  ${DIM}${dir}${UNDIM}${color}${BOLD}${filename}${RESET}${matchNote}`);
    }

    if (hit.kind === "dir" && hit.preview?.length) {
      for (const child of hit.preview) {
        const childSuffix = child.kind === "dir" ? "/" : "";
        lines.push(`    ${DIM}${child.name}${childSuffix}${RESET}`);
      }
      if (hit.preview_truncated) {
        lines.push(`    ${DIM}...${RESET}`);
      }
    }
  }

  if (d.next_hint) {
    const nhArgs = Object.entries(d.next_hint.args || {})
      .map(([k, v]) => `${fg(166, 226, 46)}${k}${RESET}${DIM}: ${UNDIM}${fg(230, 219, 116)}${v}${RESET}`)
      .join(DIM + ", " + RESET);
    lines.push("");
    lines.push(`${fg(190, 132, 255)}${BOLD}next ->${RESET} ${fg(102, 217, 239)}${d.next_hint.tool}${RESET}(${nhArgs})`);
  }

  return lines.join("\n") + "\n";
}

function renderFsearchResult(jsonStr) {
  try {
    return renderFsearchStructured(JSON.parse(jsonStr));
  } catch {
    return null;
  }
}

const fsearchNextHintSchema = z.object({
  tool: z.string(),
  args: z.object({}).passthrough(),
});

const fsearchPreviewEntrySchema = z.object({
  name: z.string(),
  kind: z.enum(["file", "dir"]),
});

const fsearchHitSchema = z.object({
  path: z.string(),
  kind: z.enum(["file", "dir"]),
  matched_on: z.enum(["name", "path", "both"]),
  preview: z.array(fsearchPreviewEntrySchema).optional(),
  preview_truncated: z.boolean().optional(),
  next_hint: fsearchNextHintSchema.nullable().optional(),
}).passthrough();

// ─── fcase pretty renderer ────────────────────────────────────────
function renderFcaseResult(jsonStr) {
  try {
    const d = JSON.parse(jsonStr);
    // fcase export returns a full dump with .events — return raw JSON string so
    // consumers can JSON.parse(textContent(result)) directly.
    if (d.events) return jsonStr;
    // Only render case views — everything else falls through (no render).
    if (!d.cases && !d.case) return null;

    // Single case view (status, note, init, resolve, etc.)
    if (d.case) {
      const c = d.case;
      const icon = c.status === "resolved" ? `${fg(80,200,80)}\u2713${RESET}`
                 : c.status === "archived" ? `${DIM}\u25CB${RESET}`
                 : c.status === "deleted"  ? `${fg(255,80,80)}\u2717${RESET}`
                 : `${fg(255,200,50)}\u25CF${RESET}`;
      const pri = c.priority === "critical" ? ` ${fg(255,80,80)}crit${RESET}`
                : c.priority === "high"     ? ` ${fg(255,80,80)}high${RESET}`
                : "";
      let out = `${icon} ${BOLD}#${c.id}${RESET} ${c.slug}${pri}\n`;
      if (c.goal) out += `${DIM}  ${c.goal}${UNDIM}\n`;
      if (c.resolution_summary) out += `${fg(80,200,80)}  ${c.resolution_summary}${RESET}\n`;
      if (c.next_move) out += `${fg(255,200,50)}  next: ${c.next_move}${RESET}\n`;
      // Pass through any message from the action with contextual icon
      if (d.message) {
        const isError = /fail|error|denied/i.test(d.message);
        const msgIcon = isError ? `${fg(255,80,80)}\u2718${RESET}` : `${fg(80,200,80)}\u2714${RESET}`;
        out += `${msgIcon} ${DIM}${d.message}${UNDIM}\n`;
      }
      return out;
    }

    // Case list view
    const cases = d.cases || [];
    const resolved = cases.filter(c => c.status === "resolved");
    const open = cases.filter(c => c.status === "open");
    const archived = cases.filter(c => c.status === "archived");
    const deleted = cases.filter(c => c.status === "deleted");

    // Priority sort: critical > high > medium > low > normal
    const priOrder = { critical: 0, high: 1, medium: 2, low: 3, normal: 4 };
    const sortByPri = (a, b) => (priOrder[a.priority] ?? 4) - (priOrder[b.priority] ?? 4);

    // Summary bar
    const parts = [`${cases.length} cases`];
    if (resolved.length) parts.push(`${resolved.length} resolved`);
    if (open.length) parts.push(`${open.length} open`);
    if (archived.length) parts.push(`${archived.length} archived`);
    if (deleted.length) parts.push(`${deleted.length} deleted`);
    let out = theme.meta(parts.join(" | ")) + "\n";

    const renderCase = (c) => {
      const icon = c.status === "resolved" ? `${fg(80,200,80)}\u2713${RESET}`
                 : c.status === "archived" ? `${DIM}\u25CB${RESET}`
                 : c.status === "deleted" ? `${fg(255,80,80)}\u2717${RESET}`
                 : `${fg(255,200,50)}\u25CF${RESET}`;
      const pri = c.priority === "critical" ? `${fg(255,80,80)}crit${RESET}   `
                : c.priority === "high"     ? `${fg(255,80,80)}high${RESET}   `
                : "       ";
      const slug = c.slug.length > 24 ? c.slug : c.slug.padEnd(24);
      const goal = c.resolution_summary || c.goal || "";
      const goalTrim = goal.length > 50 ? goal.slice(0, 47) + "..." : goal;
      return `  ${icon} ${BOLD}#${String(c.id).padStart(2)}${RESET} ${slug} ${pri}${DIM}\u2014 ${goalTrim}${UNDIM}`;
    };

    const MAX_PER_GROUP = 6;

    if (resolved.length) {
      resolved.sort(sortByPri);
      out += `${fg(80,200,80)}${BOLD} RESOLVED (${resolved.length})${RESET}\n`;
      resolved.slice(0, MAX_PER_GROUP).forEach(c => { out += renderCase(c) + "\n"; });
      if (resolved.length > MAX_PER_GROUP) out += `${DIM}  ... +${resolved.length - MAX_PER_GROUP} more${UNDIM}\n`;
    }
    if (open.length) {
      open.sort(sortByPri);
      out += `${fg(255,200,50)}${BOLD} OPEN (${open.length})${RESET}\n`;
      open.slice(0, MAX_PER_GROUP).forEach(c => { out += renderCase(c) + "\n"; });
      if (open.length > MAX_PER_GROUP) out += `${DIM}  ... +${open.length - MAX_PER_GROUP} more (ctrl+o to expand)${UNDIM}\n`;
    }
    if (archived.length) {
      out += `${DIM}${BOLD} ARCHIVED (${archived.length})${RESET}\n`;
      archived.slice(0, 3).forEach(c => { out += renderCase(c) + "\n"; });
      if (archived.length > 3) out += `${DIM}  ... +${archived.length - 3} more${UNDIM}\n`;
    }

    if (deleted.length) {
      deleted.sort(sortByPri);
      out += `${fg(255,80,80)}${BOLD} DELETED (${deleted.length})${RESET}\n`;
      deleted.slice(0, MAX_PER_GROUP).forEach(c => { out += renderCase(c) + "\n"; });
      if (deleted.length > MAX_PER_GROUP) out += `${DIM}  ... +${deleted.length - MAX_PER_GROUP} more${UNDIM}\n`;
    }

    return out;
  } catch {
    return null;
  }
}

// ─── fprobe pretty renderer ──────────────────────────────────────
function renderFprobeResult(jsonStr, ctx = {}) {
  try {
    const d = JSON.parse(jsonStr);
    // Handle array results from strings and scan modes.
    const items = Array.isArray(d) ? d : d.items || d.matches || d.results;
    if (items && Array.isArray(items)) {
      const firstItem = items[0];
      const isScanResult = ctx.action === "scan" || (!!firstItem &&
        typeof firstItem === "object" &&
        (firstItem.match_length !== undefined ||
          firstItem.context_start !== undefined ||
          firstItem.context_end !== undefined));
      const mode = isScanResult ? "scan" : "strings";
      let out = theme.meta(`fprobe ${mode} | ${items.length} matches`) + "\n";
      const filter = (d && typeof d === "object" && !Array.isArray(d)) ? d.filter : undefined;
      items.forEach(item => {
        const offset = item.offset !== undefined ? item.offset : item.start;
        const hex = offset !== undefined ? `0x${offset.toString(16).padStart(4, "0")}` : "    ";
        let text = item.text || item.content || item.value || "";
        if (text.length > 80) text = "..." + text.slice(-77);
        // Highlight filter term if present
        if (filter && text.includes(filter)) {
          text = text.replace(new RegExp(filter.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"), "g"),
            `${fg(255,200,50)}${BOLD}${filter}${RESET}`);
        }
        out += `${fg(190,132,255)}${hex}${RESET} \u2502 ${text}\n`;
      });
      return out;
    }

    // Scan mode results
    if (d.matches !== undefined && typeof d.matches === "number") {
      let out = theme.meta(`fprobe scan | ${d.matches} matches`) + "\n";
      if (d.offsets && Array.isArray(d.offsets)) {
        d.offsets.forEach(o => {
          const hex = `0x${o.toString(16).padStart(8, "0")}`;
          out += `${fg(190,132,255)}${hex}${RESET}\n`;
        });
      }
      if (d.context_preview) out += `${DIM}${d.context_preview}${UNDIM}\n`;
      return out;
    }

    // Patch mode result
    if (d.patched !== undefined || d.dry_run !== undefined) {
      const patchedCount = Number.isInteger(d.patched) ? d.patched : 0;
      const noun = patchedCount === 1 ? "replacement" : "replacements";
      const status = d.dry_run ? `${fg(255,200,50)}Dry run${RESET}` : patchedCount > 0 ? `${fg(80,200,80)}Patched${RESET}` : `${fg(255,80,80)}Failed${RESET}`;
      let out = `${status} ${patchedCount} ${noun}`;
      if (d.file) out += ` in ${colorPath(d.file)}`;
      out += "\n";
      return out;
    }

    // Window mode — just show the hex/printable dump
    if (d.window || d.hex || d.printable) {
      return null; // fall through to raw JSON for window dumps
    }

    return null;
  } catch {
    return null;
  }
}

// ─── fbash pretty renderer ──────────────────────────────────────
function renderFbashResult(jsonStr, ctx = {}) {
  const d = maybeParseJson(jsonStr);
  if (!d || d.tool !== "fbash") return null;

  // ── Palette (local aliases for readability) ──────────────────
  const GOLD    = fg(255, 215, 0);     // 256:220 — fbash signature
  const OK      = fg(80, 200, 80);     // exit=0
  const ERR     = fg(255, 80, 80);     // non-zero exit / stderr label
  const WARN    = fg(255, 200, 50);    // warnings
  const INFO    = fg(102, 217, 238);   // duration / hints (royal-cyan so it stays readable on dark)
  const MUTE    = fg(170, 160, 140);   // stderr body (muted warm — distinct from stdout without screaming)
  const GRAY    = fg(150, 150, 150);   // dim labels

  const MAX_STDOUT_LINES = ctx.full ? Number.POSITIVE_INFINITY : (ctx.maxLines ?? 30);
  const MAX_STDERR_LINES = ctx.full
    ? Number.POSITIVE_INFINITY
    : (ctx.maxLines != null ? Math.max(Math.round(ctx.maxLines / 3), 10) : 10);

  const out = [];

  // ── Header line ──────────────────────────────────────────────
  // Format: [bold gold]fbash[reset]  class=general  12ms  exit=0
  const headerParts = [`${BOLD}${GOLD}fbash${RESET}`];
  if (d.command_class) {
    headerParts.push(`${GRAY}class=${d.command_class}${RESET}`);
  }
  if (typeof d.duration_ms === "number") {
    headerParts.push(`${INFO}${d.duration_ms}ms${RESET}`);
  }
  if (d.exit_code == null) {
    // Background or still-running — no exit badge in header
  } else if (d.exit_code === 0) {
    headerParts.push(`${OK}exit=0${RESET}`);
  } else {
    headerParts.push(`${ERR}${BOLD}exit=${d.exit_code}${RESET}`);
  }
  out.push(headerParts.join("  "));

  // ── Background job callout ───────────────────────────────────
  // Background jobs have exit_code=null and metadata.background_job_id set.
  // Skip stdout/stderr for bg jobs — they haven't produced final output yet.
  const bgId = d.metadata?.background_job_id;
  const bgStatus = d.metadata?.background_status;
  const isBackgroundStart = bgId && d.exit_code == null && bgStatus !== "completed";
  if (isBackgroundStart) {
    const pollHint = d.next_hint ? ` ${DIM}· poll:${UNDIM} ${INFO}${d.next_hint}${RESET}` : "";
    out.push(`${GRAY}[bg job ${bgId} started${d.command ? ` · ${d.command}` : ""}${pollHint}${GRAY}]${RESET}`);
    return out.join("\n") + "\n";
  }

  // ── stdout block ─────────────────────────────────────────────
  const stdoutStr = typeof d.stdout === "string" ? d.stdout : "";
  if (stdoutStr.length > 0) {
    // Preserve whitespace; strip trailing newline for clean rendering.
    const trimmed = stdoutStr.replace(/\n+$/, "");
    const stdoutLines = trimmed.split("\n");
    const shown = stdoutLines.slice(0, MAX_STDOUT_LINES);
    for (const line of shown) out.push(`  ${line}`);
    if (stdoutLines.length > MAX_STDOUT_LINES) {
      const extra = stdoutLines.length - MAX_STDOUT_LINES;
      out.push(`  ${DIM}... ${extra} more line${extra === 1 ? "" : "s"}${RESET}`);
    }
  }

  // ── stderr block (only if non-empty) ────────────────────────
  const stderrStr = typeof d.stderr === "string" ? d.stderr : "";
  if (stderrStr.length > 0) {
    const trimmed = stderrStr.replace(/\n+$/, "");
    const stderrLines = trimmed.split("\n");
    out.push(`${ERR}${BOLD}stderr${RESET}${GRAY}:${RESET}`);
    const shown = stderrLines.slice(0, MAX_STDERR_LINES);
    for (const line of shown) out.push(`  ${MUTE}${line}${RESET}`);
    if (stderrLines.length > MAX_STDERR_LINES) {
      const extra = stderrLines.length - MAX_STDERR_LINES;
      out.push(`  ${DIM}... ${extra} more stderr line${extra === 1 ? "" : "s"}${RESET}`);
    }
  }

  // ── Silent-success / silent-failure indicator ───────────────
  if (stdoutStr.length === 0 && stderrStr.length === 0) {
    if (d.exit_code === 0) {
      out.push(`  ${DIM}(silent success)${RESET}`);
    } else if (d.exit_code != null && d.exit_code !== 0) {
      out.push(`  ${DIM}(no output)${RESET}`);
    }
  }

  // ── Truncation note ─────────────────────────────────────────
  if (d.truncated && d.truncation_reason) {
    out.push(`${WARN}\u26a0 truncated:${RESET} ${DIM}${d.truncation_reason}${RESET}`);
  }

  // ── Warnings ────────────────────────────────────────────────
  const warnings = Array.isArray(d.warnings) ? d.warnings : [];
  for (const w of warnings) {
    out.push(`${WARN}\u26a0${RESET} ${DIM}${w}${RESET}`);
  }

  // ── Routing suggestion / next_hint (only one, prefer routing) ─
  const routing = d.routing_suggestion;
  if (routing && routing.tool) {
    out.push(`${INFO}\u2192 hint: use ${BOLD}${routing.tool}${RESET}${INFO}${routing.reason ? ` — ${routing.reason}` : ""}${RESET}`);
  } else if (d.next_hint && !isBackgroundStart) {
    out.push(`${INFO}\u2192 next:${RESET} ${DIM}${d.next_hint}${RESET}`);
  }

  return out.join("\n") + "\n";
}

// Tool → renderer mapping
const RENDERERS = {
  fedit: renderFeditResult,
  fwrite: renderFeditResult,
  fread: renderFreadResult,
  fmap: renderFmapResult,
  fcontent: renderFcontentResult,
  ftree: renderFtreeResult,
  fls: renderFtreeResult,
  fsearch: renderFsearchResult,
  fcase: renderFcaseResult,
  fprobe: renderFprobeResult,
  fbash: renderFbashResult,
};

function maybeParseJson(raw) {
  try {
    return JSON.parse(raw);
  } catch {
    return undefined;
  }
}

function normalizeStructuredContent(parsed) {
  if (parsed === undefined) return undefined;
  // MCP results are happiest when structured content is object-shaped.
  // Preserve array payloads without forcing agents to scrape text output.
  if (Array.isArray(parsed)) return { items: parsed };
  return parsed;
}

// ─── Helper: strip redundant/telemetry fields from structured JSON ──
// Runs AFTER normalizeStructuredContent, BEFORE return in cli().
// Goal: reduce token waste — agents don't need internal telemetry or
// duplicate representations (lines[] vs tree_json, size_human vs size_bytes).
function slimStructuredContent(obj) {
  if (obj === undefined || obj === null) return obj;

  // Top-level keys to remove entirely
  const TOP_STRIP = new Set([
    "tool", "version", "mode", "backend",
    "budget_seconds", "budget_used_seconds", "budget_budget",
    "recon_depth", "ignored",
    // fbash-specific bloat: all rendered in pretty text or useless to agent
    "command",          // shown in pretty text header
    "command_class",    // internal routing info
    "cwd_changed",      // agent sees cwd in pretty header
    "stdout_lines",     // agent can count
    "stderr_lines",     // agent can count
    "truncated",        // shown in pretty text warnings
    "truncation_reason", // shown in pretty text
    "lines_total",      // telemetry only
    "bytes_total",      // telemetry only
    "token_estimate",   // telemetry only
    "routing_suggestion", // rendered as hint in pretty text
    "metadata",         // internal — files_modified, background_job_id rendered in pretty text
    "warnings",         // already rendered in pretty text
    "errors",           // already rendered in pretty text
    // fread-specific telemetry: rendered in pretty header or internal-only
    "token_estimator",  // internal implementation detail
    "bytes_emitted",    // telemetry only
    "lines_emitted",    // agent can see content directly
    "max_lines",        // budget config, not useful to agent
    "max_bytes",        // budget config, not useful to agent
    "token_budget",     // budget config, not useful to agent
    "resolved_path",    // redundant with path inside files[]
    "paths_tried",      // internal diagnostic
    // fsearch internal diagnostics
    "search_type",      // internal routing
    "match_mode",       // internal routing
    "preview_limit",    // internal config
    "count_mode",       // internal config
  ]);

  // Keys to remove from nested objects only (keep top-level duration_ms)
  const NESTED_STRIP = new Set([
    "version",
    "budget_seconds", "budget_used_seconds", "budget_budget",
    "recon_depth", "ignored",
    "size_human",
  ]);

  function slim(node, depth) {
    if (node === null || node === undefined) return node;
    if (depth >= 20) return node;
    if (Array.isArray(node)) return node.map(item => slim(item, depth));
    if (typeof node !== "object") return node;

    const strip = depth === 0 ? TOP_STRIP : NESTED_STRIP;
    const out = {};
    for (const [k, v] of Object.entries(node)) {
      if (strip.has(k)) continue;
      // Drop lines[] from tree output — tree_json has the data
      if (k === "lines" && node.tree_json) continue;
      out[k] = slim(v, depth + 1);
    }

    // Flatten single-key nesting: { snapshot: { recon: X, tree: Y } } stays,
    // but { result: { ...data } } flattens when only one key remains.
    const keys = Object.keys(out);
    if (keys.length === 1) {
      const only = out[keys[0]];
      // Flatten { wrapper: <object> } but not { wrapper: <primitive/array> }
      // Exception: keep "items" wrapper for arrays (normalizeStructuredContent made it)
      if (typeof only === "object" && only !== null && !Array.isArray(only) && keys[0] !== "items") {
        return only;
      }
    }
    return out;
  }

  return slim(obj, 0);
}


// ─── Helper: translate fread media_payload → MCP content blocks ──
// Phase 3: Engine emits snake_case mime_type; MCP spec uses camelCase mimeType.
// MIME string itself is identical (image/png, image/jpeg, application/pdf).
// Only the JSON field NAME differs — we translate via field name when emitting.
function mediaMimeType(rawMime) {
  return typeof rawMime === "string" && rawMime ? rawMime : "application/octet-stream";
}

function imageMetaSummary(payload) {
  const f = payload?.file || {};
  const dims = f.dimensions || {};
  const fmt = (f.format || "").toUpperCase();
  const w = dims.width ?? "?";
  const h = dims.height ?? "?";
  const size = f.original_size ?? "?";
  const tokens = f.tokens_estimate;
  const tokensPart = tokens !== undefined ? ` (~${tokens} tokens)` : "";
  let line = `Image: ${fmt} ${w}×${h}, ${size} bytes${tokensPart}`;
  if (f.resized) line += " [resized]";
  if (f.budget_exceeded) line += " [budget exceeded — quality degraded]";
  return line;
}

function pdfTextHeader(payload) {
  const f = payload?.file || {};
  const total = f.page_count ?? "?";
  const returned = Array.isArray(f.pages_returned) ? f.pages_returned.length : (f.pages_returned ?? "?");
  const tokens = f.tokens_estimate ?? "?";
  let header = `PDF: ${returned}/${total} pages, ${tokens} tokens`;
  if (f.truncated) header += " [truncated]";
  if (payload?.backend) header += ` (backend: ${payload.backend})`;
  return header + "\n\n";
}

function pdfPagesSummary(payload) {
  const f = payload?.file || {};
  const count = f.count ?? (Array.isArray(f.pages) ? f.pages.length : "?");
  const total = f.page_count ?? "?";
  const size = f.original_size ?? "?";
  const backend = payload?.backend ?? "?";
  return `PDF rendered ${count}/${total} pages, ${size} bytes (backend: ${backend})`;
}

function pdfMetaSummary(payload) {
  const f = payload?.file || {};
  const ps = f.page_size || {};
  const psStr = (ps.width !== undefined && ps.height !== undefined) ? `${ps.width}×${ps.height}` : "unknown";
  const fmtVal = (v) => v === null || v === undefined ? "unknown" : String(v);
  return [
    "PDF metadata:",
    `  pages: ${fmtVal(f.page_count)}`,
    `  page_size: ${psStr}`,
    `  encrypted: ${fmtVal(f.encrypted)}`,
    `  has_text: ${fmtVal(f.has_text)}`,
    `  embedded_images: ${fmtVal(f.embedded_image_count)}`,
    `  backend: ${fmtVal(payload?.backend)}`,
  ].join("\n");
}

function mediaByteBudget(maxBytes) {
  return {
    maxBytes: Number.isFinite(maxBytes) && maxBytes > 0 ? maxBytes : 0,
    usedBytes: 0,
  };
}

function utf8Bytes(value) {
  return Buffer.byteLength(String(value ?? ""), "utf8");
}

function truncateUtf8(value, maxBytes) {
  const text = String(value ?? "");
  if (!Number.isFinite(maxBytes) || maxBytes <= 0) return text;
  if (Buffer.byteLength(text, "utf8") <= maxBytes) return text;
  let out = "";
  let usedBytes = 0;
  for (const ch of text) {
    const bytes = Buffer.byteLength(ch, "utf8");
    if (usedBytes + bytes > maxBytes) break;
    out += ch;
    usedBytes += bytes;
  }
  return out;
}

function appendBudgetedText(blocks, budget, text) {
  if (!text) return;
  if (!budget?.maxBytes) {
    blocks.push({ type: "text", text });
    return;
  }
  const remaining = budget.maxBytes - budget.usedBytes;
  if (remaining <= 0) return;
  const out = truncateUtf8(text, remaining);
  if (!out) return;
  budget.usedBytes += utf8Bytes(out);
  blocks.push({ type: "text", text: out });
}

function appendBudgetedImage(blocks, budget, data, mimeType) {
  if (typeof data !== "string" || !data) return false;
  const bytes = utf8Bytes(data);
  if (budget?.maxBytes && budget.usedBytes + bytes > budget.maxBytes) {
    return false;
  }
  if (budget?.maxBytes) budget.usedBytes += bytes;
  blocks.push({ type: "image", data, mimeType });
  return true;
}

function buildMediaContent(payload, opts) {
  if (!payload || typeof payload !== "object") return null;
  const full = Boolean(opts?.full);
  const maxLines = !full && opts && Number.isFinite(opts.maxLines) && opts.maxLines > 0 ? opts.maxLines : 0;
  const budget = opts?.budget || mediaByteBudget(full ? 0 : opts?.maxBytes);
  switch (payload.type) {
    case "image": {
      const f = payload.file || {};
      const blocks = [];
      let imageIncluded = false;
      const hasImagePayload = typeof f.base64 === "string" && f.base64;
      if (hasImagePayload) {
        imageIncluded = appendBudgetedImage(blocks, budget, f.base64, mediaMimeType(f.mime_type));
      }
      const omitted = hasImagePayload && !imageIncluded ? "[media omitted: max_bytes cap blocked image payload]\n" : "";
      appendBudgetedText(blocks, budget, omitted + imageMetaSummary(payload));
      return { content: blocks };
    }
    case "image-meta":
      {
        const blocks = [];
        appendBudgetedText(blocks, budget, imageMetaSummary(payload));
        return { content: blocks.length ? blocks : [{ type: "text", text: "" }] };
      }
    case "pdf-text": {
      const f = payload.file || {};
      let text = f.text || "";
      let truncationNote = "";
      if (maxLines && text) {
        const lines = text.split("\n");
        if (lines.length > maxLines) {
          text = lines.slice(0, maxLines).join("\n");
          truncationNote = `\n... [truncated: ${lines.length - maxLines} more lines; raise max_lines to see all]\n`;
        }
      }
      const blocks = [];
      appendBudgetedText(blocks, budget, pdfTextHeader(payload) + text + truncationNote);
      return { content: blocks.length ? blocks : [{ type: "text", text: "" }] };
    }
    case "pdf-pages": {
      const f = payload.file || {};
      const pages = Array.isArray(f.pages) ? f.pages : [];
      const blocks = [];
      let omittedPages = 0;
      for (const page of pages) {
        if (!page || typeof page.base64 !== "string" || !page.base64) continue;
        if (!appendBudgetedImage(blocks, budget, page.base64, mediaMimeType(page.mime_type))) {
          omittedPages += 1;
        }
      }
      const omitted = omittedPages ? `[media omitted: max_bytes cap blocked ${omittedPages} rendered page(s)]\n` : "";
      appendBudgetedText(blocks, budget, omitted + pdfPagesSummary(payload));
      return { content: blocks };
    }
    case "pdf-meta":
      {
        const blocks = [];
        appendBudgetedText(blocks, budget, pdfMetaSummary(payload));
        return { content: blocks.length ? blocks : [{ type: "text", text: "" }] };
      }
    default:
      return null;
  }
}

function isMediaPayloadObject(value) {
  return Boolean(value && typeof value === "object" && [
    "image",
    "image-meta",
    "pdf-text",
    "pdf-pages",
    "pdf-meta",
  ].includes(value.type));
}

function isMediaJsonChunk(chunk) {
  const content = Array.isArray(chunk?.content) ? chunk.content : [];
  if (content.length !== 1 || typeof content[0] !== "string") return false;
  return isMediaPayloadObject(maybeParseJson(content[0]));
}

function textOnlyFreadPayload(parsed) {
  if (!parsed || typeof parsed !== "object" || !Array.isArray(parsed.chunks)) return null;
  const mediaPaths = new Set();
  const chunks = [];
  for (const chunk of parsed.chunks) {
    if (isMediaJsonChunk(chunk)) {
      if (chunk.path) mediaPaths.add(chunk.path);
      continue;
    }
    chunks.push(chunk);
  }
  if (chunks.length === 0) return null;

  const files = Array.isArray(parsed.files)
    ? parsed.files.filter((file) => !mediaPaths.has(file.path))
    : parsed.files;
  const lines = chunks.reduce((total, chunk) => total + (Array.isArray(chunk.content) ? chunk.content.length : 0), 0);
  return {
    ...parsed,
    chunks,
    files,
    lines_emitted: lines,
  };
}

function renderFreadTextResult(raw, parsed, opts = {}) {
  const slim = slimStructuredContent(normalizeStructuredContent(parsed));
  const renderer = RENDERERS["fread"];
  if (renderer) {
    const pretty = renderer(raw, { maxLines: opts.maxLines, full: opts.full });
    if (pretty) return { content: [{ type: "text", text: pretty }] };
    const result = { content: [{ type: "text", text: "(fread: renderer yielded no output)\n" }] };
    if (slim !== undefined) result.structuredContent = slim;
    return result;
  }
  const noRendererResult = { content: [{ type: "text", text: raw }] };
  if (slim !== undefined) noRendererResult.structuredContent = slim;
  return noRendererResult;
}

function buildFreadMcpContent(raw, parsed, opts = {}) {
  const mediaBudget = opts.full ? mediaByteBudget(0) : (opts.budget || mediaByteBudget(opts.maxBytes));
  const mediaPayloads = parsed && Array.isArray(parsed.media_payloads) && parsed.media_payloads.length > 0
    ? parsed.media_payloads
    : (parsed && parsed.media_payload ? [parsed.media_payload] : []);
  if (mediaPayloads.length === 0) {
    return renderFreadTextResult(raw, parsed, opts);
  }

  const merged = [];
  for (const payload of mediaPayloads) {
    const built = buildMediaContent(payload, { ...opts, budget: mediaBudget });
    if (built && Array.isArray(built.content)) merged.push(...built.content);
  }

  const textPayload = textOnlyFreadPayload(parsed);
  if (textPayload) {
    const renderedText = renderFreadTextResult(JSON.stringify(textPayload), textPayload, opts);
    if (renderedText && Array.isArray(renderedText.content)) merged.push(...renderedText.content);
  }

  const result = { content: merged.length ? merged : [{ type: "text", text: "" }] };

  // Preserve diagnostic/meta fields from the original parsed result
  if (parsed) {
    if (parsed.warnings) result.warnings = parsed.warnings;
    if (parsed.errors) result.errors = parsed.errors;
    if (parsed.next_hint) result.next_hint = parsed.next_hint;
    if (parsed.files) result.files = parsed.files;
  }

  return result;
}

// ─── Helper: run CLI tool, pretty-render if possible ─────────────
function formatExecError(err, tool, renderAs, renderContext) {
  // Try to parse JSON from stdout first, then stderr, then fall back to plain text
  let errorText = err.message;
  let parsed = undefined;
  const parsedErrorText = (value) => {
    if (!value || typeof value !== "object") return "";
    if (value.errors?.length) {
      return value.errors.map((e) => e.error_detail || e.error || e).join("; ");
    }
    if (value.error_detail) return value.error_detail;
    if (value.error) return value.error;
    if (typeof value.stderr === "string" && value.stderr.trim()) return value.stderr;
    if (typeof value.stdout === "string" && value.stdout.trim()) return value.stdout;
    return "";
  };

  if (err.stdout) {
    try {
      parsed = JSON.parse(err.stdout);
      // fbash: non-zero exit is normal (command failed, not tool failed)
      // Return as success with the structured JSON so renderers can display it
      if (parsed && typeof parsed.exit_code === "number" && tool === "fbash") {
        const raw = err.stdout;
        const pretty = RENDERERS[renderAs || tool]?.(raw, renderContext);
        if (pretty) return { content: [{ type: "text", text: pretty }] };
        return { content: [{ type: "text", text: raw }] };
      }
      const message = parsedErrorText(parsed);
      if (message) errorText = message;
    } catch { /* not JSON in stdout, try stderr */ }
  }
  if ((errorText === err.message || !parsed) && err.stderr) {
    try {
      const stderrParsed = JSON.parse(err.stderr);
      if (!parsed) parsed = stderrParsed;
      const message = parsedErrorText(stderrParsed);
      if (message) errorText = message;
    } catch { /* not JSON in stderr, use plain text */ }
  }

  if (errorText === err.message) {
    errorText = err.stderr || err.stdout || err.message;
  }

  return { content: [{ type: "text", text: `Error running ${tool}: ${errorText}` }], isError: true };
}

async function cli(tool, args, renderAs, renderContext) {
  try {
    const opts = execOptsFor(tool);
    const { stdout, stderr } = await run(resolveTool(tool), args, opts);
    const raw = stdout || stderr || "(no output)";
    const parsed = slimStructuredContent(normalizeStructuredContent(maybeParseJson(raw)));

        // Pretty ANSI for user display. structuredContent intentionally omitted —
        // Claude Code's "early return blender" discards content[text] when
        // structuredContent exists, so rendered tools must return content[text] only.
      const renderer = RENDERERS[renderAs || tool];
      if (renderer) {
        const pretty = renderer(raw, renderContext);
        if (pretty) {
          // When renderer produces pretty ANSI, return content[text] only.
          // Claude Code's "early return blender" discards content[text]
          // when structuredContent exists — so we must omit it here.
          const result = { content: [{ type: "text", text: pretty }] };
          return result;
        }
        // Renderer existed but returned null (unexpected tool output or wrong tool field).
        // Do NOT fall through to content[text]=raw — that dumps the full raw JSON to the user.
        // Return structuredContent only (slim metadata) with a minimal placeholder text.
        const result = { content: [{ type: "text", text: `(${renderAs || tool}: renderer yielded no output)\n` }] };
        if (parsed !== undefined) result.structuredContent = parsed;
        return result;
      }

      // No renderer registered for this tool — pass raw output + structuredContent to caller.
      const noRendererResult = { content: [{ type: "text", text: raw }] };
      if (parsed !== undefined) noRendererResult.structuredContent = parsed;
      return noRendererResult;
  } catch (err) {
    return formatExecError(err, tool, renderAs, renderContext);
  }
}

// ─── Server ──────────────────────────────────────────────────────
const server = new McpServer({ name: "fsuite", version: "3.3.0" });

// ─── ftree ───────────────────────────────────────────────────────
server.registerTool(
  "ftree",
  {
    title: coloredTitle("ftree"),
    description:
      "Scout a directory — returns full tree structure, file sizes, and recon data in one call. " +
      "Replaces multiple Glob/LS calls. Use snapshot=true for combined recon+tree (recommended).",
    inputSchema: z.object({
      path: z.string().describe("Directory to scan"),
      snapshot: z.boolean().default(true).describe("Combined recon + tree mode (recommended)"),
      depth: z.number().optional().describe("Tree depth limit"),
    }),
  },
  async ({ path, snapshot, depth }) => {
    const args = [];
    if (snapshot) args.push("--snapshot");
    args.push("-o", "json");
    if (depth) args.push("--depth", String(depth));
    args.push(path);
    return cli("ftree", args);
  }
);

// ─── fmap ────────────────────────────────────────────────────────
server.registerTool(
  "fmap",
  {
    title: coloredTitle("fmap"),
    description:
      "Code cartography — extract all symbols (functions, classes, imports, constants) from files. " +
      "Returns symbol name, line number, type, and indent. No native equivalent exists. 15+ languages.",
    inputSchema: z.object({
      path: z.string().describe("File or directory to map"),
    }),
  },
  async ({ path }) => cli("fmap", ["-o", "json", path])
);

// ─── fread ───────────────────────────────────────────────────────
server.registerTool(
  "fread",
  {
    title: coloredTitle("fread"),
    description:
      "Budgeted file reading with symbol resolution. Use symbol to read exactly one function/class " +
      "by name — no guessing line ranges. Use around for context around a pattern match.",
    inputSchema: z.object({
      path: z.string().optional().describe("File path (or directory when using symbol). Ignored when paths is provided."),
      paths: z.array(z.string()).optional().describe("Array of file paths to try in order. Returns content from first existing path."),
      symbol: z.string().optional().describe("Read exactly one symbol (function, class, etc.) by name"),
      lines: z.string().optional().describe("Line range, e.g. '120:220'"),
      around: z.string().optional().describe("Show context around first literal pattern match"),
      around_line: z.number().optional().describe("Show context around a specific line number"),
      before: z.number().optional().describe("Lines of context before match (default 5)"),
      after: z.number().optional().describe("Lines of context after match (default 10)"),
      head: z.number().optional().describe("Read first N lines"),
      tail: z.number().optional().describe("Read last N lines"),
      max_lines: z.number().int().nonnegative().optional().describe("Cap total lines emitted (0/default = uncapped)"),
      no_truncate: z.boolean().optional().describe("Alias for full; disable fread budgets and MCP preview truncation"),
      meta_only: z.boolean().optional().describe("Media: skip body, return metadata only (image dimensions / PDF page count + encryption + page size)"),
      render: z.boolean().optional().describe("Media: PDF — render pages to images instead of extracting text. Capped at 10 pages without max_pages."),
      pages: z.string().optional().describe("Media: PDF page range, e.g. '1:5'. With render, picks which pages to rasterize; with text mode, restricts extraction."),
      no_resize: z.boolean().optional().describe("Media: image — return raw base64 without auto-resize. Refused if estimated tokens exceed budget."),
      max_pages: z.number().int().positive().optional().describe("Media: PDF — raise the 10-page render cap."),
      max_tokens: z.number().int().nonnegative().optional().describe("Media: image — token budget for the resize loop (default 6000; 0 disables the cap)."),
      no_ingest: z.boolean().optional().describe("Media: skip the ShieldCortex memory-ingest spawn for this read."),
      max_bytes: z.number().int().nonnegative().optional().describe("Cap total bytes emitted (0/default = uncapped)"),
      token_budget: z.number().int().nonnegative().optional().describe("Cap by estimated tokens"),
      full: z.boolean().optional().describe("Disable fread budgets and MCP preview truncation"),
      }),
    },
    async ({ path, paths, symbol, lines, around, around_line, before, after, head, tail, max_lines, max_bytes, token_budget, full, no_truncate, meta_only, render, pages, no_resize, max_pages, max_tokens, no_ingest }) => {
      const args = [];
    if (paths && paths.length > 0) {
      args.push("--paths", paths.map((p) => p.replace(/,/g, "\\,")).join(","));
    } else if (path) {
      args.push(path);
    } else {
      return { content: [{ type: "text", text: "fread: error: Either path or paths is required" }], isError: true };
    }
    if (symbol) args.push("--symbol", symbol);
    if (lines) args.push("-r", lines);
    if (around) args.push("--around", around);
    if (around_line !== undefined) args.push("--around-line", String(around_line));
    if (before !== undefined) args.push("-B", String(before));
    if (after !== undefined) args.push("-A", String(after));
      if (head !== undefined) args.push("--head", String(head));
      if (tail !== undefined) args.push("--tail", String(tail));
      if (max_lines !== undefined) args.push("--max-lines", String(max_lines));
      if (max_bytes !== undefined) args.push("--max-bytes", String(max_bytes));
      if (token_budget !== undefined) args.push("--token-budget", String(token_budget));
      if (meta_only) args.push("--meta-only");
      if (render) args.push("--render");
      if (pages) args.push("--pages", pages);
      if (no_resize) args.push("--no-resize");
      if (max_pages !== undefined) args.push("--max-pages", String(max_pages));
      if (max_tokens !== undefined) args.push("--max-tokens", String(max_tokens));
      if (no_ingest) args.push("--no-ingest");
      const wantsFull = Boolean(full || no_truncate);
      if (wantsFull) args.push("--no-truncate");
      args.push("-o", "json");

      // Phase 3: Media-aware short-circuit. Engine emits media_payload(s) for
      // images/PDFs — translate directly to MCP image/text content blocks
      // and bypass cli()'s text-only renderer. Any failure falls through to
      // the normal text path so we never crash the MCP server.
      try {
        const opts = execOptsFor("fread");
        const { stdout, stderr } = await run(resolveTool("fread"), args, opts);
        const raw = stdout || stderr || "(no output)";
        const parsed = maybeParseJson(raw);
        // Media and text chunks can coexist in stdin/multi-file batches. Build
        // media blocks first, then append rendered non-media chunks if present.
        return buildFreadMcpContent(raw, parsed, {
          maxLines: max_lines,
          maxBytes: max_bytes,
          full: wantsFull,
        });
      } catch (err) {
        return formatExecError(err, "fread", undefined, { maxLines: max_lines, full: wantsFull });
      }
    }
  );

// ─── fcontent ────────────────────────────────────────────────────
server.registerTool(
  "fcontent",
  {
    title: coloredTitle("fcontent"),
    description:
      "Search inside files for literal strings. Wraps ripgrep with agent-friendly output. " +
      "MCP mode forces fixed-string matching by default so regex metacharacters stay literal. " +
      "For multiple terms, call multiple times.",
    inputSchema: z.object({
      query: z.string().describe("Literal string to search for"),
      path: z.string().optional().describe("Directory to search (recursive). Default: cwd"),
      max_matches: z.number().optional().describe("Limit matched lines (default 200)"),
      case_insensitive: z.boolean().optional().describe("Case-insensitive search"),
    }),
  },
  async ({ query, path, max_matches, case_insensitive }) => {
    return cli("fcontent", buildFcontentArgs({ query, path, max_matches, case_insensitive }));
  }
);

// ─── fsearch ─────────────────────────────────────────────────────
server.registerTool(
  "fsearch",
  {
    title: coloredTitle("fsearch"),
    description: "Find files or directories by name or path, with optional shallow directory preview.",
    inputSchema: z.object({
      query: z.string().describe("Literal, glob, or extension-style search input"),
      path: z.string().optional().describe("Directory to search"),
      type: z.enum(["file", "dir", "both"]).optional()
        .describe("Search files, directories, or both. Default: file"),
      match: z.enum(["name", "path", "both"]).optional()
        .describe("Match against basename, full path, or both. Default: name"),
      mode: z.enum(["auto", "literal", "glob", "ext"]).optional()
        .describe("Query interpretation mode. Default: auto"),
      preview: z.number().optional()
        .describe("Directory preview child limit. Default: 0"),
    }),
    // outputSchema removed: 2.1.88 StructuredOutput schema cache bug
    // causes silent failures with multiple schemas across tools.
  },
  async ({ query, path, type, match, mode, preview }) => {
    const args = ["-o", "json"];
    if (type) args.push("--type", type);
    if (match) args.push("--match", match);
    if (mode) args.push("--mode", mode);
    if (preview !== undefined) args.push("--preview", String(preview));
    args.push(query);
    if (path) args.push(path);
    try {
      const { stdout } = await run(resolveTool("fsearch"), args, execOptsFor("fsearch"));
      try {
        const parsed = JSON.parse(stdout);
        const rendered = renderFsearchStructured(parsed);
        if (typeof rendered !== "string") {
          return { content: [{ type: "text", text: stdout }] };
        }
        return {
          content: [{ type: "text", text: rendered }],
        };
      } catch (renderErr) {
        console.error("fsearch render error:", renderErr);
        return { content: [{ type: "text", text: stdout }] };
      }
    } catch (err) {
      return { content: [{ type: "text", text: `fsearch error: ${err.stderr || err.message || "unknown"}` }], isError: true };
    }
  }
);

// ─── fedit ───────────────────────────────────────────────────────
server.registerTool(
  "fedit",
  {
    title: coloredTitle("fedit"),
    description:
      "Surgical file editing — PREFERRED over native Edit. Auto-applies by default. " +
      "Supports symbol-scoped patches (--function), insert after/before anchors, line-range replace, and preconditions. " +
      "No need to read file first. Use function_name to scope edits without needing unique context. " +
      "Use after/before to INSERT text at an anchor point instead of replacing. " +
      "Use lines to replace a line range directly (e.g. '71:73') — fastest mode when you know the line numbers from fread.",
    inputSchema: z.object({
      path: z.string().describe("File to edit"),
      replace: z.string().optional().describe("Text to find and replace (omit when using after/before/lines mode)"),
      with_text: z.string().describe("Replacement text, or text to insert when using after/before"),
      function_name: z.string().optional().describe("Scope edit to this function/symbol — no need for large unique context"),
      after: z.string().optional().describe("Insert with_text AFTER this anchor text (insert mode)"),
      before: z.string().optional().describe("Insert with_text BEFORE this anchor text (insert mode)"),
      lines: z.string().optional().describe("Replace line range directly, e.g. '71:73'. Fastest mode — no text matching needed. Use line numbers from fread."),
      apply: z.boolean().default(true).describe("Apply changes (default: true). Set false for dry-run preview."),
      expect: z.string().optional().describe("Precondition — text that must exist in file for edit to proceed"),
      no_validate: z.boolean().optional().describe("Skip structural validation (escape hatch for JSONC, test fixtures)"),
    }),
  },
  async ({ path, replace, with_text, function_name, after, before, lines, apply, expect, no_validate }) => {
    const args = [path];
    if (function_name) args.push("--function", function_name);
    if (lines) {
      args.push("--lines", lines, "--with", with_text);
    } else if (after) {
      args.push("--after", after, "--with", with_text);
    } else if (before) {
      args.push("--before", before, "--with", with_text);
    } else if (replace) {
      args.push("--replace", replace, "--with", with_text);
    }
    if (apply) args.push("--apply");
    if (expect) args.push("--expect", expect);
    if (no_validate) args.push("--no-validate");
    args.push("-o", "json");
    return cli("fedit", args);
  }
);

// ─── fwrite ──────────────────────────────────────────────────────
// Two doorways, one brain. fwrite routes through fedit --create / --replace-file.
server.registerTool(
  "fwrite",
  {
    title: coloredTitle("fwrite"),
    description:
      "Create a new file or replace an existing one. Routes through fedit (one mutation brain). " +
      "Set overwrite=true to replace existing files. Auto-applies by default.",
    inputSchema: z.object({
      path: z.string().describe("Absolute file path to write"),
      content: z.string().describe("File content to write"),
      overwrite: z.boolean().default(false).describe("Replace existing file (default: false = create only)"),
      apply: z.boolean().default(true).describe("Apply changes (default: true). Set false for dry-run preview."),
    }),
  },
  async ({ path: filePath, content, overwrite, apply }) => {
    // Write content to a temp file for fedit --content-file
    let tmpDir, tmpFile;
    try {
      tmpDir = await mkdtemp(join(tmpdir(), "fwrite-"));
      tmpFile = join(tmpDir, "payload");
      await fsWriteFile(tmpFile, content, "utf-8");

      const args = [];
      if (overwrite) {
        args.push("--replace-file", filePath, "--content-file", tmpFile);
      } else {
        args.push("--create", filePath, "--content-file", tmpFile);
      }
      if (apply) args.push("--apply");
      args.push("-o", "json");

      return await cli("fedit", args);
    } finally {
      // Cleanup temp file
      if (tmpFile) try { await unlink(tmpFile); } catch {}
      if (tmpDir) try { await rmdir(tmpDir); } catch {}
    }
  }
);

// ─── fcase ───────────────────────────────────────────────────────
  server.registerTool(
    "fcase",
    {
      title: coloredTitle("fcase"),
      description:
        "Investigation continuity ledger. Track findings, evidence, and handoff state across sessions. Supports full lifecycle: open, resolve, archive, delete. Search resolved cases with find.",
      inputSchema: z.object({
        action: z.enum(["init", "note", "status", "list", "next", "handoff", "export",
          "resolve", "archive", "delete", "find"]).describe("Case action"),
        slug: z.string().optional().describe("Case identifier (e.g. 'auth-refactor')"),
        goal: z.string().optional().describe("Case goal (for init)"),
        body: z.string().optional().describe("Note body (for note/next)"),
        priority: z.enum(["low", "medium", "high", "critical"]).optional(),
        summary: z.string().optional().describe("Resolution summary (required for resolve action)"),
        reason: z.string().optional().describe("Deletion reason (required for delete action)"),
        confirm_delete: z.string().optional().describe("Must be literal 'DELETE' to confirm deletion"),
        query: z.string().optional().describe("Search query (for find action)"),
        deep: z.boolean().optional().describe("Deep search including evidence/hypotheses (for find)"),
        statuses: z.string().optional().describe("Comma-separated status filter: open,resolved,archived,deleted,all (for list/find)"),
      }),
    },
    async ({ action, slug, goal, body, priority, summary, reason, confirm_delete, query, deep, statuses }) => {
      const args = [action];
      const outputModeByAction = {
        init: "json",
        status: "json",
        list: "json",
        next: "json",
    note: "json",
    handoff: "json",
        export: "json",
        resolve: "json",
        archive: "json",
        delete: "json",
        find: "json",
      };
      if (action === "find" && query) {
        args.push(query);
      } else if (slug) {
        args.push(slug);
      }
      if (goal) args.push("--goal", goal);
      if (body) args.push("--body", body);
      if (priority) args.push("--priority", priority);
      if (summary) args.push("--summary", summary);
      if (reason) args.push("--reason", reason);
      if (confirm_delete) args.push("--confirm", confirm_delete);
      if (deep) args.push("--deep");
      if (statuses) args.push("--status", statuses);
      const outputMode = outputModeByAction[action];
      if (outputMode) args.push("-o", outputMode);
      return cli("fcase", args);
    }
  );

  // ─── fmetrics ────────────────────────────────────────────────────
  server.registerTool(
    "fmetrics",
    {
      title: coloredTitle("fmetrics"),
      description: "Telemetry analytics — import data, inspect stats/history, mine combos, recommend next steps, or predict runtimes.",
      inputSchema: z.object({
        action: z.enum(["import", "stats", "history", "predict", "combos", "recommend"]).describe("Metrics action"),
        tool: z.string().optional().describe("Filter by tool name"),
        project: z.string().optional().describe("Filter by project name"),
        limit: z.number().int().positive().optional().describe("Limit result count"),
        starts_with: z.string().optional().describe("Required combo prefix for combos, as comma-separated tools"),
        contains: z.string().optional().describe("Required tool anywhere in a combo"),
        min_occurrences: z.number().int().positive().optional().describe("Minimum combo occurrence count"),
        after: z.string().optional().describe("Recommendation prefix, as comma-separated tools"),
      }),
    },
    async ({ action, tool, project, limit, starts_with, contains, min_occurrences, after }) => {
      const args = [action];
      if (tool) args.push("--tool", tool);
      if (project) args.push("--project", project);
      if (limit !== undefined) args.push("--limit", String(limit));
      if (starts_with) args.push("--starts-with", starts_with);
      if (contains) args.push("--contains", contains);
      if (min_occurrences !== undefined) args.push("--min-occurrences", String(min_occurrences));
      if (after) args.push("--after", after);
      args.push("-o", "json");
      return cli("fmetrics", args);
    }
  );

  // ─── freplay ──────────────────────────────────────────────────────
  server.registerTool(
    "freplay",
    {
      title: coloredTitle("freplay"),
      description:
        "Deterministic replay engine for fsuite investigation commands. Record, inspect, export, verify, and manage replays tied to a case.",
      inputSchema: z.object({
        action: z.enum(["record", "show", "list", "export", "verify", "promote", "archive"]).describe("Replay action"),
        slug: z.string().describe("Case slug"),
        replay_id: z.number().int().positive().optional().describe("Replay ID for show/export/verify, or positional replay for promote/archive"),
        purpose: z.string().optional().describe("Human-readable purpose for record"),
        links: z.array(z.string()).optional().describe("Related links as type:id entries for record"),
        new: z.boolean().optional().describe("Force a new replay when recording"),
        command: z.array(z.string()).optional().describe("Command argv after -- for record, e.g. ['fsearch', '-o', 'json', 'docs', '/repo']"),
      }),
    },
    async ({ action, slug, replay_id, purpose, links, new: createNew, command }) => {
      const args = [action, slug];

      if (action === "record") {
        if (purpose) args.push("--purpose", purpose);
        for (const link of (links || [])) args.push("--link", link);
        if (replay_id !== undefined) args.push("--replay-id", String(replay_id));
        if (createNew) args.push("--new");
        if (!command || command.length === 0) {
          return { content: [{ type: "text", text: "freplay record requires command" }], isError: true };
        }
        args.push("--", ...command);
        return cli("freplay", args);
      }

      if (action === "promote" || action === "archive") {
        if (replay_id === undefined) {
          return { content: [{ type: "text", text: `freplay ${action} requires replay_id` }], isError: true };
        }
        args.push(String(replay_id));
        return cli("freplay", args);
      }

      if (replay_id !== undefined) args.push("--replay-id", String(replay_id));
      args.push("-o", "json");
      return cli("freplay", args);
    }
  );

  // ─── fprobe ─────────────────────────────────────────────────────

  // Decode byte escapes into a Buffer and pass them to the engine via hidden
  // hex argv flags so raw bytes survive the JS -> argv boundary unchanged.
  function decodeFprobeParam(name, s) {
    if (s === undefined || s === null) return undefined;
    const parts = [];
    let lastIndex = 0;
    const escapePattern = /\\x([0-9a-fA-F]{2})|\\u([0-9a-fA-F]{4})/g;
    let match;

    while ((match = escapePattern.exec(s)) !== null) {
      if (match.index > lastIndex) {
        parts.push(Buffer.from(s.slice(lastIndex, match.index), "utf8"));
      }

      if (match[1]) {
        parts.push(Buffer.from([parseInt(match[1], 16)]));
      } else {
        const value = parseInt(match[2], 16);
        if (value > 0xff) {
          throw new Error(`${name} contains \\u${match[2]} which exceeds one raw byte; use \\xNN for byte values`);
        }
        parts.push(Buffer.from([value]));
      }

      lastIndex = escapePattern.lastIndex;
    }

    if (lastIndex < s.length) {
      parts.push(Buffer.from(s.slice(lastIndex), "utf8"));
    }
    return Buffer.concat(parts);
  }
  server.registerTool("fprobe", {
      description:
        "Binary reconnaissance and surgical patching. Scan for patterns, read byte windows, " +
        "extract strings, and patch binaries with same-length replacements. Works on compiled " +
        "binaries, SEA bundles, packed assets — anything with embedded text.",
      inputSchema: z.object({
        action: z.enum(["strings", "scan", "window", "patch"]).describe("Subcommand"),
        file: z.string().describe("File to probe or patch"),
        filter: z.string().optional().describe("Filter strings to those containing this literal (strings mode)"),
        pattern: z.string().optional().describe("Pattern to find (scan mode). Literal by default; set decode_escapes for \\xNN/\\uNNNN"),
        context: z.number().optional().describe("Bytes of context around match (scan mode, default 300)"),
        offset: z.number().optional().describe("Byte offset to read from (window mode)"),
        before: z.number().optional().describe("Bytes before offset (window mode, default 0)"),
        after: z.number().optional().describe("Bytes after offset (window mode, default 200)"),
        decode: z.enum(["printable", "utf8", "hex"]).optional().describe("Decode mode (window mode, default printable)"),
        ignore_case: z.boolean().optional().describe("Case-insensitive matching"),
        target: z.string().optional().describe("Text to find and replace (patch mode). Literal by default; set decode_escapes for \\xNN/\\uNNNN"),
        replacement: z.string().optional().describe("Replacement text, padded with spaces if shorter (patch mode). Literal by default; set decode_escapes for \\xNN/\\uNNNN"),
        dry_run: z.boolean().optional().describe("Preview patch without writing (patch mode)"),
        decode_escapes: z.boolean().optional().describe("Decode \\\\xNN and \\\\uNNNN escape sequences in pattern/target/replacement to raw bytes. Default false (literal)"),
      }),
    },
    async ({ action, file, filter, pattern, context, offset, before, after, decode, ignore_case, target, replacement, dry_run, decode_escapes }) => {
      if (action === "scan" && !pattern) {
        return { content: [{ type: "text", text: "fprobe scan requires pattern" }], isError: true };
      }
      if (action === "window" && offset === undefined) {
        return { content: [{ type: "text", text: "fprobe window requires offset" }], isError: true };
      }
      if (action === "patch" && (!target || !replacement)) {
        return { content: [{ type: "text", text: "fprobe patch requires --target and --replacement" }], isError: true };
}
    const args = [action, file];
    if (action === "strings" && filter) args.push("--filter", filter);
    if (action === "scan" && pattern) {
      if (decode_escapes) {
        const buf = decodeFprobeParam("pattern", pattern);
        if (buf) args.push("--pattern-hex", buf.toString("hex"));
      } else {
        args.push("--pattern", pattern);
      }
    }
    if (context !== undefined) args.push("--context", String(context));
    if (offset !== undefined) args.push("--offset", String(offset));
    if (before !== undefined) args.push("--before", String(before));
    if (after !== undefined) args.push("--after", String(after));
    if (decode) args.push("--decode", decode);
    if (ignore_case) args.push("--ignore-case");
    if (action === "patch" && target) {
      if (decode_escapes) {
        const buf = decodeFprobeParam("target", target);
        if (buf) args.push("--target-hex", buf.toString("hex"));
      } else {
        args.push("--target", target);
      }
    }
    if (action === "patch" && replacement) {
      if (decode_escapes) {
        const buf = decodeFprobeParam("replacement", replacement);
        if (buf) args.push("--replacement-hex", buf.toString("hex"));
      } else {
        args.push("--replacement", replacement);
      }
    }
    if (action === "patch" && dry_run) args.push("--dry-run");
      args.push("-o", "json");
      return cli("fprobe", args, undefined, { action });
    }
  );

// ─── fs (unified search orchestrator) ───────────────────────────
server.registerTool(
  "fs",
  {
    title: coloredTitle("fs"),
    description:
      "Unified search orchestrator. One call to find files, paths, content, or symbols. " +
      "Auto-classifies query intent and chains the right fsuite tools (fsearch, fcontent, fmap). " +
      "Returns ranked hits with enrichment and a recommended next step (next_hint). " +
      "Use scope to narrow by file glob. Use intent to override auto-classification.",
    inputSchema: z.object({
      query: z.string().describe("Search intent: glob pattern, literal string, or code identifier"),
      path: z.string().optional().describe("Search root directory (default: cwd)"),
      scope: z.string().optional().describe("Glob filter to narrow file set first, e.g. '*.py'"),
        intent: z.enum(["auto", "file", "content", "symbol", "nav"]).optional()
          .describe("Override auto-classification. Default: auto"),
        compact: z.boolean().optional()
          .describe("Nav-only compact mode: relative paths, no next_hint, minimal per-hit data. Ignored for non-nav intents."),
      }),
      // outputSchema removed: 2.1.88 StructuredOutput schema cache bug
  },
  async ({ query, path, scope, intent, compact }) => {
    // fs bypasses cli() — returns both pretty ANSI content AND typed
    // structuredContent so agents get machine-readable output.
    const args = ["-o", "json", query];
    if (path) args.push("--path", path);
    if (scope) args.push("--scope", scope);
    if (intent && intent !== "auto") args.push("--intent", intent);
    if (compact) args.push("--compact");
    try {
      const { stdout } = await run(resolveTool("fs"), args, execOptsFor("fs"));
      try {
const parsed = JSON.parse(stdout);

      // ─── Pretty render fs result ───
        const intentColor = { file: fg(166, 226, 46), content: fg(102, 217, 239), symbol: fg(190, 132, 255), nav: fg(253, 151, 31) };
      const confBadge = { high: fg(80, 200, 80) + "high" + RESET, medium: fg(230, 219, 116) + "medium" + RESET, low: fg(220, 90, 90) + "low" + RESET };
      const ic = intentColor[parsed.resolved_intent] || fg(248, 248, 242);
      const cb = confBadge[parsed.route_confidence] || parsed.route_confidence;
      const chainStr = (parsed.selected_chain || []).map(t => fg(248, 248, 242) + t).join(fg(117, 113, 94) + " → ");

        const lines = [];
        lines.push(`${BOLD}${ic}${parsed.resolved_intent}${RESET} ${DIM}(${UNDIM}${cb}${DIM})${UNDIM} ${DIM}via${UNDIM} ${chainStr}${RESET}`);
        lines.push(`${DIM}  ${parsed.route_reason}${RESET}`);
        const b = parsed.budget || {};
        lines.push(`${DIM}  ${b.candidate_files || 0} candidates, ${b.enriched_files || 0} enriched, ${b.time_ms || 0}ms${parsed.truncated ? fg(230, 219, 116) + " ⚠ truncated" : ""}${RESET}`);
        lines.push("");

        for (const h of (parsed.hits || []).slice(0, 20)) {
          const itemPath = h.file || h.path || "";
          const sp = shortPath(itemPath);
          const suffix = h.kind === "dir" ? "/" : "";
          lines.push(`  ${fg(102, 217, 239)}${sp}${suffix}${RESET}${h.match_count ? DIM + ` (${h.match_count} matches)` + RESET : ""}`);
          if (h.preview?.length) {
            for (const child of h.preview.slice(0, 5)) {
              const childSuffix = child.kind === "dir" ? "/" : "";
              lines.push(`    ${DIM}${child.name}${childSuffix}${RESET}`);
            }
            if (h.preview_truncated) {
              lines.push(`    ${DIM}...${RESET}`);
            }
          }
          for (const m of (h.matches || []).slice(0, 5)) {
            const lineNum = m.line ? `${DIM}${m.line}${UNDIM}` : "";
            const lang = itemPath ? detectLang(itemPath) : "";
            const hl = lang ? highlightLine(m.text || "", lang) : fg(248, 248, 242) + (m.text || "");
            lines.push(`    ${fg(117, 113, 94)}${lineNum} ${RESET}${hl}${RESET}`);
          }
        if (h.symbols && h.symbols.length > 0) {
          const symList = h.symbols.slice(0, 8).map(s =>
            typeof s === "string" ? s : (s.text || s.name || "")
          ).filter(Boolean).map(s => fg(190, 132, 255) + s + RESET).join(fg(117, 113, 94) + ", ");
          lines.push(`    ${DIM}symbols:${UNDIM} ${symList}${RESET}`);
        }
        lines.push("");
      }

      if (parsed.next_hint) {
        const nh = parsed.next_hint;
        const nhArgs = Object.entries(nh.args || {}).map(([k, v]) => `${fg(166, 226, 46)}${k}${RESET}${DIM}: ${UNDIM}${fg(230, 219, 116)}${v}${RESET}`).join(DIM + ", " + RESET);
        lines.push(`${fg(190, 132, 255)}${BOLD}next →${RESET} ${fg(102, 217, 239)}${nh.tool}${RESET}(${nhArgs})`);
      }

      return {
        content: [{ type: "text", text: lines.join("\n") }],
      };
      } catch (renderErr) {
        console.error("fs render error:", renderErr);
        return { content: [{ type: "text", text: stdout }] };
      }
    } catch (err) {
      return { content: [{ type: "text", text: `fs error: ${err.stderr || err.message || "unknown"}` }], isError: true };
    }
  }
);

// ─── fls (thin ftree router for directory listing) ──────────────
server.registerTool(
  "fls",
  {
    title: coloredTitle("fls"),
    description:
      "Quick directory listing — thin ftree router. Use instead of bash ls. " +
      "Default: list direct children. -t: shallow tree (depth 2). -r: recon with sizes/counts. " +
      "Output is ftree's JSON contract — parse the same fields.",
    inputSchema: z.object({
      path: z.string().optional().describe("Directory to list (default: cwd)"),
      mode: z.enum(["list", "tree", "recon"]).optional()
        .describe("list (depth 1), tree (depth 2), or recon (sizes/counts). Default: list"),
      output: z.enum(["pretty", "json"]).optional()
        .describe("Output format. Default: pretty"),
    }),
  },
  async ({ path, mode, output }) => {
    const args = [];
    if (mode === "tree") args.push("-t");
    if (mode === "recon") args.push("-r");
    if (output) args.push("-o", output);
    if (path) args.push(path);
    return cli("fls", args);
  }
);

// ─── fbash ──────────────────────────────────────────────────────
server.registerTool(
  "fbash",
  {
    title: coloredTitle("fbash"),
    description:
      "Token-budgeted shell execution with session state. Runs any bash command with " +
      "output capping, command classification, and fsuite smart routing. Tracks CWD across " +
      "calls. Use for builds, tests, git, installs — anything that isn't file reading/editing " +
      "(use fread/fedit for those). Returns next_hint when an fsuite tool would be better.",
    inputSchema: z.object({
      command: z.string().optional().describe("Bash command to execute (required unless using poll or list_jobs)"),
      max_lines: z.number().int().positive().optional()
        .describe("Cap output lines (default: 200)"),
      max_bytes: z.number().int().positive().optional()
        .describe("Cap output bytes (default: 51200)"),
      full: z.boolean().optional()
        .describe("Disable fbash output caps and MCP preview truncation"),
      no_truncate: z.boolean().optional()
        .describe("Alias for full; disable fbash output caps and MCP preview truncation"),
      json: z.boolean().optional()
        .describe("Parse output as JSON and return structured"),
      cwd: z.string().optional()
        .describe("Working directory (overrides session CWD, persists after execution)"),
      timeout: z.number().int().nonnegative().optional()
        .describe("Timeout in seconds (auto-tuned by command class if omitted; 0 disables the command timeout)"),
      env: z.array(z.string()).optional()
        .describe("Environment variable overrides as KEY=VALUE strings"),
      filter: z.string().optional()
        .describe("Regex filter for output lines"),
      quiet: z.boolean().optional()
        .describe("Suppress output, return only exit code + metadata"),
      tag: z.string().optional()
        .describe("Label for fcase event logging"),
      background: z.boolean().optional()
        .describe("Run in background, return job_id"),
      poll: z.string().optional()
        .describe("Poll a background job by job_id. Returns status, exit_code, and budgeted output."),
      list_jobs: z.boolean().optional()
        .describe("List all background jobs with status"),
      tail: z.boolean().optional()
        .describe("Keep tail instead of head when truncating"),
    }),
  },
  async (params) => {
    // Poll and list_jobs route to internal commands, bypassing normal execution
    if (params.poll) {
      const wantsFull = Boolean(params.full || params.no_truncate);
      const pollArgs = ["--command", `__fbash_poll ${params.poll}`];
      if (wantsFull) pollArgs.push("--no-truncate");
      pollArgs.push("-o", "json");
      return cli("fbash", pollArgs, undefined, { full: wantsFull });
    }
    if (params.list_jobs) {
      return cli("fbash", ["--command", "__fbash_jobs", "-o", "json"]);
    }
    if (!params.command) {
      throw new Error("command is required unless using poll or list_jobs");
    }
    const hasExplicitOutputCap = params.max_lines !== undefined || params.max_bytes !== undefined;
    const wantsFull = Boolean(
      params.full ||
      params.no_truncate ||
      (!hasExplicitOutputCap && commandInvokesTool(params.command, "fread")),
    );
    const args = [];
    args.push("--command", params.command);
    if (params.max_lines !== undefined) args.push("--max-lines", String(params.max_lines));
    if (params.max_bytes !== undefined) args.push("--max-bytes", String(params.max_bytes));
    if (wantsFull) args.push("--no-truncate");
    if (params.json) args.push("--json");
    if (params.cwd) args.push("--cwd", params.cwd);
    if (params.timeout !== undefined) args.push("--timeout", String(params.timeout));
    if (params.env) {
      for (const entry of params.env) {
        args.push("--env", entry);
      }
    }
    if (params.filter) args.push("--filter", params.filter);
    if (params.quiet) args.push("--quiet");
    if (params.tag) args.push("--tag", params.tag);
    if (params.background) args.push("--background");
    if (params.tail) args.push("--tail");
    args.push("-o", "json");
    return cli("fbash", args, undefined, { maxLines: params.max_lines, full: wantsFull });
  }
);

export const __test__ = {
  buildMediaContent,
  buildFreadMcpContent,
  mediaByteBudget,
  truncateUtf8,
};

// ─── Start ───────────────────────────────────────────────────────
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const transport = new StdioServerTransport();
  await server.connect(transport);
}
