#!/usr/bin/env bash
# updateCard 网络重试 + 区分格式错误 vs 网络错误（避免误触发 AI 重跑）
set -euo pipefail

PACK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLAW_INSTALL_DIR="${CLAW_INSTALL_DIR:-${PACK_ROOT}/claw}"
SERVER="${CLAW_INSTALL_DIR}/server.ts"

if [[ ! -f "${SERVER}" ]]; then
  echo "跳过 patch-claw-card-delivery-fix: 未找到 ${SERVER}"
  exit 0
fi

python3 - "${SERVER}" <<'PY'
from pathlib import Path
import sys

server = Path(sys.argv[1])
text = server.read_text()
changed = False

if "CLAW_UPDATE_CARD_RETRY" not in text:
    old_update = """async function updateCard(
\tmessageId: string,
\tmarkdown: string,
\theader?: { title?: string; color?: string },
): Promise<{ ok: boolean; error?: string }> {
\ttry {
\t\tawait larkClient.im.message.patch({
\t\t\tpath: { message_id: messageId },
\t\t\tdata: { content: buildCard(markdown, header) },
\t\t});
\t\treturn { ok: true };
\t} catch (err) {
\t\tconst reason = extractCardError(err) || (err instanceof Error ? err.message : String(err));
\t\tconsole.error(`[更新卡片失败] ${reason}`);
\t\treturn { ok: false, error: reason };
\t}
}"""

    new_update = """// CLAW_UPDATE_CARD_RETRY: 与 replyCard 一致的网络重试
async function updateCard(
\tmessageId: string,
\tmarkdown: string,
\theader?: { title?: string; color?: string },
): Promise<{ ok: boolean; error?: string }> {
\tconst maxAttempts = 3;
\tfor (let attempt = 1; attempt <= maxAttempts; attempt++) {
\t\ttry {
\t\t\tawait larkClient.im.message.patch({
\t\t\t\tpath: { message_id: messageId },
\t\t\t\tdata: { content: buildCard(markdown, header) },
\t\t\t});
\t\t\treturn { ok: true };
\t\t} catch (err) {
\t\t\tconst reason = extractCardError(err) || (err instanceof Error ? err.message : String(err));
\t\t\tconsole.error(`[更新卡片失败] (${attempt}/${maxAttempts}) ${reason}`);
\t\t\tif (attempt < maxAttempts && isRetryableReplyError(err)) {
\t\t\t\tawait sleepMs(400 * attempt);
\t\t\t\tcontinue;
\t\t\t}
\t\t\treturn { ok: false, error: reason };
\t\t}
\t}
\treturn { ok: false, error: "更新卡片失败" };
}"""

    if old_update not in text:
        print("patch-claw-card-delivery-fix: 无法定位 updateCard", file=sys.stderr)
        sys.exit(1)
    text = text.replace(old_update, new_update, 1)
    changed = True

if "isCardFormatError" not in text:
    anchor = """function isRetryableReplyError(err: unknown): boolean {
\tconst msg = err instanceof Error ? err.message : String(err);
\treturn /socket connection was closed|ECONNRESET|ETIMEDOUT|timeout|network/i.test(msg);
}"""
    insert = anchor + """

function isCardFormatError(error: string | undefined): boolean {
\tif (!error) return false;
\tif (isRetryableReplyError(new Error(error))) return false;
\treturn /30KB|230025|230099|卡片渲染失败|大小限制|表格/i.test(error);
}"""
    if anchor not in text:
        print("patch-claw-card-delivery-fix: 无法定位 isRetryableReplyError", file=sys.stderr)
        sys.exit(1)
    text = text.replace(anchor, insert, 1)
    changed = True

old_branch = """\t\t\tif (ok) {
\t\t\t\tsendOk = true;
\t\t\t} else {
\t\t\t\t// 卡片更新失败 → 让大模型知道，自己重新组织回复
\t\t\t\tconsole.log(`[重发] 卡片更新失败: ${error}，通知 AI 重新回复`);"""

new_branch = """\t\t\tif (ok) {
\t\t\t\tsendOk = true;
\t\t\t} else if (isCardFormatError(error)) {
\t\t\t\t// 卡片格式/大小问题 → 让大模型重新组织回复
\t\t\t\tconsole.log(`[重发] 卡片格式超限: ${error}，通知 AI 重新回复`);"""

if old_branch in text:
    text = text.replace(old_branch, new_branch, 1)
    changed = True

old_warn = '\t\t\t\t\tconsole.warn("[重发] AI 重新回复后仍然超限，回退纯文本分片");'
new_warn = '\t\t\t\t\tconsole.warn("[重发] AI 重新回复后仍然失败，回退分片发送");'
if old_warn in text:
    text = text.replace(old_warn, new_warn, 1)
    changed = True

close_old = """\t\t\t\t} catch (retryErr) {
\t\t\t\t\tconsole.error("[重发] AI 重试失败:", retryErr);
\t\t\t\t}
\t\t\t}
\t\t}"""

close_new = """\t\t\t\t} catch (retryErr) {
\t\t\t\t\tconsole.error("[重发] AI 重试失败:", retryErr);
\t\t\t\t}
\t\t\t} else {
\t\t\t\tconsole.log(`[重发] 卡片更新失败（非格式）: ${error}，降级分片发送`);
\t\t\t}
\t\t}"""

if close_old in text and "[重发] 卡片更新失败（非格式）" not in text:
    text = text.replace(close_old, close_new, 1)
    changed = True

if not changed:
    if "CLAW_UPDATE_CARD_RETRY" in text and "isCardFormatError" in text:
        print("patch-claw-card-delivery-fix: 已应用，跳过")
        sys.exit(0)
    print("patch-claw-card-delivery-fix: 未找到可替换片段", file=sys.stderr)
    sys.exit(1)

server.write_text(text)
print("patch-claw-card-delivery-fix: updateCard 重试 + 格式/网络错误分流")
PY

chmod +x "${BASH_SOURCE[0]}"
