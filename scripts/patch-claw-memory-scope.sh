#!/usr/bin/env bash
# 记忆索引仅覆盖 文档/；排除 easygo/frontend/MEMORY.md；禁用蒸馏写入长期记忆
set -euo pipefail

PACK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLAW_INSTALL_DIR="${CLAW_INSTALL_DIR:-${PACK_ROOT}/claw}"
SERVER="${CLAW_INSTALL_DIR}/server.ts"
MEMORY="${CLAW_INSTALL_DIR}/memory.ts"

if [[ ! -f "${MEMORY}" ]]; then
  echo "跳过 patch-claw-memory-scope: 未找到 ${MEMORY}"
  exit 0
fi

python3 - "${SERVER}" "${MEMORY}" <<'PY'
from pathlib import Path
import sys

server = Path(sys.argv[1])
memory_path = Path(sys.argv[2])

# ── memory.ts: 限定索引范围 + 不再注入 MEMORY.md ──
mem = memory_path.read_text()
marker = "CLAW_MEMORY_SCOPE"

if marker not in mem:
    import re
    skip_pat = r'\tprivate static readonly SKIP_DIRS = new Set\(\[[^\]]+\]\);'
    m = re.search(skip_pat, mem)
    if not m:
        print("patch-claw-memory-scope: 无法定位 SKIP_DIRS", file=sys.stderr)
        sys.exit(1)
    new_skip = '\tprivate static readonly SKIP_DIRS = new Set([".git", ".cursor", "node_modules", "sessions", "inbox", "relay-bot", "vector-index", "dist", "build", "__pycache__", "easygo", "frontend", "target"]); // CLAW_MEMORY_SCOPE\n\tprivate static readonly INDEX_PREFIXES = ["文档"]; // CLAW_MEMORY_SCOPE'
    mem = mem[: m.start()] + new_skip + mem[m.end() :]

    old_walk = """\t\twalk(root);
\t\treturn result;
\t}"""

    new_walk = """\t\tfor (const prefix of MemoryManager.INDEX_PREFIXES) {
\t\t\tconst sub = resolve(root, prefix);
\t\t\tif (!existsSync(sub)) continue;
\t\t\twalk(sub);
\t\t}
\t\treturn result;
\t}"""

    if old_walk not in mem:
        print("patch-claw-memory-scope: 无法定位 walk(root)", file=sys.stderr)
        sys.exit(1)
    mem = mem.replace(old_walk, new_walk, 1)

    old_recent = """\t\tconst memPath = resolve(this.config.workspaceDir, ".cursor/MEMORY.md");
\t\tif (existsSync(memPath)) {
\t\t\tconst content = readFileSync(memPath, "utf-8");
\t\t\tif (content.trim().length > 50) {
\t\t\t\tparts.push(`## MEMORY.md（长期记忆）\\n${content.slice(0, 2000)}`);
\t\t\t}
\t\t}

\t\treturn parts.join("\\n\\n");"""

    new_recent = """\t\t// CLAW_MEMORY_SCOPE: 不注入 MEMORY.md（新对话模式）

\t\treturn parts.join("\\n\\n");"""

    if old_recent not in mem:
        print("patch-claw-memory-scope: 无法定位 getRecentSummary MEMORY 块", file=sys.stderr)
        sys.exit(1)
    mem = mem.replace(old_recent, new_recent, 1)

    memory_path.write_text(mem)
    print("patch-claw-memory-scope: memory.ts 索引范围已限定为 文档/")
else:
    print("patch-claw-memory-scope: memory.ts 已应用，跳过")

# ── server.ts: 禁用蒸馏写入 MEMORY.md ──
if server.exists():
    text = server.read_text()
    if "CLAW_DISTILL_DISABLED" not in text:
        old_distill = """async function runDistillCycle(): Promise<void> {
\tconst now = new Date();
\tconst hour = now.getHours();
\tif (hour < 6 || hour > 23) return; // 深夜不执行

\ttry {
\t\tconsole.log("[蒸馏] 开始每日对话蒸馏...");"""

        new_distill = """async function runDistillCycle(): Promise<void> {
\t// CLAW_DISTILL_DISABLED: 新对话模式，不自动蒸馏写入 MEMORY.md
\tconsole.log("[蒸馏] 已禁用（新对话模式，不维护 MEMORY.md）");
\treturn;

\tconst now = new Date();
\tconst hour = now.getHours();
\tif (hour < 6 || hour > 23) return; // 深夜不执行

\ttry {
\t\tconsole.log("[蒸馏] 开始每日对话蒸馏...");"""

        if old_distill not in text:
            print("patch-claw-memory-scope: 无法定位 runDistillCycle", file=sys.stderr)
            sys.exit(1)
        text = text.replace(old_distill, new_distill, 1)

        old_files = '\t".cursor/MEMORY.md", ".cursor/HEARTBEAT.md", ".cursor/TASKS.md",'
        new_files = '\t".cursor/HEARTBEAT.md", ".cursor/TASKS.md", // CLAW_MEMORY_SCOPE: 不引导加载 MEMORY.md'
        if old_files in text:
            text = text.replace(old_files, new_files, 1)

        server.write_text(text)
        print("patch-claw-memory-scope: server.ts 已禁用蒸馏 + 移除 MEMORY.md 引导")
    else:
        print("patch-claw-memory-scope: server.ts 已应用，跳过")
PY

chmod +x "${BASH_SOURCE[0]}"
