#!/usr/bin/env bash
# /心跳 子命令与达妮娅一致：立即 / 马上 / now 等同 执行
set -euo pipefail

PACK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLAW_INSTALL_DIR="${CLAW_INSTALL_DIR:-${PACK_ROOT}/claw}"
SERVER="${CLAW_INSTALL_DIR}/server.ts"

if [[ ! -f "${SERVER}" ]]; then
  echo "跳过 patch-claw-heartbeat-cmd: 未找到 ${SERVER}"
  exit 0
fi

python3 - "${SERVER}" <<'PY'
from pathlib import Path
import sys

server = Path(sys.argv[1])
text = server.read_text()

if "CLAW_HEARTBEAT_CMD_ALIASES" in text or "(执行|立即|马上|now" in text:
    print("patch-claw-heartbeat-cmd: 已应用，跳过")
    sys.exit(0)

old = "if (/^(执行|run|check|检查)$/i.test(subCmd)) {"
new = "if (/^(执行|立即|马上|now|run|check|检查)$/i.test(subCmd)) { // CLAW_HEARTBEAT_CMD_ALIASES"

if old not in text:
    print("patch-claw-heartbeat-cmd: 无法定位子命令正则", file=sys.stderr)
    sys.exit(1)
text = text.replace(old, new, 1)

replacements = [
    ('"- `/心跳 开启/关闭/执行`"', '"- `/心跳 开启/关闭/执行`（`立即` 同义）"'),
    ('"- `/心跳 执行` — 立即执行一次"', '"- `/心跳 执行`（或 `/心跳 立即`）— 马上跑一次同步"'),
]
for o, n in replacements:
    if o in text:
        text = text.replace(o, n, 1)

server.write_text(text)
print("patch-claw-heartbeat-cmd: 已支持 /心跳 立即|马上|now")
PY

chmod +x "${BASH_SOURCE[0]}"
