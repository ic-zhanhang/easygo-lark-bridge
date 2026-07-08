#!/usr/bin/env bash
# 群聊静默回复：
# 1) 无聊天权限 → 只打日志，不在群里回卡片（私聊仍回）
# 2) Agent 任务 → 不刷「处理中/工具/回复中」中间态，完成后一次性 replyCard
set -euo pipefail

PACK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLAW_INSTALL_DIR="${CLAW_INSTALL_DIR:-${PACK_ROOT}/claw}"
SERVER="${CLAW_INSTALL_DIR}/server.ts"

if [[ ! -f "${SERVER}" ]]; then
  echo "跳过 patch-claw-group-quiet-reply: 未找到 ${SERVER}"
  exit 0
fi

python3 - "${SERVER}" <<'PY'
from pathlib import Path
import sys

server = Path(sys.argv[1])
text = server.read_text()
changed = False

# ── 1) 群聊权限拒绝静默 ──
perm_old = """\tif (!perm.ok) {
\t\tconsole.log(`[权限] 拒绝 sender=${senderOpenId?.slice(0, 12) ?? "?"} code=${perm.code}`);
\t\tawait replyCard(messageId, perm.message, { title: perm.title, color: "orange" });
\t\treturn;
\t}"""

perm_new = """\tif (!perm.ok) {
\t\tconsole.log(`[权限] 拒绝 sender=${senderOpenId?.slice(0, 12) ?? "?"} code=${perm.code} group=${isGroup}`);
\t\t// CLAW_GROUP_QUIET_REPLY: 群聊无权限静默忽略，私聊仍提示
\t\tif (!isGroup) {
\t\t\tawait replyCard(messageId, perm.message, { title: perm.title, color: "orange" });
\t\t}
\t\treturn;
\t}"""

if perm_old in text:
    text = text.replace(perm_old, perm_new, 1)
    changed = True

# ── 2) 群聊不建中间态卡片（topic-agent 后用 text 而非 prompt）──
card_old = """\tif (!cardId) {
\t\tconst status = needsSessionQueue
\t\t\t? `⏳ 排队中（同会话有任务进行中）\\n\\n> ${text.slice(0, 120)}`
\t\t\t: `⏳ 正在执行...\\n\\n> ${text.slice(0, 120)}`;
\t\tcardId = await replyCard(messageId, status, {
\t\t\ttitle: needsSessionQueue ? "排队中" : "处理中",
\t\t\tcolor: needsSessionQueue ? "grey" : "wathet",
\t\t});
\t} else {
\t\t// 从全局排队卡片复用，看是否还需要等同会话锁
\t\tconst status = busySessions.has(currentLockKey)
\t\t\t? `⏳ 排队中（同会话有任务进行中）\\n\\n> ${text.slice(0, 120)}`
\t\t\t: `⏳ 正在执行...\\n\\n> ${text.slice(0, 120)}`;
\t\tawait updateCard(cardId, status, {
\t\t\ttitle: busySessions.has(currentLockKey) ? "排队中" : "处理中",
\t\t\tcolor: busySessions.has(currentLockKey) ? "grey" : "wathet",
\t\t});
\t}"""

card_new = """\t// CLAW_GROUP_QUIET_REPLY: 群聊不刷中间态卡片，完成后一次性回复
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

if card_old in text and "CLAW_GROUP_QUIET_REPLY: 群聊不刷中间态卡片" not in text:
    text = text.replace(card_old, card_new, 1)
    changed = True

# 兼容旧版 prompt.slice 上游（尚未 topic-agent）
card_old_legacy = card_old.replace("${text.slice(0, 120)}", "${prompt.slice(0, 120)}")
card_new_legacy = card_new.replace("${text.slice(0, 120)}", "${prompt.slice(0, 120)}")
if card_old_legacy in text and "CLAW_GROUP_QUIET_REPLY: 群聊不刷中间态卡片" not in text:
    text = text.replace(card_old_legacy, card_new_legacy, 1)
    changed = True

# ── 3) onStart / onProgress 群聊全静默 ──
start_variants = [
    """\tconst onStart = cardId
\t\t? () => {
\t\t\t\tupdateCard(cardId!, `⏳ 正在执行...\\n\\n> ${text.slice(0, 120)}`, {
\t\t\t\t\ttitle: "处理中",
\t\t\t\t\tcolor: "wathet",
\t\t\t\t}).catch(() => {});
\t\t\t}
\t\t: undefined;""",
    """\tconst onStart = cardId
\t\t? () => {
\t\t\t\tupdateCard(cardId!, `⏳ 正在执行...\\n\\n> ${prompt.slice(0, 120)}`, {
\t\t\t\t\ttitle: "处理中",
\t\t\t\t\tcolor: "wathet",
\t\t\t\t}).catch(() => {});
\t\t\t}
\t\t: undefined;""",
]

start_new = """\tconst onStart = cardId && !isGroup
\t\t? () => {
\t\t\t\tupdateCard(cardId!, `⏳ 正在执行...\\n\\n> ${text.slice(0, 120)}`, {
\t\t\t\t\ttitle: "处理中",
\t\t\t\t\tcolor: "wathet",
\t\t\t\t}).catch(() => {});
\t\t\t}
\t\t: undefined;"""

start_new_legacy = start_new.replace("${text.slice(0, 120)}", "${prompt.slice(0, 120)}")

for old, new in [(start_variants[0], start_new), (start_variants[1], start_new_legacy)]:
    if old in text and "const onStart = cardId && !isGroup" not in text:
        text = text.replace(old, new, 1)
        changed = True
        break

prog_variants = [
    """\tconst onProgress = cardId
\t\t? (p: AgentProgress) => {
\t\t\t\t// CLAW_PROGRESS_QUIET: 思考阶段不刷新卡片，完成后一次性回复
\t\t\t\tif (p.phase === "thinking") return;
\t\t\t\tconst time = formatElapsed(p.elapsed);
\t\t\t\tconst phaseLabel = p.phase === "tool_call" ? "🔧 执行工具" : "💬 回复中";
\t\t\t\tconst snippet = p.snippet.split("\\n").filter((l) => l.trim()).slice(-4).join("\\n");
\t\t\t\tupdateCard(
\t\t\t\t\tcardId!,
\t\t\t\t\t`\\`\\`\\`\\n${snippet.slice(0, 300) || "..."}\\n\\`\\`\\``,
\t\t\t\t\t{ title: `${phaseLabel} · ${time}`, color: "wathet" },
\t\t\t\t).catch(() => {});
\t\t\t}
\t\t: undefined;""",
    """\tconst onProgress = cardId
\t\t? (p: AgentProgress) => {
\t\t\t\tconst time = formatElapsed(p.elapsed);
\t\t\t\tconst phaseLabel = p.phase === "thinking" ? "🤔 思考中" : p.phase === "tool_call" ? "🔧 执行工具" : "💬 回复中";
\t\t\t\tconst snippet = p.snippet.split("\\n").filter((l) => l.trim()).slice(-4).join("\\n");
\t\t\t\tupdateCard(
\t\t\t\t\tcardId!,
\t\t\t\t\t`\\`\\`\\`\\n${snippet.slice(0, 300) || "..."}\\n\\`\\`\\``,
\t\t\t\t\t{ title: `${phaseLabel} · ${time}`, color: "wathet" },
\t\t\t\t).catch(() => {});
\t\t\t}
\t\t: undefined;""",
]

prog_new = """\tconst onProgress = cardId && !isGroup
\t\t? (p: AgentProgress) => {
\t\t\t\t// CLAW_PROGRESS_QUIET: 思考阶段不刷新卡片，完成后一次性回复
\t\t\t\tif (p.phase === "thinking") return;
\t\t\t\tconst time = formatElapsed(p.elapsed);
\t\t\t\tconst phaseLabel = p.phase === "tool_call" ? "🔧 执行工具" : "💬 回复中";
\t\t\t\tconst snippet = p.snippet.split("\\n").filter((l) => l.trim()).slice(-4).join("\\n");
\t\t\t\tupdateCard(
\t\t\t\t\tcardId!,
\t\t\t\t\t`\\`\\`\\`\\n${snippet.slice(0, 300) || "..."}\\n\\`\\`\\``,
\t\t\t\t\t{ title: `${phaseLabel} · ${time}`, color: "wathet" },
\t\t\t\t).catch(() => {});
\t\t\t}
\t\t: undefined;"""

if "const onProgress = cardId && !isGroup" not in text and "CLAW_PROGRESS_DONE_GUARD" not in text:
    for old in prog_variants:
        if old in text:
            text = text.replace(old, prog_new, 1)
            changed = True
            break
    # onStart 已静默但 onProgress 未同步时（历史半应用状态）
    if not changed and "const onStart = cardId && !isGroup" in text and "const onProgress = cardId\n" in text:
        text = text.replace("const onProgress = cardId\n", "const onProgress = cardId && !isGroup\n", 1)
        changed = True

if not changed:
    if "CLAW_GROUP_QUIET_REPLY" in text:
        print("patch-claw-group-quiet-reply: 已应用，跳过")
        sys.exit(0)
    print("patch-claw-group-quiet-reply: 未找到可替换片段", file=sys.stderr)
    sys.exit(1)

server.write_text(text)
print("patch-claw-group-quiet-reply: 群聊权限静默 + 任务完成后一次性回复")
PY

chmod +x "${BASH_SOURCE[0]}"
