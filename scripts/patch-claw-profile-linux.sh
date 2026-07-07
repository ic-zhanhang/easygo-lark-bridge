#!/usr/bin/env bash
# 秧秧（Linux）：心跳 08:00–23:00 每 2 小时（常开主机）
set -euo pipefail

PACK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="${PACK_ROOT}/config/easygo.env"
if [[ -f "${CONFIG_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${CONFIG_FILE}"
fi

CLAW_INSTALL_DIR="${CLAW_INSTALL_DIR:-${PACK_ROOT}/claw}"
SERVER="${CLAW_INSTALL_DIR}/server.ts"

if [[ ! -f "${SERVER}" ]]; then
  echo "跳过 patch-claw-profile-linux: 未找到 ${SERVER}"
  exit 0
fi

python3 - "${SERVER}" <<'PY'
from pathlib import Path
import sys

server = Path(sys.argv[1])
text = server.read_text()

hb_old = """const heartbeat = new HeartbeatRunner({
	config: {
		enabled: true,
		everyMs: 30 * 60 * 1000,
		workspaceDir: defaultWorkspace,
},"""

hb_new = """const heartbeat = new HeartbeatRunner({
	config: {
		enabled: true, // CLAW_PROFILE linux: 08–23 点每 2h
		everyMs: 2 * 60 * 60 * 1000,
		workspaceDir: defaultWorkspace,
		activeHours: { start: 8, end: 23 },
	},"""

if "CLAW_PROFILE linux" in text:
    print("patch-claw-profile-linux: 心跳已是 linux 配置，跳过")
elif hb_old in text:
    text = text.replace(hb_old, hb_new, 1)
    print("patch-claw-profile-linux: 已设置 linux 心跳 2h / 08–23")
elif "CLAW_PROFILE dev" in text:
    text = text.replace(
        "enabled: true, // CLAW_PROFILE dev: 10–22 点每 2h",
        "enabled: true, // CLAW_PROFILE linux: 08–23 点每 2h",
        1,
    )
    text = text.replace("activeHours: { start: 10, end: 22 }", "activeHours: { start: 8, end: 23 }", 1)
    print("patch-claw-profile-linux: 已从 dev 改为 linux 心跳")
else:
    print("patch-claw-profile-linux: 无法定位心跳块，请手动检查 server.ts", file=sys.stderr)
    sys.exit(1)

server.write_text(text)
PY

chmod +x "${BASH_SOURCE[0]}"
