#!/usr/bin/env bash
# 已合并进 patch-claw-mention-id-fix.sh；保留本脚本以兼容旧 install 流程
set -euo pipefail

PACK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLAW_INSTALL_DIR="${CLAW_INSTALL_DIR:-${PACK_ROOT}/claw}"
SERVER="${CLAW_INSTALL_DIR}/server.ts"

if [[ ! -f "${SERVER}" ]]; then
  echo "跳过 patch-claw-bot-openid-retry: 未找到 ${SERVER}"
  exit 0
fi

if grep -q "CLAW_BOT_OPENID_RETRY" "${SERVER}" 2>/dev/null; then
  echo "patch-claw-bot-openid-retry: 已合并至 mention-id-fix，跳过"
  exit 0
fi

echo "patch-claw-bot-openid-retry: 委托 patch-claw-mention-id-fix" >&2
exec bash "$(dirname "${BASH_SOURCE[0]}")/patch-claw-mention-id-fix.sh"
