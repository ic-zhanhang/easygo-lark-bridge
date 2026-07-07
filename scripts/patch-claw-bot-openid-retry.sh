#!/usr/bin/env bash
# 启动时网络未就绪会导致 fetchBotOpenId 一次失败 → 群聊 @ 消息全部被忽略；加重试与懒加载
set -euo pipefail

PACK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLAW_INSTALL_DIR="${CLAW_INSTALL_DIR:-${PACK_ROOT}/claw}"
SERVER="${CLAW_INSTALL_DIR}/server.ts"

if [[ ! -f "${SERVER}" ]]; then
  echo "跳过 patch-claw-bot-openid-retry: 未找到 ${SERVER}"
  exit 0
fi

python3 - "${SERVER}" <<'PY'
from pathlib import Path
import sys

server = Path(sys.argv[1])
text = server.read_text()

if "CLAW_BOT_OPENID_RETRY" in text:
    print("patch-claw-bot-openid-retry: 已应用，跳过")
    sys.exit(0)

old_fetch = """async function fetchBotOpenId(): Promise<string | undefined> {
\ttry {
\t\tconst r = (await larkClient.request({
\t\t\turl: "/open-apis/bot/v3/info",
\t\t\tmethod: "GET",
\t\t})) as { bot?: { open_id?: string; app_name?: string } };
\t\tconst id = r.bot?.open_id;
\t\tif (id) console.log(`[Bot] open_id=${id} name=${r.bot?.app_name ?? "?"}`);
\t\treturn id;
\t} catch (e) {
\t\tconsole.warn("[Bot] 无法获取 open_id，群聊 @ 过滤将不可用:", e);
\t\treturn undefined;
\t}
}"""

new_fetch = """async function fetchBotOpenId(): Promise<string | undefined> {
\t// CLAW_BOT_OPENID_RETRY: 开机网络未就绪时单次请求会 ECONNREFUSED，需重试
\tconst maxAttempts = 12;
\tfor (let attempt = 1; attempt <= maxAttempts; attempt++) {
\t\ttry {
\t\t\tconst r = (await larkClient.request({
\t\t\t\turl: "/open-apis/bot/v3/info",
\t\t\t\tmethod: "GET",
\t\t\t})) as { bot?: { open_id?: string; app_name?: string } };
\t\t\tconst id = r.bot?.open_id;
\t\t\tif (id) {
\t\t\t\tconsole.log(`[Bot] open_id=${id} name=${r.bot?.app_name ?? "?"}`);
\t\t\t\treturn id;
\t\t\t}
\t\t} catch (e) {
\t\t\tconst delayMs = Math.min(30_000, 2_000 * attempt);
\t\t\tconsole.warn(`[Bot] 获取 open_id 失败 (${attempt}/${maxAttempts})，${delayMs}ms 后重试:`, e);
\t\t\tif (attempt < maxAttempts) await new Promise((r) => setTimeout(r, delayMs));
\t\t}
\t}
\tconsole.warn("[Bot] 无法获取 open_id，群聊 @ 过滤将不可用（已重试）");
\treturn undefined;
}"""

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

old_start = "fetchBotOpenId().then((id) => { botOpenId = id; });"
new_start = """void (async () => {
\tbotOpenId = await fetchBotOpenId();
})();"""

changed = False
for old, new in [(old_fetch, new_fetch), (old_group, new_group), (old_start, new_start)]:
    if old not in text:
        print(f"patch-claw-bot-openid-retry: 无法定位片段:\n{old[:80]}...", file=sys.stderr)
        sys.exit(1)
    text = text.replace(old, new, 1)
    changed = True

if changed:
    server.write_text(text)
    print("patch-claw-bot-openid-retry: 已添加 open_id 重试与群聊懒加载")
PY

chmod +x "${BASH_SOURCE[0]}"
