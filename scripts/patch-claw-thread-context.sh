#!/usr/bin/env bash
# 非小组群话题：注入当前 thread 消息 + 硬隔离「小组旁观」路径
set -euo pipefail

PACK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLAW_INSTALL_DIR="${CLAW_INSTALL_DIR:-${PACK_ROOT}/claw}"
SERVER="${CLAW_INSTALL_DIR}/server.ts"
SRC="${PACK_ROOT}/templates/claw/thread-context.ts"
DST="${CLAW_INSTALL_DIR}/thread-context.ts"
MEMORY="${CLAW_INSTALL_DIR}/memory.ts"

if [[ ! -f "${SERVER}" ]]; then
  echo "跳过 patch-claw-thread-context: 未找到 ${SERVER}"
  exit 0
fi

if [[ ! -f "${SRC}" ]]; then
  echo "patch-claw-thread-context: 缺少 ${SRC}" >&2
  exit 1
fi

cp "${SRC}" "${DST}"

python3 - "${SERVER}" "${MEMORY}" <<'PY'
from pathlib import Path
import sys

server = Path(sys.argv[1])
memory_path = Path(sys.argv[2])
text = server.read_text()
marker = "CLAW_THREAD_CONTEXT"

if marker in text:
    print("patch-claw-thread-context: server 已应用，跳过")
else:
    # import
    imp_anchor = 'import * as XiaozuSpectator from "./xiaozu-spectator.js"; // CLAW_XIAOZHU_SPECTATOR'
    imp = 'import * as XiaozuSpectator from "./xiaozu-spectator.js"; // CLAW_XIAOZHU_SPECTATOR\nimport * as ThreadContext from "./thread-context.js"; // CLAW_THREAD_CONTEXT'
    if imp_anchor not in text:
        # fallback: topic-session import
        alt = 'import { createTopicSessionRepo'
        idx = text.find(alt)
        if idx < 0:
            print("patch-claw-thread-context: 无法定位 import 锚点", file=sys.stderr)
            sys.exit(1)
        # insert after first import block line containing topic-session
        line_end = text.find("\n", idx)
        text = text[: line_end + 1] + 'import * as ThreadContext from "./thread-context.js"; // CLAW_THREAD_CONTEXT\n' + text[line_end + 1 :]
    else:
        text = text.replace(imp_anchor, imp, 1)

    # pass threadId into handleInner
    old_call = "\treturn handleInner(text, messageId, chatId, chatType, messageType, content, senderOpenId, topicKey, xiaozuChatId, xiaozuCursorMode, xiaozuCursorIntent);"
    new_call = "\treturn handleInner(text, messageId, chatId, chatType, messageType, content, senderOpenId, topicKey, xiaozuChatId, xiaozuCursorMode, xiaozuCursorIntent, threadId); // CLAW_THREAD_CONTEXT"
    if old_call not in text:
        print("patch-claw-thread-context: 无法定位 handleInner 调用", file=sys.stderr)
        sys.exit(1)
    text = text.replace(old_call, new_call, 1)

    old_sig = """async function handleInner(
\ttext: string,
\tmessageId: string,
\tchatId: string,
\tchatType: string,
\tmessageType: string,
\tcontent: string,
\tsenderOpenId?: string,
\ttopicKey?: string,
\txiaozuChatId?: string,
\txiaozuCursorMode?: \"ask\" | \"agent\",
\txiaozuCursorIntent?: string,
): Promise<void> {"""
    new_sig = """async function handleInner(
\ttext: string,
\tmessageId: string,
\tchatId: string,
\tchatType: string,
\tmessageType: string,
\tcontent: string,
\tsenderOpenId?: string,
\ttopicKey?: string,
\txiaozuChatId?: string,
\txiaozuCursorMode?: \"ask\" | \"agent\",
\txiaozuCursorIntent?: string,
\tthreadId?: string, // CLAW_THREAD_CONTEXT
): Promise<void> {"""
    if old_sig not in text:
        print("patch-claw-thread-context: 无法定位 handleInner 签名", file=sys.stderr)
        sys.exit(1)
    text = text.replace(old_sig, new_sig, 1)

    # inject before xiaozu task turn / agent run — after unknown slash handler, before xiaozuTaskTurn
    old_xz = """\tlet xiaozuTaskTurn: ReturnType<typeof xiaozuGroupAgent.buildTaskTurn> | undefined;
\tconst resolvedXiaozuCursorMode: \"ask\" | \"agent\" | undefined = xiaozuChatId
\t\t? (xiaozuCursorMode ?? \"ask\")
\t\t: undefined;
\tif (xiaozuChatId) {"""

    new_xz = """\t// CLAW_THREAD_CONTEXT: 非小组群话题注入当前 thread；硬隔离小组旁观
\tif (!xiaozuChatId) {
\t\tif (chatType === \"group\" && threadId) {
\t\t\tconst prefix = await ThreadContext.buildThreadContextPrefix(larkClient, {
\t\t\t\tchatId,
\t\t\t\tthreadId,
\t\t\t\tcurrentMessageId: messageId,
\t\t\t});
\t\t\tif (prefix) prompt = `${prefix}\\n${prompt}`;
\t\t} else {
\t\t\tprompt = `${ThreadContext.isolationBanner(chatId, threadId)}\\n\\n[当前用户请求]\\n${prompt}`;
\t\t}
\t}

\tlet xiaozuTaskTurn: ReturnType<typeof xiaozuGroupAgent.buildTaskTurn> | undefined;
\tconst resolvedXiaozuCursorMode: \"ask\" | \"agent\" | undefined = xiaozuChatId
\t\t? (xiaozuCursorMode ?? \"ask\")
\t\t: undefined;
\tif (xiaozuChatId) {"""

    if old_xz not in text:
        print("patch-claw-thread-context: 无法定位 xiaozuTaskTurn 锚点", file=sys.stderr)
        sys.exit(1)
    text = text.replace(old_xz, new_xz, 1)

    server.write_text(text)
    print("patch-claw-thread-context: server 已注入话题上下文 + 隔离横幅")

# memory: skip 小组旁观 / 小组日报 dirs even under 文档/
if memory_path.exists():
    mem = memory_path.read_text()
    m2 = "CLAW_MEMORY_XIAOZHU_ISOLATE"
    if m2 in mem:
        print("patch-claw-thread-context: memory 隔离已应用，跳过")
    else:
        old = '\tprivate static readonly SKIP_DIRS = new Set([".git", ".cursor", "node_modules", "sessions", "inbox", "relay-bot", "vector-index", "dist", "build", "__pycache__", "easygo", "frontend", "target"]); // CLAW_MEMORY_SCOPE'
        new = '\tprivate static readonly SKIP_DIRS = new Set([".git", ".cursor", "node_modules", "sessions", "inbox", "relay-bot", "vector-index", "dist", "build", "__pycache__", "easygo", "frontend", "target", "小组旁观", "小组日报"]); // CLAW_MEMORY_SCOPE · CLAW_MEMORY_XIAOZHU_ISOLATE'
        if old not in mem:
            # try without comment
            print("patch-claw-thread-context: 无法定位 SKIP_DIRS（memory）", file=sys.stderr)
            sys.exit(1)
        mem = mem.replace(old, new, 1)
        memory_path.write_text(mem)
        print("patch-claw-thread-context: memory 已排除 小组旁观/小组日报")
PY

chmod +x "${BASH_SOURCE[0]}"
echo "patch-claw-thread-context: 完成"
