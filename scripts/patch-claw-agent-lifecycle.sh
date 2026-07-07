#!/usr/bin/env bash
# 从 server.ts 拆出 agent-lifecycle 模块 + 优雅关停（SIGTERM 通知卡片）
set -euo pipefail

PACK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLAW_INSTALL_DIR="${CLAW_INSTALL_DIR:-${PACK_ROOT}/claw}"
SERVER="${CLAW_INSTALL_DIR}/server.ts"
SRC="${PACK_ROOT}/templates/claw/agent-lifecycle.ts"
DEST="${CLAW_INSTALL_DIR}/agent-lifecycle.ts"

if [[ ! -f "${SERVER}" ]]; then
  echo "跳过 patch-claw-agent-lifecycle: 未找到 ${SERVER}"
  exit 0
fi

cp "${SRC}" "${DEST}"

python3 - "${SERVER}" <<'PY'
from pathlib import Path
import sys

server = Path(sys.argv[1])
text = server.read_text()
marker = "CLAW_AGENT_LIFECYCLE"

if marker in text:
    print("patch-claw-agent-lifecycle: 已应用，跳过")
    sys.exit(0)

# ── import ──
gate_import = 'import * as PermissionGate from "./permission-gate.js"; // CLAW_PERMISSION_GATE'
lifecycle_import = gate_import + '\nimport * as AgentLifecycle from "./agent-lifecycle.js"; // CLAW_AGENT_LIFECYCLE'
if gate_import not in text:
    # fallback: topic-agent import
    gate_import = 'import * as TopicAgent from "./topic-agent.js"; // CLAW_TOPIC_AGENT'
    lifecycle_import = gate_import + '\nimport * as AgentLifecycle from "./agent-lifecycle.js"; // CLAW_AGENT_LIFECYCLE'
    if gate_import not in text:
        print("patch-claw-agent-lifecycle: 未找到 permission-gate/topic-agent import", file=sys.stderr)
        sys.exit(1)
text = text.replace(gate_import, lifecycle_import, 1)

# ── 替换 childPids / activeAgents / SIGTERM ──
old_block = """const childPids = new Set<number>();
// lockKey → 正在运行的 agent 子进程（用于 /stop 终止）
const activeAgents = new Map<string, { pid: number; kill: () => void }>();

process.on("SIGTERM", () => {
\tfor (const pid of childPids) {
\t\ttry { process.kill(pid, "SIGTERM"); } catch {}
\t}
\tprocess.exit(0);
});"""

new_block = """// CLAW_AGENT_LIFECYCLE: 子进程追踪与优雅关停见 agent-lifecycle.ts"""

if old_block not in text:
    print("patch-claw-agent-lifecycle: 无法定位 childPids/SIGTERM 块", file=sys.stderr)
    sys.exit(1)
text = text.replace(old_block, new_block, 1)

# ── execAgent 注册/注销 ──
old_register = """\t\tif (child.pid) {
\t\t\tchildPids.add(child.pid);
\t\t\tactiveAgents.set(lockKey, {
\t\t\t\tpid: child.pid,
\t\t\t\tkill: () => { try { child.kill("SIGTERM"); } catch {} },
\t\t\t});
\t\t}"""

new_register = """\t\tif (child.pid) {
\t\t\tAgentLifecycle.registerAgent(lockKey, {
\t\t\t\tpid: child.pid,
\t\t\t\tkill: () => { try { child.kill("SIGTERM"); } catch {} },
\t\t\t});
\t\t}"""

if old_register not in text:
    print("patch-claw-agent-lifecycle: 无法定位 execAgent 注册", file=sys.stderr)
    sys.exit(1)
text = text.replace(old_register, new_register, 1)

old_cleanup_pid = "\t\t\tif (child.pid) childPids.delete(child.pid);\n\t\t\tactiveAgents.delete(lockKey);"
new_cleanup_pid = "\t\t\tAgentLifecycle.unregisterAgent(lockKey);"
if old_cleanup_pid not in text:
    print("patch-claw-agent-lifecycle: 无法定位 execAgent cleanup", file=sys.stderr)
    sys.exit(1)
text = text.replace(old_cleanup_pid, new_cleanup_pid, 1)

# ── /stop 指令 ──
old_stop = "\t\tconst agent = activeAgents.get(lk);"
new_stop = "\t\tconst agent = AgentLifecycle.getActiveAgent(lk);"
if old_stop in text:
    text = text.replace(old_stop, new_stop, 1)

# ── 绑定 cardId + initGracefulShutdown（在 updateCard 定义之后）──
init_anchor = "// CLAW_UPDATE_CARD_RETRY: 与 replyCard 一致的网络重试"
init_insert = """// CLAW_AGENT_LIFECYCLE: SIGTERM 时通知活跃卡片
AgentLifecycle.initGracefulShutdown(async (cardId, markdown) => {
\tawait updateCard(cardId, markdown, { title: "服务重启", color: "orange" });
});

""" + init_anchor

if init_anchor not in text:
    print("patch-claw-agent-lifecycle: 无法定位 updateCard 锚点", file=sys.stderr)
    sys.exit(1)
if "initGracefulShutdown" not in text:
    text = text.replace(init_anchor, init_insert, 1)

# ── runAgent 前绑定 cardId ──
card_bind_old = '\tconsole.log(`[Agent] 调用 Cursor CLI workspace=${workspace} model=${model} card=${cardId}`);'
card_bind_new = """\tif (cardId) AgentLifecycle.setAgentCardId(currentLockKey, cardId);
\tconsole.log(`[Agent] 调用 Cursor CLI workspace=${workspace} model=${model} card=${cardId}`);"""
if card_bind_old in text and "setAgentCardId" not in text:
    text = text.replace(card_bind_old, card_bind_new, 1)

server.write_text(text)
print("patch-claw-agent-lifecycle: 已拆出 agent-lifecycle + 优雅关停")
PY

chmod +x "${BASH_SOURCE[0]}"
