#!/usr/bin/env bash
# 启动 grace：首条 stream-json 前单独计时；有 stream 后才计 IDLE；用户任务 max 60min
set -euo pipefail

PACK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLAW_INSTALL_DIR="${CLAW_INSTALL_DIR:-${PACK_ROOT}/claw}"
SERVER="${CLAW_INSTALL_DIR}/server.ts"

if [[ ! -f "${SERVER}" ]]; then
  echo "跳过 patch-claw-agent-startup-grace: 未找到 ${SERVER}"
  exit 0
fi

python3 - "${SERVER}" <<'PY'
from pathlib import Path
import sys

server = Path(sys.argv[1])
text = server.read_text()

if "CLAW_AGENT_STARTUP_GRACE" in text:
    print("patch-claw-agent-startup-grace: 已应用，跳过")
    sys.exit(0)

if "CLAW_AGENT_TIMEOUT" not in text:
    print("patch-claw-agent-startup-grace: 需先应用 patch-claw-agent-timeout", file=sys.stderr)
    sys.exit(1)

replacements = [
(
"""const AGENT_DEFAULT_MAX_MS = 30 * 60 * 1000;
const AGENT_DEFAULT_IDLE_MS = 60 * 60 * 1000; // CLAW_RUNTIME_TUNING_IDLE: 空闲=无 stream 输出；工具阶段 onProgress 会刷新
const HEARTBEAT_AGENT_MAX_MS = 8 * 60 * 1000;
const HEARTBEAT_AGENT_IDLE_MS = 2 * 60 * 1000;

function isAgentTimeoutError(text: string): boolean {
\treturn /\\[TIMEOUT\\]|\\[IDLE\\]/i.test(text);
}""",
"""const AGENT_DEFAULT_MAX_MS = 60 * 60 * 1000;
const AGENT_DEFAULT_IDLE_MS = 60 * 60 * 1000; // CLAW_RUNTIME_TUNING_IDLE: 有 stream 后的空闲上限
const AGENT_DEFAULT_STARTUP_GRACE_MS = 5 * 60 * 1000; // CLAW_AGENT_STARTUP_GRACE: 首条 stream-json 前
const HEARTBEAT_AGENT_MAX_MS = 8 * 60 * 1000;
const HEARTBEAT_AGENT_IDLE_MS = 2 * 60 * 1000;
const HEARTBEAT_AGENT_STARTUP_GRACE_MS = 90 * 1000;

function isAgentTimeoutError(text: string): boolean {
\treturn /\\[TIMEOUT\\]|\\[IDLE\\]|\\[STARTUP\\]/i.test(text);
}""",
),
(
"""const AGENT_DEFAULT_MAX_MS = 30 * 60 * 1000;
const AGENT_DEFAULT_IDLE_MS = 15 * 60 * 1000; // CLAW_RUNTIME_TUNING_IDLE: 空闲=无 stream 输出；工具阶段 onProgress 会刷新
const HEARTBEAT_AGENT_MAX_MS = 8 * 60 * 1000;
const HEARTBEAT_AGENT_IDLE_MS = 2 * 60 * 1000;

function isAgentTimeoutError(text: string): boolean {
\treturn /\\[TIMEOUT\\]|\\[IDLE\\]/i.test(text);
}""",
"""const AGENT_DEFAULT_MAX_MS = 60 * 60 * 1000;
const AGENT_DEFAULT_IDLE_MS = 60 * 60 * 1000; // CLAW_RUNTIME_TUNING_IDLE: 有 stream 后的空闲上限
const AGENT_DEFAULT_STARTUP_GRACE_MS = 5 * 60 * 1000; // CLAW_AGENT_STARTUP_GRACE: 首条 stream-json 前
const HEARTBEAT_AGENT_MAX_MS = 8 * 60 * 1000;
const HEARTBEAT_AGENT_IDLE_MS = 2 * 60 * 1000;
const HEARTBEAT_AGENT_STARTUP_GRACE_MS = 90 * 1000;

function isAgentTimeoutError(text: string): boolean {
\treturn /\\[TIMEOUT\\]|\\[IDLE\\]|\\[STARTUP\\]/i.test(text);
}""",
),
(
"""\t\tonProgress?: (p: AgentProgress) => void;
\t\tmaxMs?: number;
\t\tidleMs?: number;
\t},
): Promise<{ result: string; sessionId?: string; usage?: { inputTokens?: number; outputTokens?: number } }> {""",
"""\t\tonProgress?: (p: AgentProgress) => void;
\t\tmaxMs?: number;
\t\tidleMs?: number;
\t\tstartupGraceMs?: number;
\t},
): Promise<{ result: string; sessionId?: string; usage?: { inputTokens?: number; outputTokens?: number } }> {""",
),
(
"""\t\tonProgress?: (p: AgentProgress) => void;
\t\tonStart?: () => void;
\t\tmaxMs?: number;
\t\tidleMs?: number;
\t\ttopicKey?: string;
\t},""",
"""\t\tonProgress?: (p: AgentProgress) => void;
\t\tonStart?: () => void;
\t\tmaxMs?: number;
\t\tidleMs?: number;
\t\tstartupGraceMs?: number;
\t\ttopicKey?: string;
\t},""",
),
(
"""\tconst execOpts = {
\t\tonProgress: opts?.onProgress,
\t\tmaxMs: opts?.maxMs,
\t\tidleMs: opts?.idleMs,
\t};""",
"""\tconst execOpts = {
\t\tonProgress: opts?.onProgress,
\t\tmaxMs: opts?.maxMs,
\t\tidleMs: opts?.idleMs,
\t\tstartupGraceMs: opts?.startupGraceMs,
\t};""",
),
(
"""\t\tlet done = false;
\t\tconst startTime = Date.now();
\t\tlet lastActivityTime = Date.now();
\t\tlet lastProgressTime = 0;
\t\tlet lineBuf = "";
\t\tlet usageInput: number | undefined;
\t\tlet usageOutput: number | undefined;
\t\tlet killTimer: ReturnType<typeof setTimeout> | null = null;
\t\tconst maxMs = opts?.maxMs ?? AGENT_DEFAULT_MAX_MS;
\t\tconst idleMs = opts?.idleMs ?? AGENT_DEFAULT_IDLE_MS;

\t\tfunction markActivity() {
\t\t\tlastActivityTime = Date.now();
\t\t}""",
"""\t\tlet done = false;
\t\tconst startTime = Date.now();
\t\tlet streamStarted = false;
\t\tlet lastActivityTime = Date.now();
\t\tlet lastProgressTime = 0;
\t\tlet lineBuf = "";
\t\tlet usageInput: number | undefined;
\t\tlet usageOutput: number | undefined;
\t\tlet killTimer: ReturnType<typeof setTimeout> | null = null;
\t\tconst maxMs = opts?.maxMs ?? AGENT_DEFAULT_MAX_MS;
\t\tconst idleMs = opts?.idleMs ?? AGENT_DEFAULT_IDLE_MS;
\t\tconst startupGraceMs = opts?.startupGraceMs ?? AGENT_DEFAULT_STARTUP_GRACE_MS;

\t\tfunction markStreamStarted() {
\t\t\tif (streamStarted) return;
\t\t\tstreamStarted = true;
\t\t\tlastActivityTime = Date.now();
\t\t}

\t\tfunction markActivity() {
\t\t\tlastActivityTime = Date.now();
\t\t}""",
),
(
"""\t\t\tif (now - startTime > maxMs) {
\t\t\t\tfailAgent(`[TIMEOUT] Agent 执行超过 ${formatElapsed(Math.round(maxMs / 1000))}`);
\t\t\t\treturn;
\t\t\t}
\t\t\tif (now - lastActivityTime > idleMs) {
\t\t\t\tfailAgent(`[IDLE] Agent 超过 ${formatElapsed(Math.round(idleMs / 1000))} 无响应，已终止`);
\t\t\t\treturn;
\t\t\t}""",
"""\t\t\tif (now - startTime > maxMs) {
\t\t\t\tfailAgent(`[TIMEOUT] Agent 执行超过 ${formatElapsed(Math.round(maxMs / 1000))}`);
\t\t\t\treturn;
\t\t\t}
\t\t\tif (!streamStarted) {
\t\t\t\tif (now - startTime > startupGraceMs) {
\t\t\t\t\tfailAgent(`[STARTUP] Agent 启动超过 ${formatElapsed(Math.round(startupGraceMs / 1000))} 仍无 stream 输出，已终止`);
\t\t\t\t\treturn;
\t\t\t\t}
\t\t\t} else if (now - lastActivityTime > idleMs) {
\t\t\t\tfailAgent(`[IDLE] Agent 超过 ${formatElapsed(Math.round(idleMs / 1000))} 无响应，已终止`);
\t\t\t\treturn;
\t\t\t}""",
),
(
"""\t\tfunction processLine(line: string) {
\t\t\tconst ev = tryParseJson(line);
\t\t\tif (!ev) return;
\t\t\tmarkActivity();

\t\t\tif (ev.session_id && !sessionId) sessionId = ev.session_id;""",
"""\t\tfunction processLine(line: string) {
\t\t\tconst ev = tryParseJson(line);
\t\t\tif (!ev) return;
\t\t\tif (ev.type) markStreamStarted();
\t\t\tmarkActivity();

\t\t\tif (ev.session_id && !sessionId) sessionId = ev.session_id;""",
),
(
"""\t\tchild.stdout!.on("data", (chunk: Buffer) => {
\t\t\tmarkActivity();
\t\t\tlineBuf += chunk.toString();""",
"""\t\tchild.stdout!.on("data", (chunk: Buffer) => {
\t\t\tif (streamStarted) markActivity();
\t\t\tlineBuf += chunk.toString();""",
),
(
"""\t\tchild.stderr!.on("data", (chunk: Buffer) => {
\t\t\tmarkActivity();
\t\t\tstderr += chunk.toString();
\t\t});""",
"""\t\tchild.stderr!.on("data", (chunk: Buffer) => {
\t\t\tif (streamStarted) markActivity();
\t\t\tstderr += chunk.toString();
\t\t});""",
),
]

changed = []
for i, (old, new) in enumerate(replacements):
    if old in text:
        text = text.replace(old, new, 1)
        changed.append(i + 1)

if "CLAW_AGENT_STARTUP_GRACE" not in text or "streamStarted" not in text:
    print(f"patch-claw-agent-startup-grace: 未完整应用 changed={changed}", file=sys.stderr)
    sys.exit(1)

server.write_text(text)
print(f"patch-claw-agent-startup-grace: 已应用启动 grace + stream 后 IDLE steps={changed}")
PY

chmod +x "${BASH_SOURCE[0]}"
