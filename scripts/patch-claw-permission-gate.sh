#!/usr/bin/env bash
# Claw 层权限分级：聊天名单硬校验；仅 AUTHORIZER 可触发「为他人授权」类指令
set -euo pipefail

PACK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLAW_INSTALL_DIR="${CLAW_INSTALL_DIR:-${PACK_ROOT}/claw}"
SERVER="${CLAW_INSTALL_DIR}/server.ts"
SRC="${PACK_ROOT}/templates/claw/permission-gate.ts"
DEST="${CLAW_INSTALL_DIR}/permission-gate.ts"

if [[ ! -f "${SERVER}" ]]; then
  echo "跳过 patch-claw-permission-gate: 未找到 ${SERVER}"
  exit 0
fi

cp "${SRC}" "${DEST}"

python3 - "${SERVER}" <<'PY'
from pathlib import Path
import sys

server = Path(sys.argv[1])
text = server.read_text()

if "CLAW_PERMISSION_GATE" in text:
    print("patch-claw-permission-gate: 已应用，跳过")
    sys.exit(0)

import_line = 'import * as TopicAgent from "./topic-agent.js"; // CLAW_TOPIC_AGENT'
new_import = import_line + '\nimport * as PermissionGate from "./permission-gate.js"; // CLAW_PERMISSION_GATE'
if import_line not in text:
    print("patch-claw-permission-gate: 未找到 topic-agent import", file=sys.stderr)
    sys.exit(1)
text = text.replace(import_line, new_import, 1)

env_iface_old = """interface EnvConfig {
\tCURSOR_API_KEY: string;
\tFEISHU_APP_ID: string;
\tFEISHU_APP_SECRET: string;
\tCURSOR_MODEL: string;
\tVOLC_STT_APP_ID: string;
\tVOLC_STT_ACCESS_TOKEN: string;
\tVOLC_EMBEDDING_API_KEY: string;
\tVOLC_EMBEDDING_MODEL: string;
}"""

env_iface_new = """interface EnvConfig {
\tCURSOR_API_KEY: string;
\tFEISHU_APP_ID: string;
\tFEISHU_APP_SECRET: string;
\tCURSOR_MODEL: string;
\tVOLC_STT_APP_ID: string;
\tVOLC_STT_ACCESS_TOKEN: string;
\tVOLC_EMBEDDING_API_KEY: string;
\tVOLC_EMBEDDING_MODEL: string;
\tAUTHORIZER_OPEN_ID: string;
\tAUTHORIZER_NAME: string;
\tCHAT_OPERATOR_OPEN_IDS: string;
}"""

parse_return_old = """\treturn {
\t\tCURSOR_API_KEY: env.CURSOR_API_KEY || "",
\t\tFEISHU_APP_ID: env.FEISHU_APP_ID || "",
\t\tFEISHU_APP_SECRET: env.FEISHU_APP_SECRET || "",
\t\tCURSOR_MODEL: env.CURSOR_MODEL || "opus-4.6-thinking",
\t\tVOLC_STT_APP_ID: env.VOLC_STT_APP_ID || "",
\t\tVOLC_STT_ACCESS_TOKEN: env.VOLC_STT_ACCESS_TOKEN || "",
\t\tVOLC_EMBEDDING_API_KEY: env.VOLC_EMBEDDING_API_KEY || "",
\t\tVOLC_EMBEDDING_MODEL: env.VOLC_EMBEDDING_MODEL || "doubao-embedding-vision-250615",
\t};
}"""

parse_return_new = """\tconst chatIds = env.CHAT_OPERATOR_OPEN_IDS || env.ALLOWED_OPERATOR_OPEN_IDS || "";
\treturn {
\t\tCURSOR_API_KEY: env.CURSOR_API_KEY || "",
\t\tFEISHU_APP_ID: env.FEISHU_APP_ID || "",
\t\tFEISHU_APP_SECRET: env.FEISHU_APP_SECRET || "",
\t\tCURSOR_MODEL: env.CURSOR_MODEL || "opus-4.6-thinking",
\t\tVOLC_STT_APP_ID: env.VOLC_STT_APP_ID || "",
\t\tVOLC_STT_ACCESS_TOKEN: env.VOLC_STT_ACCESS_TOKEN || "",
\t\tVOLC_EMBEDDING_API_KEY: env.VOLC_EMBEDDING_API_KEY || "",
\t\tVOLC_EMBEDDING_MODEL: env.VOLC_EMBEDDING_MODEL || "doubao-embedding-vision-250615",
\t\tAUTHORIZER_OPEN_ID: env.AUTHORIZER_OPEN_ID || chatIds.split(",")[0]?.trim() || "",
\t\tAUTHORIZER_NAME: env.AUTHORIZER_NAME || "杨展航",
\t\tCHAT_OPERATOR_OPEN_IDS: chatIds,
\t};
}"""

config_line = "let config = parseEnv();"
config_block = """let config = parseEnv();

function buildPermCfg(): PermissionGate.PermissionConfig {
\treturn PermissionGate.buildPermissionConfig(
\t\tconfig.AUTHORIZER_OPEN_ID,
\t\tconfig.AUTHORIZER_NAME,
\t\tconfig.CHAT_OPERATOR_OPEN_IDS,
\t);
}
let permCfg = buildPermCfg();"""

reload_old = """\t\tconfig = parseEnv();
\t\tif (config.CURSOR_API_KEY !== prev) {"""
reload_new = """\t\tconfig = parseEnv();
\t\tpermCfg = buildPermCfg();
\t\tif (config.CURSOR_API_KEY !== prev) {"""

inner_anchor = """): Promise<void> {
\tlet cardId: string | undefined;
\tconst isGroup = chatType === "group";
\t// 处理媒体附件"""

inner_gate = """): Promise<void> {
\tlet cardId: string | undefined;
\tconst isGroup = chatType === "group";

\t// CLAW_PERMISSION_GATE: 聊天权限 / 授权权限（Claw 硬校验，未通过不跑 Agent）
\tconst perm = PermissionGate.checkPermission(text, senderOpenId, permCfg);
\tif (!perm.ok) {
\t\tconsole.log(`[权限] 拒绝 sender=${senderOpenId?.slice(0, 12) ?? "?"} code=${perm.code}`);
\t\tawait replyCard(messageId, perm.message, { title: perm.title, color: "orange" });
\t\treturn;
\t}

\t// 处理媒体附件"""

for old, new in [
    (env_iface_old, env_iface_new),
    (parse_return_old, parse_return_new),
    (config_line, config_block),
    (reload_old, reload_new),
    (inner_anchor, inner_gate),
]:
    if old not in text:
        print(f"patch-claw-permission-gate: 无法定位片段", file=sys.stderr)
        sys.exit(1)
    text = text.replace(old, new, 1)

server.write_text(text)
print("patch-claw-permission-gate: 已添加 Claw 层权限分级")
PY

chmod +x "${BASH_SOURCE[0]}"
