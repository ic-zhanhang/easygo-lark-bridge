#!/usr/bin/env bash
# 修复 feishu-cursor-claw stream-json 回复重复（--stream-partial-output 累积全文被追加两次）
set -euo pipefail

PACK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="${PACK_ROOT}/config/easygo.env"
if [[ -f "${CONFIG_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${CONFIG_FILE}"
fi

CLAW_INSTALL_DIR="${CLAW_INSTALL_DIR:-${PACK_ROOT}/claw}"
SERVER="${CLAW_INSTALL_DIR}/server.ts"

if [[ ! -f "${SERVER}" ]]; then
  echo "跳过 patch-claw-dedupe: 未找到 ${SERVER}"
  exit 0
fi

if grep -q "function mergeStreamText" "${SERVER}"; then
  echo "patch-claw-dedupe: 已应用，跳过"
  exit 0
fi

python3 - "${SERVER}" <<'PY'
from pathlib import Path
import sys

server = Path(sys.argv[1])
text = server.read_text()

old_basename = '''function basename(p: string): string {
\tconst parts = p.split("/");
\treturn parts[parts.length - 1] || p;
}

// 核心：spawn agent CLI，解析 stream-json，返回结果'''

new_basename = '''function basename(p: string): string {
\tconst parts = p.split("/");
\treturn parts[parts.length - 1] || p;
}

/** --stream-partial-output 可能重复发送累积全文，合并时避免整段重复追加 */
function mergeStreamText(current: string, incoming: string): string {
\tif (!incoming) return current;
\tif (!current) return incoming;
\tif (incoming === current) return current;
\tif (incoming.startsWith(current)) return incoming;
\tif (current.startsWith(incoming)) return current;
\tif (current.endsWith(incoming)) return current;
\treturn current + incoming;
}

// 核心：spawn agent CLI，解析 stream-json，返回结果'''

old_assistant = '''\t\t\t\t\tif (c.type === "text" && c.text) {
\t\t\t\t\t\tassistantBuf += c.text;
\t\t\t\t\t\tlastSegment += c.text;
\t\t\t\t\t}'''

new_assistant = '''\t\t\t\t\tif (c.type === "text" && c.text) {
\t\t\t\t\t\tassistantBuf = mergeStreamText(assistantBuf, c.text);
\t\t\t\t\t\tlastSegment = mergeStreamText(lastSegment, c.text);
\t\t\t\t\t}'''

old_output = '''\t\t\t// 优先取最后一段 assistant 回复（最终结果），避免输出中间过程
\t\t\tconst finalSegment = strip(lastSegment);
\t\t\tconst output = finalSegment || resultText || strip(assistantBuf) || strip(stderr) || "(无输出)";'''

new_output = '''\t\t\t// result 事件为最终权威输出；流式片段仅作回退
\t\t\tconst finalSegment = strip(lastSegment);
\t\t\tconst output = strip(resultText) || finalSegment || strip(assistantBuf) || strip(stderr) || "(无输出)";'''

for label, old, new in [
    ("basename block", old_basename, new_basename),
    ("assistant merge", old_assistant, new_assistant),
    ("output priority", old_output, new_output),
]:
    if old not in text:
        print(f"patch-claw-dedupe: 无法定位 {label}，请手动检查 server.ts", file=sys.stderr)
        sys.exit(1)
    text = text.replace(old, new, 1)

server.write_text(text)
print("patch-claw-dedupe: 已写入 mergeStreamText 修复")
PY

chmod +x "${BASH_SOURCE[0]}"
