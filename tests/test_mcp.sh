#!/usr/bin/env bash
# test_mcp.sh — run MCP wrapper regression tests from the mcp/ Node lane

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="${SCRIPT_DIR}/.."
MCP_DIR="${REPO_DIR}/mcp"

cd "${MCP_DIR}"
npm test
