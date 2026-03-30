#!/usr/bin/env bash
# test_mcp.sh — run MCP wrapper regression tests from the mcp/ Node lane

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="${SCRIPT_DIR}/.."
MCP_DIR="${REPO_DIR}/mcp"

if [[ ! -d "${MCP_DIR}" ]]; then
  echo "test_mcp.sh: missing mcp directory: ${MCP_DIR}" >&2
  exit 1
fi

cd "${MCP_DIR}"
npm test
