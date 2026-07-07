#!/usr/bin/env bash
# 群聊仅 @Bot 触发；向 Agent 注入 chat_type / sender open_id
set -euo pipefail

PACK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="${PACK_ROOT}/config/easygo.env"
if [[ -f "${CONFIG_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${CONFIG_FILE}" 2>/dev/null || true
fi

CLAW_INSTALL_DIR="${CLAW_INSTALL_DIR:-${PACK_ROOT}/claw}"
SERVER="${CLAW_INSTALL_DIR}/server.ts"

if [[ ! -f "${SERVER}" ]]; then
  echo "跳过 patch-claw-group-mention: 未找到 ${SERVER}"
  exit 0
fi

python3 - "${SERVER}" <<'PY'
from pathlib import Path
import sys

server = Path(sys.argv[1])
text = server.read_text()
marker = "CLAW_GROUP_MENTION_ONLY"

if marker in text:
    print("patch-claw-group-mention: 已应用，跳过")
    sys.exit(0)

# ── bot open_id + mention 工具 ─────────────────────────────
insert_after = "const larkClient = new Lark.Client({\n\tappId: config.FEISHU_APP_ID,\n\tappSecret: config.FEISHU_APP_SECRET,\n\tdomain: Lark.Domain.Feishu,\n});"
bot_block = """const larkClient = new Lark.Client({
\tappId: config.FEISHU_APP_ID,
\tappSecret: config.FEISHU_APP_SECRET,
\tdomain: Lark.Domain.Feishu,
});

// CLAW_GROUP_MENTION_ONLY: 群聊须 @Bot；向 Agent 注入会话元数据
let botOpenId: string | undefined;

async function fetchBotOpenId(): Promise<string | undefined> {
\ttry {
\t\tconst r = (await larkClient.request({
\t\t\turl: "/open-apis/bot/v3/info",
\t\t\tmethod: "GET",
\t\t})) as { bot?: { open_id?: string; app_name?: string } };
\t\tconst id = r.bot?.open_id;
\t\tif (id) console.log(`[Bot] 已就绪 name=${r.bot?.app_name ?? "?"}`);
\t\treturn id;
\t} catch (e) {
\t\tconsole.warn("[Bot] 无法获取 open_id，群聊 @ 过滤将不可用:", e);
\t\treturn undefined;
\t}
}

function escapeMentionRegExp(input: string): string {
\treturn input.replace(/[.*+?^${}()|[\\]\\\\]/g, "\\\\$&");
}

function stripMentionPlaceholders(raw: string, mentions: Array<{ key: string }>): string {
\tlet result = raw;
\tfor (const m of mentions) {
\t\tif (m.key) result = result.replace(new RegExp(escapeMentionRegExp(m.key), "g"), "");
\t}
\treturn result.replace(/\\s+/g, " ").trim();
}

type FeishuMention = { key: string; id: { open_id?: string }; name: string };"""

if insert_after not in text:
    print("patch-claw-group-mention: 无法定位 larkClient", file=sys.stderr)
    sys.exit(1)
text = text.replace(insert_after, bot_block, 1)

# ── handle / handleInner 签名 ───────────────────────────────
handle_old = """async function handle(params: {
\ttext: string;
\tmessageId: string;
\tchatId: string;
\tchatType: string;
\tmessageType: string;
\tcontent: string;
}) {
\tconst { messageId, chatId, chatType, messageType, content } = params;
\tlet { text } = params;
\t// 记录最近活跃会话用于定时任务/心跳主动推送
\tlastActiveChatId = chatId;
\tconsole.log(`[${new Date().toISOString()}] [${messageType}] ${text.slice(0, 80)}`);

\treturn handleInner(text, messageId, chatId, chatType, messageType, content);
}"""

handle_new = """async function handle(params: {
\ttext: string;
\tmessageId: string;
\tchatId: string;
\tchatType: string;
\tmessageType: string;
\tcontent: string;
\tsenderOpenId?: string;
}) {
\tconst { messageId, chatId, chatType, messageType, content, senderOpenId } = params;
\tlet { text } = params;
\t// 记录最近活跃会话用于定时任务/心跳主动推送
\tlastActiveChatId = chatId;
\tconst chatTag = chatType === "group" ? "group" : "p2p";
\tconsole.log(`[${new Date().toISOString()}] [${messageType}] chat=${chatTag} sender=${senderOpenId?.slice(0, 12) ?? "?"} ${text.slice(0, 80)}`);

\treturn handleInner(text, messageId, chatId, chatType, messageType, content, senderOpenId);
}"""

if handle_old not in text:
    print("patch-claw-group-mention: 无法定位 handle()", file=sys.stderr)
    sys.exit(1)
text = text.replace(handle_old, handle_new, 1)

inner_sig_old = """async function handleInner(
\ttext: string,
\tmessageId: string,
\tchatId: string,
\tchatType: string,
\tmessageType: string,
\tcontent: string,
): Promise<void> {"""

inner_sig_new = """async function handleInner(
\ttext: string,
\tmessageId: string,
\tchatId: string,
\tchatType: string,
\tmessageType: string,
\tcontent: string,
\tsenderOpenId?: string,
): Promise<void> {"""

if inner_sig_old not in text:
    print("patch-claw-group-mention: 无法定位 handleInner()", file=sys.stderr)
    sys.exit(1)
text = text.replace(inner_sig_old, inner_sig_new, 1)

route_old = "\tconst { workspace, prompt, label } = route(text);"
route_new = """\tconst routed = route(text);
\tlet { workspace, prompt, label } = routed;
\tif (chatType === "group") {
\t\tprompt = `[飞书群聊 · 发送者 open_id: ${senderOpenId ?? "unknown"}]\\n${prompt}`;
\t} else if (senderOpenId) {
\t\tprompt = `[飞书私聊 · 发送者 open_id: ${senderOpenId}]\\n${prompt}`;
\t}"""

if route_old not in text:
    print("patch-claw-group-mention: 无法定位 route(text)", file=sys.stderr)
    sys.exit(1)
text = text.replace(route_old, route_new, 1)

# ── 事件分发：群聊 @ 过滤 ─────────────────────────────────
dispatcher_old = """\t\t\tconst chatType = (msg.chat_type as string) || "p2p";
\t\t\tconst content = msg.content as string;

\t\t\tif (isDup(messageId)) return;
\t\t\tif (!TYPES.has(messageType)) {
\t\t\t\tawait replyCard(messageId, `暂不支持: ${messageType}`);
\t\t\t\treturn;
\t\t\t}

\t\t\tconst { text: parsedText, imageKey, fileKey } = parseContent(messageType, content);
\t\t\tconsole.log(`[解析] type=${messageType} chat=${chatType} text="${parsedText.slice(0, 60)}" img=${imageKey ?? ""} file=${fileKey ?? ""}`);
\t\t\thandle({ text: parsedText.trim(), messageId, chatId, chatType, messageType, content }).catch(console.error);"""

dispatcher_new = """\t\t\tconst chatType = (msg.chat_type as string) || "p2p";
\t\t\tconst content = msg.content as string;
\t\t\tconst sender = ev.sender as Record<string, unknown> | undefined;
\t\t\tconst senderOpenId =
\t\t\t\t((sender?.sender_id as Record<string, string> | undefined)?.open_id as string | undefined) ?? "";
\t\t\tconst mentions = (msg.mentions as FeishuMention[] | undefined) ?? [];

\t\t\tif (isDup(messageId)) return;
\t\t\tif (!TYPES.has(messageType)) {
\t\t\t\tawait replyCard(messageId, `暂不支持: ${messageType}`);
\t\t\t\treturn;
\t\t\t}

\t\t\tlet { text: parsedText, imageKey, fileKey } = parseContent(messageType, content);

\t\t\tif (chatType === "group") {
\t\t\t\tif (!botOpenId) {
\t\t\t\t\tconsole.log("[群聊] 忽略：bot open_id 未就绪");
\t\t\t\t\treturn;
\t\t\t\t}
\t\t\t\tconst mentionedBot = mentions.some((m) => m.id.open_id === botOpenId);
\t\t\t\tif (!mentionedBot) {
\t\t\t\t\tconsole.log(`[群聊] 忽略：未 @Bot chat=${chatId}`);
\t\t\t\t\treturn;
\t\t\t\t}
\t\t\t\tparsedText = stripMentionPlaceholders(parsedText, mentions);
\t\t\t}

\t\t\tconsole.log(`[解析] type=${messageType} chat=${chatType} sender=${senderOpenId.slice(0, 12)} text="${parsedText.slice(0, 60)}" img=${imageKey ?? ""} file=${fileKey ?? ""}`);
\t\t\thandle({ text: parsedText.trim(), messageId, chatId, chatType, messageType, content, senderOpenId }).catch(console.error);"""

if dispatcher_old not in text:
    print("patch-claw-group-mention: 无法定位 dispatcher", file=sys.stderr)
    sys.exit(1)
text = text.replace(dispatcher_old, dispatcher_new, 1)

# ── 启动时拉 bot open_id ──────────────────────────────────
ws_old = "ws.start({ eventDispatcher: dispatcher });\nconsole.log(\"飞书长连接已启动，等待消息...\");"
ws_new = """fetchBotOpenId().then((id) => { botOpenId = id; });
ws.start({ eventDispatcher: dispatcher });
console.log("飞书长连接已启动，等待消息...（群聊须 @Bot）");"""

if ws_old not in text:
    print("patch-claw-group-mention: 无法定位 ws.start", file=sys.stderr)
    sys.exit(1)
text = text.replace(ws_old, ws_new, 1)

server.write_text(text)
print("patch-claw-group-mention: 已启用群聊 @Bot 触发 + sender 元数据")
PY

chmod +x "${BASH_SOURCE[0]}"
