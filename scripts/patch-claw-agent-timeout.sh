#!/usr/bin/env bash
# Agent 执行超时：硬上限 + 空闲超时，防止心跳/任务挂死占锁
set -euo pipefail

PACK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLAW_INSTALL_DIR="${CLAW_INSTALL_DIR:-${PACK_ROOT}/claw}"
SERVER="${CLAW_INSTALL_DIR}/server.ts"

if [[ ! -f "${SERVER}" ]]; then
  echo "跳过 patch-claw-agent-timeout: 未找到 ${SERVER}"
  exit 0
fi

python3 - "${SERVER}" <<'PY'
from pathlib import Path
import sys

server = Path(sys.argv[1])
text = server.read_text()

if "CLAW_AGENT_TIMEOUT" in text:
    print("patch-claw-agent-timeout: 已应用，跳过")
    sys.exit(0)

replacements = [
(
"const PROGRESS_INTERVAL = 2_000;",
"""const PROGRESS_INTERVAL = 2_000;

// CLAW_AGENT_TIMEOUT: 防止 Agent 挂死长期占锁（合盖/睡眠后子进程常无输出僵死）
const AGENT_DEFAULT_MAX_MS = 30 * 60 * 1000;
const AGENT_DEFAULT_IDLE_MS = 3 * 60 * 1000;
const HEARTBEAT_AGENT_MAX_MS = 8 * 60 * 1000;
const HEARTBEAT_AGENT_IDLE_MS = 2 * 60 * 1000;

function isAgentTimeoutError(text: string): boolean {
\treturn /\\[TIMEOUT\\]|\\[IDLE\\]/i.test(text);
}""",
),
(
"\t\tconst { result } = await runAgent(defaultWorkspace, prompt);",
"""\t\tconst { result } = await runAgent(defaultWorkspace, prompt, {
\t\t\tmaxMs: HEARTBEAT_AGENT_MAX_MS,
\t\t\tidleMs: HEARTBEAT_AGENT_IDLE_MS,
\t\t});""",
),
(
"""\topts?: {
\t\tsessionId?: string;
\t\tonProgress?: (p: AgentProgress) => void;
\t},""",
"""\topts?: {
\t\tsessionId?: string;
\t\tonProgress?: (p: AgentProgress) => void;
\t\tmaxMs?: number;
\t\tidleMs?: number;
\t},""",
),
(
"""\t\tonProgress?: (p: AgentProgress) => void;
\t\tonStart?: () => void;
\t},""",
"""\t\tonProgress?: (p: AgentProgress) => void;
\t\tonStart?: () => void;
\t\tmaxMs?: number;
\t\tidleMs?: number;
\t},""",
),
(
"""\t\tlet done = false;
\t\tconst startTime = Date.now();
\t\tlet lastProgressTime = 0;
\t\tlet lineBuf = "";

\t\tfunction cleanup() {
\t\t\tdone = true;
\t\t\tclearInterval(timer);
\t\t\tif (child.pid) childPids.delete(child.pid);
\t\t\tactiveAgents.delete(lockKey);
\t\t}""",
"""\t\tlet done = false;
\t\tconst startTime = Date.now();
\t\tlet lastActivityTime = Date.now();
\t\tlet lastProgressTime = 0;
\t\tlet lineBuf = "";
\t\tlet killTimer: ReturnType<typeof setTimeout> | null = null;
\t\tconst maxMs = opts?.maxMs ?? AGENT_DEFAULT_MAX_MS;
\t\tconst idleMs = opts?.idleMs ?? AGENT_DEFAULT_IDLE_MS;

\t\tfunction markActivity() {
\t\t\tlastActivityTime = Date.now();
\t\t}

\t\tfunction cleanup() {
\t\t\tdone = true;
\t\t\tclearInterval(timer);
\t\t\tif (killTimer) {
\t\t\t\tclearTimeout(killTimer);
\t\t\t\tkillTimer = null;
\t\t\t}
\t\t\tif (child.pid) childPids.delete(child.pid);
\t\t\tactiveAgents.delete(lockKey);
\t\t}

\t\tfunction failAgent(reason: string) {
\t\t\tif (done) return;
\t\t\tcleanup();
\t\t\tconsole.warn(`[Agent] ${reason} pid=${child.pid ?? "?"}`);
\t\t\ttry { child.kill("SIGTERM"); } catch {}
\t\t\tkillTimer = setTimeout(() => {
\t\t\t\ttry { if (child.pid) process.kill(child.pid, "SIGKILL"); } catch {}
\t\t\t}, 5000);
\t\t\treject(new Error(reason));
\t\t}""",
),
(
"""\t\tconst timer = setInterval(() => {
\t\t\tif (done) return;
\t\t\tconst now = Date.now();
\t\t\tif (opts?.onProgress && now - lastProgressTime >= PROGRESS_INTERVAL) {""",
"""\t\tconst timer = setInterval(() => {
\t\t\tif (done) return;
\t\t\tconst now = Date.now();
\t\t\tif (now - startTime > maxMs) {
\t\t\t\tfailAgent(`[TIMEOUT] Agent 执行超过 ${formatElapsed(Math.round(maxMs / 1000))}`);
\t\t\t\treturn;
\t\t\t}
\t\t\tif (now - lastActivityTime > idleMs) {
\t\t\t\tfailAgent(`[IDLE] Agent 超过 ${formatElapsed(Math.round(idleMs / 1000))} 无响应，已终止`);
\t\t\t\treturn;
\t\t\t}
\t\t\tif (opts?.onProgress && now - lastProgressTime >= PROGRESS_INTERVAL) {""",
),
(
"""\t\tfunction processLine(line: string) {
\t\t\tconst ev = tryParseJson(line);
\t\t\tif (!ev) return;

\t\t\tif (ev.session_id && !sessionId) sessionId = ev.session_id;""",
"""\t\tfunction processLine(line: string) {
\t\t\tconst ev = tryParseJson(line);
\t\t\tif (!ev) return;
\t\t\tmarkActivity();

\t\t\tif (ev.session_id && !sessionId) sessionId = ev.session_id;""",
),
(
"""\t\tchild.stdout!.on("data", (chunk: Buffer) => {
\t\t\tlineBuf += chunk.toString();""",
"""\t\tchild.stdout!.on("data", (chunk: Buffer) => {
\t\t\tmarkActivity();
\t\t\tlineBuf += chunk.toString();""",
),
(
"""\t\tchild.stderr!.on("data", (chunk: Buffer) => {
\t\t\tstderr += chunk.toString();
\t\t});""",
"""\t\tchild.stderr!.on("data", (chunk: Buffer) => {
\t\t\tmarkActivity();
\t\t\tstderr += chunk.toString();
\t\t});""",
),
(
"""\tconst primaryModel = config.CURSOR_MODEL;
\tconst lockKey = getLockKey(workspace);

\treturn withSessionLock(lockKey, async () => {""",
"""\tconst primaryModel = config.CURSOR_MODEL;
\tconst lockKey = getLockKey(workspace);
\tconst execOpts = {
\t\tonProgress: opts?.onProgress,
\t\tmaxMs: opts?.maxMs,
\t\tidleMs: opts?.idleMs,
\t};

\treturn withSessionLock(lockKey, async () => {""",
),
(
"""\t\t\t\tconst { result, sessionId } = await execAgent(lockKey, workspace, primaryModel, prompt, {
\t\t\t\t\tsessionId: existingSessionId,
\t\t\t\t\tonProgress: opts?.onProgress,
\t\t\t\t});""",
"""\t\t\t\tconst { result, sessionId } = await execAgent(lockKey, workspace, primaryModel, prompt, {
\t\t\t\t\tsessionId: existingSessionId,
\t\t\t\t\t...execOpts,
\t\t\t\t});""",
),
(
"if (existingSessionId && !isBillingError(e.message)) {",
"if (existingSessionId && !isBillingError(e.message) && !isAgentTimeoutError(e.message)) {",
),
(
"""\t\t\t\t\t\tconst { result, sessionId } = await execAgent(lockKey, workspace, primaryModel, prompt, {
\t\t\t\t\t\t\tonProgress: opts?.onProgress,
\t\t\t\t\t\t});""",
"""\t\t\t\t\t\tconst { result, sessionId } = await execAgent(lockKey, workspace, primaryModel, prompt, execOpts);""",
),
(
"""\t\t\t\t\t\tconst { result, sessionId: newSid } = await execAgent(lockKey, workspace, "auto", prompt, {
\t\t\t\t\t\t\tsessionId: fallbackSessionId,
\t\t\t\t\t\t\tonProgress: opts?.onProgress,
\t\t\t\t\t\t});""",
"""\t\t\t\t\t\tconst { result, sessionId: newSid } = await execAgent(lockKey, workspace, "auto", prompt, {
\t\t\t\t\t\t\tsessionId: fallbackSessionId,
\t\t\t\t\t\t\t...execOpts,
\t\t\t\t\t\t});""",
),
]

for i, (old, new) in enumerate(replacements):
    if old not in text:
        print(f"patch-claw-agent-timeout: 步骤 {i+1} 无法匹配，可能已部分 patch", file=sys.stderr)
        sys.exit(1)
    text = text.replace(old, new, 1)

server.write_text(text)
print("patch-claw-agent-timeout: 已应用 Agent 超时保护")
PY

chmod +x "${BASH_SOURCE[0]}"
