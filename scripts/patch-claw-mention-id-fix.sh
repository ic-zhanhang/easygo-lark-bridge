#!/usr/bin/env bash
# 修复群 @ 匹配：mentions.id 可能是 string；bot/v3/info 的 open_id 可能与群成员 member_id 不一致（秧秧）
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
import sys

server = Path(sys.argv[1])
text = server.read_text()

if "CLAW_MENTION_ID_FIX" in text:
    print("patch-claw-mention-id-fix: 已应用，跳过")
    sys.exit(0)

if "let botOpenId: string | undefined;" not in text:
    print("patch-claw-mention-id-fix: 未找到 botOpenId", file=sys.stderr)
    sys.exit(1)

text = text.replace(
    "let botOpenId: string | undefined;",
    "let botOpenId: string | undefined;\nlet botDisplayName: string | undefined; // CLAW_MENTION_ID_FIX",
    1,
)

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

if old_type not in text:
    print("patch-claw-mention-id-fix: 未找到 FeishuMention 类型", file=sys.stderr)
    sys.exit(1)
text = text.replace(old_type, new_helpers, 1)

# fetchBotOpenId: 简单版与重试版
fetch_patches = [
    (
        "\t\tconst id = r.bot?.open_id;\n\t\tif (id) console.log(`[Bot] open_id=${id} name=${r.bot?.app_name ?? \"?\"}`);\n\t\treturn id;",
        "\t\tconst id = r.bot?.open_id;\n\t\tconst name = r.bot?.app_name;\n\t\tif (name) botDisplayName = name;\n\t\tif (id) console.log(`[Bot] open_id=${id} name=${name ?? \"?\"}`);\n\t\treturn id;",
    ),
    (
        "\t\t\tconst id = r.bot?.open_id;\n\t\t\tif (id) {\n\t\t\t\tconsole.log(`[Bot] open_id=${id} name=${r.bot?.app_name ?? \"?\"}`);\n\t\t\t\treturn id;\n\t\t\t}",
        "\t\t\tconst id = r.bot?.open_id;\n\t\t\tconst name = r.bot?.app_name;\n\t\t\tif (name) botDisplayName = name;\n\t\t\tif (id) {\n\t\t\t\tconsole.log(`[Bot] open_id=${id} name=${name ?? \"?\"}`);\n\t\t\t\treturn id;\n\t\t\t}",
    ),
]
applied_fetch = False
for old, new in fetch_patches:
    if old in text:
        text = text.replace(old, new, 1)
        applied_fetch = True
        break
if not applied_fetch:
    print("patch-claw-mention-id-fix: 未找到 fetchBotOpenId 返回片段", file=sys.stderr)
    sys.exit(1)

old_check = "\t\t\t\tconst mentionedBot = mentions.some((m) => m.id.open_id === botOpenId);"
new_check = "\t\t\t\tconst mentionedBot = isBotMentioned(mentions);"
if old_check not in text:
    print("patch-claw-mention-id-fix: 未找到 @Bot 判断", file=sys.stderr)
    sys.exit(1)
text = text.replace(old_check, new_check, 1)

server.write_text(text)
print("patch-claw-mention-id-fix: 已修复群 @ open_id / 名称匹配")
PY

chmod +x "${BASH_SOURCE[0]}"
