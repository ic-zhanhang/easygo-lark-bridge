#!/usr/bin/env bash
# 不向 Agent prompt 注入 sender open_id；卡片展示用户原文（权限仍在 Claw 层校验）
set -euo pipefail

PACK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLAW_INSTALL_DIR="${CLAW_INSTALL_DIR:-${PACK_ROOT}/claw}"
SERVER="${CLAW_INSTALL_DIR}/server.ts"

if [[ ! -f "${SERVER}" ]]; then
  echo "跳过 patch-claw-hide-sender-openid: 未找到 ${SERVER}"
  exit 0
fi

python3 - "${SERVER}" <<'PY'
from pathlib import Path
import sys

server = Path(sys.argv[1])
text = server.read_text()
marker = "CLAW_HIDE_SENDER_OPENID"

if marker in text:
    print("patch-claw-hide-sender-openid: 已应用，跳过")
    sys.exit(0)

old_inject = """\tif (chatType === "group") {
\t\tprompt = `[飞书群聊 · 发送者 open_id: ${senderOpenId ?? "unknown"}]\\n${prompt}`;
\t} else if (senderOpenId) {
\t\tprompt = `[飞书私聊 · 发送者 open_id: ${senderOpenId}]\\n${prompt}`;
\t}"""

new_inject = "\t// CLAW_HIDE_SENDER_OPENID: open_id 仅 Claw 日志/权限门控使用，不注入 Agent prompt"

if old_inject not in text:
    print("patch-claw-hide-sender-openid: 无法定位 open_id prompt 注入", file=sys.stderr)
    sys.exit(1)
text = text.replace(old_inject, new_inject, 1)

# 卡片/排队状态展示用户原文，不展示 prompt 内部拼接
text = text.replace("> ${prompt.slice(0, 120)}", "> ${text.slice(0, 120)}")

server.write_text(text)
print("patch-claw-hide-sender-openid: 已移除 prompt 中的 open_id，卡片改展示用户原文")
PY

chmod +x "${BASH_SOURCE[0]}"
