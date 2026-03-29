# fsuite Autonomous Readiness Audit

- Timestamp (UTC): 2026-03-07T20:21:32Z
- Repo: ~/Scripts/fsuite
- Commit: 83c042561995
- Targets: ~/Projects/clawdbot-ref ; ~/Projects/phone-osint
- Linked baseline report: reports/fsuite-baseline-20260307T201930Z.md

## Scorecard

- PASS: 13
- FAIL: 2
- WARN: 1

## Checks

| Check | Status | Detail |
|---|---|---|
| Syntax Gate | PASS | bash -n passed for all core scripts |
| Headless ftree | PASS | non-interactive recon completed |
| Headless fsearch | PASS | non-interactive fsearch completed |
| Headless fcontent | PASS | non-interactive fcontent completed |
| Headless fmap | PASS | non-interactive fmap completed |
| ftree JSON Contract | PASS | core recon fields valid |
| fsearch JSON Contract | PASS | core search fields valid |
| fcontent JSON Contract | PASS | core content fields valid |
| fmap JSON Contract | PASS | core map fields valid |
| Determinism ftree(recon) | PASS | normalized outputs identical |
| Determinism fsearch(paths) | PASS | repeat hash stable |
| Pipeline Autonomy | PASS | ftree -> fsearch -> fmap/fcontent completed |
| fcontent -q Exit Semantics | FAIL | returns 0 on no match (doc says 1) |
| ftree recon-depth identity | FAIL | duplicate ambiguous names detected (2 groups) |
| Telemetry Uniqueness | WARN | import skipped duplicates=36 (possible timestamp/path/tool collisions) |
| Performance Ordering | PASS | snapshot(4923ms) >= recon(485ms) |

## Pipeline Artifacts

### snapshot summary
```json
{"recon_entries":466,"tree_lines":2105}
```

### fmap summary
```json
{"files":40,"symbols":505,"truncated":true}
```

### fcontent summary
```json
{"files":35,"matches":60}
```

## Cross-validated standards (official docs)

- Bash command substitution runs in a subshell for `$(...)` (GNU Bash manual).
- GNU `timeout` uses exit code `124` on timeout (GNU Coreutils).
- SQLite `UNIQUE` and `INSERT OR IGNORE` behavior confirmed (sqlite.org docs).
- `tree -J` JSON mode confirmed (tree manpage).

