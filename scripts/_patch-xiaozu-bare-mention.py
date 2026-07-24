#!/usr/bin/env python3
from pathlib import Path
import sys
server = Path(sys.argv[1])
text = server.read_text()
if "bareMention," in text and "用户只 @ 了我——请恢复对话" in text:
    print("patch-claw-xiaozu-group-agent: bare @ resume 已存在，跳过")
    raise SystemExit(0)

# Upgrade older bare hint if present
old_variants = [
"""\t\t\t\t\tlet behaviorText = mentionedBot
\t\t\t\t\t\t? stripMentionPlaceholders(parsedText, mentions)
\t\t\t\t\t\t: parsedText;
\t\t\t\t\tif (mentionedBot && !behaviorText.trim()) {
\t\t\t\t\t\tbehaviorText =
\t\t\t\t\t\t\t"（用户只 @ 了我，没有附带文字；请结合最近群消息决定 reply 或 ask_cursor，不要 silence）";
\t\t\t\t\t}
\t\t\t\t\tconst authorized = PermissionGate.checkPermission(behaviorText, senderOpenId, permCfg).ok;
\t\t\t\t\tconst behavior = await xiaozuGroupAgent.tick({
\t\t\t\t\t\tkind: "group_message",
\t\t\t\t\t\tchatId,
\t\t\t\t\t\tmessageId,
\t\t\t\t\t\ttext: behaviorText || `[${messageType}]`,
\t\t\t\t\t\tmessageType,
\t\t\t\t\t\tmentioned: mentionedBot,
\t\t\t\t\t\tauthorized,
\t\t\t\t\t});
""",
"""\t\t\t\t\tconst behaviorText = mentionedBot
\t\t\t\t\t\t? stripMentionPlaceholders(parsedText, mentions)
\t\t\t\t\t\t: parsedText;
\t\t\t\t\tconst authorized = PermissionGate.checkPermission(behaviorText, senderOpenId, permCfg).ok;
\t\t\t\t\tconst behavior = await xiaozuGroupAgent.tick({
\t\t\t\t\t\tkind: "group_message",
\t\t\t\t\t\tchatId,
\t\t\t\t\t\tmessageId,
\t\t\t\t\t\ttext: behaviorText || `[${messageType}]`,
\t\t\t\t\t\tmessageType,
\t\t\t\t\t\tmentioned: mentionedBot,
\t\t\t\t\t\tauthorized,
\t\t\t\t\t});
""",
]
new = """\t\t\t\t\tlet behaviorText = mentionedBot
\t\t\t\t\t\t? stripMentionPlaceholders(parsedText, mentions)
\t\t\t\t\t\t: parsedText;
\t\t\t\t\tconst bareMention = Boolean(mentionedBot && !behaviorText.trim());
\t\t\t\t\tif (bareMention) {
\t\t\t\t\t\tbehaviorText =
\t\t\t\t\t\t\t"（用户只 @ 了我——请恢复对话：结合最近群消息短回复或 ask_cursor，禁止 silence）";
\t\t\t\t\t}
\t\t\t\t\tconst authorized = PermissionGate.checkPermission(behaviorText, senderOpenId, permCfg).ok;
\t\t\t\t\tconst behavior = await xiaozuGroupAgent.tick({
\t\t\t\t\t\tkind: "group_message",
\t\t\t\t\t\tchatId,
\t\t\t\t\t\tmessageId,
\t\t\t\t\t\ttext: behaviorText || `[${messageType}]`,
\t\t\t\t\t\tmessageType,
\t\t\t\t\t\tmentioned: mentionedBot,
\t\t\t\t\t\tauthorized,
\t\t\t\t\t\tbareMention,
\t\t\t\t\t});
"""
for old in old_variants:
    if old in text:
        server.write_text(text.replace(old, new, 1))
        print("patch-claw-xiaozu-group-agent: 已升级 bare @ resume")
        raise SystemExit(0)
# already partially upgraded?
if "bareMention," in text:
    print("patch-claw-xiaozu-group-agent: bareMention 字段已在，跳过结构替换")
    raise SystemExit(0)
print("patch-claw-xiaozu-group-agent: 无法定位 bare @ resume 插入点", file=sys.stderr)
raise SystemExit(1)
