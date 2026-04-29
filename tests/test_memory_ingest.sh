#!/usr/bin/env bash
# test_memory_ingest.sh — unit tests for mcp/memory-ingest.js (Phase 4)
# Run with: bash test_memory_ingest.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INGEST_HELPER="${SCRIPT_DIR}/../mcp/memory-ingest.js"

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

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
local name="$1"
shift
echo "Running: $name"
"$@" || true
}

# ── Tests ─────────────────────────────────────────────────────────────────────

# Empty stdin: should exit 1 with "invalid payload" in stderr
test_empty_stdin() {
    local err rc=0
    err=$(printf '' | node "$INGEST_HELPER" 2>&1 >/dev/null) || rc=$?
    if (( rc == 0 )); then
        fail "empty stdin: should exit 1" "exit=$rc"
        return
    fi
    if [[ "$err" != *"invalid payload"* ]]; then
        fail "empty stdin: stderr should mention 'invalid payload'" "Got: $err"
        return
    fi
    pass "empty stdin: exits 1 with 'invalid payload'"
}

# Malformed JSON: should exit 1 with error in stderr
test_malformed_json() {
    local err rc=0
    err=$(printf 'not json' | node "$INGEST_HELPER" 2>&1 >/dev/null) || rc=$?
    if (( rc == 0 )); then
        fail "malformed JSON: should exit 1" "exit=$rc"
        return
    fi
    if [[ "$err" != *"invalid payload"* ]]; then
        fail "malformed JSON: stderr should mention 'invalid payload'" "Got: $err"
        return
    fi
    pass "malformed JSON: exits 1 with 'invalid payload'"
}

# Valid payload but no ShieldCortex config: should exit 0 with "unreachable" warning
test_no_config() {
    local err rc=0
    # Strip PATH of ~/.local/bin (where shieldcortex-mcp lives) and use a
    # non-existent HOME so ~/.claude.json and ~/.codex/config.toml can't be found.
    err=$(printf '{"title":"t","category":"c","content":"x","tags":["a"]}' \
        | PATH="/usr/local/bin:/usr/bin:/bin" HOME=/nonexistent node "$INGEST_HELPER" 2>&1 >/dev/null) || rc=$?
    if (( rc != 0 )); then
        fail "no-config: should exit 0 when no command configured" "exit=$rc stderr=$err"
        return
    fi
    if [[ "$err" != *"unreachable: no command configured"* ]]; then
        fail "no-config: stderr should mention 'unreachable: no command configured'" "Got: $err"
        return
    fi
    pass "no-config: exits 0 with 'unreachable: no command configured'"
}

# Timeout: FSUITE_SHIELDCORTEX_CMD="sleep 10" triggers the 3s internal timer.
# The helper exits 1 with "timeout" in stderr; no outer timeout wrapper needed.
test_timeout() {
    local err rc=0
    err=$(printf '{"title":"t","category":"c","content":"x","tags":["a"]}' \
        | FSUITE_SHIELDCORTEX_CMD="sleep 10" node "$INGEST_HELPER" 2>&1 >/dev/null) || rc=$?
    if (( rc == 0 )); then
        fail "timeout: should exit non-zero" "exit=$rc"
        return
    fi
    if [[ "$err" != *"timeout"* ]]; then
        fail "timeout: stderr should mention 'timeout'" "Got: $err"
        return
    fi
    pass "timeout: exits non-zero with 'timeout' in stderr"
}

# ── Main ──────────────────────────────────────────────────────────────────────

main() {
    trap 'true' EXIT INT TERM
    echo "======================================"
    echo "  memory-ingest helper Test Suite"
    echo "======================================"
    echo ""

    if [[ ! -f "$INGEST_HELPER" ]]; then
        echo -e "${RED}Error: memory-ingest.js not found at ${INGEST_HELPER}${NC}"
        exit 1
    fi

    if ! command -v node >/dev/null 2>&1; then
        echo -e "${RED}Error: node not found in PATH${NC}"
        exit 1
    fi

    echo "Running tests..."
    echo ""

    run_test "Empty stdin" test_empty_stdin
    run_test "Malformed JSON" test_malformed_json
    run_test "No ShieldCortex config" test_no_config
    run_test "Timeout" test_timeout

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
