#!/usr/bin/env bash
# 群 @ 匹配 + bot open_id 启动重试 + 群聊懒加载（达妮娅/秧秧通用）
set -euo pipefail

PACK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLAW_INSTALL_DIR="${CLAW_INSTALL_DIR:-${PACK_ROOT}/claw}"
SERVER="${CLAW_INSTALL_DIR}/server.ts"

if [[ ! -f "${SERVER}" ]]; then
  echo "跳过 patch-claw-mention-id-fix: 未找到 ${SERVER}"
  exit 0
fi

python3 - "${SERVER}" <<'PY'
from pathlib import Path
import re
import sys

server = Path(sys.argv[1])
text = server.read_text()
changed = False

# fix-up：启动日志不打印 open_id（已打补丁的环境也适用）
old_bot_log = "\t\t\t\tconsole.log(`[Bot] open_id=${id} name=${name ?? \"?\"}`);"
new_bot_log = "\t\t\t\tconsole.log(`[Bot] 已就绪 name=${name ?? \"?\"}`);"
if old_bot_log in text:
    text = text.replace(old_bot_log, new_bot_log, 1)
    changed = True

if "CLAW_MENTION_ID_FIX" in text and "CLAW_BOT_OPENID_RETRY" in text:
    if changed:
        server.write_text(text)
        print("patch-claw-mention-id-fix: 启动日志不再打印 open_id")
    else:
        print("patch-claw-mention-id-fix: 已应用，跳过")
    sys.exit(0)

if "let botOpenId: string | undefined;" not in text:
    print("patch-claw-mention-id-fix: 未找到 botOpenId", file=sys.stderr)
    sys.exit(1)

if "botDisplayName" not in text:
    text = text.replace(
        "let botOpenId: string | undefined;",
        "let botOpenId: string | undefined;\nlet botDisplayName: string | undefined; // CLAW_MENTION_ID_FIX",
        1,
    )
    changed = True

old_type = "type FeishuMention = { key: string; id: { open_id?: string }; name: string };"
new_helpers = """type FeishuMention = { key: string; id: string | { open_id?: string }; name: string };

// CLAW_MENTION_ID_FIX: 飞书 mentions.id 可能是 string；群 member_id 与 bot/v3/info open_id 可能不一致
function getMentionOpenId(m: FeishuMention): string | undefined {
\tconst id = m.id;
\tif (!id) return undefined;
\tif (typeof id === "string") return id;
\treturn id.open_id;
}

function isBotMentioned(mentions: FeishuMention[]): boolean {
\tif (!botOpenId && !botDisplayName) return false;
\treturn mentions.some((m) => {
\t\tconst mid = getMentionOpenId(m);
\t\tif (mid && botOpenId && mid === botOpenId) return true;
\t\tif (botDisplayName && m.name === botDisplayName) return true;
\t\treturn false;
\t});
}"""

if old_type in text:
    text = text.replace(old_type, new_helpers, 1)
    changed = True

# 整段替换 fetchBotOpenId（兼容 vanilla / 旧补丁）
fetch_new = """async function fetchBotOpenId(): Promise<string | undefined> {
\t// CLAW_BOT_OPENID_RETRY + CLAW_MENTION_ID_FIX: 开机网络未就绪时重试；记录 app_name 供 @ 匹配
\tconst maxAttempts = 12;
\tfor (let attempt = 1; attempt <= maxAttempts; attempt++) {
\t\ttry {
\t\t\tconst r = (await larkClient.request({
\t\t\t\turl: "/open-apis/bot/v3/info",
\t\t\t\tmethod: "GET",
\t\t\t})) as { bot?: { open_id?: string; app_name?: string } };
\t\t\tconst id = r.bot?.open_id;
\t\t\tconst name = r.bot?.app_name;
\t\t\tif (name) botDisplayName = name;
\t\t\tif (id) {
\t\t\t\tconsole.log(`[Bot] 已就绪 name=${name ?? "?"}`);
\t\t\t\treturn id;
\t\t\t}
\t\t} catch (e) {
\t\t\tconst delayMs = Math.min(30_000, 2_000 * attempt);
\t\t\tconsole.warn(`[Bot] 获取 open_id 失败 (${attempt}/${maxAttempts})，${delayMs}ms 后重试:`, e);
\t\t\tif (attempt < maxAttempts) await sleepMs(delayMs);
\t\t}
\t}
\tconsole.warn("[Bot] 无法获取 open_id，群聊 @ 过滤将不可用（已重试）");
\treturn undefined;
}"""

if "CLAW_BOT_OPENID_RETRY" not in text:
    m = re.search(r"async function fetchBotOpenId\(\): Promise<string \| undefined> \{.*?\n\}", text, re.S)
    if not m:
        print("patch-claw-mention-id-fix: 未找到 fetchBotOpenId", file=sys.stderr)
        sys.exit(1)
    text = text[: m.start()] + fetch_new + text[m.end() :]
    changed = True

old_check = "\t\t\t\tconst mentionedBot = mentions.some((m) => m.id.open_id === botOpenId);"
new_check = "\t\t\t\tconst mentionedBot = isBotMentioned(mentions);"
if old_check in text:
    text = text.replace(old_check, new_check, 1)
    changed = True

old_group = """\t\t\tif (chatType === "group") {
\t\t\t\tif (!botOpenId) {
\t\t\t\t\tconsole.log("[群聊] 忽略：bot open_id 未就绪");
\t\t\t\t\treturn;
\t\t\t\t}"""

new_group = """\t\t\tif (chatType === "group") {
\t\t\t\tif (!botOpenId) {
\t\t\t\t\tbotOpenId = await fetchBotOpenId();
\t\t\t\t\tif (!botOpenId) {
\t\t\t\t\t\tconsole.log("[群聊] 忽略：bot open_id 未就绪");
\t\t\t\t\t\treturn;
\t\t\t\t\t}
\t\t\t\t}"""

if old_group in text:
    text = text.replace(old_group, new_group, 1)
    changed = True

old_start = "fetchBotOpenId().then((id) => { botOpenId = id; });"
new_start = """void (async () => {
\tbotOpenId = await fetchBotOpenId();
})();"""
if old_start in text:
    text = text.replace(old_start, new_start, 1)
    changed = True

if not changed:
    print("patch-claw-mention-id-fix: 无需变更")
    sys.exit(0)

server.write_text(text)
print("patch-claw-mention-id-fix: @ 匹配 + open_id 重试 + 群聊懒加载")
PY

chmod +x "${BASH_SOURCE[0]}"
