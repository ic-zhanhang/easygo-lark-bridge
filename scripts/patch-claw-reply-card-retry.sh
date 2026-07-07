#!/usr/bin/env bash
# 回复卡片：网络抖动时重试；纯文本降级时不把 text message_id 当 card 更新（避免「无消息框」）
set -euo pipefail

PACK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLAW_INSTALL_DIR="${CLAW_INSTALL_DIR:-${PACK_ROOT}/claw}"
SERVER="${CLAW_INSTALL_DIR}/server.ts"

if [[ ! -f "${SERVER}" ]]; then
  echo "跳过 patch-claw-reply-card-retry: 未找到 ${SERVER}"
  exit 0
fi

python3 - "${SERVER}" <<'PY'
from pathlib import Path
import sys

server = Path(sys.argv[1])
text = server.read_text()

if "CLAW_REPLY_CARD_RETRY" in text:
    print("patch-claw-reply-card-retry: 已应用，跳过")
    sys.exit(0)

old = """async function replyCard(
\tmessageId: string,
\tmarkdown: string,
\theader?: { title?: string; color?: string },
): Promise<string | undefined> {
\ttry {
\t\tconst res = await larkClient.im.message.reply({
\t\t\tpath: { message_id: messageId },
\t\t\tdata: { content: buildCard(markdown, header), msg_type: "interactive" },
\t\t});
\t\treturn res.data?.message_id;
\t} catch (err) {
\t\tconsole.error("[回复卡片失败]", err);
\t\ttry {
\t\t\tconst res = await larkClient.im.message.reply({
\t\t\t\tpath: { message_id: messageId },
\t\t\t\tdata: { content: JSON.stringify({ text: markdown }), msg_type: "text" },
\t\t\t});
\t\t\treturn res.data?.message_id;
\t\t} catch {}
\t}
}"""

new = """function isRetryableReplyError(err: unknown): boolean {
\tconst msg = err instanceof Error ? err.message : String(err);
\treturn /socket connection was closed|ECONNRESET|ETIMEDOUT|timeout|network/i.test(msg);
}

function sleepMs(ms: number): Promise<void> {
\treturn new Promise((r) => setTimeout(r, ms));
}

// CLAW_REPLY_CARD_RETRY: 互动卡片失败时重试；勿用纯文本 message_id 做 updateCard
async function replyCard(
\tmessageId: string,
\tmarkdown: string,
\theader?: { title?: string; color?: string },
\topts?: { allowTextFallback?: boolean },
): Promise<string | undefined> {
\tconst allowTextFallback = opts?.allowTextFallback ?? false;
\tconst maxAttempts = 3;
\tfor (let attempt = 1; attempt <= maxAttempts; attempt++) {
\t\ttry {
\t\t\tconst res = await larkClient.im.message.reply({
\t\t\t\tpath: { message_id: messageId },
\t\t\t\tdata: { content: buildCard(markdown, header), msg_type: "interactive" },
\t\t\t});
\t\t\treturn res.data?.message_id;
\t\t} catch (err) {
\t\t\tconsole.error(`[回复卡片失败] (${attempt}/${maxAttempts})`, err);
\t\t\tif (attempt < maxAttempts && isRetryableReplyError(err)) {
\t\t\t\tawait sleepMs(400 * attempt);
\t\t\t\tcontinue;
\t\t\t}
\t\t\tbreak;
\t\t}
\t}
\tif (allowTextFallback) {
\t\ttry {
\t\t\tawait larkClient.im.message.reply({
\t\t\t\tpath: { message_id: messageId },
\t\t\t\tdata: { content: JSON.stringify({ text: markdown }), msg_type: "text" },
\t\t\t});
\t\t} catch {}
\t}
\treturn undefined;
}"""

if old not in text:
    print("patch-claw-reply-card-retry: 无法定位 replyCard", file=sys.stderr)
    sys.exit(1)
text = text.replace(old, new, 1)

# 错误提示等短消息允许纯文本降级
text = text.replace(
    '\t\t\tawait replyCard(messageId, "❌ 媒体下载失败，请重新发送", { color: "red" });',
    '\t\t\tawait replyCard(messageId, "❌ 媒体下载失败，请重新发送", { color: "red" }, { allowTextFallback: true });',
)
text = text.replace(
    "\t\t\tawait replyCard(messageId, body, { title, color: \"red\" });",
    "\t\t\tawait replyCard(messageId, body, { title, color: \"red\" }, { allowTextFallback: true });",
)

server.write_text(text)
print("patch-claw-reply-card-retry: 已应用卡片重试与降级修复")
PY

chmod +x "${BASH_SOURCE[0]}"
