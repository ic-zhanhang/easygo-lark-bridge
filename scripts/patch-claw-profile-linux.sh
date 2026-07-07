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
import re
import sys

server = Path(sys.argv[1])
text = server.read_text()

if "CLAW_PROFILE linux" in text:
    print("patch-claw-profile-linux: 心跳已是 linux 配置，跳过")
    sys.exit(0)

m = re.search(
    r"const heartbeat = new HeartbeatRunner\(\{\s*config: \{\s*enabled: true,\s*everyMs: \d+ \* 60 \* 1000,\s*workspaceDir: defaultWorkspace,\s*\},",
    text,
)
if not m:
    print("patch-claw-profile-linux: 无法定位心跳块", file=sys.stderr)
    sys.exit(1)

replacement = """const heartbeat = new HeartbeatRunner({
	config: {
		enabled: true, // CLAW_PROFILE linux: 08–23 点每 2h
		everyMs: 2 * 60 * 60 * 1000,
		workspaceDir: defaultWorkspace,
		activeHours: { start: 8, end: 23 },
	},"""

text = text[: m.start()] + replacement + text[m.end() :]
server.write_text(text)
print("patch-claw-profile-linux: 已设置 linux 心跳 2h / 08–23")
PY

chmod +x "${BASH_SOURCE[0]}"
