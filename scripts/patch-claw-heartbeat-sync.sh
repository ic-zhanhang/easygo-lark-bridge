#!/usr/bin/env bash
# 心跳直接跑 sync-dev-repos.sh，不依赖 Agent 执行 git pull
set -euo pipefail

PACK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLAW_INSTALL_DIR="${CLAW_INSTALL_DIR:-${PACK_ROOT}/claw}"
SERVER="${CLAW_INSTALL_DIR}/server.ts"

if [[ ! -f "${SERVER}" ]]; then
  echo "跳过 patch-claw-heartbeat-sync: 未找到 ${SERVER}"
  exit 0
fi

python3 - "${SERVER}" <<'PY'
from pathlib import Path
import sys

server = Path(sys.argv[1])
text = server.read_text()

marker = "runSyncDevReposReport"
if marker in text:
    print("patch-claw-heartbeat-sync: 已应用，跳过")
    sys.exit(0)

old = """// ── 心跳系统 ──────────────────────────────────────
const heartbeat = new HeartbeatRunner({
\tconfig: {
\t\tenabled: true,
\t\teveryMs: 30 * 60 * 1000,
\t\tworkspaceDir: defaultWorkspace,
\t},"""

# 可能已被 patch-claw-profile 改过
old_profile = """// ── 心跳系统 ──────────────────────────────────────
const heartbeat = new HeartbeatRunner({
\tconfig: {
\t\tenabled: true, // CLAW_PROFILE dev: 10–22 点每 2h
\t\teveryMs: 2 * 60 * 60 * 1000,
\t\tworkspaceDir: defaultWorkspace,
\t\tactiveHours: { start: 10, end: 22 },
\t},"""

new_block = """// ── 心跳系统 ──────────────────────────────────────
const SYNC_DEV_REPOS_SCRIPT = resolve(ROOT, "scripts/sync-dev-repos.sh");

async function runSyncDevReposReport(): Promise<string> {
\tif (!existsSync(SYNC_DEV_REPOS_SCRIPT)) {
\t\tconsole.warn("[心跳] 未找到 sync-dev-repos.sh，跳过本地 pull");
\t\treturn "HEARTBEAT_OK";
\t}
\tconst proc = Bun.spawn(["bash", SYNC_DEV_REPOS_SCRIPT], {
\t\tcwd: defaultWorkspace,
\t\tstdout: "pipe",
\t\tstderr: "pipe",
\t\tenv: { ...process.env, RUNTIME_DIR: defaultWorkspace },
\t});
\tconst [stdout, stderr] = await Promise.all([
\t\tnew Response(proc.stdout).text(),
\t\tnew Response(proc.stderr).text(),
\t]);
\tconst code = await proc.exited;
\tconst report = stdout.trim() || stderr.trim();
\tconsole.log(`[心跳] sync-dev-repos exit=${code} (${report.length} chars)`);
\tif (code === 0 && report.includes("全部仓库已是最新")) return "HEARTBEAT_OK";
\tif (report) return report;
\treturn code === 0 ? "HEARTBEAT_OK" : `同步脚本失败 (exit ${code})`;
}

const heartbeat = new HeartbeatRunner({
\tconfig: {
\t\tenabled: true, // CLAW_PROFILE dev: 10–22 点每 2h
\t\teveryMs: 2 * 60 * 60 * 1000,
\t\tworkspaceDir: defaultWorkspace,
\t\tactiveHours: { start: 10, end: 22 },
\t},"""

old_profile_linux = """// ── 心跳系统 ──────────────────────────────────────
const heartbeat = new HeartbeatRunner({
\tconfig: {
\t\tenabled: true, // CLAW_PROFILE linux: 08–23 点每 2h
\t\teveryMs: 2 * 60 * 60 * 1000,
\t\tworkspaceDir: defaultWorkspace,
\t\tactiveHours: { start: 8, end: 23 },
\t},"""

new_block_linux = new_block.replace(
    "CLAW_PROFILE dev: 10–22 点每 2h",
    "CLAW_PROFILE linux: 08–23 点每 2h",
).replace("start: 10, end: 22", "start: 8, end: 23")

if old_profile in text:
    text = text.replace(old_profile, new_block, 1)
elif old_profile_linux in text:
    text = text.replace(old_profile_linux, new_block_linux, 1)
elif old in text:
    text = text.replace(old, new_block.replace("CLAW_PROFILE dev: 10–22 点每 2h\n\t\t", "").replace("everyMs: 2 * 60 * 60 * 1000", "everyMs: 30 * 60 * 1000").replace("\n\t\tactiveHours: { start: 10, end: 22 },", ""), 1)
else:
    print("patch-claw-heartbeat-sync: 无法定位心跳块", file=sys.stderr)
    sys.exit(1)

on_old = """\tonExecute: async (prompt: string) => {
\t\tmemory?.appendSessionLog(defaultWorkspace, "user", "[心跳检查] " + prompt.slice(0, 200), config.CURSOR_MODEL);
\t\tconst { result } = await runAgent(defaultWorkspace, prompt);
\t\tmemory?.appendSessionLog(defaultWorkspace, "assistant", result.slice(0, 3000), config.CURSOR_MODEL);
\t\treturn result;
\t},"""

on_old_timeout = """\tonExecute: async (prompt: string) => {
\t\tmemory?.appendSessionLog(defaultWorkspace, "user", "[心跳检查] " + prompt.slice(0, 200), config.CURSOR_MODEL);
\t\tconst { result } = await runAgent(defaultWorkspace, prompt, {
\t\t\tmaxMs: HEARTBEAT_AGENT_MAX_MS,
\t\t\tidleMs: HEARTBEAT_AGENT_IDLE_MS,
\t\t});
\t\tmemory?.appendSessionLog(defaultWorkspace, "assistant", result.slice(0, 3000), config.CURSOR_MODEL);
\t\treturn result;
\t},"""

on_new = """\tonExecute: async (_prompt: string) => {
\t\tconst result = await runSyncDevReposReport();
\t\tmemory?.appendSessionLog(defaultWorkspace, "user", "[心跳检查] sync-dev-repos", config.CURSOR_MODEL);
\t\tmemory?.appendSessionLog(defaultWorkspace, "assistant", result.slice(0, 3000), config.CURSOR_MODEL);
\t\treturn result;
\t},"""

if on_old_timeout in text:
    text = text.replace(on_old_timeout, on_new, 1)
elif on_old in text:
    text = text.replace(on_old, on_new, 1)
else:
    print("patch-claw-heartbeat-sync: 无法定位 onExecute", file=sys.stderr)
    sys.exit(1)

server.write_text(text)
print("patch-claw-heartbeat-sync: 心跳已改为直接 sync-dev-repos")
PY

chmod +x "${BASH_SOURCE[0]}"
