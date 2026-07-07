#!/usr/bin/env bash
# 心跳/主动推送固定私聊发给 AUTHORIZER（默认杨展航），不再发到 lastActiveChatId 群聊
set -euo pipefail

PACK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLAW_INSTALL_DIR="${CLAW_INSTALL_DIR:-${PACK_ROOT}/claw}"
SERVER="${CLAW_INSTALL_DIR}/server.ts"

if [[ ! -f "${SERVER}" ]]; then
  echo "跳过 patch-claw-heartbeat-p2p-authorizer: 未找到 ${SERVER}"
  exit 0
fi

python3 - "${SERVER}" <<'PY'
from pathlib import Path
import sys

server = Path(sys.argv[1])
text = server.read_text()
marker = "CLAW_HEARTBEAT_P2P_AUTHORIZER"

if marker in text:
    print("patch-claw-heartbeat-p2p-authorizer: 已应用，跳过")
    sys.exit(0)

send_card_old = """async function sendCard(
\tchatId: string,
\tmarkdown: string,
\theader?: { title?: string; color?: string },
): Promise<string | undefined> {
\ttry {
\t\tconst res = await larkClient.im.message.create({
\t\t\tparams: { receive_id_type: "chat_id" },
\t\t\tdata: { receive_id: chatId, msg_type: "interactive", content: buildCard(markdown, header) },
\t\t});
\t\treturn res.data?.message_id;
\t} catch (err) {
\t\tconsole.error("[发送卡片失败]", err);
\t}
}"""

send_card_new = """async function sendCard(
\tchatId: string,
\tmarkdown: string,
\theader?: { title?: string; color?: string },
): Promise<string | undefined> {
\ttry {
\t\tconst res = await larkClient.im.message.create({
\t\t\tparams: { receive_id_type: "chat_id" },
\t\t\tdata: { receive_id: chatId, msg_type: "interactive", content: buildCard(markdown, header) },
\t\t});
\t\treturn res.data?.message_id;
\t} catch (err) {
\t\tconsole.error("[发送卡片失败]", err);
\t}
}

// CLAW_HEARTBEAT_P2P_AUTHORIZER: 心跳等主动推送固定私聊授权人（open_id）
async function sendCardToOpenId(
\topenId: string,
\tmarkdown: string,
\theader?: { title?: string; color?: string },
): Promise<string | undefined> {
\ttry {
\t\tconst res = await larkClient.im.message.create({
\t\t\tparams: { receive_id_type: "open_id" },
\t\t\tdata: { receive_id: openId, msg_type: "interactive", content: buildCard(markdown, header) },
\t\t});
\t\treturn res.data?.message_id;
\t} catch (err) {
\t\tconsole.error("[发送卡片失败·open_id]", err);
\t}
}"""

if send_card_old not in text:
    print("patch-claw-heartbeat-p2p-authorizer: 无法定位 sendCard", file=sys.stderr)
    sys.exit(1)
text = text.replace(send_card_old, send_card_new, 1)

hb_delivery_old = """\tonDelivery: async (content: string) => {
\t\tif (!lastActiveChatId) {
\t\t\tconsole.warn("[心跳] 无活跃会话，跳过发送");
\t\t\treturn;
\t\t}
\t\tawait sendCard(lastActiveChatId, content, { title: "💓 心跳检查", color: "purple" });
\t},"""

hb_delivery_new = """\tonDelivery: async (content: string) => {
\t\tconst openId = config.AUTHORIZER_OPEN_ID;
\t\tif (!openId) {
\t\t\tconsole.warn("[心跳] 未配置 AUTHORIZER_OPEN_ID，跳过发送");
\t\t\treturn;
\t\t}
\t\tawait sendCardToOpenId(openId, content, { title: "💓 心跳检查", color: "purple" });
\t},"""

if hb_delivery_old not in text:
    print("patch-claw-heartbeat-p2p-authorizer: 无法定位 heartbeat onDelivery", file=sys.stderr)
    sys.exit(1)
text = text.replace(hb_delivery_old, hb_delivery_new, 1)

server.write_text(text)
print("patch-claw-heartbeat-p2p-authorizer: 心跳已改为私聊 AUTHORIZER_OPEN_ID")
PY

chmod +x "${BASH_SOURCE[0]}"
