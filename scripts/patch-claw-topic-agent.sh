#!/usr/bin/env bash
# 话题 Agent：thread 分锁、本机 jsonl 存储、3 话题并行、Linux 仿真主机互斥、图片路径入库
set -euo pipefail

PACK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLAW_INSTALL_DIR="${CLAW_INSTALL_DIR:-${PACK_ROOT}/claw}"
SERVER="${CLAW_INSTALL_DIR}/server.ts"
TOPIC_SRC="${PACK_ROOT}/templates/claw/topic-agent.ts"
TOPIC_DST="${CLAW_INSTALL_DIR}/topic-agent.ts"

if [[ ! -f "${SERVER}" ]]; then
  echo "跳过 patch-claw-topic-agent: 未找到 ${SERVER}"
  exit 0
fi

cp "${TOPIC_SRC}" "${TOPIC_DST}"

python3 - "${SERVER}" <<'PY'
from pathlib import Path
import sys

server = Path(sys.argv[1])
text = server.read_text()

if "CLAW_TOPIC_AGENT" in text:
    print("patch-claw-topic-agent: 已应用，跳过")
    sys.exit(0)

# ── import ──
imp = 'import { HeartbeatRunner } from "./heartbeat.js";'
if imp not in text:
    print("patch-claw-topic-agent: 无法定位 heartbeat import", file=sys.stderr)
    sys.exit(1)
text = text.replace(
    imp,
    imp + '\nimport * as TopicAgent from "./topic-agent.js"; // CLAW_TOPIC_AGENT',
    1,
)

# ── init cleanup after ensureWorkspace ──
anchor = "ensureWorkspace(defaultWorkspace);"
if anchor not in text:
    print("patch-claw-topic-agent: 无法定位 ensureWorkspace", file=sys.stderr)
    sys.exit(1)
text = text.replace(
    anchor,
    anchor + """
TopicAgent.cleanupOldTopicFiles(defaultWorkspace);
setInterval(() => TopicAgent.cleanupOldTopicFiles(defaultWorkspace), 6 * 60 * 60 * 1000);""",
    1,
)

# ── runAgent: topicKey + parallel slot ──
run_old = """async function runAgent(
\tworkspace: string,
\tprompt: string,
\topts?: {
\t\tonProgress?: (p: AgentProgress) => void;
\t\tonStart?: () => void;
\t\tmaxMs?: number;
\t\tidleMs?: number;
\t},
): Promise<{ result: string; quotaWarning?: string }> {
\tconst primaryModel = config.CURSOR_MODEL;
\tconst lockKey = getLockKey(workspace);"""

run_new = """async function runAgent(
\tworkspace: string,
\tprompt: string,
\topts?: {
\t\tonProgress?: (p: AgentProgress) => void;
\t\tonStart?: () => void;
\t\tmaxMs?: number;
\t\tidleMs?: number;
\t\ttopicKey?: string;
\t},
): Promise<{ result: string; quotaWarning?: string }> {
\tconst primaryModel = config.CURSOR_MODEL;
\tconst lockKey = TopicAgent.topicLockKey(opts?.topicKey, getLockKey(workspace));
\tlet releaseTopicSlot: (() => void) | undefined;
\tif (opts?.topicKey) {
\t\treleaseTopicSlot = await TopicAgent.acquireTopicParallelSlot(opts.topicKey);
\t}"""

if run_old not in text:
    print("patch-claw-topic-agent: 无法定位 runAgent 头", file=sys.stderr)
    sys.exit(1)
text = text.replace(run_old, run_new, 1)

wrap_old = "\treturn withSessionLock(lockKey, async () => {"
wrap_new = "\ttry {\n\treturn await withSessionLock(lockKey, async () => {"
if wrap_old not in text:
    print("patch-claw-topic-agent: 无法定位 withSessionLock", file=sys.stderr)
    sys.exit(1)
text = text.replace(wrap_old, wrap_new, 1)

fin_old = "\t\t} finally {\n\t\t\tbusySessions.delete(lockKey);\n\t\t}\n\t});\n}"
fin_new = "\t\t} finally {\n\t\t\tbusySessions.delete(lockKey);\n\t\t}\n\t});\n\t} finally {\n\t\treleaseTopicSlot?.();\n\t}\n}"
if fin_old not in text:
    print("patch-claw-topic-agent: 无法定位 runAgent finally", file=sys.stderr)
    sys.exit(1)
text = text.replace(fin_old, fin_new, 1)

# ── handle params ──
handle_params_old = """async function handle(params: {
\ttext: string;
\tmessageId: string;
\tchatId: string;
\tchatType: string;
\tmessageType: string;
\tcontent: string;
\tsenderOpenId?: string;
}) {
\tconst { messageId, chatId, chatType, messageType, content, senderOpenId } = params;
\tlet { text } = params;"""

handle_params_new = """async function handle(params: {
\ttext: string;
\tmessageId: string;
\tchatId: string;
\tchatType: string;
\tmessageType: string;
\tcontent: string;
\tsenderOpenId?: string;
\tthreadId?: string;
\ttopicKey?: string;
}) {
\tconst { messageId, chatId, chatType, messageType, content, senderOpenId, threadId, topicKey } = params;
\tlet { text } = params;"""

if handle_params_old not in text:
    print("patch-claw-topic-agent: 无法定位 handle params", file=sys.stderr)
    sys.exit(1)
text = text.replace(handle_params_old, handle_params_new, 1)

handle_call_old = "\treturn handleInner(text, messageId, chatId, chatType, messageType, content, senderOpenId);"
handle_call_new = "\treturn handleInner(text, messageId, chatId, chatType, messageType, content, senderOpenId, threadId, topicKey);"
text = text.replace(handle_call_old, handle_call_new, 1)

handle_inner_sig_old = """async function handleInner(
\ttext: string,
\tmessageId: string,
\tchatId: string,
\tchatType: string,
\tmessageType: string,
\tcontent: string,
\tsenderOpenId?: string,
): Promise<void> {"""

handle_inner_sig_new = """async function handleInner(
\ttext: string,
\tmessageId: string,
\tchatId: string,
\tchatType: string,
\tmessageType: string,
\tcontent: string,
\tsenderOpenId?: string,
\tthreadId?: string,
\ttopicKey?: string,
): Promise<void> {"""

if handle_inner_sig_old not in text:
    print("patch-claw-topic-agent: 无法定位 handleInner", file=sys.stderr)
    sys.exit(1)
text = text.replace(handle_inner_sig_old, handle_inner_sig_new, 1)

# ── after media download block, append topic user message ──
media_end = """\t} catch (e) {
\t\tconsole.error("[下载失败]", e);
\t\tif (!text) {
\t\t\tif (cardId) await updateCard(cardId, "❌ 媒体下载失败，请重新发送", { color: "red" });
\t\t\telse await replyCard(messageId, "❌ 媒体下载失败，请重新发送");
\t\t\treturn;
\t\t}
\t}"""

media_end_new = media_end + """

\t// CLAW_TOPIC_AGENT: 本机记录用户 @（含图片路径）
\tif (topicKey) {
\t\ttry {
\t\t\tTopicAgent.appendTopicMessage(defaultWorkspace, topicKey, {
\t\t\t\tts: new Date().toISOString(),
\t\t\t\tmessage_id: messageId,
\t\t\t\trole: "user",
\t\t\t\tsender_open_id: senderOpenId,
\t\t\t\ttext: text.slice(0, 8000),
\t\t\t\timage_path: TopicAgent.extractImagePathFromText(text),
\t\t\t\tmessage_type: messageType,
\t\t\t});
\t\t} catch (e) {
\t\t\tconsole.warn("[话题] 写入用户消息失败:", e);
\t\t}
\t}"""

if media_end not in text:
    print("patch-claw-topic-agent: 无法定位媒体下载块", file=sys.stderr)
    sys.exit(1)
text = text.replace(media_end, media_end_new, 1)

# ── queue key + sim mutex + topic history before runAgent ──
queue_old = """\tconst currentLockKey = getLockKey(workspace);
\tconst needsSessionQueue = !cardId && busySessions.has(currentLockKey);"""

queue_new = """\tconst currentLockKey = TopicAgent.topicLockKey(topicKey, getLockKey(workspace));
\tconst needsSessionQueue = !cardId && busySessions.has(currentLockKey);

\tif (process.platform === "linux" && TopicAgent.isSimLaunchIntent(prompt)) {
\t\tif (TopicAgent.isSimRunningOnHost()) {
\t\t\tawait replyCard(messageId, TopicAgent.simHostBusyMessage(), { title: "仿真占用中", color: "orange" });
\t\t\treturn;
\t\t}
\t}

\tif (topicKey && TopicAgent.shouldLoadTopicHistory(prompt)) {
\t\tprompt += TopicAgent.topicHistoryPromptSuffix(defaultWorkspace, topicKey);
\t}"""

if queue_old not in text:
    print("patch-claw-topic-agent: 无法定位 queue key", file=sys.stderr)
    sys.exit(1)
text = text.replace(queue_old, queue_new, 1)

run_call_old = "\t\tconst { result, quotaWarning } = await runAgent(workspace, prompt, { onProgress, onStart });"
run_call_new = "\t\tconst { result, quotaWarning } = await runAgent(workspace, prompt, { onProgress, onStart, topicKey });"
text = text.replace(run_call_old, run_call_new, 1)

# ── append assistant to topic after success ──
assist_old = """\t\tconsole.log(`[${new Date().toISOString()}] 完成 [${label}] model=${usedModel} elapsed=${elapsed} (${result.length} chars)`);

\t\t// 记录 assistant 回复到会话日志
\t\tif (memory) {"""

assist_new = """\t\tconsole.log(`[${new Date().toISOString()}] 完成 [${label}] model=${usedModel} elapsed=${elapsed} (${result.length} chars)`);

\t\tif (topicKey) {
\t\t\ttry {
\t\t\t\tTopicAgent.appendTopicMessage(defaultWorkspace, topicKey, {
\t\t\t\t\tts: new Date().toISOString(),
\t\t\t\t\trole: "assistant",
\t\t\t\t\ttext: result.slice(0, 8000),
\t\t\t\t});
\t\t\t} catch (e) {
\t\t\t\tconsole.warn("[话题] 写入 Bot 回复失败:", e);
\t\t\t}
\t\t}

\t\t// 记录 assistant 回复到会话日志
\t\tif (memory) {"""

if assist_old not in text:
    print("patch-claw-topic-agent: 无法定位 assistant 日志", file=sys.stderr)
    sys.exit(1)
text = text.replace(assist_old, assist_new, 1)

# ── dispatcher: thread_id + group gate ──
disp_old = """\t\t\tconst mentions = (msg.mentions as FeishuMention[] | undefined) ?? [];

\t\t\tif (isDup(messageId)) return;"""

disp_new = """\t\t\tconst mentions = (msg.mentions as FeishuMention[] | undefined) ?? [];
\t\t\tconst threadId = (msg.thread_id as string | undefined) || undefined;

\t\t\tif (isDup(messageId)) return;

\t\t\tif (chatType === "group" && !threadId) {
\t\t\t\tconsole.log("[群聊] 忽略：无话题 thread_id");
\t\t\t\tawait replyCard(messageId, "请在**话题**里 @我，我才能处理这条消息。", { title: "请使用话题", color: "orange" });
\t\t\t\treturn;
\t\t\t}"""

if disp_old not in text:
    print("patch-claw-topic-agent: 无法定位 dispatcher", file=sys.stderr)
    sys.exit(1)
text = text.replace(disp_old, disp_new, 1)

handle_invoke_old = """\t\t\tconsole.log(`[解析] type=${messageType} chat=${chatType} sender=${senderOpenId.slice(0, 12)} text="${parsedText.slice(0, 60)}" img=${imageKey ?? ""} file=${fileKey ?? ""}`);
\t\t\thandle({ text: parsedText.trim(), messageId, chatId, chatType, messageType, content, senderOpenId }).catch(console.error);"""

handle_invoke_new = """\t\t\tconst topicKey = TopicAgent.getTopicKey(chatType, threadId, senderOpenId);
\t\t\tconsole.log(`[解析] type=${messageType} chat=${chatType} thread=${threadId?.slice(0, 12) ?? "-"} sender=${senderOpenId.slice(0, 12)} text="${parsedText.slice(0, 60)}" img=${imageKey ?? ""} file=${fileKey ?? ""}`);
\t\t\thandle({ text: parsedText.trim(), messageId, chatId, chatType, messageType, content, senderOpenId, threadId, topicKey }).catch(console.error);"""

if handle_invoke_old not in text:
    print("patch-claw-topic-agent: 无法定位 handle 调用", file=sys.stderr)
    sys.exit(1)
text = text.replace(handle_invoke_old, handle_invoke_new, 1)

# pure image: allow empty text if imageKey
# parseContent for image type returns empty text - dispatcher still needs to pass imageKey
# handleInner re-parses content - OK for image messageType

server.write_text(text)
print("patch-claw-topic-agent: 已应用话题 Agent（存储/并行/仿真锁/图片路径）")
PY

chmod +x "${BASH_SOURCE[0]}"
