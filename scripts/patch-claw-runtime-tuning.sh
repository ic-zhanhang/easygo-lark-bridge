#!/usr/bin/env bash
# IDLE 60min、usage 日志、启动 banner、停用 session 日记写入
set -euo pipefail

PACK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLAW_INSTALL_DIR="${CLAW_INSTALL_DIR:-${PACK_ROOT}/claw}"
SERVER="${CLAW_INSTALL_DIR}/server.ts"
MEMORY="${CLAW_INSTALL_DIR}/memory.ts"

if [[ ! -f "${SERVER}" ]]; then
  echo "跳过 patch-claw-runtime-tuning: 未找到 ${SERVER}"
  exit 0
fi

python3 - "${SERVER}" "${MEMORY}" <<'PY'
from pathlib import Path
import sys

server = Path(sys.argv[1])
memory = Path(sys.argv[2])
text = server.read_text()
changed = []

IDLE_60 = "const AGENT_DEFAULT_IDLE_MS = 60 * 60 * 1000; // CLAW_RUNTIME_TUNING_IDLE: 空闲=无 stream 输出；工具阶段 onProgress 会刷新"
IDLE_15 = "const AGENT_DEFAULT_IDLE_MS = 15 * 60 * 1000; // CLAW_RUNTIME_TUNING_IDLE: 空闲=无 stream 输出；工具阶段 onProgress 会刷新"
IDLE_8 = "const AGENT_DEFAULT_IDLE_MS = 8 * 60 * 1000; // 空闲=无 stream 输出；正常工具调用会持续刷新"

already_tuned = "CLAW_RUNTIME_TUNING_IDLE" in text

if "60 * 60 * 1000; // CLAW_RUNTIME_TUNING_IDLE" in text:
    pass
elif IDLE_15 in text:
    text = text.replace(IDLE_15, IDLE_60, 1)
    changed.append("IDLE 15min→60min")
elif IDLE_8 in text:
    text = text.replace(IDLE_8, IDLE_60, 1)
    changed.append("IDLE 60min")

if not already_tuned:

    old_sig = "): Promise<{ result: string; sessionId?: string }> {"
    new_sig = "): Promise<{ result: string; sessionId?: string; usage?: { inputTokens?: number; outputTokens?: number } }> {"
    if old_sig in text:
        text = text.replace(old_sig, new_sig, 1)

    old_vars = "\t\tlet lineBuf = \"\";\n\t\tlet killTimer:"
    new_vars = """\t\tlet lineBuf = "";
\t\tlet usageInput: number | undefined;
\t\tlet usageOutput: number | undefined;
\t\tlet killTimer:"""
    if old_vars in text:
        text = text.replace(old_vars, new_vars, 1)

    old_result = """\t\t\tcase "result":
\t\t\t\tif (ev.result != null) resultText = ev.result;
\t\t\t\tif (ev.subtype === "error" && ev.error) {
\t\t\t\t\tresultText = ev.error;
\t\t\t\t}
\t\t\t\tbreak;"""
    new_result = """\t\t\tcase "result":
\t\t\t\tif (ev.result != null) resultText = ev.result;
\t\t\t\tif (ev.subtype === "error" && ev.error) {
\t\t\t\t\tresultText = ev.error;
\t\t\t\t}
\t\t\t\tif (ev.usage && typeof ev.usage === "object") {
\t\t\t\t\tconst u = ev.usage as Record<string, unknown>;
\t\t\t\t\tusageInput = (u.inputTokens ?? u.input_tokens ?? u.prompt_tokens) as number | undefined;
\t\t\t\t\tusageOutput = (u.outputTokens ?? u.output_tokens ?? u.completion_tokens) as number | undefined;
\t\t\t\t}
\t\t\t\tbreak;"""
    if old_result in text:
        text = text.replace(old_result, new_result, 1)

    old_res = "\t\t\tres({ result: output, sessionId });"
    new_res = """\t\t\tif (usageInput != null || usageOutput != null) {
\t\t\t\tconsole.log(`[Agent] usage input=${usageInput ?? "?"} output=${usageOutput ?? "?"}`);
\t\t\t}
\t\t\tres({
\t\t\t\tresult: output,
\t\t\t\tsessionId,
\t\t\t\t...(usageInput != null || usageOutput != null
\t\t\t\t\t? { usage: { inputTokens: usageInput, outputTokens: usageOutput } }
\t\t\t\t\t: {}),
\t\t\t});"""
    if old_res in text:
        text = text.replace(old_res, new_res, 1)
        changed.append("usage 解析")

    old_run_sig = "): Promise<{ result: string; quotaWarning?: string }> {"
    new_run_sig = "): Promise<{ result: string; quotaWarning?: string; usage?: { inputTokens?: number; outputTokens?: number } }> {"
    idx = text.find("async function runAgent(")
    if idx >= 0 and old_run_sig in text[idx:idx + 800]:
        text = text[:idx] + text[idx:].replace(old_run_sig, new_run_sig, 1)

    old_log = "\t\tconsole.log(`[${new Date().toISOString()}] 完成 [${label}] model=${usedModel} elapsed=${elapsed} (${result.length} chars)`);"
    new_log = "\t\tconst tokLog = usage?.inputTokens != null ? ` inputTokens=${usage.inputTokens}` : \"\";\n\t\tconsole.log(`[${new Date().toISOString()}] 完成 [${label}] model=${usedModel} elapsed=${elapsed} (${result.length} chars)${tokLog}`);"
    if old_log in text:
        text = text.replace(old_log, new_log, 1)

    banner_old = """│  规则（每次会话自动加载）:
│    soul.mdc, agent-identity.mdc, user-context.mdc
│    workspace-rules.mdc, tools.mdc, memory-protocol.mdc
│    scheduler-protocol.mdc, heartbeat-protocol.mdc
│    cursor-capabilities.mdc
│  记忆索引: 全工作区文本文件（memory-tool.ts）"""
    banner_new = """│  规则: runtime/.cursor/rules/（6 条 alwaysApply + 按需 rule）
│  记忆索引: 仅 topics/、文档/（memory-tool.ts；无 MEMORY.md）"""
    if banner_old in text:
        text = text.replace(banner_old, banner_new, 1)
        changed.append("启动 banner")

# 兼容 topic-agent / no-resume 等后续 patch 的 usage 传播 fix-up
replacements = [
    (
        """\t\t\t\tconst { result, sessionId } = await execAgent(lockKey, workspace, primaryModel, prompt, {
\t\t\t\t\tsessionId: existingSessionId,
\t\t\t\t\t...execOpts,
\t\t\t\t});
\t\t\t\tif (sessionId && topicKeyForSession) {
\t\t\t\t\ttopicSessionRepo.set(topicKeyForSession, sessionId);
\t\t\t\t} else if (sessionId && CLAW_RESUME_SESSIONS) {
\t\t\t\t\tsetActiveSession(workspace, sessionId);
\t\t\t\t\tif (isNewSession) {
\t\t\t\t\t\tgenerateSessionTitle(workspace, sessionId, prompt, result);
\t\t\t\t\t}
\t\t\t\t}
\t\t\t\treturn { result, sessionRenewed };""",
        """\t\t\t\tconst { result, sessionId, usage } = await execAgent(lockKey, workspace, primaryModel, prompt, {
\t\t\t\t\tsessionId: existingSessionId,
\t\t\t\t\t...execOpts,
\t\t\t\t});
\t\t\t\tif (sessionId && topicKeyForSession) {
\t\t\t\t\ttopicSessionRepo.set(topicKeyForSession, sessionId);
\t\t\t\t} else if (sessionId && CLAW_RESUME_SESSIONS) {
\t\t\t\t\tsetActiveSession(workspace, sessionId);
\t\t\t\t\tif (isNewSession) {
\t\t\t\t\t\tgenerateSessionTitle(workspace, sessionId, prompt, result);
\t\t\t\t\t}
\t\t\t\t}
\t\t\t\treturn { result, usage, sessionRenewed };""",
        "runAgent 主路径 usage(topic session)",
    ),
    (
        "\t\tconst { result, quotaWarning } = await runAgent(workspace, prompt, { onProgress, onStart, topicKey });",
        "\t\tconst { result, quotaWarning, usage } = await runAgent(workspace, prompt, { onProgress, onStart, topicKey });",
        "handle usage 解构(topicKey)",
    ),
    (
        "\t\tconst { result, quotaWarning, sessionRenewed } = await runAgent(workspace, prompt, { onProgress, onStart, topicKey });",
        "\t\tconst { result, quotaWarning, usage, sessionRenewed } = await runAgent(workspace, prompt, { onProgress, onStart, topicKey });",
        "handle usage 解构(topicKey+sessionRenewed)",
    ),
    (
        "\t\tconst { result, quotaWarning } = await runAgent(workspace, prompt, { onProgress, onStart });",
        "\t\tconst { result, quotaWarning, usage } = await runAgent(workspace, prompt, { onProgress, onStart });",
        "handle usage 解构",
    ),
    (
        """\t\t\t\tconst { result, sessionId } = await execAgent(lockKey, workspace, primaryModel, prompt, {
\t\t\t\t\tsessionId: existingSessionId,
\t\t\t\t\t...execOpts,
\t\t\t\t});
\t\t\t\tif (sessionId && CLAW_RESUME_SESSIONS) {
\t\t\t\t\tsetActiveSession(workspace, sessionId);
\t\t\t\t\tif (isNewSession) {
\t\t\t\t\t\tgenerateSessionTitle(workspace, sessionId, prompt, result);
\t\t\t\t\t}
\t\t\t\t}
\t\t\t\treturn { result };""",
        """\t\t\t\tconst { result, sessionId, usage } = await execAgent(lockKey, workspace, primaryModel, prompt, {
\t\t\t\t\tsessionId: existingSessionId,
\t\t\t\t\t...execOpts,
\t\t\t\t});
\t\t\t\tif (sessionId && CLAW_RESUME_SESSIONS) {
\t\t\t\t\tsetActiveSession(workspace, sessionId);
\t\t\t\t\tif (isNewSession) {
\t\t\t\t\t\tgenerateSessionTitle(workspace, sessionId, prompt, result);
\t\t\t\t\t}
\t\t\t\t}
\t\t\t\treturn { result, usage };""",
        "runAgent 主路径 usage",
    ),
    (
        """\t\t\t\tconst { result, sessionId } = await execAgent(lockKey, workspace, primaryModel, prompt, {
\t\t\t\t\tsessionId: existingSessionId,
\t\t\t\t\t...execOpts,
\t\t\t\t});
\t\t\t\tif (sessionId) {
\t\t\t\t\tsetActiveSession(workspace, sessionId);
\t\t\t\t\tif (isNewSession) {
\t\t\t\t\t\tgenerateSessionTitle(workspace, sessionId, prompt, result);
\t\t\t\t\t}
\t\t\t\t}
\t\t\t\treturn { result };""",
        """\t\t\t\tconst { result, sessionId, usage } = await execAgent(lockKey, workspace, primaryModel, prompt, {
\t\t\t\t\tsessionId: existingSessionId,
\t\t\t\t\t...execOpts,
\t\t\t\t});
\t\t\t\tif (sessionId) {
\t\t\t\t\tsetActiveSession(workspace, sessionId);
\t\t\t\t\tif (isNewSession) {
\t\t\t\t\t\tgenerateSessionTitle(workspace, sessionId, prompt, result);
\t\t\t\t\t}
\t\t\t\t}
\t\t\t\treturn { result, usage };""",
        "runAgent 主路径 usage(无 resume)",
    ),
    (
        """\t\t\t\t\tconst { result, sessionId } = await execAgent(lockKey, workspace, primaryModel, prompt, execOpts);
\t\t\t\t\tif (sessionId && CLAW_RESUME_SESSIONS) {
\t\t\t\t\t\tsetActiveSession(workspace, sessionId);
\t\t\t\t\t\tgenerateSessionTitle(workspace, sessionId, prompt, result);
\t\t\t\t\t}
\t\t\t\t\treturn { result };""",
        """\t\t\t\t\tconst { result, sessionId, usage } = await execAgent(lockKey, workspace, primaryModel, prompt, execOpts);
\t\t\t\t\tif (sessionId && CLAW_RESUME_SESSIONS) {
\t\t\t\t\t\tsetActiveSession(workspace, sessionId);
\t\t\t\t\t\tgenerateSessionTitle(workspace, sessionId, prompt, result);
\t\t\t\t\t}
\t\t\t\t\treturn { result, usage };""",
        "runAgent 重试 usage",
    ),
    (
        """\t\t\t\t\tconst { result, sessionId: newSid } = await execAgent(lockKey, workspace, "auto", prompt, {
\t\t\t\t\t\tsessionId: fallbackSessionId,
\t\t\t\t\t\t...execOpts,
\t\t\t\t\t});
\t\t\t\t\tif (newSid && CLAW_RESUME_SESSIONS) {
\t\t\t\t\t\tsetActiveSession(workspace, newSid);
\t\t\t\t\t\tif (!fallbackSessionId) {
\t\t\t\t\t\t\tgenerateSessionTitle(workspace, newSid, prompt, result);
\t\t\t\t\t\t}
\t\t\t\t\t}
\t\t\t\t\treturn {
\t\t\t\t\t\tresult,
\t\t\t\t\t\tquotaWarning: `⚠️ **模型降级通知**\\n\\n${primaryModel} 欠费，本次已用 auto 完成。\\n\\n> ${e.message.slice(0, 100)}`,
\t\t\t\t\t};""",
        """\t\t\t\t\tconst { result, sessionId: newSid, usage } = await execAgent(lockKey, workspace, "auto", prompt, {
\t\t\t\t\t\tsessionId: fallbackSessionId,
\t\t\t\t\t\t...execOpts,
\t\t\t\t\t});
\t\t\t\t\tif (newSid && CLAW_RESUME_SESSIONS) {
\t\t\t\t\t\tsetActiveSession(workspace, newSid);
\t\t\t\t\t\tif (!fallbackSessionId) {
\t\t\t\t\t\t\tgenerateSessionTitle(workspace, newSid, prompt, result);
\t\t\t\t\t\t}
\t\t\t\t\t}
\t\t\t\t\treturn {
\t\t\t\t\t\tresult,
\t\t\t\t\t\tusage,
\t\t\t\t\t\tquotaWarning: `⚠️ **模型降级通知**\\n\\n${primaryModel} 欠费，本次已用 auto 完成。\\n\\n> ${e.message.slice(0, 100)}`,
\t\t\t\t\t};""",
        "runAgent 降级 usage",
    ),
]
for old, new, label in replacements:
    if old in text:
        text = text.replace(old, new, 1)
        changed.append(label)

if changed:
    server.write_text(text)
    print("patch-claw-runtime-tuning: " + ", ".join(changed))
else:
    print("patch-claw-runtime-tuning: server.ts 已应用，跳过")

if memory.exists() and "CLAW_NO_SESSION_LOG" not in memory.read_text():
    mem = memory.read_text()
    old_fn = """\tappendSessionLog(workspace: string, role: "user" | "assistant", content: string, model?: string): void {
\t\tconst logPath = resolve(this.sessionsDir, `${todayStr()}.jsonl`);
\t\tconst entry = JSON.stringify({
\t\t\tts: new Date().toISOString(),
\t\t\tworkspace,
\t\t\trole,
\t\t\tcontent: content.slice(0, 8000),
\t\t\t...(model && { model }),
\t\t});
\t\tappendFileSync(logPath, entry + "\\n");
\t}"""
    new_fn = """\tappendSessionLog(_workspace: string, _role: "user" | "assistant", _content: string, _model?: string): void {
\t\t// CLAW_NO_SESSION_LOG: 桥接层不维护 .cursor/sessions 日记（topics/ 已记录飞书对话）
\t}"""
    if old_fn in mem:
        mem = mem.replace(old_fn, new_fn, 1)
        memory.write_text(mem)
        print("patch-claw-runtime-tuning: 停用 session 日记")
    else:
        print("patch-claw-runtime-tuning: 无法定位 appendSessionLog", file=sys.stderr)
        sys.exit(1)
elif memory.exists():
    print("patch-claw-runtime-tuning: memory.ts 已应用，跳过")
PY

chmod +x "${BASH_SOURCE[0]}"
