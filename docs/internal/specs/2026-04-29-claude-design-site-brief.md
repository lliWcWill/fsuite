# Claude Design Brief — fsuite GitHub Pages Site Upgrade

> Pass this entire file to Claude Design. It is self-contained — Claude Design does not need any other context to start.

---

## 1. The ask

Take the current Astro Starlight docs site at `https://lliwcwill.github.io/fsuite/` from "good starter" to **the marketing-and-onboarding layer the project deserves**. The current site is essentially auto-generated `--help` pages plus a thin landing page. We need it to be a destination that:

1. **Tells the story** — fsuite is a worldview about how AI agents should interact with filesystems, not just a CLI bundle. The story is currently buried in a sidebar. It needs to be the spine of the site.
2. **Demonstrates the magic** — show fsuite *in action* with motion, real terminal output, side-by-side comparisons against native `grep`/`find`/`cat`/`bash`. Words don't do it justice. Visuals do.
3. **Sells the technical depth** — fourteen tools, MCP-native, ShieldCortex memory integration, learning-loop telemetry, 50-language `fmap`, image+PDF media reading, ~516 tests across 16 suites. None of this is on the landing page right now.
4. **Hands agents a clean front door** — both human readers and AI agents (this is an agent-tooling project; agents will visit this site) should leave with the right mental model in under 90 seconds.
5. **Doesn't break the existing structure** — the Astro Starlight scaffold, the auto-generated commands directory, the sidebar IA all stay. We're upgrading the surface, not refactoring the framework.

---

## 2. Repo + site facts

- **Live URL**: https://lliwcwill.github.io/fsuite/
- **Deploy target**: GitHub Pages (set in `astro.config.mjs` as `site: 'https://lliwcwill.github.io', base: '/fsuite'`)
- **Framework**: Astro 5.x + Starlight 0.38.x
- **Theme**: Starlight defaults + custom CSS at `src/styles/custom.css` (Monokai-leaning)
- **Code theme**: ExpressiveCode with Monokai (dark) + github-light, JetBrains Mono Nerd Font
- **Site source**: `site/` directory in the repo
- **Hero asset**: `site/src/assets/fsuite-hero.jpeg` (currently used as logo too — feels like overload)
- **Repo**: https://github.com/lliWcWill/fsuite

### Existing IA (sidebar)

```
Story
├── The Lightbulb Moment
├── Episode 0 — Origins
├── Episode 1
├── Episode 2
└── Episode 3

Getting Started
├── Installation
├── Mental Model
└── First Contact

Commands  (auto-generated from --help; 14 entries)

Architecture
├── MCP Adapter
├── Hooks & Enforcement
├── Telemetry
└── Chain Combinations

Reference
├── Cheat Sheet
├── Output Formats
└── Changelog
```

This IA is sound. **Don't restructure it.** The fix is in the landing page, the visual language between sections, the connective tissue, and a few key deep-dive pages getting hero treatment.

---

## 3. The fourteen tools (canonical list — for any tools-table you draw)

| Tool | One-liner | Surface |
|---|---|---|
| `fs` | Universal search orchestrator — auto-routes query intent | CLI + MCP |
| `ftree` | Territory scout — full tree + recon in one call | CLI + MCP |
| `fls` | Quick directory listing with recon mode | CLI + MCP |
| `fsearch` | File / glob discovery, ranked | CLI + MCP |
| `fcontent` | Bounded content search (token-capped ripgrep) | CLI + MCP |
| `fmap` | Symbol cartography — 50 languages | CLI + MCP |
| `fread` | Budgeted reading — text, image (PNG/JPEG/GIF/WEBP), PDF | CLI + MCP |
| `fedit` | Surgical editing — line-range, symbol-scoped, anchor-based | CLI + MCP |
| `fwrite` | Atomic file creation via fedit's mutation engine | **MCP-only** |
| `fbash` | Token-budgeted shell, classified, session-aware, async jobs | **MCP-native** |
| `fcase` | Investigation continuity ledger | CLI + MCP |
| `freplay` | Derivation chain replay | CLI + MCP |
| `fprobe` | Binary / bundle inspection + patching | CLI + MCP |
| `fmetrics` | Telemetry analytics + tool-chain prediction (learning loop) | CLI + MCP |

Plus `fsuite` — the suite-level guide command itself.

---

## 4. What's currently weak (specifics, not vibes)

### Landing page (`site/src/content/docs/index.mdx`)
- Hero tagline ("Deploy the drones. Map the terrain. Return with intel.") is good, but it's the *only* thing carrying the vibe.
- 4-card grid ("Recon without floods" etc.) is a fine starter but generic — could be on any CLI tool's site.
- Tools table is a flat list. Doesn't communicate flow, doesn't communicate hierarchy (e.g., `fs` is the entry point, others are primitives).
- No motion, no real terminal output, no diagrams.
- "Why it exists" section is two sentences and a link out. Should be a hook, not a footnote.
- Call-to-action buttons are fine but could do more work.

### Story section
- The lightbulb-moment narrative is the most compelling piece of writing in the entire repo, but it's hidden behind a sidebar click.
- Episodes 0–3 are excellent in-depth narrative content. They should be discoverable from the landing page, not just the sidebar.

### Getting Started
- "Installation" is mechanical. Fine.
- "Mental Model" is the single most important page for an agent or new user — should look and feel like the centerpiece.
- "First Contact" is fine.

### Commands (auto-generated)
- These pages are functional but visually uniform. A user landing on `/commands/fread` sees the same template as `/commands/fls`. We could add per-command flair (a one-line tagline at the top, a "this tool's killer feature" callout, related-tools recommendations, copy-paste-ready agent prompts).

### Architecture
- MCP Adapter, Hooks, Telemetry, Chain Combinations are all there but could use diagrams. fsuite has been talking about chains for months and we still don't have a clean chain diagram on the site.

### Reference
- Cheat Sheet, Output Formats, Changelog — all fine but dry. Changelog especially could be richer with screenshots / links to PRs / mini "what changed" callouts.

### Visual language overall
- Monokai code theme is fine but the *site* itself is the default Starlight theme with minor tweaks. Doesn't feel branded.
- No diagrams. fsuite is conceptually rich (sensor metaphor, chain compositions, MCP/CLI duality) and a site without diagrams squanders that.
- The hero JPEG is a single image. There's no visual identity beyond it.

---

## 5. Proof points to surface (currently invisible)

Surface these on the landing page and/or in dedicated callouts. Each one is a real fact you can verify in the repo:

- **14 tools**, 1 unified entry point (`fs`)
- **~22 test suites**, all green per release
- **MCP-native** — drops into Claude Code, Codex, OpenCode as first-class tool calls
- **fmap supports 50 programming languages**
- **fread reads PDFs and images** as first-class inputs (PNG/JPEG/GIF/WEBP via Pillow, PDFs via PyMuPDF or Poppler)
- **ShieldCortex memory integration** — successful media reads auto-write to a persistent memory store
- **fmetrics learning loop** — predicts run-times, recommends tool combos, refines based on history
- **Token-budgeted everywhere** — every tool has caps; no flooding the agent's context
- **Pixel-perfect MCP rendering** — outputs look the same in Claude Code as in a terminal
- **Available as Debian package** + source install + manual symlink
- **Works headless by default** — no prompts, no TTY required
- **Open source** (MIT or whatever's actually in `LICENSE` — verify)

---

## 6. Audience ranking (design priority)

1. **AI agents** (Claude Code, Codex, OpenCode users) doing first-contact reconnaissance on the project. They land here because their human asked "what's this fsuite thing?" The site needs to make the agent confident in 90 seconds.
2. **Terminal-native developers** evaluating the tools as grep/find/cat replacements. They want to see speed, structure, and "yes this is real software."
3. **AI agent tool authors** who want to learn from fsuite's design decisions (MCP integration patterns, token budgeting, chain composition). They want depth and architecture pages.
4. **Casual visitors** who clicked from a tweet or HN. They want the hero, the screenshot, the "ohhh that's clever" moment.

Audience #1 is the most under-served on the current site. They get the auto-gen `--help` output and a generic landing page. They deserve a "for AI agents, here is your front door" treatment.

---

## 7. Concrete ask — what to ship

### Must-have

1. **Landing page rebuild** (`site/src/content/docs/index.mdx`).
   - Replace the 4-card grid with **a flow diagram** showing the canonical chain: `ftree -> fsearch | fcontent -> fmap -> fread -> fcase -> fedit -> freplay -> fmetrics` with `fs` as a side-bubble entry point. Make this diagram beautiful. SVG or MDX components (Starlight-compatible). Animated entrance is a plus, not a requirement.
   - Add a **"native vs fsuite"** comparison block — three side-by-side terminals showing `grep` flooding context vs `fcontent` returning bounded ranked results. Same for `find` vs `fsearch`, `cat` vs `fread --symbol`. Use static screenshots if motion is overkill, or asciinema-style animated snippets if you can pull it off.
   - Add a **"see one full chain"** demo. Pick a real investigation (e.g., "find the auth function and read its symbol") and show the four-tool sequence with annotated terminal output.
   - Add **proof-point counters** ("14 tools • 516 tests • 50 languages • MCP-native") in a clean strip.
   - Cut the existing "Why it exists" two-liner and replace with a one-screen pitch that earns the click into the Story section.

2. **Story section spine** — make Episode 0 ("Origins") accessible directly from the landing page with a real card, not just a sidebar link. Add a "Read the story" CTA visually equal in weight to "Get Started."

3. **Mental Model page upgrade** (`site/src/content/docs/getting-started/mental-model.mdx`). This page is the single most important conceptual page in the repo. It should have a **hero diagram** of the sensor metaphor (fsuite tools as drones, target repo as terrain) and a **table of "default reflexes"** mapping native tool habits to fsuite equivalents. This is the page that, if an agent only reads one thing, makes them effective immediately.

4. **Architecture / Chain Combinations page** — make this *the* showcase for fsuite's chain doctrine. Visual: a graph of which tools pipe into which, color-coded by producer/consumer/non-pipe. Include the canonical chain patterns (Scout, Investigation, Surgical, Full Recon, Progressive Narrowing) with diagrams.

5. **Per-command page polish** (`site/src/content/docs/commands/*.md`, auto-generated by `npm run gen:commands`). The `gen-commands.mjs` script can be extended to inject:
   - A one-line tagline at the top (same as the tools-table column).
   - A "killer feature" callout (e.g., for `fread`: "Reads exact symbols by name — no line-number guessing").
   - A "related tools" footer (e.g., `fread` links to `fmap`, `fedit`, `fs`).

   Important: the script currently shells out to each tool's `--help`. The polish layer should sit *above* the auto-gen output (front-matter or pre-content), not replace it. Don't touch the live `--help` rendering itself.

6. **Visual identity refresh** in `src/styles/custom.css`:
   - Lean into the Monokai palette but extend it with a brand accent (suggest fsuite-green `#A6E22E` from the Monokai keyword color, used sparingly for CTAs and chain-flow arrows).
   - Add a custom hero font pairing (something display-y for h1, JetBrains Mono Nerd Font for code, system sans for body — current setup is fine for body but h1 could pop more).
   - The hero JPEG should stay on the landing page but **stop being used as the navbar logo**. Either generate a clean wordmark (text "fsuite" with a small drone-glyph) or just use text-only branding in the navbar. The hero image is a heavy aesthetic statement; reusing it shrunken to 48px in the navbar undermines it.

### Nice-to-have

- **Animated terminal demos** (asciinema-style). At least two: one for `fs "authenticate"` showing the auto-routing magic, one for `fread invoice.pdf --render --pages 1:3` showing the new media reading.
- **Diagram for fcase lifecycle** — shows the init → note → resolve → archive flow. Use mermaid or a custom SVG.
- **Comparison page**: dedicated side-by-side ("fsuite vs native") page that the landing page links to. Per-tool comparisons with examples.
- **Showcase page**: "Agents using fsuite" — Claude Code config snippet, Codex config snippet, OpenCode config snippet. With copy buttons.
- **Search hero** — Pagefind ships with Starlight; consider promoting it more prominently on the landing page.
- **Social cards / OG images** — the current OG image is probably the default Starlight one. Generate fsuite-branded ones for at least the landing page, the Story episodes, and the Mental Model page.

### Don't-do

- Don't restructure the sidebar IA. The 5-section layout (Story / Getting Started / Commands / Architecture / Reference) is correct. Reorder *within* sections if you want, but the top-level shape stays.
- Don't replace Astro/Starlight. We chose this stack deliberately for its self-hosting, search, and zero-runtime cost. No Next.js, no Gatsby, no SPA rewrites.
- Don't break the auto-generation pipeline (`npm run gen:commands`, `npm run gen:story`). Build must still produce identical command pages from `--help` output.
- Don't claim things that aren't true. If you draft a counter that says "10,000 GitHub stars" and we have 50, fix it. All stat claims should be verifiable in the repo or marked as illustrative.
- Don't add JavaScript that breaks at static-export time. The site has to build to pure HTML/CSS/JS for GitHub Pages serving.

---

## 8. The fsuite voice (so your copy sounds right)

- **Direct.** No hedging. No "perhaps." Either it does the thing or it doesn't.
- **Slightly cocky, never preachy.** "fsuite fills the reconnaissance gap — the weakest phase of agent operation." That's the tone.
- **Drone metaphor is canon.** "Deploy the drones. Map the terrain. Return with intel." Use the metaphor where it lands; don't force it where it doesn't.
- **Specifics over abstractions.** "84 tests" beats "well-tested." "50 languages" beats "broad language support." "Token-budgeted everywhere" beats "performance-conscious."
- **Anti-marketing-speak.** No "synergy," "leverage," "best-in-class." Engineers smell that and bounce.

Sample lines that fit:
- *"Stop overcompensating for weak default tools. Trust the direct contract."*
- *"Literal search is a strength here, not a fallback."*
- *"Composable sensor suite. Not a single sacred path."*
- *"Bounded reads around lines, patterns, symbols, and diffs."*
- *"Three focused subcommands map directly to three phases of binary recon."*

---

## 9. Source material to mine

When you're stuck or want raw quotes / numbers / specific phrasings, these files in the repo are gold:

- `README.md` — most-recent canonical pitch (just updated for v2.4.0). Has the tool table, the chain flow, the changelog.
- `fsuite` (the script, not the directory) — the suite-level guide command. Source for the "first-contact mindset" and "strong combinations" voice.
- `docs/EPISODE-0.md` through `docs/EPISODE-3.md` — narrative project history. Episode 0 is "origins"; Episode 3 is the latest milestone. These are the real story content.
- `docs/internal/readme-drafts/04-cheatsheet-changelog.md` — full cheat sheet + changelog with PR-level detail. Internal-source-of-truth for what shipped when.
- `docs/internal/specs/2026-03-31-fsuite-v3-roadmap.md` — where the project is going.
- `site/src/content/docs/getting-started/mental-model.mdx` — current state of the most important page.
- `site/src/content/docs/index.mdx` — current landing page (replace, but mine the existing copy).

---

## 10. Deliverable shape

When you're done, hand back:

1. **A pull request** to `https://github.com/lliWcWill/fsuite` against `master`, branch named something like `claude-design/site-upgrade-2026-04-29`.
2. **Touch only `site/`** (and root `README.md` only if you genuinely need to align a phrase). Do not touch the bash scripts, the MCP adapter, the tests, the tool engines, or any of the agent operating policy.
3. **Build passes**: `cd site && npm install && npm run build` must complete with zero errors. The dist/ directory must serve correctly when previewed (`npm run preview`).
4. **PR body** should include:
   - One screenshot of the new landing page hero
   - One screenshot of the new mental-model page
   - One screenshot of the new architecture/chains diagram
   - Bullet list of files changed and why
   - Any deliberate decisions that diverge from this brief (with rationale)
5. **No hand-waving on stats**. Every numeric claim ("14 tools," "516 tests," "50 languages") should reference where the number came from in the repo so the human reviewer can verify in 30 seconds.
6. **Don't auto-merge**. This goes through human review.

---

## 11. The single sentence

If you only get one chance to land this:

> *fsuite is the sensor suite the AI coding agent in your terminal should have been built with — fourteen bounded, token-budgeted, MCP-native tools that replace grep, find, cat, sed, and bash with something an LLM can actually use without burning its context window on irrelevant junk.*

Make the site live up to that sentence.

---

## 12. Authorization scope

You have authority to:
- Touch any file inside `site/`
- Add new diagrams, components, or assets under `site/src/`
- Extend `site/scripts/gen-commands.mjs` with non-breaking enhancements
- Adjust `site/astro.config.mjs` sidebar order (within sections), add new pages, register new content directories
- Edit `site/src/styles/custom.css` freely
- Open the PR

You do **not** have authority to:
- Modify any tool source (`fs`, `ftree`, `fread`, etc. in repo root)
- Modify the MCP adapter (`mcp/`)
- Modify tests or CI
- Modify agent operating policy files (`AGENTS.md`, `CLAUDE.md`, `GEMINI.md`, root `README.md` beyond minor phrase alignment)
- Push to master or merge the PR yourself

If you find a problem outside your scope (e.g., a typo in a tool's `--help` that breaks an auto-gen page), open a GitHub issue against `lliWcWill/fsuite` describing it and continue with the site work. The human will handle the cross-scope fix.

---

End of brief.
