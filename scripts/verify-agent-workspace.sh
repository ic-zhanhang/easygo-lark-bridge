#!/usr/bin/env bash
set -euo pipefail

PACK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="${PACK_ROOT}/config/easygo.env"

if [[ -f "${CONFIG_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${CONFIG_FILE}"
fi

RUNTIME_DIR="${RUNTIME_DIR:-${EASYGO_CLAW_ROOT:-${PACK_ROOT}/runtime}}"
EASYGO_WORKSPACE_FILE="${EASYGO_WORKSPACE_FILE:-/Users/ic/workspace/easygo-dev.code-workspace}"
AGENT_BIN="${AGENT_BIN:-$HOME/.local/bin/agent}"

export CURSOR_API_KEY="${CURSOR_API_KEY:-}"

echo "==> Agent workspace 验证"
echo "    runtime=${RUNTIME_DIR}"
echo ""

if [[ ! -x "${AGENT_BIN}" ]]; then
  echo "❌ 未找到 Agent CLI: ${AGENT_BIN}"
  exit 1
fi

if [[ -z "${CURSOR_API_KEY}" ]]; then
  echo "⚠️  未设置 CURSOR_API_KEY（source config/easygo.env 后再试）"
fi

run_probe() {
  local label="$1" workspace="$2"
  echo "── ${label}: ${workspace}"
  if "$AGENT_BIN" --workspace "${workspace}" -p --force --trust \
    "只回复一行：OK" 2>&1; then
    echo "✅ 通过"
  else
    echo "❌ 失败"
    return 1
  fi
  echo ""
}

FAIL=0
run_probe "runtime 目录" "${RUNTIME_DIR}" || FAIL=1

if [[ -f "${EASYGO_WORKSPACE_FILE}" ]]; then
  run_probe ".code-workspace（可选）" "${EASYGO_WORKSPACE_FILE}" || \
    echo "ℹ️  .code-workspace 不可用，使用 runtime/ 即可。"
fi

exit "${FAIL}"
