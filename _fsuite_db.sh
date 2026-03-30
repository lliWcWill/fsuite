#!/usr/bin/env bash
# _fsuite_db.sh — shared SQLite database helpers for fsuite tools (fcase, freplay).
# Sourced (not executed). Provides: ensure_db, db_query, db_exec, migrations.

# Guard: only source once.
[[ -z "${_FSUITE_DB_LOADED:-}" ]] || return 0
_FSUITE_DB_LOADED=1

# ---------------------------------------------------------------------------
# Globals — callers may override before sourcing.
# ---------------------------------------------------------------------------
FCASE_DIR="${FCASE_DIR:-$HOME/.fsuite}"
DB_FILE="${DB_FILE:-$FCASE_DIR/fcase.db}"
SQLITE_BUSY_TIMEOUT_MS="${SQLITE_BUSY_TIMEOUT_MS:-5000}"
SQLITE_SUPPORTS_DOT_TIMEOUT=""

# _FSUITE_DB_TOOL_NAME: callers set this before sourcing so die() prints
# the right tool name (e.g. "fcase" or "freplay").

# ---------------------------------------------------------------------------
# Utility helpers
# ---------------------------------------------------------------------------

die() {
  local code=1
  if [[ "${1:-}" =~ ^[0-9]+$ ]]; then
    code="$1"
    shift
  fi
  echo "${_FSUITE_DB_TOOL_NAME:-fsuite}: $*" >&2
  exit "$code"
}

has() { command -v "$1" >/dev/null 2>&1; }

json_escape() {
  perl -CS -0pe '
    s/\\/\\\\/g;
    s/"/\\"/g;
    s/\x08/\\b/g;
    s/\x0c/\\f/g;
    s/\n/\\n/g;
    s/\r/\\r/g;
    s/\t/\\t/g;
    s/([\x00-\x07\x0b\x0e-\x1f])/sprintf("\\u%04x", ord($1))/ge;
  '
}

sql_quote() {
  local value="${1//\'/\'\'}"
  printf "'%s'" "$value"
}

now_utc() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# ---------------------------------------------------------------------------
# DB existence check (for read-only paths — no side effects)
# ---------------------------------------------------------------------------

db_exists() {
  [[ -f "$DB_FILE" ]]
}

# ---------------------------------------------------------------------------
# SQLite session plumbing
# ---------------------------------------------------------------------------

sqlite_supports_dot_timeout() {
  if [[ -n "$SQLITE_SUPPORTS_DOT_TIMEOUT" ]]; then
    [[ "$SQLITE_SUPPORTS_DOT_TIMEOUT" == "1" ]]
    return
  fi

  local probe_output="" probe_rc=0
  probe_output=$(sqlite3 ':memory:' ".timeout 1" "SELECT 1;" 2>/dev/null) || probe_rc=$?
  if [[ $probe_rc -eq 0 && "$probe_output" == "1" ]]; then
    SQLITE_SUPPORTS_DOT_TIMEOUT="1"
  else
    SQLITE_SUPPORTS_DOT_TIMEOUT="0"
  fi

  [[ "$SQLITE_SUPPORTS_DOT_TIMEOUT" == "1" ]]
}

emit_db_session_prefix() {
  if sqlite_supports_dot_timeout; then
    # Prefer the sqlite shell timeout command when available because it does
    # not leak a result row into stdout before JSON payloads.
    printf '.timeout %s\nPRAGMA foreign_keys=ON;\n' "$SQLITE_BUSY_TIMEOUT_MS"
  else
    # Some environments provide a minimal sqlite3 shim that echoes PRAGMA
    # assignment results. Preserve clean stdout for JSON commands there.
    printf 'PRAGMA foreign_keys=ON;\n'
  fi
}

db_query() {
  local separator=""
  if [[ "${1:-}" == "--separator" ]]; then
    separator="${2:-}"
    [[ -n "$separator" ]] || die "db_query requires a value for --separator"
    shift 2
  fi

  has sqlite3 || die 3 "sqlite3 is required"

  if [[ -n "$separator" ]]; then
    { emit_db_session_prefix; cat; } | sqlite3 -separator "$separator" "$DB_FILE"
  else
    { emit_db_session_prefix; cat; } | sqlite3 "$DB_FILE"
  fi
}

db_exec() {
  has sqlite3 || die 3 "sqlite3 is required"
  mkdir -p "$FCASE_DIR" 2>/dev/null || die "Cannot create $FCASE_DIR"
  { emit_db_session_prefix; cat; } | sqlite3 "$DB_FILE" >/dev/null
}

# ---------------------------------------------------------------------------
# Version-aware database migration
# ---------------------------------------------------------------------------

ensure_db() {
  has sqlite3 || die 3 "sqlite3 is required"
  mkdir -p "$FCASE_DIR" 2>/dev/null || die "Cannot create $FCASE_DIR"

  # Keep WAL enabled even for pre-existing DBs or externally created files.
  sqlite3 "$DB_FILE" 'PRAGMA journal_mode=WAL;' >/dev/null 2>&1 || true

  local current_version=0
  if [[ -f "$DB_FILE" ]]; then
    current_version="$(sqlite3 "$DB_FILE" 'PRAGMA user_version;' 2>/dev/null || echo 0)"
  fi

  # --- Migration to version 1: fcase core tables ---
  if (( current_version < 1 )); then
    db_exec <<'SQL'
PRAGMA foreign_keys=ON;

CREATE TABLE IF NOT EXISTS cases (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  slug TEXT NOT NULL UNIQUE,
  goal TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'open',
  priority TEXT NOT NULL DEFAULT 'normal',
  case_kind TEXT NOT NULL DEFAULT 'explicit_diagnosis',
  next_move TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS case_sessions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  case_id INTEGER NOT NULL REFERENCES cases(id) ON DELETE CASCADE,
  started_at TEXT NOT NULL,
  ended_at TEXT,
  actor TEXT NOT NULL,
  summary TEXT NOT NULL DEFAULT ''
);

CREATE TABLE IF NOT EXISTS targets (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  case_id INTEGER NOT NULL REFERENCES cases(id) ON DELETE CASCADE,
  path TEXT NOT NULL,
  symbol TEXT,
  symbol_type TEXT,
  rank INTEGER,
  reason TEXT,
  state TEXT NOT NULL DEFAULT 'candidate',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS evidence (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  case_id INTEGER NOT NULL REFERENCES cases(id) ON DELETE CASCADE,
  tool TEXT NOT NULL,
  path TEXT,
  symbol TEXT,
  line_start INTEGER,
  line_end INTEGER,
  match_line INTEGER,
  summary TEXT,
  body TEXT NOT NULL,
  payload_json TEXT,
  fingerprint TEXT,
  created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS hypotheses (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  case_id INTEGER NOT NULL REFERENCES cases(id) ON DELETE CASCADE,
  body TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'open',
  confidence TEXT,
  reason TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  case_id INTEGER NOT NULL REFERENCES cases(id) ON DELETE CASCADE,
  session_id INTEGER REFERENCES case_sessions(id) ON DELETE SET NULL,
  event_type TEXT NOT NULL,
  payload_json TEXT,
  created_at TEXT NOT NULL
);

PRAGMA user_version=1;
SQL
    current_version=1
  fi

  # --- Migration to version 2: replay tables ---
  if (( current_version < 2 )); then
    db_exec <<'SQL'
PRAGMA foreign_keys=ON;

CREATE TABLE IF NOT EXISTS replays (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  case_id INTEGER NOT NULL REFERENCES cases(id) ON DELETE CASCADE,
  label TEXT NOT NULL DEFAULT '',
  status TEXT NOT NULL DEFAULT 'draft'
    CHECK (status IN ('draft','canonical','archived')),
  origin TEXT NOT NULL DEFAULT 'recorded'
    CHECK (origin IN ('recorded','imported','inferred')),
  fsuite_version TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  actor TEXT NOT NULL DEFAULT '',
  parent_replay_id INTEGER REFERENCES replays(id) ON DELETE SET NULL,
  notes TEXT NOT NULL DEFAULT ''
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_replays_one_canonical_per_case
  ON replays(case_id) WHERE status = 'canonical';

CREATE TABLE IF NOT EXISTS replay_steps (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  replay_id INTEGER NOT NULL REFERENCES replays(id) ON DELETE CASCADE,
  order_num INTEGER NOT NULL,
  tool TEXT NOT NULL,
  argv_json TEXT NOT NULL,
  cwd TEXT NOT NULL,
  mode TEXT NOT NULL CHECK (mode IN ('read_only','mutating','unknown')),
  purpose TEXT,
  provenance TEXT NOT NULL DEFAULT 'recorded'
    CHECK (provenance IN ('recorded','imported','inferred')),
  exit_code INTEGER NOT NULL,
  duration_ms INTEGER NOT NULL DEFAULT 0,
  started_at TEXT NOT NULL,
  telemetry_run_id TEXT,
  result_summary TEXT,
  error_excerpt TEXT,
  UNIQUE (replay_id, order_num)
);

CREATE TABLE IF NOT EXISTS replay_step_links (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  step_id INTEGER NOT NULL REFERENCES replay_steps(id) ON DELETE CASCADE,
  link_type TEXT NOT NULL
    CHECK (link_type IN ('evidence','target','hypothesis')),
  link_ref TEXT NOT NULL,
  UNIQUE (step_id, link_type, link_ref)
);

PRAGMA user_version=2;
SQL
    current_version=2
  fi

    # --- Migration to version 3: lifecycle columns, indexes, FTS ---
    if (( current_version < 3 )); then
    # New columns on cases (idempotent — SQLite errors if column exists)
    db_exec <<'SQL' 2>/dev/null || true
ALTER TABLE cases ADD COLUMN resolution_summary TEXT NOT NULL DEFAULT '';
SQL
    db_exec <<'SQL' 2>/dev/null || true
ALTER TABLE cases ADD COLUMN resolved_at TEXT;
SQL
    db_exec <<'SQL' 2>/dev/null || true
ALTER TABLE cases ADD COLUMN archived_at TEXT;
SQL
    db_exec <<'SQL' 2>/dev/null || true
ALTER TABLE cases ADD COLUMN deleted_at TEXT;
SQL
    db_exec <<'SQL' 2>/dev/null || true
ALTER TABLE cases ADD COLUMN delete_reason TEXT NOT NULL DEFAULT '';
SQL

    # Performance indexes
    db_exec <<'SQL'
CREATE INDEX IF NOT EXISTS idx_cases_status_updated ON cases(status, updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_events_case_id ON events(case_id, id DESC);
CREATE INDEX IF NOT EXISTS idx_evidence_case_id ON evidence(case_id);
CREATE INDEX IF NOT EXISTS idx_hypotheses_case_id ON hypotheses(case_id);
CREATE INDEX IF NOT EXISTS idx_targets_case_id ON targets(case_id);
CREATE INDEX IF NOT EXISTS idx_sessions_case_id ON case_sessions(case_id, id DESC);
SQL

    # FTS virtual table (standalone — not bound to cases content table)
    # Uses FTS4 for broad SQLite compatibility (FTS5 not always compiled in).
    db_exec <<'SQL'
CREATE VIRTUAL TABLE IF NOT EXISTS cases_fts USING fts4(
  slug,
  goal,
  resolution_summary,
  targets_text,
  evidence_text,
  hypotheses_text,
  notes_text
);
SQL

    db_exec <<'SQL'
PRAGMA user_version=3;
SQL
    current_version=3

      # Rebuild FTS index for all existing cases
      rebuild_all_fts
    fi

    # --- Migration to version 4: case kinds for shadow/promoted visibility ---
    if (( current_version < 4 )); then
      db_exec <<'SQL' 2>/dev/null || true
ALTER TABLE cases ADD COLUMN case_kind TEXT NOT NULL DEFAULT 'explicit_diagnosis';
SQL
      db_exec <<'SQL'
UPDATE cases
SET case_kind = 'explicit_diagnosis'
WHERE case_kind IS NULL OR TRIM(case_kind) = '';
PRAGMA user_version=4;
SQL
      current_version=4
    fi
  }

# ---------------------------------------------------------------------------
# FTS rebuild helpers
# ---------------------------------------------------------------------------

rebuild_fts_for_case() {
  local case_id="$1"
  [[ "$case_id" =~ ^[0-9]+$ ]] || return 1
  # Delete existing FTS row for this case
  db_exec <<SQL
DELETE FROM cases_fts WHERE rowid = $case_id;
SQL
  # Rebuild from current data
  db_exec <<SQL
INSERT INTO cases_fts(rowid, slug, goal, resolution_summary, targets_text, evidence_text, hypotheses_text, notes_text)
SELECT
  c.id,
  c.slug,
  c.goal,
  c.resolution_summary,
  COALESCE((SELECT group_concat(COALESCE(t.path,'') || ' ' || COALESCE(t.symbol,''), ' ') FROM targets t WHERE t.case_id = c.id), ''),
  COALESCE((SELECT group_concat(COALESCE(e.summary,'') || ' ' || COALESCE(e.body,''), ' ') FROM evidence e WHERE e.case_id = c.id), ''),
  COALESCE((SELECT group_concat(COALESCE(h.body,'') || ' ' || COALESCE(h.reason,''), ' ') FROM hypotheses h WHERE h.case_id = c.id), ''),
    COALESCE((SELECT group_concat(COALESCE(ev.payload_json,''), ' ') FROM events ev WHERE ev.case_id = c.id AND ev.event_type IN ('note','next_move_set','case_resolved','case_deleted','agent_feedback','user_feedback','insight','progress','verification','promotion')), '')
FROM cases c WHERE c.id = $case_id;
SQL
}

rebuild_all_fts() {
  db_exec <<'SQL'
BEGIN;
DELETE FROM cases_fts;
INSERT INTO cases_fts(rowid, slug, goal, resolution_summary, targets_text, evidence_text, hypotheses_text, notes_text)
SELECT
  c.id,
  c.slug,
  c.goal,
  c.resolution_summary,
  COALESCE((SELECT group_concat(COALESCE(t.path,'') || ' ' || COALESCE(t.symbol,''), ' ') FROM targets t WHERE t.case_id = c.id), ''),
  COALESCE((SELECT group_concat(COALESCE(e.summary,'') || ' ' || COALESCE(e.body,''), ' ') FROM evidence e WHERE e.case_id = c.id), ''),
  COALESCE((SELECT group_concat(COALESCE(h.body,'') || ' ' || COALESCE(h.reason,''), ' ') FROM hypotheses h WHERE h.case_id = c.id), ''),
    COALESCE((SELECT group_concat(COALESCE(ev.payload_json,''), ' ') FROM events ev WHERE ev.case_id = c.id AND ev.event_type IN ('note','next_move_set','case_resolved','case_deleted','agent_feedback','user_feedback','insight','progress','verification','promotion')), '')
FROM cases c;
COMMIT;
SQL
}

# ---------------------------------------------------------------------------
# Case lookup helpers
# ---------------------------------------------------------------------------

case_id_for_slug() {
  local slug="$1"
  db_query <<<"SELECT id FROM cases WHERE slug = $(sql_quote "$slug");"
}

case_exists_or_die() {
  local slug="$1"
  local case_id
  case_id="$(case_id_for_slug "$slug")"
  [[ -n "$case_id" ]] || die "case not found: $slug"
  printf '%s' "$case_id"
}
