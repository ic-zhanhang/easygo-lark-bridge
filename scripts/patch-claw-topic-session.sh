#!/usr/bin/env bash
# Topic Session + EasyGo 斜杠 + Group Topic Only 入站门控
set -euo pipefail

PACK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLAW_INSTALL_DIR="${CLAW_INSTALL_DIR:-${PACK_ROOT}/claw}"
SERVER="${CLAW_INSTALL_DIR}/server.ts"

if [[ ! -f "${SERVER}" ]]; then
  echo "跳过 patch-claw-topic-session: 未找到 ${SERVER}"
  exit 0
fi

cp "${PACK_ROOT}/templates/claw/topic-session.ts" "${CLAW_INSTALL_DIR}/topic-session.ts"
cp "${PACK_ROOT}/templates/claw/easygo-commands.ts" "${CLAW_INSTALL_DIR}/easygo-commands.ts"

python3 - "${SERVER}" <<'PY'
from pathlib import Path
import sys

server = Path(sys.argv[1])
text = server.read_text()

if "CLAW_TOPIC_SESSION" in text:
    print("patch-claw-topic-session: 已应用，跳过")
    sys.exit(0)

# ── imports ──
anchor_imp = 'import * as TopicAgent from "./topic-agent.js"; // CLAW_TOPIC_AGENT'
if anchor_imp not in text:
    print("patch-claw-topic-session: 需要先应用 patch-claw-topic-agent", file=sys.stderr)
    sys.exit(1)

text = text.replace(
    anchor_imp,
    anchor_imp
    + '\nimport { createTopicSessionRepo } from "./topic-session.js"; // CLAW_TOPIC_SESSION'
    + '\nimport * as EasyGoCmd from "./easygo-commands.js";',
    1,
)

# ── repo after defaultWorkspace ──
ws_anchor = "const defaultWorkspace = projectsConfig.projects[projectsConfig.default_project]?.path || ROOT;"
if ws_anchor not in text:
    print("patch-claw-topic-session: 无法定位 defaultWorkspace", file=sys.stderr)
    sys.exit(1)
text = text.replace(
    ws_anchor,
    ws_anchor
    + "\nconst topicSessionRepo = createTopicSessionRepo(defaultWorkspace); // CLAW_TOPIC_SESSION",
    1,
)

# ── runAgent: Topic Session resume instead of workspace active ──
old_sess = """\t\t\tconst existingSessionId = getActiveSessionId(workspace);
\t\t\tconst isNewSession = !existingSessionId;

\t\t\ttry {
\t\t\t\tconst { result, sessionId } = await execAgent(lockKey, workspace, primaryModel, prompt, {
\t\t\t\t\tsessionId: existingSessionId,
\t\t\t\t\t...execOpts,
\t\t\t\t});
\t\t\t\tif (sessionId && CLAW_RESUME_SESSIONS) {
\t\t\t\t\tsetActiveSession(workspace, sessionId);
\t\t\t\t\tif (isNewSession) {
\t\t\t\t\t\tgenerateSessionTitle(workspace, sessionId, prompt, result);
\t\t\t\t\t}
\t\t\t\t}
\t\t\t\treturn { result };
\t\t\t} catch (err) {
\t\t\t\tconst e = err instanceof Error ? err : new Error(String(err));

\t\t\t\tif (existingSessionId && !isBillingError(e.message) && !isAgentTimeoutError(e.message)) {
\t\t\t\t\tconsole.warn(`[重试] 会话可能过期，重新创建: ${e.message.slice(0, 100)}`);
\t\t\t\t\tarchiveAndResetSession(workspace);
\t\t\t\t\ttry {
\t\t\t\t\t\tconst { result, sessionId } = await execAgent(lockKey, workspace, primaryModel, prompt, execOpts);
\t\t\t\t\t\tif (sessionId && CLAW_RESUME_SESSIONS) {
\t\t\t\t\t\t\tsetActiveSession(workspace, sessionId);
\t\t\t\t\t\t\tgenerateSessionTitle(workspace, sessionId, prompt, result);
\t\t\t\t\t\t}
\t\t\t\t\t\treturn { result };
\t\t\t\t\t} catch (retryErr) {
\t\t\t\t\t\tconst re = retryErr instanceof Error ? retryErr : new Error(String(retryErr));
\t\t\t\t\t\tif (!isBillingError(re.message)) throw re;
\t\t\t\t\t}
\t\t\t\t}"""

new_sess = """\t\t\tconst topicKeyForSession = opts?.topicKey;
\t\t\tconst existingSessionId = topicKeyForSession
\t\t\t\t? topicSessionRepo.get(topicKeyForSession)
\t\t\t\t: (CLAW_RESUME_SESSIONS ? getActiveSessionId(workspace) : undefined);
\t\t\tconst isNewSession = !existingSessionId;
\t\t\tlet sessionRenewed = false;

\t\t\ttry {
\t\t\t\tconst { result, sessionId, usage } = await execAgent(lockKey, workspace, primaryModel, prompt, {
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
\t\t\t\treturn { result, sessionRenewed };
\t\t\t} catch (err) {
\t\t\t\tconst e = err instanceof Error ? err : new Error(String(err));

\t\t\t\tif (existingSessionId && !isBillingError(e.message) && !isAgentTimeoutError(e.message)) {
\t\t\t\t\tconsole.warn(`[重试] Topic Session 可能过期，重新创建: ${e.message.slice(0, 100)}`);
\t\t\t\t\tif (topicKeyForSession) topicSessionRepo.clear(topicKeyForSession);
\t\t\t\t\telse archiveAndResetSession(workspace);
\t\t\t\t\tsessionRenewed = true;
\t\t\t\t\ttry {
\t\t\t\t\t\tconst { result, sessionId } = await execAgent(lockKey, workspace, primaryModel, prompt, execOpts);
\t\t\t\t\t\tif (sessionId && topicKeyForSession) {
\t\t\t\t\t\t\ttopicSessionRepo.set(topicKeyForSession, sessionId);
\t\t\t\t\t\t} else if (sessionId && CLAW_RESUME_SESSIONS) {
\t\t\t\t\t\t\tsetActiveSession(workspace, sessionId);
\t\t\t\t\t\t\tgenerateSessionTitle(workspace, sessionId, prompt, result);
\t\t\t\t\t\t}
\t\t\t\t\t\treturn { result, sessionRenewed };
\t\t\t\t\t} catch (retryErr) {
\t\t\t\t\t\tconst re = retryErr instanceof Error ? retryErr : new Error(String(retryErr));
\t\t\t\t\t\tif (!isBillingError(re.message)) throw re;
\t\t\t\t\t}
\t\t\t\t}"""

if old_sess not in text:
    print("patch-claw-topic-session: 无法定位 runAgent 会话块", file=sys.stderr)
    sys.exit(1)
text = text.replace(old_sess, new_sess, 1)

# return type may need sessionRenewed — also update Promise type if present
# widen runAgent return type for sessionRenewed
for a, b in [
    (
        "): Promise<{ result: string; quotaWarning?: string }> {",
        "): Promise<{ result: string; quotaWarning?: string; sessionRenewed?: boolean }> {",
    ),
    (
        "): Promise<{ result: string; quotaWarning?: string; usage?: { inputTokens?: number; outputTokens?: number } }> {",
        "): Promise<{ result: string; quotaWarning?: string; usage?: { inputTokens?: number; outputTokens?: number }; sessionRenewed?: boolean }> {",
    ),
]:
    if a in text:
        text = text.replace(a, b, 1)
        break

# ── EasyGo slash + reset early in handleInner (after permission, before upstream /help) ──
# Insert before "// /help →"
help_marker = "\t// /help → 显示所有可用指令"
easygo_slash = """\t// CLAW_TOPIC_SESSION: EasyGo 斜杠白名单（先于上游全量指令）
\t{
\t\tconst slash = EasyGoCmd.parseEasyGoSlash(text);
\t\tif (slash.kind === "help") {
\t\t\tawait replyCard(messageId, EasyGoCmd.easyGoHelpText(), { title: "EasyGo 帮助", color: "blue" });
\t\t\treturn;
\t\t}
\t\tif (slash.kind === "reset") {
\t\t\tif (topicKey) topicSessionRepo.clear(topicKey);
\t\t\telse archiveAndResetSession(defaultWorkspace);
\t\t\tawait replyCard(messageId, EasyGoCmd.RESET_REPLY, { title: "新会话", color: "blue" });
\t\t\treturn;
\t\t}
\t\tif (slash.kind === "unknown") {
\t\t\tawait replyCard(messageId, EasyGoCmd.unknownSlashReply(slash.cmd), { title: "未知指令", color: "orange" });
\t\t\treturn;
\t\t}
\t\t// heartbeat / stop → 落入下方既有处理器
\t}

\t// /help → 显示所有可用指令"""

if help_marker not in text:
    print("patch-claw-topic-session: 无法定位 /help 标记", file=sys.stderr)
    sys.exit(1)
if "CLAW_TOPIC_SESSION: EasyGo 斜杠" not in text:
    text = text.replace(help_marker, easygo_slash, 1)

# ── notify on sessionRenewed after runAgent ──
run_ret_variants = [
    (
        "\t\tconst { result, quotaWarning } = await runAgent(workspace, prompt, { onProgress, onStart, topicKey });",
        """\t\tconst { result, quotaWarning, sessionRenewed } = await runAgent(workspace, prompt, { onProgress, onStart, topicKey });
\t\tconst resultWithNote = sessionRenewed
\t\t\t? `⚠️ 原 Topic Session 无法续聊，已自动开启新会话。\\n\\n${result}`
\t\t\t: result;""",
    ),
    (
        "\t\tconst { result, quotaWarning, usage } = await runAgent(workspace, prompt, { onProgress, onStart, topicKey });",
        """\t\tconst { result, quotaWarning, usage, sessionRenewed } = await runAgent(workspace, prompt, { onProgress, onStart, topicKey });
\t\tconst resultWithNote = sessionRenewed
\t\t\t? `⚠️ 原 Topic Session 无法续聊，已自动开启新会话。\\n\\n${result}`
\t\t\t: result;""",
    ),
]
for run_ret_old, run_ret_new in run_ret_variants:
    if run_ret_old in text:
        text = text.replace(run_ret_old, run_ret_new, 1)
        text = text.replace("await updateCard(cardId, result,", "await updateCard(cardId, resultWithNote,", 1)
        text = text.replace("await replyCard(messageId, result,", "await replyCard(messageId, resultWithNote,", 1)
        break

# ── dispatcher: Group Topic Only via EasyGoCmd + reject p2p ──
gate_old = """\t\t\t// CLAW_GROUP_TOPIC_GATE: 仅对已 @Bot 的消息要求话题；未 @ 已在上方静默忽略
\t\t\tif (chatType === "group" && !threadId) {
\t\t\t\tconsole.log("[群聊] 忽略：已 @Bot 但无话题 thread_id");
\t\t\t\treturn;
\t\t\t}"""

gate_new = """\t\t\t// CLAW_TOPIC_SESSION + CLAW_GROUP_TOPIC_GATE: Group Topic Only
\t\t\t{
\t\t\t\tconst gate = EasyGoCmd.gateInboundMessage(chatType, threadId);
\t\t\t\tif (gate.action === "reject") {
\t\t\t\t\tconsole.log(`[入站] 拒绝: ${gate.reason}`);
\t\t\t\t\tawait replyCard(messageId, gate.reply, { title: gate.reason === "no_thread" ? "请使用话题" : "仅群话题", color: "orange" });
\t\t\t\t\treturn;
\t\t\t\t}
\t\t\t}"""

if gate_old in text:
    text = text.replace(gate_old, gate_new, 1)
else:
    # insert before topicKey if gate missing
    tk = "\t\t\tconst topicKey = TopicAgent.getTopicKey(chatType, threadId, senderOpenId);"
    if tk in text and "gateInboundMessage" not in text:
        text = text.replace(tk, gate_new + "\n\n" + tk, 1)

# banner
text = text.replace(
    "│  直连: 飞书消息 → Cursor CLI（stream-json，独立会话）",
    "│  直连: 飞书消息 → Cursor CLI（Topic Session --resume）",
    1,
)

server.write_text(text)
print("patch-claw-topic-session: Topic Session + EasyGo 斜杠 + Group Topic Only")
PY

chmod +x "${BASH_SOURCE[0]}"
