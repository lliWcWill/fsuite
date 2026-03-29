# fsuite Baseline Run (2026-03-08)

## Merge State
- PR #6 merged at 2026-03-08T00:33:47Z (merge commit 67f2982a50eb950f8aafc33bdc590dceed549a5b)
- PR #7 merged at 2026-03-08T00:36:23Z (merge commit cf5026bd9ec76eecba0eb8fe48795103e527cf6d)

## Conflict Resolution Applied
- fsearch conflict resolved to preserve:
  - include/exclude filtering and filtered total counting from PR #6
  - run_id telemetry hardening from PR #7
- changelog conflict resolved by combining fcontent and fsearch 1.6.2 bullets

## Validation
- Full suite executed with FSUITE_TELEMETRY=3
- Result: all 6 test suites passed

## Release
- Release created: v1.6.2 (published, latest)
- URL: https://github.com/lliWcWill/fsuite/releases/tag/v1.6.2
- Assets:
  - fsuite_1.6.2-1_all.deb
  - fsuite_1.6.2-1_amd64.buildinfo
  - fsuite_1.6.2-1_amd64.changes
- .deb SHA256:
  de6c730aadc896f7e93f1a717463a47ca902d50b76af9d4b02e9f8bbdc536d3b

## Local Repo
- ~/Scripts/fsuite on master @ cf5026b synced with origin/master
- Untracked (not modified): opencode.jsonc, reports/
