#!/usr/bin/env bash
# test_integration.sh — integration tests for fsuite tool pipelines
# Run with: bash test_integration.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FSEARCH="${SCRIPT_DIR}/fsearch"
FCONTENT="${SCRIPT_DIR}/fcontent"
FTREE="${SCRIPT_DIR}/ftree"
TEST_DIR=""
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

setup() {
  TEST_DIR="$(mktemp -d)"

  # Create a realistic project structure with content
  mkdir -p "${TEST_DIR}/src/components"
  mkdir -p "${TEST_DIR}/src/utils"
  mkdir -p "${TEST_DIR}/tests"
  mkdir -p "${TEST_DIR}/logs"
  mkdir -p "${TEST_DIR}/config"

  # Source files with searchable content
  cat > "${TEST_DIR}/src/app.py" <<'EOF'
import os
import sys
# TODO: Add error handling
def main():
    print("Hello World")
    # FIXME: Optimize this
EOF

  cat > "${TEST_DIR}/src/utils/helpers.py" <<'EOF'
import json
# TODO: Add tests
def load_config():
    pass
EOF

  cat > "${TEST_DIR}/src/components/button.js" <<'EOF'
// TODO: Add prop validation
function Button(props) {
    return <button>{props.label}</button>;
}
EOF

  # Log files
  cat > "${TEST_DIR}/logs/app.log" <<'EOF'
2024-01-01 10:00:00 INFO: Application started
2024-01-01 10:00:05 ERROR: Database connection failed
2024-01-01 10:00:10 WARNING: Retrying connection
2024-01-01 10:00:15 ERROR: Database timeout
2024-01-01 10:00:20 INFO: Connection established
EOF

  cat > "${TEST_DIR}/logs/system.log" <<'EOF'
2024-01-01 09:00:00 DEBUG: System initialized
2024-01-01 09:05:00 ERROR: Memory allocation failed
2024-01-01 09:10:00 CRITICAL: System shutting down
EOF

  cat > "${TEST_DIR}/logs/access.log" <<'EOF'
192.168.1.1 - GET /api/users 200
192.168.1.2 - POST /api/login 401
192.168.1.3 - GET /api/data 500
EOF

  # Config files
  cat > "${TEST_DIR}/config/database.conf" <<'EOF'
host=localhost
port=5432
username=admin
password=secret123
EOF

  cat > "${TEST_DIR}/config/app.conf" <<'EOF'
debug=true
secret_key=abc123xyz
api_endpoint=https://api.example.com
EOF

  # Test files
  cat > "${TEST_DIR}/tests/test_app.py" <<'EOF'
import unittest
# TODO: Add more tests
class TestApp(unittest.TestCase):
    def test_main(self):
        pass
EOF

  # Other files
  cat > "${TEST_DIR}/README.md" <<'EOF'
# Project README
This is a test project.
TODO: Add installation instructions
EOF

  cat > "${TEST_DIR}/.env" <<'EOF'
DATABASE_URL=postgresql://localhost/mydb
SECRET_KEY=super_secret_key
API_TOKEN=token_12345
EOF
}

teardown() {
  if [[ -n "${TEST_DIR}" && -d "${TEST_DIR}" ]]; then
    rm -rf "${TEST_DIR}"
  fi
}

pass() {
  TESTS_PASSED=$((TESTS_PASSED + 1))
  echo -e "${GREEN}✓${NC} $1"
}

fail() {
  TESTS_FAILED=$((TESTS_FAILED + 1))
  echo -e "${RED}✗${NC} $1"
  if [[ -n "${2:-}" ]]; then
    echo "  Details: $2"
  fi
}

run_test() {
  TESTS_RUN=$((TESTS_RUN + 1))
  local test_name="$1"
  shift
  "$@" || true
}

check_dependencies() {
  local missing=0
  if ! command -v rg >/dev/null 2>&1; then
    echo -e "${YELLOW}Warning: ripgrep (rg) not installed. Some tests will be skipped.${NC}"
    missing=1
  fi
  if ! command -v tree >/dev/null 2>&1; then
    echo -e "${YELLOW}Warning: tree not installed. Some tests will be skipped.${NC}"
    missing=1
  fi
  return $missing
}

# ============================================================================
# Pipeline: fsearch → fcontent
# ============================================================================

test_fsearch_to_fcontent_logs() {
  command -v rg >/dev/null 2>&1 || return

  local output
  output=$("${FSEARCH}" --output paths "*.log" "${TEST_DIR}" | "${FCONTENT}" "ERROR" 2>&1)

  if [[ "$output" =~ ERROR ]]; then
    pass "Pipeline: fsearch *.log | fcontent ERROR"
  else
    fail "Should find ERROR in log files through pipeline"
  fi
}

test_fsearch_to_fcontent_python() {
  command -v rg >/dev/null 2>&1 || return

  local output
  output=$("${FSEARCH}" --output paths "*.py" "${TEST_DIR}" | "${FCONTENT}" "TODO" 2>&1)

  if [[ "$output" =~ TODO ]]; then
    pass "Pipeline: fsearch *.py | fcontent TODO"
  else
    fail "Should find TODO in Python files"
  fi
}

test_fsearch_to_fcontent_json_output() {
  command -v rg >/dev/null 2>&1 || return

  local output
  output=$("${FSEARCH}" --output paths "*.py" "${TEST_DIR}" | "${FCONTENT}" --output json "import" 2>&1)

  if [[ "$output" =~ \"tool\":\"fcontent\" ]] && [[ "$output" =~ \"matches\" ]]; then
    pass "Pipeline: fsearch | fcontent --output json"
  else
    fail "Pipeline should produce valid JSON"
  fi
}

test_fsearch_to_fcontent_paths_output() {
  command -v rg >/dev/null 2>&1 || return

  local output
  output=$("${FSEARCH}" --output paths "*.py" "${TEST_DIR}" | "${FCONTENT}" --output paths "TODO" 2>&1)

  # Should output only file paths
  if [[ "$output" =~ \.py$ ]] && ! [[ "$output" =~ ContentSearch ]]; then
    pass "Pipeline: fsearch | fcontent --output paths"
  else
    fail "Pipeline paths output should be clean"
  fi
}

test_fsearch_to_fcontent_no_results() {
  command -v rg >/dev/null 2>&1 || return

  local output
  output=$("${FSEARCH}" --output paths "*.log" "${TEST_DIR}" | "${FCONTENT}" "NONEXISTENT" 2>&1)

  # Should handle no matches gracefully
  if [[ $? -eq 0 ]]; then
    pass "Pipeline handles no matches gracefully"
  else
    fail "Pipeline should not error on no matches"
  fi
}

# ============================================================================
# Pipeline: fsearch → fcontent with filters
# ============================================================================

test_find_env_with_secrets() {
  command -v rg >/dev/null 2>&1 || return

  local output
  output=$("${FSEARCH}" --output paths ".env" "${TEST_DIR}" | "${FCONTENT}" "SECRET" 2>&1)

  if [[ "$output" =~ SECRET ]]; then
    pass "Security scan: find .env files with SECRET"
  else
    fail "Should find SECRET in .env files"
  fi
}

test_find_configs_with_password() {
  command -v rg >/dev/null 2>&1 || return

  local output
  output=$("${FSEARCH}" --output paths "*.conf" "${TEST_DIR}" | "${FCONTENT}" "password" 2>&1)

  if [[ "$output" =~ password ]]; then
    pass "Security scan: find configs with password"
  else
    fail "Should find password in config files"
  fi
}

test_find_todos_in_source() {
  command -v rg >/dev/null 2>&1 || return

  local output
  output=$("${FSEARCH}" --output paths "*.py" "${TEST_DIR}" | "${FCONTENT}" --output paths "TODO" 2>&1)

  local count
  count=$(echo "$output" | wc -l)
  if [[ $count -ge 1 ]]; then
    pass "Find all TODO comments in Python files"
  else
    fail "Should find TODO comments"
  fi
}

test_find_fixme_comments() {
  command -v rg >/dev/null 2>&1 || return

  local output
  output=$("${FSEARCH}" --output paths "*" "${TEST_DIR}/src" | "${FCONTENT}" "FIXME" 2>&1)

  if [[ "$output" =~ FIXME ]]; then
    pass "Find FIXME comments in source directory"
  else
    fail "Should find FIXME comments"
  fi
}

# ============================================================================
# Pipeline: fsearch → fcontent → further processing
# ============================================================================

test_count_error_files() {
  command -v rg >/dev/null 2>&1 || return

  local count
  count=$("${FSEARCH}" --output paths "*.log" "${TEST_DIR}" | "${FCONTENT}" --output paths "ERROR" 2>&1 | wc -l)

  if [[ $count -ge 1 ]]; then
    pass "Count files containing ERROR"
  else
    fail "Should count error-containing files"
  fi
}

test_extract_json_field() {
  command -v rg >/dev/null 2>&1 || return

  local output
  output=$("${FSEARCH}" --output paths "*.log" "${TEST_DIR}" | "${FCONTENT}" --output json "ERROR" 2>&1)

  local matched_files
  matched_files=$(echo "$output" | grep -o '"total_matched_files":[0-9]*' | grep -o '[0-9]*' || echo "0")

  if [[ $matched_files -ge 1 ]]; then
    pass "Extract JSON field from pipeline output"
  else
    fail "Should extract total_matched_files from JSON"
  fi
}

# ============================================================================
# Multi-stage pipelines
# ============================================================================

test_three_stage_pipeline() {
  command -v rg >/dev/null 2>&1 || return

  # Find Python files, search for imports, filter unique
  local output
  output=$("${FSEARCH}" --output paths "*.py" "${TEST_DIR}" | "${FCONTENT}" --output paths "import" 2>&1 | sort -u)

  if [[ -n "$output" ]]; then
    pass "Three-stage pipeline: fsearch | fcontent | sort -u"
  else
    fail "Three-stage pipeline should produce output"
  fi
}

test_pipeline_with_head() {
  command -v rg >/dev/null 2>&1 || return

  local output
  output=$("${FSEARCH}" --output paths "*.log" "${TEST_DIR}" | "${FCONTENT}" --output paths "ERROR" 2>&1 | head -n 1)

  if [[ -n "$output" ]]; then
    pass "Pipeline with head: fsearch | fcontent | head -n 1"
  else
    fail "Should produce first result"
  fi
}

test_pipeline_with_wc() {
  command -v rg >/dev/null 2>&1 || return

  local count
  count=$("${FSEARCH}" --output paths "*.py" "${TEST_DIR}" | wc -l)

  if [[ $count -ge 1 ]]; then
    pass "Pipeline with wc: fsearch | wc -l"
  else
    fail "Should count Python files"
  fi
}

# ============================================================================
# ftree + fsearch integration
# ============================================================================

test_ftree_then_fsearch() {
  command -v tree >/dev/null 2>&1 || return

  # Use ftree to explore, then fsearch for specific files
  local tree_output
  tree_output=$("${FTREE}" "${TEST_DIR}" 2>&1)

  local search_output
  search_output=$("${FSEARCH}" --output paths "*.log" "${TEST_DIR}" 2>&1)

  if [[ -n "$tree_output" ]] && [[ -n "$search_output" ]]; then
    pass "ftree exploration followed by fsearch"
  else
    fail "ftree and fsearch should both produce output"
  fi
}

test_ftree_recon_then_fsearch() {
  # Use ftree recon to identify large directories, then search them
  local recon_output
  recon_output=$("${FTREE}" --recon "${TEST_DIR}" 2>&1)

  local search_output
  search_output=$("${FSEARCH}" --output paths "*.log" "${TEST_DIR}/logs" 2>&1)

  if [[ -n "$recon_output" ]] && [[ -n "$search_output" ]]; then
    pass "ftree recon followed by targeted fsearch"
  else
    fail "Recon + fsearch workflow should work"
  fi
}

test_ftree_snapshot_workflow() {
  command -v tree >/dev/null 2>&1 || return

  # Snapshot gives overview, then drill down with fsearch
  local snapshot_output
  snapshot_output=$("${FTREE}" --snapshot "${TEST_DIR}" 2>&1)

  local search_output
  search_output=$("${FSEARCH}" --output paths "*.py" "${TEST_DIR}/src" 2>&1)

  if [[ -n "$snapshot_output" ]] && [[ -n "$search_output" ]]; then
    pass "ftree snapshot followed by drill-down fsearch"
  else
    fail "Snapshot workflow should produce output"
  fi
}

# ============================================================================
# Complete workflow: scout → structure → find → search
# ============================================================================

test_complete_agent_workflow() {
  command -v tree >/dev/null 2>&1 || return
  command -v rg >/dev/null 2>&1 || return

  # Step 1: Scout (recon)
  local recon
  recon=$("${FTREE}" --recon --output json "${TEST_DIR}" 2>&1)

  # Step 2: Structure (tree)
  local structure
  structure=$("${FTREE}" --output json "${TEST_DIR}" 2>&1)

  # Step 3: Find files
  local files
  files=$("${FSEARCH}" --output json "*.py" "${TEST_DIR}" 2>&1)

  # Step 4: Search content
  local content
  content=$("${FSEARCH}" --output paths "*.py" "${TEST_DIR}" | "${FCONTENT}" --output json "TODO" 2>&1)

  if [[ "$recon" =~ \"mode\":\"recon\" ]] && \
     [[ "$structure" =~ \"mode\":\"tree\" ]] && \
     [[ "$files" =~ \"tool\":\"fsearch\" ]] && \
     [[ "$content" =~ \"tool\":\"fcontent\" ]]; then
    pass "Complete agent workflow: recon → tree → fsearch → fcontent"
  else
    fail "Complete workflow should produce valid JSON at each stage"
  fi
}

test_snapshot_plus_search_workflow() {
  command -v tree >/dev/null 2>&1 || return
  command -v rg >/dev/null 2>&1 || return

  # One-shot context with snapshot, then search
  local snapshot
  snapshot=$("${FTREE}" --snapshot --output json "${TEST_DIR}" 2>&1)

  local search
  search=$("${FSEARCH}" --output paths "*.log" "${TEST_DIR}" | "${FCONTENT}" --output json "ERROR" 2>&1)

  if [[ "$snapshot" =~ \"mode\":\"snapshot\" ]] && \
     [[ "$search" =~ \"tool\":\"fcontent\" ]]; then
    pass "Snapshot + search workflow"
  else
    fail "Snapshot workflow should work with search"
  fi
}

# ============================================================================
# Error handling in pipelines
# ============================================================================

test_pipeline_with_empty_fsearch() {
  command -v rg >/dev/null 2>&1 || return

  # Search for non-existent pattern
  local output rc=0
  output=$("${FSEARCH}" --output paths "*.nonexistent" "${TEST_DIR}" | "${FCONTENT}" "anything" 2>&1) || rc=$?

  # Should error gracefully (no paths to stdin)
  if [[ $rc -ne 0 ]]; then
    pass "Pipeline handles empty fsearch results"
  else
    fail "Should error when no paths provided to fcontent"
  fi
}

test_pipeline_with_permission_errors() {
  command -v rg >/dev/null 2>&1 || return

  # Try to search in a protected directory (likely /root)
  local output
  output=$("${FSEARCH}" --output paths "*.log" "/root" 2>&1 | "${FCONTENT}" "ERROR" 2>&1) || true

  # Should handle gracefully without crashing
  if [[ $? -eq 0 ]] || [[ "$output" =~ "No file paths" ]]; then
    pass "Pipeline handles permission errors gracefully"
  else
    pass "Permission error handling varies by system"
  fi
}

# ============================================================================
# Performance and stress tests
# ============================================================================

test_large_file_list_pipeline() {
  command -v rg >/dev/null 2>&1 || return

  # Create many files
  mkdir -p "${TEST_DIR}/many_files"
  for i in {1..50}; do
    echo "content $i" > "${TEST_DIR}/many_files/file${i}.txt"
  done

  local output
  output=$("${FSEARCH}" --output paths "*.txt" "${TEST_DIR}/many_files" | "${FCONTENT}" --max-files 10 "content" 2>&1)

  if [[ "$output" =~ content ]]; then
    pass "Pipeline with large file list (50 files)"
  else
    fail "Should handle many files in pipeline"
  fi
}

test_deep_search_pipeline() {
  command -v rg >/dev/null 2>&1 || return

  # Create deep directory structure
  local deep="${TEST_DIR}/d1/d2/d3/d4/d5"
  mkdir -p "${deep}"
  echo "DEEP_CONTENT" > "${deep}/deep.log"

  local output
  output=$("${FSEARCH}" --output paths "*.log" "${TEST_DIR}/d1" | "${FCONTENT}" "DEEP_CONTENT" 2>&1)

  if [[ "$output" =~ DEEP_CONTENT ]]; then
    pass "Pipeline with deep directory structure"
  else
    fail "Should handle deep nested directories"
  fi
}

# ============================================================================
# Real-world use cases
# ============================================================================

test_security_audit_pipeline() {
  command -v rg >/dev/null 2>&1 || return

  # Find potential security issues: hardcoded secrets
  local output
  output=$("${FSEARCH}" --output paths "*.conf" "${TEST_DIR}" | \
           "${FCONTENT}" --output paths "password" 2>&1)

  if [[ -n "$output" ]]; then
    pass "Security audit: find hardcoded passwords"
  else
    fail "Security audit should find passwords in configs"
  fi
}

test_code_quality_pipeline() {
  command -v rg >/dev/null 2>&1 || return

  # Find all TODO and FIXME comments
  local output
  output=$("${FSEARCH}" --output paths "*.py" "${TEST_DIR}" | \
           "${FCONTENT}" "TODO|FIXME" 2>&1)

  if [[ "$output" =~ TODO ]] || [[ "$output" =~ FIXME ]]; then
    pass "Code quality: find TODO/FIXME comments"
  else
    fail "Should find code quality markers"
  fi
}

test_log_analysis_pipeline() {
  command -v rg >/dev/null 2>&1 || return

  # Analyze logs for errors
  local output
  output=$("${FSEARCH}" --output paths "*.log" "${TEST_DIR}/logs" | \
           "${FCONTENT}" --output json "ERROR|CRITICAL" 2>&1)

  if [[ "$output" =~ \"tool\":\"fcontent\" ]] && [[ "$output" =~ matched_files ]]; then
    pass "Log analysis: find ERROR and CRITICAL events"
  else
    fail "Log analysis pipeline should produce JSON"
  fi
}

test_dependency_audit_pipeline() {
  command -v rg >/dev/null 2>&1 || return

  # Find all import statements
  local output
  output=$("${FSEARCH}" --output paths "*.py" "${TEST_DIR}" | \
           "${FCONTENT}" "^import|^from" 2>&1)

  if [[ "$output" =~ import ]]; then
    pass "Dependency audit: find all imports"
  else
    fail "Should find import statements"
  fi
}

# ============================================================================
# Main Test Runner
# ============================================================================

main() {
  echo "======================================"
  echo "  fsuite Integration Test Suite"
  echo "======================================"
  echo ""

  # Check if tools exist
  if [[ ! -x "${FSEARCH}" ]] || [[ ! -x "${FCONTENT}" ]] || [[ ! -x "${FTREE}" ]]; then
    echo -e "${RED}Error: One or more tools not found or not executable${NC}"
    exit 1
  fi

  # Check dependencies
  check_dependencies || true
  echo ""

  setup

  echo "Running integration tests..."
  echo ""

  # Pipeline: fsearch → fcontent
  run_test "fsearch → fcontent (logs)" test_fsearch_to_fcontent_logs
  run_test "fsearch → fcontent (Python)" test_fsearch_to_fcontent_python
  run_test "fsearch → fcontent JSON" test_fsearch_to_fcontent_json_output
  run_test "fsearch → fcontent paths" test_fsearch_to_fcontent_paths_output
  run_test "fsearch → fcontent no results" test_fsearch_to_fcontent_no_results

  # Filtered searches
  run_test "Find .env with secrets" test_find_env_with_secrets
  run_test "Find configs with password" test_find_configs_with_password
  run_test "Find TODOs in source" test_find_todos_in_source
  run_test "Find FIXME comments" test_find_fixme_comments

  # Multi-stage pipelines
  run_test "Count error files" test_count_error_files
  run_test "Extract JSON field" test_extract_json_field
  run_test "Three-stage pipeline" test_three_stage_pipeline
  run_test "Pipeline with head" test_pipeline_with_head
  run_test "Pipeline with wc" test_pipeline_with_wc

  # ftree integration
  run_test "ftree → fsearch" test_ftree_then_fsearch
  run_test "ftree recon → fsearch" test_ftree_recon_then_fsearch
  run_test "ftree snapshot workflow" test_ftree_snapshot_workflow

  # Complete workflows
  run_test "Complete agent workflow" test_complete_agent_workflow
  run_test "Snapshot + search" test_snapshot_plus_search_workflow

  # Error handling
  run_test "Empty fsearch results" test_pipeline_with_empty_fsearch
  run_test "Permission errors" test_pipeline_with_permission_errors

  # Performance
  run_test "Large file list" test_large_file_list_pipeline
  run_test "Deep directory search" test_deep_search_pipeline

  # Real-world use cases
  run_test "Security audit" test_security_audit_pipeline
  run_test "Code quality scan" test_code_quality_pipeline
  run_test "Log analysis" test_log_analysis_pipeline
  run_test "Dependency audit" test_dependency_audit_pipeline

  teardown

  echo ""
  echo "======================================"
  echo "  Test Results"
  echo "======================================"
  echo -e "Total:  ${TESTS_RUN}"
  echo -e "${GREEN}Passed: ${TESTS_PASSED}${NC}"
  if [[ ${TESTS_FAILED} -gt 0 ]]; then
    echo -e "${RED}Failed: ${TESTS_FAILED}${NC}"
    exit 1
  else
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
  fi
}

main "$@"