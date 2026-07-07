#!/usr/bin/env bash
# 1) 群聊须先 @Bot 再判话题；未 @ 或无话题时静默忽略，不弹「请使用话题」
# 2) 思考阶段不刷新卡片，避免「思考中」刷屏
set -euo pipefail

PACK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLAW_INSTALL_DIR="${CLAW_INSTALL_DIR:-${PACK_ROOT}/claw}"
SERVER="${CLAW_INSTALL_DIR}/server.ts"

if [[ ! -f "${SERVER}" ]]; then
  echo "跳过 patch-claw-group-topic-gate-fix: 未找到 ${SERVER}"
  exit 0
fi

python3 - "${SERVER}" <<'PY'
from pathlib import Path
import sys

server = Path(sys.argv[1])
text = server.read_text()
changed = False

# ── 修复 dispatcher：去掉无话题自动回复，@ 过滤优先 ──
bad = """\t\t\tif (isDup(messageId)) return;

\t\t\tif (chatType === "group" && !threadId) {
\t\t\t\tconsole.log("[群聊] 忽略：无话题 thread_id");
\t\t\t\tawait replyCard(messageId, "请在**话题**里 @我，我才能处理这条消息。", { title: "请使用话题", color: "orange" });
\t\t\t\treturn;
\t\t\t}
\t\t\tif (!TYPES.has(messageType)) {"""

good = """\t\t\tif (isDup(messageId)) return;

\t\t\tif (!TYPES.has(messageType)) {"""

if bad in text:
    text = text.replace(bad, good, 1)
    changed = True

# 在 @ 过滤之后插入静默话题门控
gate_anchor = """\t\t\t\tparsedText = stripMentionPlaceholders(parsedText, mentions);
\t\t\t}

\t\t\tconst topicKey = TopicAgent.getTopicKey(chatType, threadId, senderOpenId);"""

gate_insert = """\t\t\t\tparsedText = stripMentionPlaceholders(parsedText, mentions);
\t\t\t}

\t\t\t// CLAW_GROUP_TOPIC_GATE: 仅对已 @Bot 的消息要求话题；未 @ 已在上方静默忽略
\t\t\tif (chatType === "group" && !threadId) {
\t\t\t\tconsole.log("[群聊] 忽略：已 @Bot 但无话题 thread_id");
\t\t\t\treturn;
\t\t\t}

\t\t\tconst topicKey = TopicAgent.getTopicKey(chatType, threadId, senderOpenId);"""

if gate_anchor in text and "CLAW_GROUP_TOPIC_GATE" not in text:
    text = text.replace(gate_anchor, gate_insert, 1)
    changed = True

# 无 TopicAgent 的旧版（仅 group-mention patch）
gate_anchor_legacy = """\t\t\t\tparsedText = stripMentionPlaceholders(parsedText, mentions);
\t\t\t}

\t\t\tconsole.log(`[解析] type=${messageType} chat=${chatType} sender=${senderOpenId.slice(0, 12)} text="${parsedText.slice(0, 60)}" img=${imageKey ?? ""} file=${fileKey ?? ""}`);"""

gate_insert_legacy = """\t\t\t\tparsedText = stripMentionPlaceholders(parsedText, mentions);
\t\t\t}

\t\t\t// CLAW_GROUP_TOPIC_GATE
\t\t\tif (chatType === "group" && !threadId) {
\t\t\t\tconsole.log("[群聊] 忽略：已 @Bot 但无话题 thread_id");
\t\t\t\treturn;
\t\t\t}

\t\t\tconsole.log(`[解析] type=${messageType} chat=${chatType} sender=${senderOpenId.slice(0, 12)} text="${parsedText.slice(0, 60)}" img=${imageKey ?? ""} file=${fileKey ?? ""}`);"""

if "CLAW_GROUP_TOPIC_GATE" not in text and gate_anchor_legacy in text:
    text = text.replace(gate_anchor_legacy, gate_insert_legacy, 1)
    changed = True

# ── 思考阶段不更新卡片 ──
prog_old = """\tconst onProgress = cardId
\t\t? (p: AgentProgress) => {
\t\t\t\tconst time = formatElapsed(p.elapsed);
\t\t\t\tconst phaseLabel = p.phase === "thinking" ? "🤔 思考中" : p.phase === "tool_call" ? "🔧 执行工具" : "💬 回复中";"""

prog_new = """\tconst onProgress = cardId
\t\t? (p: AgentProgress) => {
\t\t\t\t// CLAW_PROGRESS_QUIET: 思考阶段不刷新卡片，完成后一次性回复
\t\t\t\tif (p.phase === "thinking") return;
\t\t\t\tconst time = formatElapsed(p.elapsed);
\t\t\t\tconst phaseLabel = p.phase === "tool_call" ? "🔧 执行工具" : "💬 回复中";"""

if prog_old in text and "CLAW_PROGRESS_QUIET" not in text:
    text = text.replace(prog_old, prog_new, 1)
    changed = True

if not changed:
    if "CLAW_GROUP_TOPIC_GATE" in text and "CLAW_PROGRESS_QUIET" in text:
        print("patch-claw-group-topic-gate-fix: 已应用，跳过")
        sys.exit(0)
    print("patch-claw-group-topic-gate-fix: 未找到可替换片段", file=sys.stderr)
    sys.exit(1)

server.write_text(text)
print("patch-claw-group-topic-gate-fix: 群聊静默门控 + 思考阶段不刷卡片")
PY

chmod +x "${BASH_SOURCE[0]}"
