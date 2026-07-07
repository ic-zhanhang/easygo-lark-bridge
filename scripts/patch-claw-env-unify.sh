#!/usr/bin/env bash
# Claw 统一读 config/easygo.env（单一配置源，避免 claw/.env 与 easygo.env 分叉）
set -euo pipefail

PACK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLAW_INSTALL_DIR="${CLAW_INSTALL_DIR:-${PACK_ROOT}/claw}"
SERVER="${CLAW_INSTALL_DIR}/server.ts"

if [[ ! -f "${SERVER}" ]]; then
  echo "跳过 patch-claw-env-unify: 未找到 ${SERVER}"
  exit 0
fi

python3 - "${SERVER}" <<'PY'
from pathlib import Path
import sys

server = Path(sys.argv[1])
text = server.read_text()

if "CLAW_ENV_UNIFY" in text:
    print("patch-claw-env-unify: 已应用，跳过")
    sys.exit(0)

old = 'const ENV_PATH = resolve(import.meta.dirname, ".env");'
new = """const ENV_PATH = existsSync(resolve(ROOT, "config/easygo.env")) // CLAW_ENV_UNIFY
\t? resolve(ROOT, "config/easygo.env")
\t: resolve(import.meta.dirname, ".env");"""

if old not in text:
    print("patch-claw-env-unify: 无法定位 ENV_PATH", file=sys.stderr)
    sys.exit(1)

text = text.replace(old, new, 1)
server.write_text(text)
print("patch-claw-env-unify: Claw 将优先读取 config/easygo.env")
PY

chmod +x "${BASH_SOURCE[0]}"
