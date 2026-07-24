#!/usr/bin/env bash
# 「小组」群 Agent：每条消息 Tick 行为树；Qwen/任务/上下文是外部叶子适配
set -euo pipefail

PACK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLAW_INSTALL_DIR="${CLAW_INSTALL_DIR:-${PACK_ROOT}/claw}"
SERVER="${CLAW_INSTALL_DIR}/server.ts"
GROUP_SRC="${PACK_ROOT}/templates/claw/xiaozu-group-agent.ts"
BEHAVIOR_SRC="${PACK_ROOT}/templates/claw/xiaozu-behavior-tree.ts"
COMMAND_SRC="${PACK_ROOT}/templates/claw/easygo-commands.ts"

if [[ ! -f "${SERVER}" ]]; then
  echo "跳过 patch-claw-xiaozu-group-agent: 未找到 ${SERVER}"
  exit 0
fi
if [[ ! -f "${GROUP_SRC}" || ! -f "${BEHAVIOR_SRC}" || ! -f "${COMMAND_SRC}" ]]; then
  echo "patch-claw-xiaozu-group-agent: 缺少模板" >&2
  exit 1
fi

cp "${GROUP_SRC}" "${CLAW_INSTALL_DIR}/xiaozu-group-agent.ts"
cp "${BEHAVIOR_SRC}" "${CLAW_INSTALL_DIR}/xiaozu-behavior-tree.ts"
cp "${COMMAND_SRC}" "${CLAW_INSTALL_DIR}/easygo-commands.ts"
mkdir -p "${PACK_ROOT}/runtime/state/xiaozu-groups"

python3 - "${SERVER}" <<'PY'
from pathlib import Path
import sys

server = Path(sys.argv[1])
text = server.read_text()
marker = "CLAW_XIAOZHU_GROUP_AGENT"

if marker in text:
    print("patch-claw-xiaozu-group-agent: 已应用，仅同步模板")
    sys.exit(0)

def replace_once(old: str, new: str, label: str) -> None:
    global text
    if old not in text:
        print(f"patch-claw-xiaozu-group-agent: 无法定位 {label}", file=sys.stderr)
        sys.exit(1)
    text = text.replace(old, new, 1)

replace_once(
    'import * as XiaozuSpectator from "./xiaozu-spectator.js"; // CLAW_XIAOZHU_SPECTATOR',
    'import * as XiaozuSpectator from "./xiaozu-spectator.js"; // CLAW_XIAOZHU_SPECTATOR\n'
    'import { createXiaozuGroupAgent } from "./xiaozu-group-agent.js"; // CLAW_XIAOZHU_GROUP_AGENT',
    "小组旁观 import",
)
replace_once(
    "const xiaozuSpectatorChatIds = XiaozuSpectator.loadSpectatorChatIdsFromPack(); // CLAW_XIAOZHU_SPECTATOR",
    "const xiaozuSpectatorChatIds = XiaozuSpectator.loadSpectatorChatIdsFromPack(); // CLAW_XIAOZHU_SPECTATOR\n"
    "const xiaozuGroupAgent = createXiaozuGroupAgent({ workspace: defaultWorkspace }); // CLAW_XIAOZHU_GROUP_AGENT",
    "小组 chatIds",
)

# 现有 topic-session 补丁已在调用处读取 usage，这里补齐返回类型和首轮透传。
text = text.replace(
    "): Promise<{ result: string; quotaWarning?: string; sessionRenewed?: boolean }> {",
    "): Promise<{ result: string; quotaWarning?: string; sessionRenewed?: boolean; usage?: { inputTokens?: number; outputTokens?: number } }> {",
    1,
)
text = text.replace("return { result, sessionRenewed };", "return { result, sessionRenewed, usage };", 1)

replace_once(
'''\tmentions?: FeishuMention[];
}) {
\tconst { messageId, chatId, chatType, messageType, content, senderOpenId, threadId, topicKey, mentions } = params;''',
'''\tmentions?: FeishuMention[];
\txiaozuChatId?: string;
}) {
\tconst { messageId, chatId, chatType, messageType, content, senderOpenId, threadId, topicKey, mentions, xiaozuChatId } = params;''',
    "handle 参数",
)
replace_once(
    "return handleInner(text, messageId, chatId, chatType, messageType, content, senderOpenId);",
    "return handleInner(text, messageId, chatId, chatType, messageType, content, senderOpenId, topicKey, xiaozuChatId);",
    "handleInner 调用",
)
replace_once(
'''\tcontent: string,
\tsenderOpenId?: string,
): Promise<void> {''',
'''\tcontent: string,
\tsenderOpenId?: string,
\ttopicKey?: string,
\txiaozuChatId?: string,
): Promise<void> {''',
    "handleInner 签名",
)
replace_once(
'''\t\tif (slash.kind === "reset") {
\t\t\tif (topicKey) topicSessionRepo.clear(topicKey);
\t\t\telse archiveAndResetSession(defaultWorkspace);''',
'''\t\tif (slash.kind === "reset") {
\t\t\tif (topicKey) topicSessionRepo.clear(topicKey);
\t\t\telse archiveAndResetSession(defaultWorkspace);
\t\t\tif (xiaozuChatId) xiaozuGroupAgent.resetExecutionContext(xiaozuChatId);''',
    "reset 水位",
)
replace_once(
'''\t\tif (slash.kind === "reset") {
\t\t\tif (topicKey) topicSessionRepo.clear(topicKey);
\t\t\telse archiveAndResetSession(defaultWorkspace);
\t\t\tif (xiaozuChatId) xiaozuGroupAgent.resetExecutionContext(xiaozuChatId);
\t\t\tawait replyCard(messageId, EasyGoCmd.RESET_REPLY, { title: "新会话", color: "blue" });
\t\t\treturn;
\t\t}
\t\tif (slash.kind === "unknown") {''',
'''\t\tif (slash.kind === "reset") {
\t\t\tif (topicKey) topicSessionRepo.clear(topicKey);
\t\t\telse archiveAndResetSession(defaultWorkspace);
\t\t\tif (xiaozuChatId) xiaozuGroupAgent.resetExecutionContext(xiaozuChatId);
\t\t\tawait replyCard(messageId, EasyGoCmd.RESET_REPLY, { title: "新会话", color: "blue" });
\t\t\treturn;
\t\t}
\t\tif (slash.kind === "context") {
\t\t\tconst sessionId = topicKey ? topicSessionRepo.get(topicKey) : undefined;
\t\t\tconst body = xiaozuChatId
\t\t\t\t? xiaozuGroupAgent.describeCursorContext(xiaozuChatId, { topicKey, sessionId })
\t\t\t\t: EasyGoCmd.formatCursorContext({ topicKey, sessionId });
\t\t\tawait replyCard(messageId, body, { title: "Cursor 上下文", color: "blue" });
\t\t\treturn;
\t\t}
\t\tif (slash.kind === "unknown") {''',
    "上下文命令",
)
replace_once(
'''\tconst model = config.CURSOR_MODEL;

\t// 创建或复用卡片：全局排队卡片 → 同会话排队 → 处理中''',
'''\tlet xiaozuTaskTurn: ReturnType<typeof xiaozuGroupAgent.buildTaskTurn> | undefined;
\tif (xiaozuChatId) {
\t\txiaozuTaskTurn = xiaozuGroupAgent.buildTaskTurn({
\t\t\tchatId: xiaozuChatId,
\t\t\tmessageId,
\t\t\trequest: prompt,
\t\t});
\t\tprompt = xiaozuTaskTurn.prompt;
\t}

\tconst model = config.CURSOR_MODEL;

\t// 创建或复用卡片：全局排队卡片 → 同会话排队 → 处理中''',
    "执行上下文注入点",
)
replace_once(
'''\t\tconst resultWithNote = sessionRenewed
\t\t\t? `⚠️ 原 Topic Session 无法续聊，已自动开启新会话。\\n\\n${result}`
\t\t\t: result;
\t\tprogressEnabled = false;''',
'''\t\tconst resultWithNote = sessionRenewed
\t\t\t? `⚠️ 原 Topic Session 无法续聊，已自动开启新会话。\\n\\n${result}`
\t\t\t: result;
\t\tif (xiaozuTaskTurn) xiaozuGroupAgent.completeTaskTurn(xiaozuTaskTurn, resultWithNote);
\t\tprogressEnabled = false;''',
    "执行完成水位",
)
text = text.replace(
    "const fullResult = quotaWarning ? `${quotaWarning}\\n\\n---\\n\\n${result}` : result;",
    "const fullResult = quotaWarning ? `${quotaWarning}\\n\\n---\\n\\n${resultWithNote}` : resultWithNote;",
    1,
)
text = text.replace(
    "await replyLongMessage(messageId, chatId, result, { title: doneTitle, color: \"green\" });",
    "await replyLongMessage(messageId, chatId, resultWithNote, { title: doneTitle, color: \"green\" });",
    1,
)

replace_once(
'''\t\t\tlet { text: parsedText, imageKey, fileKey, fileName } = parseContent(messageType, content);
\t\t\t// 补齐 media/video 等类型里的 key（parseContent 未覆盖时）''',
'''\t\t\tlet { text: parsedText, imageKey, fileKey, fileName } = parseContent(messageType, content);
\t\t\tconst isXiaozuChat = chatType === "group" && xiaozuSpectatorChatIds.has(chatId);
\t\t\t// 补齐 media/video 等类型里的 key（parseContent 未覆盖时）''',
    "小组 chat 判定",
)
replace_once(
'''\t\t\t\tconst mentionedBot = isBotMentioned(mentions);
\t\t\t\tif (!mentionedBot) {
\t\t\t\t\tconsole.log(`[群聊] 忽略：未 @Bot chat=${chatId}`);
\t\t\t\t\treturn;
\t\t\t\t}''',
'''\t\t\t\tconst mentionedBot = isBotMentioned(mentions);
\t\t\t\tif (!mentionedBot) {
\t\t\t\t\tif (isXiaozuChat) {
\t\t\t\t\t\tconst decision = await xiaozuGroupAgent.observe({
\t\t\t\t\t\t\tchatId,
\t\t\t\t\t\t\tmessageId,
\t\t\t\t\t\t\ttext: parsedText || `[${messageType}]`,
\t\t\t\t\t\t});
\t\t\t\t\t\tconsole.log(`[Speak Gate] action=${decision.action} confidence=${decision.confidence.toFixed(2)} reason=${decision.reason}`);
\t\t\t\t\t\tif (decision.action !== "silence") {
\t\t\t\t\t\t\tconst suffix = decision.action === "propose_task"
\t\t\t\t\t\t\t\t? "\\n\\n> 这是候选任务；需要我开工时请 @我确认。"
\t\t\t\t\t\t\t\t: "";
\t\t\t\t\t\t\tawait replyCard(
\t\t\t\t\t\t\t\tmessageId,
\t\t\t\t\t\t\t\t`${decision.message}${suffix}`,
\t\t\t\t\t\t\t\t{ title: xiaozuGroupAgent.personaName, color: decision.action === "propose_task" ? "orange" : "blue" },
\t\t\t\t\t\t\t\t{ allowTextFallback: true },
\t\t\t\t\t\t\t);
\t\t\t\t\t\t}
\t\t\t\t\t} else {
\t\t\t\t\t\tconsole.log(`[群聊] 忽略：未 @Bot chat=${chatId}`);
\t\t\t\t\t}
\t\t\t\t\treturn;
\t\t\t\t}''',
    "未 @ Speak Gate",
)
replace_once(
'''\t\t\t// CLAW_TOPIC_SESSION + CLAW_GROUP_TOPIC_GATE: Group Topic Only
\t\t\t{
\t\t\t\tconst gate = EasyGoCmd.gateInboundMessage(chatType, threadId);
\t\t\t\tif (gate.action === "reject") {
\t\t\t\t\tconsole.log(`[入站] 拒绝: ${gate.reason}`);
\t\t\t\t\tawait replyCard(messageId, gate.reply, { title: gate.reason === "no_thread" ? "请使用话题" : "仅群话题", color: "orange" });
\t\t\t\t\treturn;
\t\t\t\t}
\t\t\t}

\t\t\tconst topicKey = TopicAgent.getTopicKey(chatType, threadId, senderOpenId);''',
'''\t\t\t// CLAW_TOPIC_SESSION + CLAW_GROUP_TOPIC_GATE: 普通群仍需话题；「小组」主群使用单一共享会话
\t\t\tconst inboundGate = EasyGoCmd.gateInboundMessage(chatType, threadId, {
\t\t\t\tmainGroupTopicKey: isXiaozuChat ? `xiaozu:${chatId}` : undefined,
\t\t\t});
\t\t\tif (inboundGate.action === "reject") {
\t\t\t\tconsole.log(`[入站] 拒绝: ${inboundGate.reason}`);
\t\t\t\tawait replyCard(messageId, inboundGate.reply, { title: inboundGate.reason === "no_thread" ? "请使用话题" : "仅群话题", color: "orange" });
\t\t\t\treturn;
\t\t\t}

\t\t\tconst topicKey = inboundGate.topicKey;''',
    "小组主群会话门",
)
replace_once(
    "handle({ text: parsedText.trim(), messageId, chatId, chatType, messageType, content, senderOpenId, threadId, topicKey }).catch(console.error);",
    "handle({ text: parsedText.trim(), messageId, chatId, chatType, messageType, content, senderOpenId, threadId, topicKey, xiaozuChatId: isXiaozuChat ? chatId : undefined }).catch(console.error);",
    "handle 小组参数",
)

server.write_text(text)
print("patch-claw-xiaozu-group-agent: 已应用（Qwen Speak Gate + 群状态 + 增量执行上下文）")
PY

python3 - "${SERVER}" <<'PY'
from pathlib import Path
import sys

server = Path(sys.argv[1])
text = server.read_text()
marker = "CLAW_XIAOZHU_BEHAVIOR_TREE"

if marker in text:
    print("patch-claw-xiaozu-group-agent: 行为树已应用，仅同步模板")
    sys.exit(0)

old_init = "const xiaozuGroupAgent = createXiaozuGroupAgent({ workspace: defaultWorkspace }); // CLAW_XIAOZHU_GROUP_AGENT"
if old_init not in text:
    print("patch-claw-xiaozu-group-agent: 无法定位行为树初始化点", file=sys.stderr)
    sys.exit(1)
text = text.replace(
    old_init,
    "const xiaozuGroupAgent = createXiaozuGroupAgent({ workspace: defaultWorkspace }); // CLAW_XIAOZHU_GROUP_AGENT · CLAW_XIAOZHU_BEHAVIOR_TREE",
    1,
)

old_branch = '''\t\t\t\tconst mentionedBot = isBotMentioned(mentions);
\t\t\t\tif (!mentionedBot) {
\t\t\t\t\tif (isXiaozuChat) {
\t\t\t\t\t\tconst decision = await xiaozuGroupAgent.observe({
\t\t\t\t\t\t\tchatId,
\t\t\t\t\t\t\tmessageId,
\t\t\t\t\t\t\ttext: parsedText || `[${messageType}]`,
\t\t\t\t\t\t});
\t\t\t\t\t\tconsole.log(`[Speak Gate] action=${decision.action} confidence=${decision.confidence.toFixed(2)} reason=${decision.reason}`);
\t\t\t\t\t\tif (decision.action !== "silence") {
\t\t\t\t\t\t\tconst suffix = decision.action === "propose_task"
\t\t\t\t\t\t\t\t? "\\n\\n> 这是候选任务；需要我开工时请 @我确认。"
\t\t\t\t\t\t\t\t: "";
\t\t\t\t\t\t\tawait replyCard(
\t\t\t\t\t\t\t\tmessageId,
\t\t\t\t\t\t\t\t`${decision.message}${suffix}`,
\t\t\t\t\t\t\t\t{ title: xiaozuGroupAgent.personaName, color: decision.action === "propose_task" ? "orange" : "blue" },
\t\t\t\t\t\t\t\t{ allowTextFallback: true },
\t\t\t\t\t\t\t);
\t\t\t\t\t\t}
\t\t\t\t\t} else {
\t\t\t\t\t\tconsole.log(`[群聊] 忽略：未 @Bot chat=${chatId}`);
\t\t\t\t\t}
\t\t\t\t\treturn;
\t\t\t\t}'''

new_branch = '''\t\t\t\tconst mentionedBot = isBotMentioned(mentions);
\t\t\t\tif (isXiaozuChat) {
\t\t\t\t\t// CLAW_XIAOZHU_BEHAVIOR_TREE: 「小组」每条群消息恰好 Tick 一次
\t\t\t\t\tconst behaviorText = mentionedBot
\t\t\t\t\t\t? stripMentionPlaceholders(parsedText, mentions)
\t\t\t\t\t\t: parsedText;
\t\t\t\t\tconst behavior = await xiaozuGroupAgent.tick({
\t\t\t\t\t\tkind: "group_message",
\t\t\t\t\t\tchatId,
\t\t\t\t\t\tmessageId,
\t\t\t\t\t\ttext: behaviorText || `[${messageType}]`,
\t\t\t\t\t\tmessageType,
\t\t\t\t\t\tmentioned: mentionedBot,
\t\t\t\t\t\tauthorized: PermissionGate.checkPermission(behaviorText, senderOpenId, permCfg).ok,
\t\t\t\t\t});
\t\t\t\t\tconsole.log(`[行为树] action=${behavior.action} confidence=${behavior.confidence.toFixed(2)} reason=${behavior.reason}`);
\t\t\t\t\tif (behavior.action !== "work") {
\t\t\t\t\t\tif (behavior.action === "reply" || behavior.action === "propose_task" || behavior.action === "propose_decision") {
\t\t\t\t\t\t\tconst suffix = behavior.action === "propose_task"
\t\t\t\t\t\t\t\t? "\\n\\n> 这是候选任务；需要我开工时请 @我确认。"
\t\t\t\t\t\t\t\t: "";
\t\t\t\t\t\t\tawait replyCard(
\t\t\t\t\t\t\t\tmessageId,
\t\t\t\t\t\t\t\t`${behavior.message}${suffix}`,
\t\t\t\t\t\t\t\t{ title: xiaozuGroupAgent.personaName, color: behavior.action === "propose_task" || behavior.action === "propose_decision" ? "orange" : "blue" },
\t\t\t\t\t\t\t\t{ allowTextFallback: true },
\t\t\t\t\t\t\t);
\t\t\t\t\t\t}
\t\t\t\t\t\treturn;
\t\t\t\t\t}
\t\t\t\t} else if (!mentionedBot) {
\t\t\t\t\tconsole.log(`[群聊] 忽略：未 @Bot chat=${chatId}`);
\t\t\t\t\treturn;
\t\t\t\t}'''

if old_branch not in text:
    print("patch-claw-xiaozu-group-agent: 无法定位旧 Speak Gate 分支", file=sys.stderr)
    sys.exit(1)
text = text.replace(old_branch, new_branch, 1)

server.write_text(text)
print("patch-claw-xiaozu-group-agent: 已升级为每消息一 Tick 的行为树")
PY

# Cursor Ask/Agent + 结果回灌（幂等）
python3 "${PACK_ROOT}/scripts/_patch-xiaozu-cursor-mode.py" "${SERVER}"
python3 "${PACK_ROOT}/scripts/_patch-xiaozu-bare-mention.py" "${SERVER}"
