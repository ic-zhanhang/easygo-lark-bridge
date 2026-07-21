#!/usr/bin/env bash
# 升级已安装 claw：
# 1) 群话题默认附话题上下文（私聊仍按需）
# 2) 群聊恢复中间态卡片，并显示「🤔 思考中」
set -euo pipefail

PACK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLAW_INSTALL_DIR="${CLAW_INSTALL_DIR:-${PACK_ROOT}/claw}"
SERVER="${CLAW_INSTALL_DIR}/server.ts"
TOPIC_SRC="${PACK_ROOT}/templates/claw/topic-agent.ts"
TOPIC_DST="${CLAW_INSTALL_DIR}/topic-agent.ts"

if [[ ! -f "${SERVER}" ]]; then
  echo "跳过 patch-claw-group-topic-context-progress: 未找到 ${SERVER}"
  exit 0
fi

# 同步 topic-agent.ts（含 shouldAttachTopicHistory）
if [[ -f "${TOPIC_SRC}" ]]; then
  cp "${TOPIC_SRC}" "${TOPIC_DST}"
fi

python3 - "${SERVER}" <<'PY'
from pathlib import Path
import sys

server = Path(sys.argv[1])
text = server.read_text()
changed = False

# ── 1) 群话题默认附上下文 ──
hist_old = """\tif (topicKey && TopicAgent.shouldLoadTopicHistory(prompt)) {
\t\tprompt += TopicAgent.topicHistoryPromptSuffix(defaultWorkspace, topicKey);
\t}"""

hist_new = """\t// CLAW_TOPIC_DEFAULT_CONTEXT: 群话题默认附上下文；私聊仍按需
\tif (topicKey && TopicAgent.shouldAttachTopicHistory(chatType, prompt)) {
\t\tprompt += TopicAgent.topicHistoryPromptSuffix(defaultWorkspace, topicKey);
\t}"""

if hist_old in text:
    text = text.replace(hist_old, hist_new, 1)
    changed = True
elif "CLAW_TOPIC_DEFAULT_CONTEXT" not in text and "shouldAttachTopicHistory" not in text:
    # 可能已被改成别的形式
    pass

# ── 2) 恢复群聊中间态卡片创建 ──
quiet_card = """\t// CLAW_GROUP_QUIET_REPLY: 群聊不刷中间态卡片，完成后一次性回复
\tif (!isGroup) {
\t\tif (!cardId) {
\t\t\tconst status = needsSessionQueue
\t\t\t\t? `⏳ 排队中（同会话有任务进行中）\\n\\n> ${text.slice(0, 120)}`
\t\t\t\t: `⏳ 正在执行...\\n\\n> ${text.slice(0, 120)}`;
\t\t\tcardId = await replyCard(messageId, status, {
\t\t\t\ttitle: needsSessionQueue ? "排队中" : "处理中",
\t\t\t\tcolor: needsSessionQueue ? "grey" : "wathet",
\t\t\t});
\t\t} else {
\t\t\tconst status = busySessions.has(currentLockKey)
\t\t\t\t? `⏳ 排队中（同会话有任务进行中）\\n\\n> ${text.slice(0, 120)}`
\t\t\t\t: `⏳ 正在执行...\\n\\n> ${text.slice(0, 120)}`;
\t\t\tawait updateCard(cardId, status, {
\t\t\t\ttitle: busySessions.has(currentLockKey) ? "排队中" : "处理中",
\t\t\t\tcolor: busySessions.has(currentLockKey) ? "grey" : "wathet",
\t\t\t});
\t\t}
\t}"""

card_restored = """\t// CLAW_TOPIC_PROGRESS: 群聊/私聊均刷中间态（含思考中）
\tif (!cardId) {
\t\tconst status = needsSessionQueue
\t\t\t? `⏳ 排队中（同会话有任务进行中）\\n\\n> ${text.slice(0, 120)}`
\t\t\t: `⏳ 正在执行...\\n\\n> ${text.slice(0, 120)}`;
\t\tcardId = await replyCard(messageId, status, {
\t\t\ttitle: needsSessionQueue ? "排队中" : "处理中",
\t\t\tcolor: needsSessionQueue ? "grey" : "wathet",
\t\t});
\t} else {
\t\tconst status = busySessions.has(currentLockKey)
\t\t\t? `⏳ 排队中（同会话有任务进行中）\\n\\n> ${text.slice(0, 120)}`
\t\t\t: `⏳ 正在执行...\\n\\n> ${text.slice(0, 120)}`;
\t\tawait updateCard(cardId, status, {
\t\t\ttitle: busySessions.has(currentLockKey) ? "排队中" : "处理中",
\t\t\tcolor: busySessions.has(currentLockKey) ? "grey" : "wathet",
\t\t});
\t}"""

if quiet_card in text:
    text = text.replace(quiet_card, card_restored, 1)
    changed = True

# ── 3) onStart / onProgress：去掉 !isGroup，恢复思考中 ──
start_old = """\tconst onStart = cardId && !isGroup
\t\t? () => {
\t\t\t\tif (!progressEnabled) return;
\t\t\t\tenqueueCardUpdate(`⏳ 正在执行...\\n\\n> ${text.slice(0, 120)}`, {
\t\t\t\t\ttitle: "处理中",
\t\t\t\t\tcolor: "wathet",
\t\t\t\t}).catch(() => {});
\t\t\t}
\t\t: undefined;"""

start_new = """\tconst onStart = cardId
\t\t? () => {
\t\t\t\tif (!progressEnabled) return;
\t\t\t\tenqueueCardUpdate(`⏳ 正在执行...\\n\\n> ${text.slice(0, 120)}`, {
\t\t\t\t\ttitle: "处理中",
\t\t\t\t\tcolor: "wathet",
\t\t\t\t}).catch(() => {});
\t\t\t}
\t\t: undefined;"""

if start_old in text:
    text = text.replace(start_old, start_new, 1)
    changed = True

prog_old_variants = [
    """\tconst onProgress = cardId && !isGroup
\t\t? (p: AgentProgress) => {
\t\t\t\t// CLAW_PROGRESS_DONE_GUARD + CLAW_PROGRESS_QUIET
\t\t\t\tif (!progressEnabled || p.phase === "thinking") return;
\t\t\t\tconst time = formatElapsed(p.elapsed);
\t\t\t\tconst phaseLabel = p.phase === "tool_call" ? "🔧 执行工具" : "💬 回复中";
\t\t\t\tconst snippet = p.snippet.split("\\n").filter((l) => l.trim()).slice(-4).join("\\n");
\t\t\t\tenqueueCardUpdate(
\t\t\t\t\t`\\`\\`\\`\\n${snippet.slice(0, 300) || "..."}\\n\\`\\`\\``,
\t\t\t\t\t{ title: `${phaseLabel} · ${time}`, color: "wathet" },
\t\t\t\t).catch(() => {});
\t\t\t}
\t\t: undefined;""",
    """\tconst onProgress = cardId
\t\t? (p: AgentProgress) => {
\t\t\t\t// CLAW_PROGRESS_DONE_GUARD + CLAW_PROGRESS_QUIET
\t\t\t\tif (!progressEnabled || p.phase === "thinking") return;
\t\t\t\tconst time = formatElapsed(p.elapsed);
\t\t\t\tconst phaseLabel = p.phase === "tool_call" ? "🔧 执行工具" : "💬 回复中";
\t\t\t\tconst snippet = p.snippet.split("\\n").filter((l) => l.trim()).slice(-4).join("\\n");
\t\t\t\tenqueueCardUpdate(
\t\t\t\t\t`\\`\\`\\`\\n${snippet.slice(0, 300) || "..."}\\n\\`\\`\\``,
\t\t\t\t\t{ title: `${phaseLabel} · ${time}`, color: "wathet" },
\t\t\t\t).catch(() => {});
\t\t\t}
\t\t: undefined;""",
]

prog_new = """\tconst onProgress = cardId
\t\t? (p: AgentProgress) => {
\t\t\t\t// CLAW_PROGRESS_DONE_GUARD: 含思考中状态
\t\t\t\tif (!progressEnabled) return;
\t\t\t\tconst time = formatElapsed(p.elapsed);
\t\t\t\tconst phaseLabel = p.phase === "thinking" ? "🤔 思考中" : p.phase === "tool_call" ? "🔧 执行工具" : "💬 回复中";
\t\t\t\tconst snippet = p.snippet.split("\\n").filter((l) => l.trim()).slice(-4).join("\\n");
\t\t\t\tenqueueCardUpdate(
\t\t\t\t\t`\\`\\`\\`\\n${snippet.slice(0, 300) || "..."}\\n\\`\\`\\``,
\t\t\t\t\t{ title: `${phaseLabel} · ${time}`, color: "wathet" },
\t\t\t\t).catch(() => {});
\t\t\t}
\t\t: undefined;"""

for old in prog_old_variants:
    if old in text:
        text = text.replace(old, prog_new, 1)
        changed = True
        break

# 幂等：已是目标态
already = (
    "CLAW_TOPIC_DEFAULT_CONTEXT" in text
    and "shouldAttachTopicHistory" in text
    and "CLAW_TOPIC_PROGRESS" in text
    and 'phase === "thinking" ? "🤔 思考中"' in text
    and "const onStart = cardId\n" in text
    and "const onProgress = cardId\n" in text
    and "p.phase === \"thinking\") return" not in text
)

# 全新 install 链：topic-agent / progress-done-guard 已是目标态时，视为成功
fresh_ok = (
    "shouldAttachTopicHistory" in text
    and 'phase === "thinking" ? "🤔 思考中"' in text
    and "CLAW_GROUP_QUIET_REPLY: 群聊不刷中间态卡片" not in text
    and "const onStart = cardId\n" in text
    and "const onProgress = cardId\n" in text
)

if not changed:
    if already or fresh_ok:
        print("patch-claw-group-topic-context-progress: 已应用，跳过")
        sys.exit(0)
    print("patch-claw-group-topic-context-progress: 未找到可替换片段", file=sys.stderr)
    sys.exit(1)

server.write_text(text)
print("patch-claw-group-topic-context-progress: 群话题默认上下文 + 思考中进度")
PY

chmod +x "${BASH_SOURCE[0]}"
