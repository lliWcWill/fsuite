# fsuite Baseline Report

- Timestamp (UTC): 2026-03-07T20:19:30Z
- Repo: ~/Scripts/fsuite
- Commit: 83c042561995
- Working tree untracked/changed entries: 1
- Baseline scope: ftree/fsearch/fcontent/fmap/fmetrics
- Target A (Claude bot project): ~/Projects/clawdbot-ref
- Target B (random project): ~/Projects/phone-osint

## Test Suite Baseline

- Result: pass

```
[0;32mfmap Test Suite: PASSED[0m
[0;32mPassed: 61[0m
[0;32mftree Test Suite: PASSED[0m
[0;32mPassed: 27[0m
[0;32mIntegration Test Suite: PASSED[0m
[0;32mPassed: 30[0m
[0;32mTelemetry Test Suite: PASSED[0m
Total Test Suites: 6
[0;32mPassed: 6[0m
[0;32mAll test suites passed![0m
```

## Runtime Baseline

- Target A recon wall ms: 763
- Target A snapshot wall ms: 4978
- Target B recon wall ms: 140
- Target B snapshot wall ms: 498

## Target A: ftree Recon (JSON Summary)

```json
{"mode":"recon","path":"~/Projects/clawdbot-ref","recon_depth":1,"total_entries":74,"visible":71,"excluded":3,"budget_used_seconds":0,"partial":null,"duration_ms":497,"top_entries":[{"name":"src","type":"directory","size_human":"25.1M","items_total":4563,"excluded":false,"reason":null,"heavy":null},{"name":"extensions","type":"directory","size_human":"14.3M","items_total":1047,"excluded":false,"reason":null,"heavy":null},{"name":"docs","type":"directory","size_human":"13.5M","items_total":775,"excluded":false,"reason":null,"heavy":null},{"name":"apps","type":"directory","size_human":"9.2M","items_total":880,"excluded":false,"reason":null,"heavy":null},{"name":"ui","type":"directory","size_human":"1.5M","items_total":225,"excluded":false,"reason":null,"heavy":null},{"name":"assets","type":"directory","size_human":"1.2M","items_total":16,"excluded":false,"reason":null,"heavy":null}]}
```

## Target A: ftree Snapshot (JSON Summary)

```json
{"mode":"snapshot","path":"~/Projects/clawdbot-ref","duration_ms":4910,"recon_entries":466,"recon_partial":null,"tree_total_lines":2105,"tree_shown_lines":200,"tree_truncated":true}
```

## Target B: ftree Recon (JSON Summary)

```json
{"mode":"recon","path":"~/Projects/phone-osint","recon_depth":1,"total_entries":8,"visible":8,"excluded":0,"budget_used_seconds":1,"partial":null,"duration_ms":79,"top_entries":[{"name":"WhatsApp-OSINT","type":"directory","size_human":"2.9M","items_total":59,"excluded":false,"reason":null,"heavy":null},{"name":"Phunter","type":"directory","size_human":"244K","items_total":69,"excluded":false,"reason":null,"heavy":null},{"name":"phone-number-lookup","type":"directory","size_human":"169.7K","items_total":51,"excluded":false,"reason":null,"heavy":null},{"name":"Inspector","type":"directory","size_human":"138.1K","items_total":67,"excluded":false,"reason":null,"heavy":null},{"name":"ViberOSINT","type":"directory","size_human":"120.9K","items_total":54,"excluded":false,"reason":null,"heavy":null},{"name":"results","type":"directory","size_human":"31.7K","items_total":18,"excluded":false,"reason":null,"heavy":null}]}
```

## Target B: ftree Snapshot (JSON Summary)

```json
{"mode":"snapshot","path":"~/Projects/phone-osint","duration_ms":455,"recon_entries":46,"recon_partial":null,"tree_total_lines":85,"tree_shown_lines":85,"tree_truncated":false}
```

## Tool Chain Baseline (Target A)

### fsearch
```json
{"tool":"fsearch","backend":"find","total_found":5514,"shown":40,"sample":["~/Projects/clawdbot-ref/vitest.config.ts","~/Projects/clawdbot-ref/vitest.live.config.ts","~/Projects/clawdbot-ref/tsdown.config.ts","~/Projects/clawdbot-ref/vitest.e2e.config.ts","~/Projects/clawdbot-ref/ui/vitest.config.ts","~/Projects/clawdbot-ref/ui/vite.config.ts","~/Projects/clawdbot-ref/ui/src/ui/theme-transition.ts","~/Projects/clawdbot-ref/ui/src/ui/focus-mode.browser.test.ts"]}
```

### fmap
```json
{"tool":"fmap","mode":"stdin_files","total_files_scanned":40,"total_files_with_symbols":39,"total_symbols":505,"shown_symbols":160,"truncated":true,"languages":{"typescript":39}}
```

### fcontent
```json
{"tool":"fcontent","mode":"stdin_files","total_matched_files":35,"shown_matches":80,"matched_sample":["~/Projects/clawdbot-ref/tsdown.config.ts","~/Projects/clawdbot-ref/ui/src/ui/app-chat.ts","~/Projects/clawdbot-ref/ui/src/ui/app-defaults.ts","~/Projects/clawdbot-ref/ui/src/ui/app-lifecycle.ts","~/Projects/clawdbot-ref/ui/src/ui/app-polling.ts","~/Projects/clawdbot-ref/ui/src/ui/app-render.helpers.node.test.ts","~/Projects/clawdbot-ref/ui/src/ui/app-render.helpers.ts","~/Projects/clawdbot-ref/ui/src/ui/app-render.ts"],"match_sample":["~/Projects/clawdbot-ref/ui/src/ui/views/channels.nostr-profile-form.ts:7:import { html, nothing, type TemplateResult } from \"lit\";","~/Projects/clawdbot-ref/ui/src/ui/views/channels.nostr-profile-form.ts:8:import type { NostrProfile as NostrProfileType } from \"../types.ts\";","~/Projects/clawdbot-ref/ui/src/ui/views/channels.nostr-profile-form.ts:21:  /** Whether import is in progress */","~/Projects/clawdbot-ref/ui/src/ui/views/channels.nostr-profile-form.ts:38:  /** Called when import is clicked */"]}
```

## fmetrics Baseline

### import
```json
{"subcommand":"import","total_lines":34,"inserted":22,"skipped":12,"errors":0}
```

### stats
```json
{"total_runs":83,"tools":[{"name":"fcontent","runs":26,"avg_ms":81,"min_ms":9,"max_ms":536,"success_rate":100.0},{"name":"fmap","runs":6,"avg_ms":823,"min_ms":21,"max_ms":1810,"success_rate":100.0},{"name":"fsearch","runs":27,"avg_ms":55,"min_ms":4,"max_ms":349,"success_rate":100.0},{"name":"ftree","runs":24,"avg_ms":1112,"min_ms":6,"max_ms":8853,"success_rate":100.0}],"top_projects":[{"name":"clawdbot-ref","runs":15},{"name":"fsuite","runs":8},{"name":"tmp.kMFJFFlF1P","runs":7},{"name":"logs","runs":5},{"name":"src","runs":5}]}
```

### predict (ftree, target A)
```json
{"method":"knn_regression","target_features":{"items":74,"bytes":350850968,"depth":3},"predictions":[{"tool":"ftree","predicted_ms":716,"std_dev_ms":115,"confidence":"high","k_used":5,"avg_neighbor_distance":0.042,"neighbor_durations":[700,725,722,452,643],"samples":24}],"total_historical_samples":83}
```

### predict (ftree, target B)
```json
{"method":"knn_regression","target_features":{"items":8,"bytes":3792456,"depth":3},"predictions":[{"tool":"ftree","predicted_ms":103,"std_dev_ms":53,"confidence":"low","k_used":5,"avg_neighbor_distance":0.003,"neighbor_durations":[99,107,7,6,7],"samples":24}],"total_historical_samples":83}
```

## Notes

- This file is intended as run-0 baseline for future comparison after fixes.
- Report generated by automated command run in one shell session.
