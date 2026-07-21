#!/usr/bin/env bash
# 群聊权限静默：
# 无聊天权限 → 只打日志，不在群里回卡片（私聊仍回）
# 注：群话题中间态/思考中进度已恢复，由 progress-done-guard 统一管理
set -euo pipefail

PACK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLAW_INSTALL_DIR="${CLAW_INSTALL_DIR:-${PACK_ROOT}/claw}"
SERVER="${CLAW_INSTALL_DIR}/server.ts"

if [[ ! -f "${SERVER}" ]]; then
  echo "跳过 patch-claw-group-quiet-reply: 未找到 ${SERVER}"
  exit 0
fi

python3 - "${SERVER}" <<'PY'
from pathlib import Path
import sys

server = Path(sys.argv[1])
text = server.read_text()
changed = False

# ── 1) 群聊权限拒绝静默 ──
perm_old = """\tif (!perm.ok) {
\t\tconsole.log(`[权限] 拒绝 sender=${senderOpenId?.slice(0, 12) ?? "?"} code=${perm.code}`);
\t\tawait replyCard(messageId, perm.message, { title: perm.title, color: "orange" });
\t\treturn;
\t}"""

perm_new = """\tif (!perm.ok) {
\t\tconsole.log(`[权限] 拒绝 sender=${senderOpenId?.slice(0, 12) ?? "?"} code=${perm.code} group=${isGroup}`);
\t\t// CLAW_GROUP_QUIET_REPLY: 群聊无权限静默忽略，私聊仍提示
\t\tif (!isGroup) {
\t\t\tawait replyCard(messageId, perm.message, { title: perm.title, color: "orange" });
\t\t}
\t\treturn;
\t}"""

if perm_old in text:
    text = text.replace(perm_old, perm_new, 1)
    changed = True

# 已应用权限静默即可；旧版若还压制了群聊中间态，留给 patch-claw-group-topic-context-progress 升级
if not changed:
    if "CLAW_GROUP_QUIET_REPLY" in text:
        print("patch-claw-group-quiet-reply: 已应用，跳过")
        sys.exit(0)
    print("patch-claw-group-quiet-reply: 未找到可替换片段", file=sys.stderr)
    sys.exit(1)

server.write_text(text)
print("patch-claw-group-quiet-reply: 群聊权限静默（保留中间态进度）")
PY

chmod +x "${BASH_SOURCE[0]}"
