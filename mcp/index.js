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

const run = promisify(execFile);
const TOOL_TIMEOUT = 30_000;
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
const EXEC_OPTS = { timeout: TOOL_TIMEOUT, maxBuffer: MAX_BUFFER, env: { ...process.env, FSUITE_TELEMETRY: "3" } };

// ─── Per-tool color palette (256-color ANSI for Claude Code tool headers) ────
// Binary patch v2 passes _.annotations?.title through as-is.
// We embed the ANSI color in the title so Claude Code renders it.
const TOOL_PALETTE = {
  fread: 46, ftree: 46, freplay: 46,           // neon green — read/scout
  fedit: 208, fwrite: 208,                      // orange — mutation
  fcontent: 27, fsearch: 27, fs: 27,            // royal blue — search
  fmap: 129, fcase: 129,                        // dark violet — structure/knowledge
  fprobe: 196, fmetrics: 196,                   // pure red — diagnostic/recon
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
  // Try stderr (may still be a TTY), env var, or fall back to generous default.
  const cols = process.stderr.columns || parseInt(process.env.COLUMNS, 10) || 160;
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
    if (!d.tool || d.tool !== "fedit") return null;

    const mode = d.mode === "create" ? "create" : d.mode === "replace_file" ? "replace" : "patch";

    // Count diff lines for summary
    let added = 0, removed = 0;
    if (d.diff) {
      for (const line of d.diff.split("\n")) {
        if (line.startsWith("+") && !line.startsWith("+++")) added++;
        if (line.startsWith("-") && !line.startsWith("---")) removed++;
      }
    }

    // Status-only body — no path line, Claude Code header already shows it
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

    let out = parts.join(" ") + "\n";

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

    return out;
  } catch {
    return null;
  }
}

function renderFreadResult(jsonStr) {
  try {
    const d = JSON.parse(jsonStr);
    if (!d.tool || d.tool !== "fread") return null;

    let meta = `${d.lines_emitted} lines | ~${d.token_estimate} tokens`;
    if (d.symbol_resolution) {
      meta += ` | L${d.symbol_resolution.line_start}-${d.symbol_resolution.line_end}`;
    }
    if (d.truncated) meta += ` ${theme.warn("truncated")}`;
    let out = theme.meta(meta) + "\n";

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

    for (const chunk of (d.chunks || [])) {
      for (const rawLine of chunk.content) {
        const m = rawLine.match(/^(\d+)(\s{2,})(.*)/);
        if (m) {
          const ln = `${DIM} ${m[1].padStart(4)} ${UNDIM}`;
          const hl = highlightLine(m[3], lang);
          out += `${ln}${hl}${RESET}\n`;
        } else {
          out += rawLine + "\n";
        }
      }
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
  let out = theme.meta(`${d.total_matched_files} files, ${d.shown_matches} matches`) + "\n";

  for (const m of (d.matches || [])) {
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
    if (!d.tool || d.tool !== "ftree") return null;

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
    return null;
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
  const summary = d.shown < d.total_found
    ? `${d.shown}/${d.total_found} results shown`
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

// Tool → renderer mapping
const RENDERERS = {
  fedit: renderFeditResult,
  fwrite: renderFeditResult,
  fread: renderFreadResult,
  fmap: renderFmapResult,
  fcontent: renderFcontentResult,
  ftree: renderFtreeResult,
  fsearch: renderFsearchResult,
};

// ─── Helper: run CLI tool, pretty-render if possible ─────────────
async function cli(tool, args, renderAs) {
  try {
    const { stdout, stderr } = await run(resolveTool(tool), args, EXEC_OPTS);
    const raw = stdout || stderr || "(no output)";

    // Try pretty rendering
    const renderer = RENDERERS[renderAs || tool];
    if (renderer) {
      const pretty = renderer(raw);
      if (pretty) return { content: [{ type: "text", text: pretty }] };
    }

    return { content: [{ type: "text", text: raw }] };
  } catch (err) {
    return { content: [{ type: "text", text: `Error running ${tool}: ${err.stderr || err.stdout || err.message}` }], isError: true };
  }
}

// ─── Server ──────────────────────────────────────────────────────
const server = new McpServer({ name: "fsuite", version: "2.3.0" });

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
      path: z.string().describe("File path (or directory when using symbol)"),
      symbol: z.string().optional().describe("Read exactly one symbol (function, class, etc.) by name"),
      lines: z.string().optional().describe("Line range, e.g. '120:220'"),
      around: z.string().optional().describe("Show context around first literal pattern match"),
      around_line: z.number().optional().describe("Show context around a specific line number"),
      before: z.number().optional().describe("Lines of context before match (default 5)"),
      after: z.number().optional().describe("Lines of context after match (default 10)"),
      head: z.number().optional().describe("Read first N lines"),
      tail: z.number().optional().describe("Read last N lines"),
      max_lines: z.number().optional().describe("Cap total lines emitted (default 200)"),
    }),
  },
  async ({ path, symbol, lines, around, around_line, before, after, head, tail, max_lines }) => {
    const args = [path];
    if (symbol) args.push("--symbol", symbol);
    if (lines) args.push("-r", lines);
    if (around) args.push("--around", around);
    if (around_line !== undefined) args.push("--around-line", String(around_line));
    if (before !== undefined) args.push("-B", String(before));
    if (after !== undefined) args.push("-A", String(after));
    if (head !== undefined) args.push("--head", String(head));
    if (tail !== undefined) args.push("--tail", String(tail));
    if (max_lines !== undefined) args.push("--max-lines", String(max_lines));
    args.push("-o", "json");
    return cli("fread", args);
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
    outputSchema: z.object({
      tool: z.literal("fsearch"),
      version: z.string(),
      pattern: z.string(),
      name_glob: z.string(),
      path: z.string(),
      backend: z.string(),
      search_type: z.enum(["file", "dir", "both"]),
      match_mode: z.enum(["name", "path", "both"]),
      preview_limit: z.number(),
      total_found: z.number(),
      shown: z.number(),
      results: z.array(z.string()),
      hits: z.array(fsearchHitSchema),
      next_hint: fsearchNextHintSchema.nullable(),
    }),
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
      const { stdout } = await run(resolveTool("fsearch"), args, EXEC_OPTS);
      try {
        const parsed = JSON.parse(stdout);
        return {
          content: [{ type: "text", text: renderFsearchStructured(parsed) }],
          structuredContent: parsed,
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
    }),
  },
  async ({ path, replace, with_text, function_name, after, before, lines, apply, expect }) => {
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
    args.push("-o", "pretty");
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
      return cli("fmetrics", args);
    }
  );

// ─── fprobe ─────────────────────────────────────────────────────
server.registerTool(
  "fprobe",
  {
    title: coloredTitle("fprobe"),
    description:
      "Binary/opaque file reconnaissance. Extracts printable strings, scans for literal " +
      "byte patterns with context, and reads raw byte windows at known offsets. Works on " +
      "compiled binaries, SEA bundles, packed assets — anything with embedded text.",
    inputSchema: z.object({
      action: z.enum(["strings", "scan", "window"]).describe("Subcommand"),
      file: z.string().describe("File to probe"),
      filter: z.string().optional().describe("Filter strings to those containing this literal (strings mode)"),
      pattern: z.string().optional().describe("Literal pattern to find (scan mode)"),
      context: z.number().optional().describe("Bytes of context around match (scan mode, default 300)"),
      offset: z.number().optional().describe("Byte offset to read from (window mode)"),
      before: z.number().optional().describe("Bytes before offset (window mode, default 0)"),
      after: z.number().optional().describe("Bytes after offset (window mode, default 200)"),
      decode: z.enum(["printable", "utf8", "hex"]).optional().describe("Decode mode (window mode, default printable)"),
      ignore_case: z.boolean().optional().describe("Case-insensitive matching"),
    }),
  },
async ({ action, file, filter, pattern, context, offset, before, after, decode, ignore_case }) => {
    if (action === "scan" && !pattern) {
      return { content: [{ type: "text", text: "fprobe scan requires pattern" }], isError: true };
    }
    if (action === "window" && offset === undefined) {
      return { content: [{ type: "text", text: "fprobe window requires offset" }], isError: true };
    }
    const args = [action, file];
    if (action === "strings" && filter) args.push("--filter", filter);
    if (action === "scan" && pattern) args.push("--pattern", pattern);
    if (context) args.push("--context", String(context));
    if (offset !== undefined) args.push("--offset", String(offset));
    if (before !== undefined) args.push("--before", String(before));
    if (after !== undefined) args.push("--after", String(after));
    if (decode) args.push("--decode", decode);
    if (ignore_case) args.push("--ignore-case");
    args.push("-o", "json");
    return cli("fprobe", args);
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
      }),
      outputSchema: z.object({
        query: z.string(),
        path: z.string(),
        scope: z.string().optional(),
        intent: z.enum(["auto", "file", "content", "symbol", "nav"]),
        resolved_intent: z.enum(["file", "content", "symbol", "nav"]),
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
  },
  async ({ query, path, scope, intent }) => {
    // fs bypasses cli() — returns both pretty ANSI content AND typed
    // structuredContent so agents get machine-readable output.
    const args = ["-o", "json", query];
    if (path) args.push("--path", path);
    if (scope) args.push("--scope", scope);
    if (intent) args.push("--intent", intent);
    try {
      const { stdout } = await run(resolveTool("fs"), args, EXEC_OPTS);
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
        structuredContent: parsed,
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

// ─── Start ───────────────────────────────────────────────────────
const transport = new StdioServerTransport();
await server.connect(transport);
