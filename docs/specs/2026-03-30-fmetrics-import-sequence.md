# fmetrics Import Sequence

Validated against the current implementation on 2026-03-30.

Key points the diagram below preserves:

- `fmetrics import` delegates to `python3 fmetrics-import.py --db --jsonl` when `telemetry.jsonl` exists.
- `fmetrics-import.py` resumes from `analytics_meta` cursor state (`device`, `inode`, `offset`, `size`) and resets to offset `0` when the file identity or size indicates a reset.
- New rows are inserted with `INSERT OR IGNORE`.
- Derived analytics tables are cleared and `analytics_dirty=1` is set only when new rows were inserted.
- Import updates the `telemetry_import_*` cursor metadata and `telemetry_last_imported_at`, then commits.
- The importer returns JSON. `fmetrics` either echoes that JSON unchanged or renders a pretty summary.
- Import does not rebuild analytics tables. It marks them dirty and leaves rebuild to `fmetrics rebuild` or lazy rebuild paths like `combos` / `recommend`.

```mermaid
sequenceDiagram
    participant User as User
    participant FMetrics as fmetrics (shell)
    participant Import as fmetrics-import.py
    participant DB as SQLite
    participant Out as stdout

    User->>FMetrics: fmetrics import
    alt telemetry.jsonl missing
        FMetrics-->>Out: JSON stub or "No telemetry data found..."
    else telemetry.jsonl present
        FMetrics->>Import: python3 fmetrics-import.py --db --jsonl
        Import->>DB: read analytics_meta import cursor
        Import->>Import: compute starting_offset(reset if needed)
        Import->>DB: BEGIN IMMEDIATE
        Import->>Import: read appended JSONL lines from start_offset
        Import->>Import: parse JSON + normalize_record validation
        Import->>DB: INSERT OR IGNORE into telemetry
        alt inserted > 0
            Import->>DB: clear derived tables
            Import->>DB: set analytics_dirty=1
        end
        Import->>DB: update telemetry_import_* + telemetry_last_imported_at
        Import->>DB: COMMIT
        Import-->>FMetrics: JSON {tool, subcommand, db_path, jsonl_path, total_lines, inserted, skipped, errors, validation_errors, start_offset, end_offset, cursor_reset, analytics_dirty}
        alt -o json
            FMetrics-->>Out: echo importer JSON unchanged
        else pretty output
            FMetrics-->>Out: processed/inserted/skipped/errors summary + dirty hint
        end
    end
```
