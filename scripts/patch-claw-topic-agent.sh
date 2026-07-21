#!/usr/bin/env bash
# 话题 Agent：thread 分锁、3 话题并行、Linux 仿真主机互斥（Relay：无 jsonl）
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
    # tolerate startupGraceMs / usage already present from other patches order
    run_old_alt = """async function runAgent(
\tworkspace: string,
\tprompt: string,
\topts?: {
\t\tonProgress?: (p: AgentProgress) => void;
\t\tonStart?: () => void;
\t\tmaxMs?: number;
\t\tidleMs?: number;
\t\tstartupGraceMs?: number;
\t},
): Promise<{ result: string; quotaWarning?: string; usage?: { inputTokens?: number; outputTokens?: number } }> {
\tconst primaryModel = config.CURSOR_MODEL;
\tconst lockKey = getLockKey(workspace);"""
    run_new_alt = """async function runAgent(
\tworkspace: string,
\tprompt: string,
\topts?: {
\t\tonProgress?: (p: AgentProgress) => void;
\t\tonStart?: () => void;
\t\tmaxMs?: number;
\t\tidleMs?: number;
\t\tstartupGraceMs?: number;
\t\ttopicKey?: string;
\t},
): Promise<{ result: string; quotaWarning?: string; usage?: { inputTokens?: number; outputTokens?: number } }> {
\tconst primaryModel = config.CURSOR_MODEL;
\tconst lockKey = TopicAgent.topicLockKey(opts?.topicKey, getLockKey(workspace));
\tlet releaseTopicSlot: (() => void) | undefined;
\tif (opts?.topicKey) {
\t\treleaseTopicSlot = await TopicAgent.acquireTopicParallelSlot(opts.topicKey);
\t}"""
    if run_old_alt in text:
        text = text.replace(run_old_alt, run_new_alt, 1)
    else:
        print("patch-claw-topic-agent: 无法定位 runAgent 头", file=sys.stderr)
        sys.exit(1)
else:
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
\tmentions?: FeishuMention[];
}) {
\tconst { messageId, chatId, chatType, messageType, content, senderOpenId, threadId, topicKey, mentions } = params;
\tlet { text } = params;"""

if handle_params_old not in text:
    print("patch-claw-topic-agent: 无法定位 handle params（可能已被 group-mention 改过）", file=sys.stderr)
    # continue — group-mention may already expand handle
else:
    text = text.replace(handle_params_old, handle_params_new, 1)

# ── queue key + sim mutex (no history) ──
queue_old = """\tconst currentLockKey = getLockKey(workspace);
\tconst needsSessionQueue = !cardId && busySessions.has(currentLockKey);"""

queue_new = """\tconst currentLockKey = TopicAgent.topicLockKey(topicKey, getLockKey(workspace));
\tconst needsSessionQueue = !cardId && busySessions.has(currentLockKey);

\tif (process.platform === "linux" && TopicAgent.isSimLaunchIntent(prompt)) {
\t\tif (TopicAgent.isSimRunningOnHost()) {
\t\t\tawait replyCard(messageId, TopicAgent.simHostBusyMessage(), { title: "仿真占用中", color: "orange" });
\t\t\treturn;
\t\t}
\t}"""

if queue_old not in text:
    print("patch-claw-topic-agent: 无法定位 queue key", file=sys.stderr)
    sys.exit(1)
text = text.replace(queue_old, queue_new, 1)

run_call_old = "\t\tconst { result, quotaWarning } = await runAgent(workspace, prompt, { onProgress, onStart });"
run_call_new = "\t\tconst { result, quotaWarning } = await runAgent(workspace, prompt, { onProgress, onStart, topicKey });"
if run_call_old in text:
    text = text.replace(run_call_old, run_call_new, 1)
else:
    run_call_old2 = "\t\tconst { result, quotaWarning, usage } = await runAgent(workspace, prompt, { onProgress, onStart });"
    run_call_new2 = "\t\tconst { result, quotaWarning, usage } = await runAgent(workspace, prompt, { onProgress, onStart, topicKey });"
    if run_call_old2 in text:
        text = text.replace(run_call_old2, run_call_new2, 1)

# ── dispatcher: thread_id ──
disp_old = """\t\t\tconst mentions = (msg.mentions as FeishuMention[] | undefined) ?? [];

\t\t\tif (isDup(messageId)) return;"""

disp_new = """\t\t\tconst mentions = (msg.mentions as FeishuMention[] | undefined) ?? [];
\t\t\tconst threadId = (msg.thread_id as string | undefined) || undefined;

\t\t\tif (isDup(messageId)) return;"""

if disp_old in text and "msg.thread_id" not in text.split("if (isDup(messageId)) return;")[0][-200:]:
    text = text.replace(disp_old, disp_new, 1)

handle_invoke_old = """\t\t\t\tparsedText = stripMentionPlaceholders(parsedText, mentions);
\t\t\t}

\t\t\tconsole.log(`[解析] type=${messageType} chat=${chatType} sender=${senderOpenId.slice(0, 12)} text="${parsedText.slice(0, 60)}" img=${imageKey ?? ""} file=${fileKey ?? ""}`);
\t\t\thandle({ text: parsedText.trim(), messageId, chatId, chatType, messageType, content, senderOpenId }).catch(console.error);"""

handle_invoke_new = """\t\t\t\tparsedText = stripMentionPlaceholders(parsedText, mentions);
\t\t\t}

\t\t\tconst topicKey = TopicAgent.getTopicKey(chatType, threadId, senderOpenId);
\t\t\tconsole.log(`[解析] type=${messageType} chat=${chatType} thread=${threadId?.slice(0, 12) ?? "-"} sender=${senderOpenId.slice(0, 12)} text="${parsedText.slice(0, 60)}" img=${imageKey ?? ""} file=${fileKey ?? ""}`);
\t\t\thandle({ text: parsedText.trim(), messageId, chatId, chatType, messageType, content, senderOpenId, threadId, topicKey }).catch(console.error);"""

if handle_invoke_old in text:
    text = text.replace(handle_invoke_old, handle_invoke_new, 1)

server.write_text(text)
print("patch-claw-topic-agent: 已应用话题并行/仿真锁（无 jsonl）")
PY

chmod +x "${BASH_SOURCE[0]}"
