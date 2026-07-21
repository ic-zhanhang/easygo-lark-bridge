#!/usr/bin/env bash
# Agent 完成后禁止 onProgress 再改卡片，并串行化卡片更新，避免「完成」被「执行工具」覆盖
set -euo pipefail

PACK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLAW_INSTALL_DIR="${CLAW_INSTALL_DIR:-${PACK_ROOT}/claw}"
SERVER="${CLAW_INSTALL_DIR}/server.ts"

if [[ ! -f "${SERVER}" ]]; then
  echo "跳过 patch-claw-progress-done-guard: 未找到 ${SERVER}"
  exit 0
fi

python3 - "${SERVER}" <<'PY'
from pathlib import Path
import sys

server = Path(sys.argv[1])
text = server.read_text()

if "CLAW_PROGRESS_DONE_GUARD" in text:
    print("patch-claw-progress-done-guard: 已应用，跳过")
    sys.exit(0)

# ── 1) onStart 前插入卡片更新串行化 + progressEnabled ──
anchor = "\t// runAgent 获取 session lock 后回调 onStart，更新卡片为\"处理中\""
insert = """\t// CLAW_PROGRESS_DONE_GUARD: 串行化卡片更新，完成后忽略迟到的 progress
\tlet progressEnabled = true;
\tlet cardUpdateChain: Promise<unknown> = Promise.resolve();
\tconst enqueueCardUpdate = (
\t\tmarkdown: string,
\t\theader?: { title?: string; color?: string },
\t) => {
\t\tcardUpdateChain = cardUpdateChain
\t\t\t.then(() => updateCard(cardId!, markdown, header))
\t\t\t.catch(() => ({ ok: false as const }));
\t\treturn cardUpdateChain;
\t};

\t// runAgent 获取 session lock 后回调 onStart，更新卡片为\"处理中\""""

if anchor not in text:
    print("patch-claw-progress-done-guard: 未找到 onStart 锚点", file=sys.stderr)
    sys.exit(1)
text = text.replace(anchor, insert, 1)

# ── 2) onStart：enqueue + isGroup 兼容 ──
start_variants = [
    """\tconst onStart = cardId
\t\t? () => {
\t\t\t\tupdateCard(cardId!, `⏳ 正在执行...\\n\\n> ${text.slice(0, 120)}`, {
\t\t\t\t\ttitle: "处理中",
\t\t\t\t\tcolor: "wathet",
\t\t\t\t}).catch(() => {});
\t\t\t}
\t\t: undefined;""",
    """\tconst onStart = cardId && !isGroup
\t\t? () => {
\t\t\t\tupdateCard(cardId!, `⏳ 正在执行...\\n\\n> ${text.slice(0, 120)}`, {
\t\t\t\t\ttitle: "处理中",
\t\t\t\t\tcolor: "wathet",
\t\t\t\t}).catch(() => {});
\t\t\t}
\t\t: undefined;""",
]
start_new = """\tconst onStart = cardId
\t\t? () => {
\t\t\t\tif (!progressEnabled) return;
\t\t\t\tenqueueCardUpdate(`⏳ 正在执行...\\n\\n> ${text.slice(0, 120)}`, {
\t\t\t\t\ttitle: "处理中",
\t\t\t\t\tcolor: "wathet",
\t\t\t\t}).catch(() => {});
\t\t\t}
\t\t: undefined;"""

if not any(v in text for v in start_variants):
    print("patch-claw-progress-done-guard: 未找到 onStart 块", file=sys.stderr)
    sys.exit(1)
for v in start_variants:
    if v in text:
        text = text.replace(v, start_new, 1)
        break

# ── 3) onProgress：progressEnabled + enqueueCardUpdate ──
prog_variants = [
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
    """\tconst onProgress = cardId && !isGroup
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
]
prog_new = """\tconst onProgress = cardId
\t\t? (p: AgentProgress) => {
\t\t\t\t// CLAW_PROGRESS_DONE_GUARD: 完成后忽略迟到 progress；保留思考中进度
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

if not any(v in text for v in prog_variants):
    print("patch-claw-progress-done-guard: 未找到 onProgress 块", file=sys.stderr)
    sys.exit(1)
for v in prog_variants:
    if v in text:
        text = text.replace(v, prog_new, 1)
        break

# ── 4) runAgent 返回后：等待队列、关闭 progress ──
after_agent_variants = [
    # Topic Session + resultWithNote（无 usage，在 runtime-tuning 之前）
    (
        """\t\tconst { result, quotaWarning, sessionRenewed } = await runAgent(workspace, prompt, { onProgress, onStart, topicKey });
\t\tconst resultWithNote = sessionRenewed
\t\t\t? `⚠️ 原 Topic Session 无法续聊，已自动开启新会话。\\n\\n${result}`
\t\t\t: result;
\t\tconst usedModel = quotaWarning ? "auto" : model;""",
        """\t\tconst { result, quotaWarning, sessionRenewed } = await runAgent(workspace, prompt, { onProgress, onStart, topicKey });
\t\tconst resultWithNote = sessionRenewed
\t\t\t? `⚠️ 原 Topic Session 无法续聊，已自动开启新会话。\\n\\n${result}`
\t\t\t: result;
\t\tprogressEnabled = false;
\t\tif (cardId) await cardUpdateChain.catch(() => {});
\t\tconst usedModel = quotaWarning ? "auto" : model;""",
    ),
    (
        """\t\tconst { result, quotaWarning, usage } = await runAgent(workspace, prompt, { onProgress, onStart, topicKey });
\t\tconst usedModel = quotaWarning ? "auto" : model;""",
        """\t\tconst { result, quotaWarning, usage } = await runAgent(workspace, prompt, { onProgress, onStart, topicKey });
\t\tprogressEnabled = false;
\t\tif (cardId) await cardUpdateChain.catch(() => {});
\t\tconst usedModel = quotaWarning ? "auto" : model;""",
    ),
    (
        """\t\tconst { result, quotaWarning } = await runAgent(workspace, prompt, { onProgress, onStart, topicKey });
\t\tconst usedModel = quotaWarning ? "auto" : model;""",
        """\t\tconst { result, quotaWarning } = await runAgent(workspace, prompt, { onProgress, onStart, topicKey });
\t\tprogressEnabled = false;
\t\tif (cardId) await cardUpdateChain.catch(() => {});
\t\tconst usedModel = quotaWarning ? "auto" : model;""",
    ),
]
matched = False
for after_agent, after_agent_new in after_agent_variants:
    if after_agent in text:
        text = text.replace(after_agent, after_agent_new, 1)
        matched = True
        break
if not matched:
    print("patch-claw-progress-done-guard: 未找到 runAgent 完成锚点", file=sys.stderr)
    sys.exit(1)

# ── 5) 格式重试不再刷 progress 中间态 ──
retry_old = "\t\t\t\tconst { result: retryResult } = await runAgent(workspace, retryPrompt, { onProgress });"
retry_new = "\t\t\t\tconst { result: retryResult } = await runAgent(workspace, retryPrompt, { onStart: undefined, onProgress: undefined });"
if retry_old in text:
    text = text.replace(retry_old, retry_new, 1)

server.write_text(text)
print("patch-claw-progress-done-guard: 完成后禁用 progress + 串行化卡片更新")
PY

chmod +x "${BASH_SOURCE[0]}"
