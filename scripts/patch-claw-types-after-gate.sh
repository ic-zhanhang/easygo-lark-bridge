#!/usr/bin/env bash
# 将 TYPES 校验移到群聊 @ 过滤与话题门控之后；群聊不支持类型静默忽略
set -euo pipefail

PACK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLAW_INSTALL_DIR="${CLAW_INSTALL_DIR:-${PACK_ROOT}/claw}"
SERVER="${CLAW_INSTALL_DIR}/server.ts"

if [[ ! -f "${SERVER}" ]]; then
  echo "跳过 patch-claw-types-after-gate: 未找到 ${SERVER}"
  exit 0
fi

python3 - "${SERVER}" <<'PY'
from pathlib import Path
import re
import sys

server = Path(sys.argv[1])
text = server.read_text()
changed = False

types_block = """\t\t\t// CLAW_TYPES_AFTER_GATE: 类型校验放在门控之后；群聊不支持类型静默忽略
\t\t\tif (!TYPES.has(messageType)) {
\t\t\t\tif (chatType === "group") {
\t\t\t\t\tconsole.log(`[群聊] 忽略：不支持的消息类型 ${messageType}`);
\t\t\t\t\treturn;
\t\t\t\t}
\t\t\t\tawait replyCard(messageId, `暂不支持: ${messageType}`);
\t\t\t\treturn;
\t\t\t}

"""

# ── 1) 去掉 isDup 之后、parseContent 之前的前置 TYPES 校验 ──
early_pattern = re.compile(
    r"(\t\t\tif \(isDup\(messageId\)\) return;\n)"
    r"(?:\n)?"
    r"\t\t\tif \(!TYPES\.has\(messageType\)\) \{\n"
    r"\t\t\t\tawait replyCard\(messageId, `暂不支持: \$\{messageType\}`\);\n"
    r"\t\t\t\treturn;\n"
    r"\t\t\t\}\n"
    r"\n"
    r"(\t\t\tlet \{ text: parsedText, imageKey, fileKey \} = parseContent\(messageType, content\);)",
    re.MULTILINE,
)

if early_pattern.search(text):
    text = early_pattern.sub(r"\1\n\2", text, count=1)
    changed = True

# ── 2a) 话题 Agent 路径：门控之后、topicKey 之前 ──
gate_with_topic = """\t\t\t// CLAW_GROUP_TOPIC_GATE: 仅对已 @Bot 的消息要求话题；未 @ 已在上方静默忽略
\t\t\tif (chatType === "group" && !threadId) {
\t\t\t\tconsole.log("[群聊] 忽略：已 @Bot 但无话题 thread_id");
\t\t\t\treturn;
\t\t\t}

\t\t\tconst topicKey = TopicAgent.getTopicKey(chatType, threadId, senderOpenId);"""

gate_with_topic_new = gate_with_topic.replace(
    "\t\t\tconst topicKey = TopicAgent.getTopicKey(chatType, threadId, senderOpenId);",
    types_block + "\t\t\tconst topicKey = TopicAgent.getTopicKey(chatType, threadId, senderOpenId);",
    1,
)

if "CLAW_TYPES_AFTER_GATE" not in text and gate_with_topic in text:
    text = text.replace(gate_with_topic, gate_with_topic_new, 1)
    changed = True

# ── 2b) 无 TopicAgent 的旧路径 ──
gate_legacy = """\t\t\t// CLAW_GROUP_TOPIC_GATE
\t\t\tif (chatType === "group" && !threadId) {
\t\t\t\tconsole.log("[群聊] 忽略：已 @Bot 但无话题 thread_id");
\t\t\t\treturn;
\t\t\t}

\t\t\tconsole.log(`[解析] type=${messageType} chat=${chatType} sender=${senderOpenId.slice(0, 12)} text="${parsedText.slice(0, 60)}" img=${imageKey ?? ""} file=${fileKey ?? ""}`);"""

gate_legacy_new = gate_legacy.replace(
    "\t\t\tconsole.log(`[解析] type=${messageType} chat=${chatType} sender=${senderOpenId.slice(0, 12)} text=\"${parsedText.slice(0, 60)}\" img=${imageKey ?? \"\"} file=${fileKey ?? \"\"}`);",
    types_block + "\t\t\tconsole.log(`[解析] type=${messageType} chat=${chatType} sender=${senderOpenId.slice(0, 12)} text=\"${parsedText.slice(0, 60)}\" img=${imageKey ?? \"\"} file=${fileKey ?? \"\"}`);",
    1,
)

if "CLAW_TYPES_AFTER_GATE" not in text and gate_legacy in text:
    text = text.replace(gate_legacy, gate_legacy_new, 1)
    changed = True

if not changed:
    if "CLAW_TYPES_AFTER_GATE" in text and not early_pattern.search(text):
        print("patch-claw-types-after-gate: 已应用，跳过")
        sys.exit(0)
    print("patch-claw-types-after-gate: 未找到可替换片段", file=sys.stderr)
    sys.exit(1)

server.write_text(text)
print("patch-claw-types-after-gate: TYPES 校验已移至门控之后")
PY

chmod +x "${BASH_SOURCE[0]}"
