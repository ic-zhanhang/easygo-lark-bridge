#!/usr/bin/env bash
# 验证 Cursor Agent CLI 对 EasyGo workspace 的支持（D 策略 · 升级路径探测）
set -euo pipefail

PACK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="${PACK_ROOT}/config/easygo.env"

if [[ -f "${CONFIG_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${CONFIG_FILE}"
fi

EASYGO_CLAW_ROOT="${EASYGO_CLAW_ROOT:-/Users/ic/workspace/easygo-claw}"
EASYGO_WORKSPACE_FILE="${EASYGO_WORKSPACE_FILE:-/Users/ic/workspace/easygo-dev.code-workspace}"
AGENT_BIN="${AGENT_BIN:-$HOME/.local/bin/agent}"

echo "==> EasyGo Agent Workspace 验证"
echo ""

if [[ ! -x "${AGENT_BIN}" ]]; then
  echo "❌ 未找到 Agent CLI: ${AGENT_BIN}"
  echo "   请先安装: cursor agent update  （或见 Cursor 官方文档）"
  exit 1
fi
echo "✅ Agent CLI: ${AGENT_BIN}"
"$AGENT_BIN" --version 2>/dev/null || true
echo ""

run_probe() {
  local label="$1"
  local workspace="$2"
  echo "── 探测: ${label}"
  echo "    workspace=${workspace}"
  if "$AGENT_BIN" --workspace "${workspace}" -p --force --trust \
    "只回复一行：当前 workspace 根目录的绝对路径是什么？" 2>&1; then
    echo "✅ ${label} 可用"
  else
    echo "❌ ${label} 失败"
    return 1
  fi
  echo ""
}

FAIL=0
run_probe "easygo-claw 目录（当前基线）" "${EASYGO_CLAW_ROOT}" || FAIL=1

if [[ -f "${EASYGO_WORKSPACE_FILE}" ]]; then
  run_probe ".code-workspace 文件（升级路径）" "${EASYGO_WORKSPACE_FILE}" || {
    echo "ℹ️  .code-workspace 暂不可用，继续使用 easygo-claw/ symlink 目录即可。"
    echo "    若日后 Agent CLI 支持，可给 feishu-cursor-claw 提 PR 分离 templateDir 与 agentWorkspace。"
  }
else
  echo "⚠️  未找到 ${EASYGO_WORKSPACE_FILE}，跳过 .code-workspace 探测"
fi

echo "==> 完成"
exit "${FAIL}"
