#!/usr/bin/env python3
from pathlib import Path
import sys
server = Path(sys.argv[1])
text = server.read_text()
if "用户只 @ 了我，没有附带文字" in text:
    print("patch-claw-xiaozu-group-agent: bare @ 提示已存在，跳过")
    raise SystemExit(0)
cands = [
(
"""					const behaviorText = mentionedBot
						? stripMentionPlaceholders(parsedText, mentions)
						: parsedText;
					const authorized = PermissionGate.checkPermission(behaviorText, senderOpenId, permCfg).ok;
""",
"""					let behaviorText = mentionedBot
						? stripMentionPlaceholders(parsedText, mentions)
						: parsedText;
					if (mentionedBot && !behaviorText.trim()) {
						behaviorText =
							"（用户只 @ 了我，没有附带文字；请结合最近群消息决定 reply 或 ask_cursor，不要 silence）";
					}
					const authorized = PermissionGate.checkPermission(behaviorText, senderOpenId, permCfg).ok;
""",
),
(
"""					let behaviorText = mentionedBot
						? stripMentionPlaceholders(parsedText, mentions)
						: parsedText;
					const authorized = PermissionGate.checkPermission(behaviorText, senderOpenId, permCfg).ok;
""",
"""					let behaviorText = mentionedBot
						? stripMentionPlaceholders(parsedText, mentions)
						: parsedText;
					if (mentionedBot && !behaviorText.trim()) {
						behaviorText =
							"（用户只 @ 了我，没有附带文字；请结合最近群消息决定 reply 或 ask_cursor，不要 silence）";
					}
					const authorized = PermissionGate.checkPermission(behaviorText, senderOpenId, permCfg).ok;
""",
),
]
for old, new in cands:
    if old in text:
        server.write_text(text.replace(old, new, 1))
        print("patch-claw-xiaozu-group-agent: 已打 bare @ 提示")
        raise SystemExit(0)
print("patch-claw-xiaozu-group-agent: 无法定位 bare @ 插入点", file=sys.stderr)
raise SystemExit(1)
