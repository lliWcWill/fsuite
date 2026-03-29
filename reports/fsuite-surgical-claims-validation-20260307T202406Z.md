# fsuite Surgical Claims Validation

- Timestamp (UTC): 2026-03-07T20:24:20Z
- Repo: ~/Scripts/fsuite
- Commit: 83c042561995

## Verdicts

| Claim | Verdict | Evidence |
|---|---|---|
| fsuite is 5 tools incl. fmetrics | **Confirmed** | Executables present: `ftree`, `fmap`, `fcontent`, `fsearch`, `fmetrics` ([repo listing](~/Scripts/fsuite)). |
| README frames suite as 4 tools and omits fmetrics in top table | **Confirmed** | README states "A four-tool ..." and top tool table has 4 entries ([README.md](~/Scripts/fsuite/README.md:13), [README.md](~/Scripts/fsuite/README.md:17)). |
| fmetrics is undocumented in README | **Partially true / overstated** | fmetrics is documented later with flags/subcommands ([README.md](~/Scripts/fsuite/README.md:688), [README.md](~/Scripts/fsuite/README.md:770)). |
| ftree JSON truncation lacks drill-down hint | **Confirmed** | Truncated JSON has `truncated:true` but no hint field ([ftree](~/Scripts/fsuite/ftree:1079), [ftree](~/Scripts/fsuite/ftree:1085)). |
| fmetrics prediction can be highly inaccurate at low confidence | **Confirmed** | Predicted: 56ms, actual snapshot: 8198ms, error factor: 146.39x, confidence=low, distance=17159.345. |
| fmap truncation doesn’t identify which files were cut | **Confirmed** | JSON has `truncated`, `shown_symbols`, `total_symbols` but no `files_truncated` field ([fmap](~/Scripts/fsuite/fmap:831), [fmap](~/Scripts/fsuite/fmap:887)). |
| Missing lifecycle tool: fread | **Confirmed as product gap** | Current suite has no read-preview tool for bounded file content extraction after mapping/search. |

## Additional Critical Defects (from local audit)

- `ftree` recon-depth identity bug for duplicate basenames at depth >1 ([ftree](~/Scripts/fsuite/ftree:631), [ftree](~/Scripts/fsuite/ftree:924)).
- `fcontent -q` exit code semantics mismatch vs docs ([fcontent](~/Scripts/fsuite/fcontent:468), [README.md](~/Scripts/fsuite/README.md:500)).
- Telemetry uniqueness collisions from second-granularity timestamp + unique key design ([fmetrics](~/Scripts/fsuite/fmetrics:115)).

## Official Standards Cross-Validation (External)

- Bash command substitution subshell semantics: GNU Bash manual
  - https://www.gnu.org/s/bash/manual/html_node/Command-Substitution.html
- timeout exit 124 semantics: GNU Coreutils
  - https://www.gnu.org/s/coreutils/timeout
- SQLite UNIQUE and IGNORE conflict handling: sqlite.org
  - https://sqlite.org/lang_createtable.html
  - https://sqlite.org/lang_conflict.html
- tree -J JSON output mode: tree manpage
  - https://gitlab.com/OldManProgrammer/unix-tree/-/blob/master/doc/tree.1

