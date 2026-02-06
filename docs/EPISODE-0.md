```
    ███████╗███████╗██╗   ██╗██╗████████╗███████╗
    ██╔════╝██╔════╝██║   ██║██║╚══██╔══╝██╔════╝
    █████╗  ███████╗██║   ██║██║   ██║   █████╗
    ██╔══╝  ╚════██║██║   ██║██║   ██║   ██╔══╝
    ██║     ███████║╚██████╔╝██║   ██║   ███████╗
    ╚═╝     ╚══════╝ ╚═════╝ ╚═╝   ╚═╝   ╚══════╝
    ─────────────────────────────────────────────
    [ FIELD DISPATCH ]  Episode 0: The Launch
    [ PREVIOUS ]        Episode -1: The Return Trip
    [ STATUS ]          Drones explain themselves. QA showed up. Ground control upgraded.
```

---

## Mission Context

The countdown hit zero.

Episode -3, the Stark Autopsy — we sat Claude Code down and asked it what it was missing. It said reconnaissance. The ability to land somewhere new and know what you're looking at before you start reading. That was January.

Episode -2, the Field Test — we sent the drones into hostile territory and they didn't come back. du_bytes was out there doing a recursive byte count on a 200GB directory like it had all the time in the world. We added timeouts, budgets, heavy tags. The drones learned to come home.

Episode -1, the Return Trip — we handed a fresh agent (different model, zero history) the keys to v1.4. It ran every tool live, filed a report, and dropped five nitpicks. Five specific things that weren't right yet.

That was forty-eight hours ago.

All five nitpicks are fixed. The test suite that was supposed to catch regressions was broken in ways nobody noticed — entire suites crashing before half the tests could run. That's fixed too. And the ground station learned to talk to the drones by name.

This is Episode 0. The drones aren't prototypes anymore.

---

## The Nitpick Report Card

The Opus 4.6 agent filed five specific issues in its V2 analysis. Here's what happened to them:

| # | Nitpick | Status | What We Did |
|---|---------|--------|-------------|
| 1 | Excluded dir sizes are `-1` with no explanation | **FIXED** | Recon entries now carry a `reason` field: `excluded`, `budget_exceeded`, `timeout`, `stat_failed` |
| 2 | Empty project names in telemetry | **FIXED** | All tools walk up from scan path to find project markers (`.git`, `package.json`, `Cargo.toml`, etc). fcontent also infers from stdin. `--project-name` override still wins. Falls back to `basename` when no markers found |
| 3 | `--self-check` doesn't verify Python | **FIXED** | Reports python3, fmetrics-predict.py, and k-NN availability as three separate lines |
| 4 | No wall-clock timing in JSON output | **FIXED** | `duration_ms` field added to recon, tree, and snapshot JSON envelopes |
| 5 | Predict always returns all three tools | **FIXED** | `fmetrics predict --tool ftree` filters to a single drone |

Five out of five. The agent filed the nitpicks. We fixed them. That's the loop working.

---

## The Real Story: The Tests Were Lying

Here's the thing nobody talks about in release notes: the test suite was broken.

Not "a few tests were flaky" broken. **Structurally broken.** Three out of five test suites were crashing before half their tests could execute, and the master runner was reporting them as failures without telling you that 40% of the assertions never ran.

The root causes:

**`run_test()` was a suicide pact.** In fsearch and fcontent, the test harness function didn't have `|| true`. Under `set -e`, any test function that returned nonzero killed the entire suite. Not the test — the *suite*. Every test after the first failure was silently skipped. The ftree suite had the fix. The other two didn't. Nobody noticed because the suite "failed" either way — you just didn't know it failed on test 6 instead of test 19.

**SIGPIPE was a landmine.** `test_paths_pipeable` piped command output through `head -n 1` under `set -eo pipefail`. When `head` got its one line and closed the pipe, the upstream command caught SIGPIPE and the whole script died. Not the test. The script. Capture full output first, extract later. This is the kind of bug that only fires when the tool *works correctly*.

**`$?` was always zero.** Three fcontent tests did this:

```bash
output=$("${FCONTENT}" "query" "${DIR}" 2>&1)
if [[ $? -ne 0 ]]; then    # $? is ALWAYS 0 here
```

`$?` checks the *assignment*, not the command. The command could segfault and `$?` would still be 0 because the variable assignment succeeded. The fix: `output=$(cmd) || rc=$?` on the same line.

**The hide-excluded test was checking the wrong thing.** `test_recon_hide_excluded` asserted that the string "default-excluded" shouldn't appear in output. But the summary header *always* contains "N entries (M visible, K default-excluded)" as a count. The `[default-excluded]` *section* is what gets hidden. The test was checking a substring that appears in every recon output regardless of the flag. It passed when it should have failed. It would have passed if `--hide-excluded` did nothing at all.

**After the fix:** 197 tests across 5 suites. Zero failures. Zero skipped. Every assertion actually executes.

The drones were tested. The tests weren't. Now they are.

---

## Technical Changes

### ftree v1.4.0 → v1.5.0

The mapper drone learned to explain itself and got a new output mode.

**Recon reason field.** Every entry with `size_bytes: -1` now carries a reason:

```json
{"name": "node_modules", "type": "dir", "size_bytes": -1, "reason": "excluded"}
{"name": "build",        "type": "dir", "size_bytes": -1, "reason": "budget_exceeded"}
{"name": "cache",        "type": "dir", "size_bytes": -1, "reason": "timeout"}
{"name": "locked.db",    "type": "file","size_bytes": -1, "reason": "stat_failed"}
```

Four distinct reasons. No more magic `-1` with no explanation. Agents can now make different decisions: `excluded` means "this is fine, we skip these on purpose." `timeout` means "this tunnel goes deep, send a specialist." `stat_failed` means "permissions problem, escalate." The `-1` used to mean all of these simultaneously. Now it speaks.

Pretty output shows reasons inline: `node_modules/ [excluded] (heavy)` — human-readable at a glance.

**`--no-lines` flag.** Snapshot JSON normally includes both `tree_json` (the structural map) and `lines` (the rendered text tree). `--no-lines` drops the lines array — keeps the machine-readable structure, sheds the human-readable rendering. For agents that parse JSON and never display text, this cuts payload size.

Validated strictly: only works with `--snapshot -o json`. Using it with pretty output or non-snapshot mode dies with a clear error. No silent no-ops.

**Telemetry flag accumulation.** Every flag you pass is now recorded in telemetry. Not just the mode and output format — every `-L`, `--budget`, `--include`, `--hide-excluded`, `-q`. Accumulated with space-prefixed concatenation, sanitized through `tr -cd '[:alnum:] _./-'` before JSONL emission. Caps at 200 chars.

The sanitizer is a deliberate tradeoff: `--rg-args "-i --hidden"` records as `--rg-args` (flag name only, value stripped). For analytics — understanding which features are used and how often — flag presence is enough. For JSONL integrity — not shipping broken JSON because someone passed a brace in an argument — safety wins.

Default seeding: even if you pass zero flags, telemetry records the output format (`-o pretty`). Mode flags (`--recon`, `--snapshot`) are seeded after arg parsing, not accumulated in the case branch, to avoid duplication.

**`--project-name` flag.** Overrides the auto-detected project name in telemetry. The path hash stays derived from the actual filesystem path — these serve different purposes. Path hash correlates runs against the same directory. Project name is a human label. `--project-name "my-monorepo-frontend"` lets you tag telemetry without changing what path you're scanning.

Project names are sanitized: `tr -cd '[:alnum:]. _-'`. No injection through the name field.

**`duration_ms` in JSON output.** Every JSON mode now reports wall-clock milliseconds. The V2 agent specifically noted that tree mode had no timing data — agents couldn't decide whether to drill deeper without knowing how long the last scan took. Now they can:

```json
{"tool":"ftree", "mode":"recon", "duration_ms":77, "path":"/project", ...}
{"tool":"ftree", "mode":"tree",  "duration_ms":8,  "path":"/project", ...}
{"tool":"ftree", "mode":"snapshot", "duration_ms":410, "snapshot":{...}}
```

Recon and tree both have top-level `duration_ms`. Snapshot has top-level `duration_ms` for total time, and the nested recon object has its own `duration_ms` for the recon phase. The nested tree object inside snapshot intentionally omits `duration_ms` to avoid the impossible case where child duration exceeds parent (they'd be measured at different moments in the output stream).

Timestamps reuse the existing `_TELEM_START_MS` infrastructure — no new syscalls.

**Smart project name inference.** All three tools now walk up from the scan path to find the nearest project root marker (`.git`, `package.json`, `Cargo.toml`, `go.mod`, `pyproject.toml`, `setup.py`, `.project`, `Makefile`). If found, the project name is the marker directory's basename. If not found, falls back to the scan path's basename (previous behavior).

The heuristic is extracted into `_fsuite_infer_project_name()` in `_fsuite_common.sh` — shared by all tools, no duplication. Guarded with `type` check so tools still work if the common library isn't available (graceful degradation, verified by test).

This means `ftree /home/user/myproject/src` now records `project_name: "myproject"` instead of `project_name: "src"`. The V2 agent flagged 17 out of 57 runs with wrong or empty project names. This fix addresses the root cause rather than just the empty case.

### fsearch v1.4.0 → v1.5.0

Same additions as ftree: `--project-name`, telemetry flag accumulation with JSONL safety, default flag seeding, and smart project name inference. The search drone records what switches were flipped and knows what project it's scanning.

### fcontent v1.4.0 → v1.5.0

The content scanner got the same three telemetry features plus one unique capability:

**Stdin project inference.** When fcontent receives file paths on stdin (the pipeline case: `fsearch -o paths '*.ts' | fcontent "TODO"`), it now infers the project from the first file path. Walks up the directory tree looking for `.git`, `package.json`, `Cargo.toml`, `go.mod`, or `pyproject.toml`. Sets `SEARCH_PATH` so telemetry records the project name, not the user's home directory.

This matters because the pipeline use case is fcontent's primary deployment mode. Before this fix, `fsearch -o paths '*.ts' /home/user/project/src | fcontent "TODO"` would record project name as `user` (derived from cwd). Now it records `project` (derived from where the files actually live).

### fmetrics v1.4.0 → v1.5.0

Ground control got smarter about its drones and its own dependencies.

**`predict --tool` filter.** `fmetrics predict --tool ftree /path` returns only the ftree prediction. Before: always returned all three tools. If you're an agent and you only care about how long `ftree --recon` will take on a target, you don't need fsearch and fcontent predictions cluttering your context.

Validated both in Bash (the tool loop) and Python (the k-NN engine). Invalid tool names die with a clear error listing the three valid options.

**`_find_predict_script()` multi-path resolution.** The predict command shells out to `fmetrics-predict.py`. In a source checkout, it's `$SCRIPT_DIR/fmetrics-predict.py`. In a .deb install, it's `/usr/share/fsuite/fmetrics-predict.py`. The old code hardcoded the source checkout path. The new helper searches four candidate locations:

```bash
_find_predict_script() {
  local candidates=(
    "$SCRIPT_DIR/fmetrics-predict.py"
    "$SCRIPT_DIR/fmetrics-predict"
    "/usr/share/fsuite/fmetrics-predict.py"
    "/usr/lib/fsuite/fmetrics-predict.py"
  )
  for c in "${candidates[@]}"; do
    [[ -f "$c" ]] && { printf "%s" "$c"; return 0; }
  done
  return 1
}
```

**`--self-check` enhancement.** Now reports three separate lines instead of one:

```
python3: Python 3.11.2
fmetrics-predict.py: found at /home/user/fsuite/fmetrics-predict.py
k-NN predictions: available
```

If python3 is missing but the script exists, you see it. If python3 is installed but the script can't be found, you see that too. Different problems, different diagnostic messages. Same philosophy as the recon reason field — don't say `-1` when you could say *why*.

**Error messages split.** The old "Install python3 for k-NN predictions" message now distinguishes between python3 not installed and predict script not found. Different fix instructions for different problems.

### Packaging

**debian/rules fix.** `fmetrics-predict.py` now installs to `/usr/share/fsuite/` with its `.py` extension preserved, not `/usr/bin/fmetrics-predict` stripped of its extension. The multi-path resolver in fmetrics finds it in either location.

---

## The Test Overhaul

Not a patch. A rebuild.

| Suite | Before | After | What Changed |
|-------|--------|-------|-------------|
| test_fsearch.sh | 36 tests, suite crashes on test 6 | 39 tests, all pass | `run_test || true`, SIGPIPE fix, +3 v1.5.0 tests |
| test_fcontent.sh | 40 tests, `$?` bugs mask failures | 45 tests, all pass | `run_test || true`, 3 `$?` fixes, missing-query fix, +5 v1.5.0 tests |
| test_ftree.sh | 50 tests, wrong assertion passes | 62 tests, all pass | hide-excluded fix, +8 v1.5.0 tests, +4 duration_ms + inference tests |
| test_integration.sh | 28 tests | 28 tests, all pass | Unchanged (was already clean) |
| test_telemetry.sh | 19 tests | 29 tests, all pass | +7 v1.5.0 tests, +3 walk-up inference tests (all tools + fallback) |

**New v1.5.0+ coverage (36 tests):**
- `--project-name` override in all three tools (3 tests)
- Telemetry flag accumulation with correct values (3 tests)
- Default flag seeding when no explicit flags passed (3 tests)
- JSONL safety with `--rg-args` special characters (2 tests)
- `--no-lines` JSON output, snapshot-only validation, json-only validation (3 tests)
- Recon reason field in JSON and pretty output (2 tests)
- Recon reason for excluded entries specifically (1 test)
- Stdin project inference from piped file paths (1 test)
- fmetrics `--self-check` python3 reporting (1 test)
- fmetrics `--self-check` predict script reporting (1 test)
- fmetrics `predict --tool` filter (1 test)
- Cross-tool flag accumulation and JSONL validation in telemetry suite (7 tests)
- Predict with varied directory sizes for k-NN coverage (1 test)
- `duration_ms` in recon JSON (1 test)
- `duration_ms` in tree JSON (1 test)
- `duration_ms` in snapshot JSON with hierarchy validation (1 test)
- Project name walk-up inference across all 3 tools (1 test, 3 assertions)
- Project name basename fallback without markers (1 test)
- Project name inference from ftree subdir scan (1 test)

**Portability fixes (CodeRabbit findings):**
- 8 instances of `grep -oP` (GNU Perl regex, fails on macOS/BSD) replaced with `grep -o`
- 1 shell injection via `python3 -c "json.loads('$var')"` replaced with stdin pipe

---

## The Numbers

```
14 files changed
~780 insertions(+)
~95 deletions(-)
──────────────────
net ~685 lines

203 tests across 5 suites
0 failures
5/5 suites passing
```

Half the weight is in tests. The other half is split between ftree (reason field, --no-lines, flag accumulation) and fmetrics (predict --tool, self-check, multi-path resolution). The three-tool telemetry additions (--project-name, flags, JSONL safety) are small per-file but replicated across ftree, fsearch, and fcontent.

---

## Test Plan

- [ ] `ftree --recon -o json /project` — entries with `size_bytes: -1` show `reason` field
- [ ] `ftree --recon --hide-excluded /project` — `[default-excluded]` section hidden, summary header still shows count
- [ ] `ftree --snapshot --no-lines -o json /project` — `tree_json` present, no `lines` array
- [ ] `ftree --no-lines /project` — errors: "only valid with --snapshot"
- [ ] `ftree --snapshot --no-lines -o pretty /project` — errors: "only meaningful with -o json"
- [ ] `fmetrics predict --tool ftree /project` — only ftree prediction returned
- [ ] `fmetrics predict --tool invalid /project` — clean error with valid options listed
- [ ] `fmetrics --self-check` — reports python3 and fmetrics-predict.py separately
- [ ] `ftree --project-name "TestProject" /tmp && tail -1 ~/.fsuite/telemetry.jsonl` — project_name is "TestProject"
- [ ] `ftree --recon --budget 5 -L 2 -o json /tmp && tail -1 ~/.fsuite/telemetry.jsonl` — flags include `--budget 5 -L 2 --recon -o json`
- [ ] `ftree /tmp && tail -1 ~/.fsuite/telemetry.jsonl` — flags still show `-o pretty` (seeded default)
- [ ] `fcontent --rg-args "-i --hidden" "test" /tmp && python3 -c "import json; json.loads(open('$HOME/.fsuite/telemetry.jsonl').readlines()[-1])"` — JSONL parses clean
- [ ] `fsearch -o paths '*.txt' /project | fcontent "TODO" && tail -1 ~/.fsuite/telemetry.jsonl` — project inferred from file paths, not cwd
- [ ] `ftree --recon -o json /project | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['duration_ms'])"` — integer >= 0
- [ ] `ftree -o json /project | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['duration_ms'])"` — integer >= 0
- [ ] `ftree --snapshot -o json /project` — top-level `duration_ms` present, nested tree omits it
- [ ] `ftree /project/src` then check telemetry — project_name should be "project" (found .git), not "src"
- [ ] `ftree /tmp/random_dir` then check telemetry — project_name should be "random_dir" (basename fallback)
- [ ] `bash tests/run_all_tests.sh` — 203 tests, 0 failures, 5/5 suites
- [ ] `bash -n ftree fsearch fcontent fmetrics` — syntax check passes on all scripts
- [ ] All tools report `1.5.0` via `--version`

---

## Closing Transmission

The negative episodes were about building. Build the drones. Test them in the field. Instrument them with telemetry. Hand them to a stranger and see what breaks.

Episode 0 is about trust.

The drones explain why they couldn't scan something — not just `-1` but *excluded*, *timeout*, *budget_exceeded*, *stat_failed*. They report how long they took — millisecond precision, right in the JSON output. They know what project they're working on even when pointed at a subdirectory six levels deep — they walk up until they find `.git` and name the project correctly.

The ground station knows which drone to ask about. The flight recorders capture every switch that was flipped, sanitized so the log files don't corrupt themselves. The pipeline drones figure out what project they're working on even when deployed through a pipe.

And the test suite — the thing that's supposed to catch all of this — actually runs every assertion instead of silently dying on test 6 and pretending the other 33 were fine.

The agent filed five nitpicks. We fixed all five. The countdown hit zero. The drones are production-grade.

```
[ F-SUITE DAEMON ]
[ STATUS: OPERATIONAL ]
[ DRONES: PRODUCTION-GRADE ]
[ GROUND CONTROL: UPGRADED ]
[ QA: ACTUALLY RUNNING ]
[ EPISODE: 0 ]
```

---

*Field dispatch filed by Claude Code (Opus 4.6) on February 6, 2026.*
*Five nitpicks fixed. Thirty-six tests added. Zero failures. The countdown hit zero.*

---

### Summary

**New Features**
- Recon reason field (`excluded`, `budget_exceeded`, `timeout`, `stat_failed`) for all entries with `size_bytes: -1`
- `--no-lines` flag for ftree snapshot JSON — omit rendered tree lines, keep structural data
- `--project-name` flag for all tools — override telemetry project name
- `fmetrics predict --tool` filter — predict for a single tool instead of all three
- `duration_ms` field in ftree JSON output — wall-clock timing for recon, tree, and snapshot modes
- Smart project name inference — all tools walk up to find project root markers (`.git`, `package.json`, etc)
- fcontent stdin project inference — pipeline deployments auto-detect project from file paths
- Telemetry flag accumulation with JSONL safety — every flag recorded, special characters sanitized

**Improvements**
- `fmetrics --self-check` reports python3, predict script, and k-NN availability separately
- `_find_predict_script()` multi-path resolution for source checkout and .deb install
- `_fsuite_infer_project_name()` shared function in common library with graceful fallback
- Split error messages: python3 missing vs predict script missing
- Packaging fix: fmetrics-predict.py installs to `/usr/share/fsuite/` with extension preserved

**Testing**
- Test suite overhaul: 162 → 203 tests, 3 crashing suites → 0 failures
- Fixed `run_test` harness in fsearch/fcontent (missing `|| true` under `set -e`)
- Fixed SIGPIPE crash in `test_paths_pipeable` (capture-then-extract pattern)
- Fixed `$?` capture bugs in 3 fcontent tests (`output=$(cmd) || rc=$?`)
- Fixed `test_recon_hide_excluded` wrong assertion (`[default-excluded]` section vs substring)
- 36 new feature tests across all 5 suites
- 8x `grep -oP` → `grep -o` for macOS/BSD portability
- 1x shell injection fix in JSON validation (stdin pipe instead of string interpolation)

**Chores**
- Version bumped to 1.5.0 across all tools + predict script
- `debian/changelog` updated
- `docs/ftree.md` and `README.md` updated with new flags and features
