#!/usr/bin/env bash
# 「小组」旁观日志：入站消息在 @ 过滤之前落盘（含媒体下载），不起 Cursor
set -euo pipefail

PACK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLAW_INSTALL_DIR="${CLAW_INSTALL_DIR:-${PACK_ROOT}/claw}"
SERVER="${CLAW_INSTALL_DIR}/server.ts"
SRC="${PACK_ROOT}/templates/claw/xiaozu-spectator.ts"
DST="${CLAW_INSTALL_DIR}/xiaozu-spectator.ts"

if [[ ! -f "${SERVER}" ]]; then
  echo "跳过 patch-claw-xiaozu-spectator: 未找到 ${SERVER}"
  exit 0
fi

if [[ ! -f "${SRC}" ]]; then
  echo "patch-claw-xiaozu-spectator: 缺少 ${SRC}" >&2
  exit 1
fi

cp "${SRC}" "${DST}"
mkdir -p "${PACK_ROOT}/runtime/文档/小组旁观" "${PACK_ROOT}/runtime/文档/小组旁观/media"

python3 - "${SERVER}" <<'PY'
from pathlib import Path
import sys

server = Path(sys.argv[1])
text = server.read_text()
marker = "CLAW_XIAOZHU_SPECTATOR"

# 幂等：若已是「媒体直接下本地」版，只同步 ts 后跳过
if "媒体直接下本地" in text and marker in text:
    print("patch-claw-xiaozu-spectator: 已应用（含媒体），跳过")
    sys.exit(0)

# 旧版仅文字旁观：替换 hook 块
old_hook = '''\t\t\tlet { text: parsedText, imageKey, fileKey } = parseContent(messageType, content);

\t\t\t// CLAW_XIAOZHU_SPECTATOR: 「小组」旁观落盘（未 @ 也写；不起 Agent）
\t\t\ttry {
\t\t\t\tconst written = XiaozuSpectator.maybeAppendSpectator(defaultWorkspace, xiaozuSpectatorChatIds, {
\t\t\t\t\tchatId,
\t\t\t\t\tchatType,
\t\t\t\t\tmessageId,
\t\t\t\t\tmessageType,
\t\t\t\t\ttext: parsedText,
\t\t\t\t\tsenderOpenId,
\t\t\t\t\tthreadId,
\t\t\t\t});
\t\t\t\tif (written) console.log(`[旁观] 已写入 ${written}`);
\t\t\t} catch (e) {
\t\t\t\tconsole.warn("[旁观] 写入失败:", e);
\t\t\t}'''

new_hook = '''\t\t\tlet { text: parsedText, imageKey, fileKey, fileName } = parseContent(messageType, content);
\t\t\t// 补齐 media/video 等类型里的 key（parseContent 未覆盖时）
\t\t\tif ((!imageKey && !fileKey) && content) {
\t\t\t\ttry {
\t\t\t\t\tconst raw = JSON.parse(content) as Record<string, string>;
\t\t\t\t\timageKey = raw.image_key || imageKey;
\t\t\t\t\tfileKey = raw.file_key || fileKey;
\t\t\t\t\tfileName = raw.file_name || fileName;
\t\t\t\t} catch { /* ignore */ }
\t\t\t}

\t\t\t// CLAW_XIAOZHU_SPECTATOR: 「小组」旁观落盘（未 @ 也写；媒体直接下本地；不起 Agent）
\t\t\ttry {
\t\t\t\tlet mediaPath: string | undefined;
\t\t\t\tlet mediaKey: string | undefined;
\t\t\t\tconst need = XiaozuSpectator.shouldDownloadSpectatorMedia(
\t\t\t\t\txiaozuSpectatorChatIds,
\t\t\t\t\tchatId,
\t\t\t\t\tchatType,
\t\t\t\t\tmessageType,
\t\t\t\t\timageKey,
\t\t\t\t\tfileKey,
\t\t\t\t);
\t\t\t\tif (need) {
\t\t\t\t\tmediaKey = need.key;
\t\t\t\t\tconst ext = XiaozuSpectator.guessMediaExt(messageType, fileName, need.key);
\t\t\t\t\ttry {
\t\t\t\t\t\tmediaPath = await XiaozuSpectator.saveSpectatorMedia(
\t\t\t\t\t\t\tdefaultWorkspace,
\t\t\t\t\t\t\tmessageId,
\t\t\t\t\t\t\tneed.key,
\t\t\t\t\t\t\text,
\t\t\t\t\t\t\tasync () => {
\t\t\t\t\t\t\t\tconst response = await larkClient.im.messageResource.get({
\t\t\t\t\t\t\t\t\tpath: { message_id: messageId, file_key: need.key },
\t\t\t\t\t\t\t\t\tparams: { type: need.kind },
\t\t\t\t\t\t\t\t});
\t\t\t\t\t\t\t\treturn await readResponseBuffer(response);
\t\t\t\t\t\t\t},
\t\t\t\t\t\t);
\t\t\t\t\t\tconsole.log(`[旁观] 媒体已保存 ${mediaPath}`);
\t\t\t\t\t} catch (e) {
\t\t\t\t\t\tconsole.warn("[旁观] 媒体下载失败:", e);
\t\t\t\t\t}
\t\t\t\t}
\t\t\t\tconst written = XiaozuSpectator.maybeAppendSpectator(defaultWorkspace, xiaozuSpectatorChatIds, {
\t\t\t\t\tchatId,
\t\t\t\t\tchatType,
\t\t\t\t\tmessageId,
\t\t\t\t\tmessageType,
\t\t\t\t\ttext: parsedText || (mediaKey ? `[${messageType}: ${mediaKey}]` : ""),
\t\t\t\t\tsenderOpenId,
\t\t\t\t\tthreadId,
\t\t\t\t\tmediaKey,
\t\t\t\t\tmediaPath,
\t\t\t\t\tfileName,
\t\t\t\t});
\t\t\t\tif (written) console.log(`[旁观] 已写入 ${written}`);
\t\t\t} catch (e) {
\t\t\t\tconsole.warn("[旁观] 写入失败:", e);
\t\t\t}'''

if old_hook in text:
    text = text.replace(old_hook, new_hook, 1)
    server.write_text(text)
    print("patch-claw-xiaozu-spectator: 已升级为含媒体下载")
    sys.exit(0)

if marker in text:
    print("patch-claw-xiaozu-spectator: 已有标记但 hook 形态未知，请人工检查", file=sys.stderr)
    sys.exit(1)

# ── 全新安装：import + chatIds + hook ──
anchors = [
    'import * as EasyGoCmd from "./easygo-commands.js";',
    'import { createTopicSessionRepo } from "./topic-session.js"; // CLAW_TOPIC_SESSION',
    'import * as TopicAgent from "./topic-agent.js"; // CLAW_TOPIC_AGENT',
]
imp = 'import * as XiaozuSpectator from "./xiaozu-spectator.js"; // CLAW_XIAOZHU_SPECTATOR'
placed = False
for a in anchors:
    if a in text:
        text = text.replace(a, a + "\n" + imp, 1)
        placed = True
        break
if not placed:
    print("patch-claw-xiaozu-spectator: 无法定位 import 锚点", file=sys.stderr)
    sys.exit(1)

ws_anchor = "const defaultWorkspace = projectsConfig.projects[projectsConfig.default_project]?.path || ROOT;"
if "const topicSessionRepo = createTopicSessionRepo(defaultWorkspace); // CLAW_TOPIC_SESSION" in text:
    ws_anchor = "const topicSessionRepo = createTopicSessionRepo(defaultWorkspace); // CLAW_TOPIC_SESSION"
if ws_anchor not in text:
    print("patch-claw-xiaozu-spectator: 无法定位 defaultWorkspace/topicSessionRepo", file=sys.stderr)
    sys.exit(1)
text = text.replace(
    ws_anchor,
    ws_anchor
    + "\nconst xiaozuSpectatorChatIds = XiaozuSpectator.loadSpectatorChatIdsFromPack(); // CLAW_XIAOZHU_SPECTATOR",
    1,
)

hook_anchor = """\t\t\tlet { text: parsedText, imageKey, fileKey } = parseContent(messageType, content);

\t\t\tif (chatType === \"group\") {"""
if hook_anchor not in text:
    print("patch-claw-xiaozu-spectator: 无法定位 parseContent/@ 过滤锚点", file=sys.stderr)
    sys.exit(1)
text = text.replace(hook_anchor, new_hook + "\n\n\t\t\tif (chatType === \"group\") {", 1)
server.write_text(text)
print("patch-claw-xiaozu-spectator: 已应用（小组旁观落盘+媒体）")
PY
