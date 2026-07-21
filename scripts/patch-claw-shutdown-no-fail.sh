#!/usr/bin/env bash
# 服务关停（SIGTERM）时：不要把被中断的 Agent 标成「执行失败」盖掉重启提示
set -euo pipefail

PACK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLAW_INSTALL_DIR="${CLAW_INSTALL_DIR:-${PACK_ROOT}/claw}"
SERVER="${CLAW_INSTALL_DIR}/server.ts"

if [[ ! -f "${SERVER}" ]]; then
  echo "跳过 patch-claw-shutdown-no-fail: 未找到 ${SERVER}"
  exit 0
fi

python3 - "${SERVER}" <<'PY'
from pathlib import Path
import sys

server = Path(sys.argv[1])
text = server.read_text()

if "CLAW_SHUTDOWN_NO_FAIL" in text:
    print("patch-claw-shutdown-no-fail: 已应用，跳过")
    sys.exit(0)

old = """\t} catch (err) {
\t\tconst msg = err instanceof Error ? err.message : String(err);
\t\tconsole.error(`[${new Date().toISOString()}] 失败 [${label}]: ${msg}`);
\t\tif (err instanceof Error && err.stack) console.error(`[Stack] ${err.stack}`);

\t\tconst isAuthError = /authentication required|not authenticated|unauthorized|api.key/i.test(msg);"""

new = """\t} catch (err) {
\t\tconst msg = err instanceof Error ? err.message : String(err);
\t\t// CLAW_SHUTDOWN_NO_FAIL: 关停中断不刷「执行失败」，保留「服务正在重启」卡片
\t\tif (typeof AgentLifecycle !== "undefined" && AgentLifecycle.isShuttingDown()) {
\t\t\tconsole.warn(`[${new Date().toISOString()}] 关停中断 [${label}]: ${msg.slice(0, 200)}`);
\t\t\treturn;
\t\t}
\t\tconsole.error(`[${new Date().toISOString()}] 失败 [${label}]: ${msg}`);
\t\tif (err instanceof Error && err.stack) console.error(`[Stack] ${err.stack}`);

\t\tconst isAuthError = /authentication required|not authenticated|unauthorized|api.key/i.test(msg);"""

if old not in text:
    print("patch-claw-shutdown-no-fail: 未找到 catch 失败块", file=sys.stderr)
    sys.exit(1)

text = text.replace(old, new, 1)
server.write_text(text)
print("patch-claw-shutdown-no-fail: 关停中断不再标执行失败")
PY

chmod +x "${BASH_SOURCE[0]}"
