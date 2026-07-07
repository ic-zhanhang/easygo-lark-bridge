#!/usr/bin/env bash
# 禁用 --resume：每条飞书消息独立 Agent 会话，不累积对话历史
set -euo pipefail

PACK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="${PACK_ROOT}/config/assistant.env"
if [[ -f "${CONFIG_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${CONFIG_FILE}" 2>/dev/null || true
fi
CONFIG_FILE="${PACK_ROOT}/config/easygo.env"
if [[ -f "${CONFIG_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${CONFIG_FILE}" 2>/dev/null || true
fi

CLAW_INSTALL_DIR="${CLAW_INSTALL_DIR:-${PACK_ROOT}/claw}"
SERVER="${CLAW_INSTALL_DIR}/server.ts"

if [[ ! -f "${SERVER}" ]]; then
  echo "跳过 patch-claw-no-resume: 未找到 ${SERVER}"
  exit 0
fi

python3 - "${SERVER}" <<'PY'
from pathlib import Path
import sys

server = Path(sys.argv[1])
text = server.read_text()

marker = "CLAW_NO_SESSION_RESUME"

if marker in text:
    print("patch-claw-no-resume: 已应用，跳过")
    sys.exit(0)

const_insert_after = "} catch {}\n});\n\n// ── 项目配置"
const_block = """} catch {}
});

// CLAW_NO_SESSION_RESUME: 每条飞书消息独立会话，不用 --resume
const CLAW_RESUME_SESSIONS = false;

// ── 项目配置"""

if const_insert_after not in text:
    print("patch-claw-no-resume: 无法定位 config 块", file=sys.stderr)
    sys.exit(1)
text = text.replace(const_insert_after, const_block, 1)

get_old = """function getActiveSessionId(workspace: string): string | undefined {
\treturn sessionsStore.get(workspace)?.active || undefined;
}"""
get_new = """function getActiveSessionId(workspace: string): string | undefined {
\tif (!CLAW_RESUME_SESSIONS) return undefined;
\treturn sessionsStore.get(workspace)?.active || undefined;
}"""
if get_old not in text:
    print("patch-claw-no-resume: 无法定位 getActiveSessionId", file=sys.stderr)
    sys.exit(1)
text = text.replace(get_old, get_new, 1)

set_old = """function setActiveSession(workspace: string, sessionId: string, summary?: string): void {
\tlet ws = sessionsStore.get(workspace);"""
set_new = """function setActiveSession(workspace: string, sessionId: string, summary?: string): void {
\tif (!CLAW_RESUME_SESSIONS) return;
\tlet ws = sessionsStore.get(workspace);"""
if set_old not in text:
    print("patch-claw-no-resume: 无法定位 setActiveSession", file=sys.stderr)
    sys.exit(1)
text = text.replace(set_old, set_new, 1)

load_old = '\t\tconsole.log(`[Session] 从磁盘恢复 ${sessionsStore.size} 个工作区会话`);\n\t} catch {}'
load_new = """\t\tconsole.log(`[Session] 从磁盘恢复 ${sessionsStore.size} 个工作区会话`);
\t\tif (!CLAW_RESUME_SESSIONS) {
\t\t\tfor (const ws of sessionsStore.values()) ws.active = null;
\t\t\tconsole.log("[Session] 无 resume 模式：不恢复 active 会话");
\t\t}
\t} catch {}"""
if load_old not in text:
    print("patch-claw-no-resume: 无法定位 loadSessionsFromDisk", file=sys.stderr)
    sys.exit(1)
text = text.replace(load_old, load_new, 1)

# runAgent 内三处 setActiveSession + generateSessionTitle
text = text.replace(
    """\t\t\t\tif (sessionId) {
\t\t\t\t\tsetActiveSession(workspace, sessionId);
\t\t\t\t\tif (isNewSession) {
\t\t\t\t\t\tgenerateSessionTitle(workspace, sessionId, prompt, result);
\t\t\t\t\t}
\t\t\t\t}""",
    """\t\t\t\tif (sessionId && CLAW_RESUME_SESSIONS) {
\t\t\t\t\tsetActiveSession(workspace, sessionId);
\t\t\t\t\tif (isNewSession) {
\t\t\t\t\t\tgenerateSessionTitle(workspace, sessionId, prompt, result);
\t\t\t\t\t}
\t\t\t\t}""",
    1,
)

text = text.replace(
    """\t\t\t\t\t\tif (sessionId) {
\t\t\t\t\t\t\tsetActiveSession(workspace, sessionId);
\t\t\t\t\t\t\tgenerateSessionTitle(workspace, sessionId, prompt, result);
\t\t\t\t\t\t}""",
    """\t\t\t\t\t\tif (sessionId && CLAW_RESUME_SESSIONS) {
\t\t\t\t\t\t\tsetActiveSession(workspace, sessionId);
\t\t\t\t\t\t\tgenerateSessionTitle(workspace, sessionId, prompt, result);
\t\t\t\t\t\t}""",
    1,
)

text = text.replace(
    """\t\t\t\t\t\tif (newSid) {
\t\t\t\t\t\t\tsetActiveSession(workspace, newSid);
\t\t\t\t\t\t\tif (!fallbackSessionId) {
\t\t\t\t\t\t\t\tgenerateSessionTitle(workspace, newSid, prompt, result);
\t\t\t\t\t\t\t}
\t\t\t\t\t\t}""",
    """\t\t\t\t\t\tif (newSid && CLAW_RESUME_SESSIONS) {
\t\t\t\t\t\t\tsetActiveSession(workspace, newSid);
\t\t\t\t\t\t\tif (!fallbackSessionId) {
\t\t\t\t\t\t\t\tgenerateSessionTitle(workspace, newSid, prompt, result);
\t\t\t\t\t\t\t}
\t\t\t\t\t\t}""",
    1,
)

text = text.replace(
    "│  直连: 飞书消息 → Cursor CLI（stream-json + --resume）",
    "│  直连: 飞书消息 → Cursor CLI（stream-json，独立会话）",
    1,
)

server.write_text(text)
print("patch-claw-no-resume: 已禁用 --resume")
PY

chmod +x "${BASH_SOURCE[0]}"
