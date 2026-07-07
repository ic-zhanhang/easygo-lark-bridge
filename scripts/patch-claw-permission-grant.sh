#!/usr/bin/env bash
# Claw 层 L1 授权：用本 Bot 事件里的 mention/sender open_id 写 easygo.env，不跑 Agent
set -euo pipefail

PACK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLAW_INSTALL_DIR="${CLAW_INSTALL_DIR:-${PACK_ROOT}/claw}"
SERVER="${CLAW_INSTALL_DIR}/server.ts"

for f in permission-grant.ts operator-registry.ts; do
  cp "${PACK_ROOT}/templates/claw/${f}" "${CLAW_INSTALL_DIR}/${f}"
done

if [[ ! -f "${SERVER}" ]]; then
  echo "跳过 patch-claw-permission-grant: 未找到 ${SERVER}"
  exit 0
fi

python3 - "${SERVER}" <<'PY'
from pathlib import Path
import sys

server = Path(sys.argv[1])
text = server.read_text()

if "CLAW_PERMISSION_GRANT" in text:
    print("patch-claw-permission-grant: 已应用，跳过")
    sys.exit(0)

if "CLAW_PERMISSION_GATE" not in text:
    print("patch-claw-permission-grant: 请先应用 patch-claw-permission-gate", file=sys.stderr)
    sys.exit(1)

import_line = 'import * as PermissionGate from "./permission-gate.js"; // CLAW_PERMISSION_GATE'
text = text.replace(
    import_line,
    import_line
    + '\nimport * as PermissionGrant from "./permission-grant.js"; // CLAW_PERMISSION_GRANT'
    + '\nimport * as OperatorRegistry from "./operator-registry.js"; // CLAW_PERMISSION_GRANT',
    1,
)

# handle() 增加 mentions
handle_params_old = """\tsenderOpenId?: string;
\tthreadId?: string;
\ttopicKey?: string;
}) {
\tconst { messageId, chatId, chatType, messageType, content, senderOpenId, threadId, topicKey } = params;"""

handle_params_new = """\tsenderOpenId?: string;
\tthreadId?: string;
\ttopicKey?: string;
\tmentions?: FeishuMention[];
}) {
\tconst { messageId, chatId, chatType, messageType, content, senderOpenId, threadId, topicKey, mentions } = params;"""

handle_call_old = "\treturn handleInner(text, messageId, chatId, chatType, messageType, content, senderOpenId, threadId, topicKey);"
handle_call_new = "\treturn handleInner(text, messageId, chatId, chatType, messageType, content, senderOpenId, threadId, topicKey, mentions ?? []);"

inner_sig_old = """\tsenderOpenId?: string,
\tthreadId?: string,
\ttopicKey?: string,
): Promise<void> {"""

inner_sig_new = """\tsenderOpenId?: string,
\tthreadId?: string,
\ttopicKey?: string,
\tmentions: FeishuMention[] = [],
): Promise<void> {"""

gate_block = """\t// CLAW_PERMISSION_GATE: 聊天权限 / 授权权限（Claw 硬校验，未通过不跑 Agent）
\tconst perm = PermissionGate.checkPermission(text, senderOpenId, permCfg);
\tif (!perm.ok) {
\t\tconsole.log(`[权限] 拒绝 sender=${senderOpenId?.slice(0, 12) ?? "?"} code=${perm.code} group=${isGroup}`);
\t\t// CLAW_GROUP_QUIET_REPLY: 群聊无权限静默忽略，私聊仍提示
\t\tif (!isGroup) {
\t\t\tawait replyCard(messageId, perm.message, { title: perm.title, color: "orange" });
\t\t}
\t\treturn;
\t}

\t// 处理媒体附件"""

gate_block_linux = """\t// CLAW_PERMISSION_GATE: 聊天权限 / 授权权限（Claw 硬校验，未通过不跑 Agent）
\tconst perm = PermissionGate.checkPermission(text, senderOpenId, permCfg);
\tif (!perm.ok) {
\t\tconsole.log(`[权限] 拒绝 sender=${senderOpenId?.slice(0, 12) ?? "?"} code=${perm.code}${isGroup ? "（群聊静默）" : ""}`);
\t\t// CLAW_PERM_GROUP_SILENT: 群聊拒绝不弹卡片，避免刷屏
\t\tif (!isGroup) {
\t\t\tawait replyCard(messageId, perm.message, { title: perm.title, color: "orange" });
\t\t}
\t\treturn;
\t}

\t// 处理媒体附件"""

grant_insert = """
\t// CLAW_PERMISSION_GRANT: L1 授权指令在 Claw 层处理（open_id 来自本 Bot mention/注册表）
\tif (PermissionGate.isAuthManagementIntent(text) && senderOpenId && permCfg.authorizerOpenIds.has(senderOpenId)) {
\t\tconst runtimeDir = defaultWorkspace;
\t\tconst registryPath = resolve(runtimeDir, "state/operator-registry.json");
\t\tconst grant = await PermissionGrant.handlePermissionGrant({
\t\t\ttext,
\t\t\tmentions,
\t\t\tbotOpenId,
\t\t\tenvPath: ENV_PATH,
\t\t\tpackRoot: ROOT,
\t\t\truntimeDir,
\t\t\tregistryPath,
\t\t\tfetchUserName: async (openId) => {
\t\t\t\ttry {
\t\t\t\t\tconst r = (await larkClient.contact.user.get({
\t\t\t\t\t\tpath: { user_id: openId },
\t\t\t\t\t\tparams: { user_id_type: "open_id" },
\t\t\t\t\t})) as { data?: { user?: { name?: string } } };
\t\t\t\t\treturn r.data?.user?.name;
\t\t\t\t} catch {
\t\t\t\t\treturn undefined;
\t\t\t\t}
\t\t\t},
\t\t});
\t\tif (grant.ok) {
\t\t\tpermCfg = buildPermCfg();
\t\t\tconsole.log(`[权限] ${grant.action} L2 name=${grant.name} id=${grant.openId.slice(0, 12)}`);
\t\t\tawait replyCard(messageId, grant.message, { title: grant.action === "grant" ? "已授权" : "已撤销", color: "green" });
\t\t} else {
\t\t\tawait replyCard(messageId, grant.message, { title: "授权失败", color: "orange" });
\t\t}
\t\treturn;
\t}

"""

grant_block = gate_block.replace("\n\t// 处理媒体附件", grant_insert + "\t// 处理媒体附件")
grant_block_linux = gate_block_linux.replace("\n\t// 处理媒体附件", grant_insert + "\t// 处理媒体附件")

event_record = """\t\t\tconst topicKey = TopicAgent.getTopicKey(chatType, threadId, senderOpenId);
\t\t\tconsole.log(`[解析] type=${messageType} chat=${chatType} thread=${threadId?.slice(0, 12) ?? "-"} sender=${senderOpenId.slice(0, 12)} text="${parsedText.slice(0, 60)}" img=${imageKey ?? ""} file=${fileKey ?? ""}`);
\t\t\thandle({ text: parsedText.trim(), messageId, chatId, chatType, messageType, content, senderOpenId, threadId, topicKey }).catch(console.error);"""

event_record_new = """\t\t\tconst topicKey = TopicAgent.getTopicKey(chatType, threadId, senderOpenId);
\t\t\tconst registryPath = resolve(defaultWorkspace, "state/operator-registry.json");
\t\t\tOperatorRegistry.recordSender(registryPath, senderOpenId);
\t\t\tOperatorRegistry.recordMentions(registryPath, mentions, botOpenId);
\t\t\tconsole.log(`[解析] type=${messageType} chat=${chatType} thread=${threadId?.slice(0, 12) ?? "-"} sender=${senderOpenId.slice(0, 12)} text="${parsedText.slice(0, 60)}" img=${imageKey ?? ""} file=${fileKey ?? ""}`);
\t\t\thandle({ text: parsedText.trim(), messageId, chatId, chatType, messageType, content, senderOpenId, threadId, topicKey, mentions }).catch(console.error);"""

gate_replaced = False
for old, new in ((gate_block, grant_block), (gate_block_linux, grant_block_linux)):
    if old in text:
        text = text.replace(old, new, 1)
        gate_replaced = True
        break
if not gate_replaced:
    print("patch-claw-permission-grant: 无法定位权限 gate 片段", file=sys.stderr)
    sys.exit(1)

for old, new in [
    (handle_params_old, handle_params_new),
    (handle_call_old, handle_call_new),
    (inner_sig_old, inner_sig_new),
    (event_record, event_record_new),
]:
    if old not in text:
        print(f"patch-claw-permission-grant: 无法定位片段", file=sys.stderr)
        sys.exit(1)
    text = text.replace(old, new, 1)

server.write_text(text)
print("patch-claw-permission-grant: 已添加 Claw 层 L1 授权 + sender 注册表")
PY

chmod +x "${BASH_SOURCE[0]}"
