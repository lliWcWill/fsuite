#!/usr/bin/env python3
"""Incremental telemetry importer for fmetrics."""

from __future__ import annotations

import argparse
import json
import os
import sqlite3
import sys
import time


class RecordValidationError(ValueError):
    """Raised when a JSON payload is structurally valid but missing required fields."""


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Incremental telemetry importer for fmetrics")
    parser.add_argument("--db", required=True, help="Path to telemetry SQLite database")
    parser.add_argument("--jsonl", required=True, help="Path to telemetry JSONL file")
    return parser.parse_args()


def meta_get(conn: sqlite3.Connection, key: str, default: str = "") -> str:
    row = conn.execute(
        "SELECT value FROM analytics_meta WHERE key = ?;",
        (key,),
    ).fetchone()
    if not row:
        return default
    return row[0]


def meta_set(conn: sqlite3.Connection, key: str, value: object) -> None:
    conn.execute(
        """
        INSERT INTO analytics_meta (key, value) VALUES (?, ?)
        ON CONFLICT(key) DO UPDATE SET value = excluded.value;
        """,
        (key, str(value)),
    )


def safe_int(value: object, default: int) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return default


def starting_offset(conn: sqlite3.Connection, stat_result: os.stat_result) -> tuple[int, bool]:
    prev_device = meta_get(conn, "telemetry_import_device")
    prev_inode = meta_get(conn, "telemetry_import_inode")
    prev_offset = safe_int(meta_get(conn, "telemetry_import_offset", "0"), 0)
    prev_size = safe_int(meta_get(conn, "telemetry_import_size", "0"), 0)
    same_identity = (
        prev_device == str(stat_result.st_dev)
        and prev_inode == str(stat_result.st_ino)
    )
    if not prev_device or not prev_inode or not same_identity:
        return 0, True
    if prev_offset < 0 or stat_result.st_size < prev_offset or stat_result.st_size < prev_size:
        return 0, True
    return prev_offset, False


def table_exists(conn: sqlite3.Connection, table_name: str) -> bool:
    row = conn.execute(
        "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?;",
        (table_name,),
    ).fetchone()
    return row is not None


def clear_derived_tables(conn: sqlite3.Connection) -> None:
    for table_name in ("run_steps_v1", "run_facts_v1", "combo_stats_v1", "combo_next_stats_v1"):
        if table_exists(conn, table_name):
            conn.execute(f"DELETE FROM {table_name};")


def normalize_record(payload: dict[str, object], line_offset: int) -> tuple:
    timestamp = str(payload.get("timestamp", "") or "").strip()
    tool = str(payload.get("tool", "") or "").strip()
    if not timestamp or not tool:
        raise RecordValidationError("record missing required timestamp/tool")

    version = str(payload.get("version", "") or "").strip()
    mode = str(payload.get("mode", "") or "").strip()
    path_hash = str(payload.get("path_hash", "") or "").strip()
    project_name = str(payload.get("project_name", "") or "").strip()
    duration_ms = safe_int(payload.get("duration_ms", 0), 0)
    exit_code = safe_int(payload.get("exit_code", 0), 0)
    depth = safe_int(payload.get("depth", -1), -1)
    items_scanned = safe_int(payload.get("items_scanned", -1), -1)
    bytes_scanned = safe_int(payload.get("bytes_scanned", -1), -1)
    flags = str(payload.get("flags", "") or "")
    backend = str(payload.get("backend", "") or "")
    cpu_temp_mc = safe_int(payload.get("cpu_temp_mc", -1), -1)
    disk_temp_mc = safe_int(payload.get("disk_temp_mc", -1), -1)
    ram_total_kb = safe_int(payload.get("ram_total_kb", -1), -1)
    ram_available_kb = safe_int(payload.get("ram_available_kb", -1), -1)
    load_avg_1m = str(payload.get("load_avg_1m", "-1") or "-1").strip() or "-1"
    filesystem_type = str(payload.get("filesystem_type", "unknown") or "unknown").strip() or "unknown"
    storage_type = str(payload.get("storage_type", "unknown") or "unknown").strip() or "unknown"
    run_id = str(payload.get("run_id", "") or "").strip()
    if not run_id:
        run_id = f"{timestamp}_{duration_ms}_{line_offset}"

    return (
        timestamp,
        tool,
        version,
        mode,
        path_hash,
        project_name,
        duration_ms,
        exit_code,
        depth,
        items_scanned,
        bytes_scanned,
        flags,
        backend,
        cpu_temp_mc,
        disk_temp_mc,
        ram_total_kb,
        ram_available_kb,
        load_avg_1m,
        filesystem_type,
        storage_type,
        run_id,
    )


def main() -> int:
    args = parse_args()
    db_path = os.path.abspath(args.db)
    jsonl_path = os.path.abspath(args.jsonl)

    if not os.path.exists(jsonl_path):
        print(f"fmetrics-import.py: telemetry file not found: {jsonl_path}", file=sys.stderr)
        return 2

    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA busy_timeout = 5000;")

    total_lines = 0
    inserted = 0
    skipped = 0
    errors = 0
    validation_errors = 0
    start_offset = 0
    end_offset = 0
    reset_cursor = False

    try:
        initial_stat = os.stat(jsonl_path)
        start_offset, reset_cursor = starting_offset(conn, initial_stat)
        end_offset = start_offset

        conn.execute("BEGIN IMMEDIATE;")
        insert_sql = """
            INSERT OR IGNORE INTO telemetry (
                timestamp, tool, version, mode, path_hash, project_name,
                duration_ms, exit_code, depth, items_scanned, bytes_scanned,
                flags, backend, cpu_temp_mc, disk_temp_mc, ram_total_kb,
                ram_available_kb, load_avg_1m, filesystem_type, storage_type, run_id
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """

        with open(jsonl_path, "rb") as handle:
            handle.seek(start_offset)
            while True:
                line_offset = handle.tell()
                raw = handle.readline()
                if not raw:
                    break
                end_offset = handle.tell()
                if not raw.strip():
                    continue
                total_lines += 1
                try:
                    payload = json.loads(raw)
                except (json.JSONDecodeError, UnicodeDecodeError):
                    errors += 1
                    continue
                if not isinstance(payload, dict):
                    errors += 1
                    continue
                try:
                    row = normalize_record(payload, line_offset)
                except RecordValidationError:
                    errors += 1
                    validation_errors += 1
                    continue
                before = conn.total_changes
                conn.execute(insert_sql, row)
                if conn.total_changes > before:
                    inserted += 1
                else:
                    skipped += 1

            final_stat = os.fstat(handle.fileno())

        if inserted > 0:
            clear_derived_tables(conn)
            meta_set(conn, "analytics_dirty", 1)
        meta_set(conn, "telemetry_import_device", final_stat.st_dev)
        meta_set(conn, "telemetry_import_inode", final_stat.st_ino)
        meta_set(conn, "telemetry_import_offset", end_offset)
        meta_set(conn, "telemetry_import_size", final_stat.st_size)
        meta_set(conn, "telemetry_last_imported_at", time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()))
        conn.commit()
    except (sqlite3.Error, OSError) as exc:
        conn.rollback()
        print(f"fmetrics-import.py: {exc}", file=sys.stderr)
        return 1
    finally:
        conn.close()

    result = {
        "tool": "fmetrics",
        "subcommand": "import",
        "db_path": db_path,
        "jsonl_path": jsonl_path,
        "total_lines": total_lines,
        "inserted": inserted,
        "skipped": skipped,
        "errors": errors,
        "validation_errors": validation_errors,
        "start_offset": start_offset,
        "end_offset": end_offset,
        "cursor_reset": 1 if reset_cursor else 0,
        "analytics_dirty": 1 if inserted > 0 else 0,
    }
    print(json.dumps(result, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())