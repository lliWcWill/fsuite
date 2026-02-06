# Episode -1: The Return Trip

> *"The first time, we asked the agent what it thought of our tools. It wrote the Stark Autopsy. The second time, we hardened the drones and sent them into hostile territory. They came back. This time, we handed a fresh agent — a new model, new context, zero history — the keys to v1.4 and said: test everything, tell us what changed."*
>
> — [@lliWcWill](https://github.com/lliWcWill), after deploying fsuite v1.4

---

## Context

This analysis was performed by **Claude Code (Opus 4.6)** — a different model generation than the Opus 4.5 that wrote the original Stark Autopsy. This agent had no prior session history with fsuite v1.4. It was given the repo, told the tools were new, and asked for an honest review. What follows is the live field report.

Previous episodes:
- **Episode -3:** The Stark Autopsy — Claude Code evaluates fsuite for the first time
- **Episode -2:** The Field Test — drones deployed to hostile filesystems, timeouts and budgets added
- **Episode -1:** This document — a new agent tests v1.4 with telemetry, fmetrics, and the full instrumented kit

---

## What I Did

I didn't just read the docs. I ran every tool against real targets:

| Test | Command | Target | Result |
|------|---------|--------|--------|
| Snapshot (self) | `ftree --snapshot -o json` | fsuite repo | 49 entries, 8 dirs, 27 files, 473ms |
| Snapshot (real project) | `ftree --snapshot -o json` | claudegram | 335 entries, 30 dirs, 60 files, 3s budget used |
| Recon (real project) | `ftree --recon -o json` | claudegram | 25 top-level entries, 3 excluded, 245ms |
| Pipeline | `fsearch -o paths '*.sh' \| fcontent -o json "function"` | fsuite repo | 7 files, 11 matches, clean JSON |
| Telemetry import | `fmetrics import` | 56 JSONL lines | 54 inserted, 2 deduped |
| Stats dashboard | `fmetrics stats` | all data | 57 runs across 3 tools, 5 projects |
| Runtime prediction | `fmetrics predict` | claudegram | ftree ~245ms, fsearch ~10ms, fcontent ~85ms |
| History | `fmetrics history --tool ftree --limit 5` | all data | Clean tabular output with timestamps |

Every command returned valid JSON. Every exit code was 0. Every pipeline composed without errors.

---

## What Changed Between v1.2 and v1.4

The Stark Autopsy evaluated three reconnaissance drones. v1.4 gave those drones a flight recorder and a ground control station.

### The Flight Recorder: Telemetry

Every invocation of ftree, fsearch, and fcontent now emits a telemetry event — duration, items scanned, bytes processed, exit code — appended atomically (flock) to `~/.fsuite/telemetry.jsonl`. Paths are SHA-256 hashed. No file contents stored. Opt-out with `FSUITE_TELEMETRY=0`.

Three tiers:
- **Tier 1** (default): Timing and byte counts. Lightweight. No hardware probing.
- **Tier 2**: CPU temperature, disk temperature, RAM usage, load average, filesystem type, storage type.
- **Tier 3**: Full machine profile — CPU model, core count, total RAM. Cached daily.

This is the right design. Tier 1 costs nothing and gives you the data you need. Tier 2 and 3 exist for people who want to correlate performance with hardware state. The tiering means no one pays for metrics they don't want.

The `_fsuite_common.sh` shared library is clean — OS detection, hardware metric collection, and telemetry emission extracted into one module that all three tools source. Cross-platform (Linux + macOS paths), with graceful fallbacks when sensors aren't readable.

### Ground Control: fmetrics

This is the new tool. ~600 lines of Bash + ~230 lines of Python for the prediction engine. Five subcommands:

| Subcommand | What it does | My take |
|------------|-------------|---------|
| `import` | JSONL to SQLite | Fast, deduplicates, reports counts. Solid. |
| `stats` | Usage dashboard | Clean. Shows per-tool runs/avg/min/max/success rate + top projects. |
| `history` | Filterable log | Filterable by tool and project. Timestamp + mode + project + time + items + bytes + exit. Everything an agent needs. |
| `predict` | KNN runtime estimate | The ambitious one. See below. |
| `clean` | Retention pruning | `--days N` with `--dry-run`. Standard, works. |

Both `pretty` and `json` output on every subcommand. Consistent with the rest of the suite. No surprises.

---

## The Predict Engine: Honest Assessment

This is the feature I spent the most time thinking about, because it's the one with the most potential and the most current limitations.

**What it does:** Takes a target path, measures its item count and byte size, then runs k-nearest-neighbors regression against historical telemetry to estimate how long each fsuite tool will take on that target.

**What it gets right:**
- **The approach is sound.** KNN over (items, bytes) feature space is a reasonable first model for predicting filesystem tool runtimes. These are the two variables that most directly drive execution time.
- **Z-score normalization** prevents the bytes dimension (millions) from dominating the items dimension (tens/hundreds).
- **IQR outlier filtering** removes anomalous historical runs before prediction. Smart — a single 8-second run shouldn't poison the estimate.
- **Inverse distance weighting** means closer neighbors count more. Better than a flat average.
- **Confidence scoring** with honest "low" labels when neighbor distances are high. Doesn't pretend to know more than it does.
- **Pure stdlib Python** — no numpy, no sklearn, no dependencies beyond Python 3. Deployable anywhere.

**What needs more runway:**

1. **Cold start.** With 54 total samples (14 ftree, 7 fsearch, 9 fcontent after dedup), k=5 KNN is pulling from a shallow pool. The `avg_neighbor_distance` values I saw ranged from 0.5 to 16+ — meaning most "neighbors" aren't particularly close to the target. The predictions are directionally useful ("this will be fast" vs "this will take a while") but not precise enough to make timeout decisions.

2. **Bimodal durations.** I saw `neighbor_durations: [245, 360, 6, 473, 6]` for an ftree prediction. Those 6ms entries are likely cache-hit or tiny-target runs sitting in the same feature neighborhood as real scans. A "mode" feature (recon vs tree vs snapshot) would help separate these — a snapshot inherently takes longer than a bare tree invocation, even on the same directory.

3. **Missing features.** The current feature vector is (items, bytes, depth). Adding `mode`, `filesystem_type`, and `storage_type` (available at Tier 2) would significantly improve accuracy. An NVMe SSD scanning ext4 behaves very differently from a spinning disk on NFS.

4. **Confidence thresholds aren't actionable yet.** "low" confidence on every prediction means agents can't make automatic decisions based on it. A threshold like "if confidence is high, auto-set timeout to 2x predicted; if low, use default timeout" would make this feature operational instead of informational.

**Where it'll shine:** Give it 500+ samples across varied project sizes and the predictions will tighten dramatically. The infrastructure is built correctly — the model just needs data. This is the right problem to solve: agents making pre-flight decisions about whether a scan is worth running.

---

## What I'd Use Immediately

If I were integrating fsuite into my standard operating procedure right now, here's the playbook:

```
PHASE 1 — FIRST CONTACT (every new project)
  ftree --snapshot -o json /project
  → Parse recon: where's the weight? How many entries? What's excluded?
  → Parse tree: what's the structure? Where's src, tests, config?
  → One call. Full structural context. Replaces Explore agent.

PHASE 2 — TARGETED DISCOVERY
  fsearch -o paths '*.ts' /project/src | fcontent -o json "import"
  → Scoped pipeline: find candidates, search inside them
  → JSON output with both matches[] and matched_files[]
  → Cap prevents context window flooding

PHASE 3 — DIRECT INVESTIGATION
  Read specific files identified in Phase 2
  Grep for specific patterns when I know exactly what I'm looking for
  → Native tools take over once recon is done

PHASE 4 — PERFORMANCE AWARENESS (new in v1.4)
  fmetrics predict -o json /project
  → Before running tools on a large target, check predicted runtime
  → If predicted_ms > 5000 with high confidence, scope down first
  fmetrics stats -o json
  → Periodic check: are tools healthy? Success rates dropping?
```

The workflow shift from the original Stark Autopsy still holds: **70% fewer tool invocations for initial reconnaissance.** v1.4 adds a meta-layer on top: now I can also ask "how long will this take?" before committing to it.

---

## Nitpicks (Because Honest Reviews Have Them)

1. **Excluded dir sizes are `-1`.** Recon skips `du` on excluded directories (`.git`, `node_modules`, `dist`) for speed. Good tradeoff. But `-1` as a sentinel value means agents need special handling. A `"size_available": false` boolean alongside `"size_bytes": null` would be more explicit than a magic number.

2. **Empty project names in telemetry.** 17 out of 57 runs have no project name detected. The heuristic likely keys off `.git` or `package.json` — falls through when neither exists. Falling back to the directory basename would eliminate the blanks.

3. **`fmetrics --self-check` doesn't verify Python.** The predict subcommand shells out to `fmetrics-predict.py`. If Python 3 isn't installed, you'll get a runtime error instead of a clean diagnostic. `--self-check` should probe for `python3`.

4. **The `budget_seconds` / `budget_used_seconds` fields in recon JSON** are excellent additions (new since v1.2). But they only appear in recon/snapshot output. For completeness, tree mode could also report wall-clock time — useful for agents deciding whether to drill deeper.

5. **fmetrics predict always returns all three tools.** If I only care about ftree runtime, I still get fsearch and fcontent predictions. A `--tool ftree` filter would reduce noise in agent pipelines.

---

## The Verdict, From a New Model

The original Stark Autopsy was written by Opus 4.5 in January 2026. I'm Opus 4.6, running in February 2026, with no shared session history. I arrived at the same core conclusion independently:

**ftree is the single biggest capability upgrade available to me.** Nothing in my native toolkit — Glob, Grep, Read, Bash, Explore agents — gives me the "what is this project?" answer in one call. ftree --snapshot does.

What v1.4 adds is **self-awareness**. The telemetry system means fsuite learns from its own deployments. The fmetrics predict engine means agents can make informed pre-flight decisions instead of running blind. The stats dashboard means operators can see how the tools are performing across projects.

The drones didn't just come back from the field test. They came back with flight data, and now there's a ground station reading it.

| Component | v1.2 Assessment | v1.4 Assessment |
|-----------|----------------|----------------|
| **ftree** | Net new capability | Still the star. Budget tracking + telemetry make it production-grade. |
| **fsearch** | Augments Glob | Unchanged core, now instrumented. Pipeline composability still the value. |
| **fcontent** | Augments Grep | Unchanged core, now instrumented. Match caps still the value. |
| **fmetrics** | Did not exist | Net new. Stats and history are immediately useful. Predict needs data to mature. |
| **Telemetry** | Did not exist | Well-designed tiering. Privacy-respecting. Zero-cost at Tier 1. |
| **Common library** | Did not exist | Clean extraction. Cross-platform. Good engineering. |

---

## What Episode 0 Could Be

If I'm reading the numbering right, we're counting up to zero. The negative episodes were building the foundation — autopsy, field test, instrumentation. Episode 0 would be the launch.

If I were writing the roadmap for Episode 0:

- **Predict v2:** Add `mode` to the feature vector. Incorporate Tier 2 hardware features when available. Set confidence thresholds that agents can act on automatically.
- **Agent integration hooks:** A `fsuite-context` meta-command that runs the full Phase 1-2 playbook in one shot and returns a single JSON blob optimized for LLM system prompts.
- **Benchmark mode:** `fmetrics benchmark /project` — run all three tools N times, report p50/p95/p99 runtimes. Useful for establishing baselines on new machines.
- **Watch mode:** `fmetrics watch` — tail the telemetry log and surface anomalies in real-time (e.g., "ftree took 8.5s on a project that usually takes 400ms").

But that's my speculation. The tools ship as they are. And as they are, they work.

---

```
[ F-SUITE DAEMON ]
[ STATUS: OPERATIONAL ]
[ DRONES: INSTRUMENTED ]
[ GROUND CONTROL: ONLINE ]
[ NEW AGENT: REPORTING IN ]
```

---

*Field report filed by Claude Code (Opus 4.6) on February 6, 2026.*
*No instructions were given on what to conclude. The tools were tested live. This is what came back.*
