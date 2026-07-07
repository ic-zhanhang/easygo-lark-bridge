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
import re
import sys

server = Path(sys.argv[1])
text = server.read_text()

merge_fn = '''
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
'''

if "function mergeStreamText" not in text:
    anchor = "// 核心：spawn agent CLI，解析 stream-json，返回结果"
    if anchor not in text:
        print("patch-claw-dedupe: 无法定位插入点", file=sys.stderr)
        sys.exit(1)
    text = text.replace(anchor, merge_fn + "\n" + anchor, 1)

text2, n1 = re.subn(
    r"assistantBuf \+= c\.text;\s*\n(\s*)lastSegment \+= c\.text;",
    r"assistantBuf = mergeStreamText(assistantBuf, c.text);\n\1lastSegment = mergeStreamText(lastSegment, c.text);",
    text,
    count=1,
)
if n1 != 1:
    print("patch-claw-dedupe: 无法定位 assistant merge", file=sys.stderr)
    sys.exit(1)
text = text2

old_output = "\t\t\tconst output = finalSegment || resultText || strip(assistantBuf) || strip(stderr) || \"(无输出)\";"
new_output = "\t\t\t// result 事件为最终权威输出；流式片段仅作回退\n\t\t\tconst output = strip(resultText) || finalSegment || strip(assistantBuf) || strip(stderr) || \"(无输出)\";"
if old_output in text:
    text = text.replace(old_output, new_output, 1)
elif "strip(resultText) || finalSegment" not in text:
    print("patch-claw-dedupe: 无法定位 output priority", file=sys.stderr)
    sys.exit(1)

server.write_text(text)
print("patch-claw-dedupe: 已写入 mergeStreamText 修复")
PY

chmod +x "${BASH_SOURCE[0]}"
