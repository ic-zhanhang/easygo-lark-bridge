#!/usr/bin/env python3
"""Idempotent: wire Cursor Ask/Agent + persona rewrite into claw/server.ts."""
from __future__ import annotations

import sys
from pathlib import Path

server = Path(sys.argv[1])
text = server.read_text()
marker = "CLAW_XIAOZHU_CURSOR_MODE"
if marker in text:
    print("patch-claw-xiaozu-group-agent: Cursor Ask/Agent 已应用，跳过")
    sys.exit(0)


def rep(old: str, new: str, label: str) -> None:
    global text
    if old not in text:
        print(f"patch-claw-xiaozu-group-agent: 无法定位 {label}", file=sys.stderr)
        sys.exit(1)
    text = text.replace(old, new, 1)


if "opts?.cursorMode === \"ask\"" not in text:
    rep(
        "\topts?: {\n"
        "\t\tsessionId?: string;\n"
        "\t\tonProgress?: (p: AgentProgress) => void;\n"
        "\t\tmaxMs?: number;\n"
        "\t\tidleMs?: number;\n"
        "\t\tstartupGraceMs?: number;\n"
        "\t},\n"
        "): Promise<{ result: string; sessionId?: string; usage?: { inputTokens?: number; outputTokens?: number } }> {\n"
        "\treturn new Promise((res, reject) => {\n"
        "\t\tconst args = [\n"
        "\t\t\t\"-p\", \"--force\", \"--trust\", \"--approve-mcps\",\n"
        "\t\t\t\"--workspace\", workspace,\n"
        "\t\t\t\"--model\", model,\n"
        "\t\t\t\"--output-format\", \"stream-json\",\n"
        "\t\t\t\"--stream-partial-output\",\n"
        "\t\t];\n"
        "\n"
        "\t\tif (opts?.sessionId) {\n"
        "\t\t\targs.push(\"--resume\", opts.sessionId);\n"
        "\t\t}\n"
        "\t\targs.push(\"--\", prompt);\n",
        "\topts?: {\n"
        "\t\tsessionId?: string;\n"
        "\t\tonProgress?: (p: AgentProgress) => void;\n"
        "\t\tmaxMs?: number;\n"
        "\t\tidleMs?: number;\n"
        "\t\tstartupGraceMs?: number;\n"
        "\t\tcursorMode?: \"ask\" | \"agent\";\n"
        "\t},\n"
        "): Promise<{ result: string; sessionId?: string; usage?: { inputTokens?: number; outputTokens?: number } }> {\n"
        "\treturn new Promise((res, reject) => {\n"
        "\t\tconst args = [\n"
        "\t\t\t\"-p\",\n"
        "\t\t\t\"--trust\",\n"
        "\t\t\t\"--workspace\", workspace,\n"
        "\t\t\t\"--model\", model,\n"
        "\t\t\t\"--output-format\", \"stream-json\",\n"
        "\t\t\t\"--stream-partial-output\",\n"
        "\t\t];\n"
        "\t\tif (opts?.cursorMode === \"ask\") {\n"
        "\t\t\targs.push(\"--mode\", \"ask\");\n"
        "\t\t} else {\n"
        "\t\t\targs.push(\"--force\", \"--approve-mcps\");\n"
        "\t\t}\n"
        "\n"
        "\t\tif (opts?.sessionId) {\n"
        "\t\t\targs.push(\"--resume\", opts.sessionId);\n"
        "\t\t}\n"
        "\t\targs.push(\"--\", prompt);\n",
        "execAgent ask/agent",
    )

if "cursorMode: opts?.cursorMode" not in text:
    if 'cursorMode?: "ask" | "agent"' not in text.split("async function runAgent")[1][:500]:
        rep(
            "\t\tstartupGraceMs?: number;\n\t\ttopicKey?: string;\n\t},\n"
            "): Promise<{ result: string; quotaWarning?: string; sessionRenewed?: boolean; usage?: { inputTokens?: number; outputTokens?: number } }> {\n",
            "\t\tstartupGraceMs?: number;\n\t\ttopicKey?: string;\n\t\tcursorMode?: \"ask\" | \"agent\";\n\t},\n"
            "): Promise<{ result: string; quotaWarning?: string; sessionRenewed?: boolean; usage?: { inputTokens?: number; outputTokens?: number } }> {\n",
            "runAgent opts",
        )
    rep(
        "\tconst execOpts = {\n\t\tonProgress: opts?.onProgress,\n\t\tmaxMs: opts?.maxMs,\n\t\tidleMs: opts?.idleMs,\n\t\tstartupGraceMs: opts?.startupGraceMs,\n\t};\n",
        "\tconst execOpts = {\n\t\tonProgress: opts?.onProgress,\n\t\tmaxMs: opts?.maxMs,\n\t\tidleMs: opts?.idleMs,\n\t\tstartupGraceMs: opts?.startupGraceMs,\n\t\tcursorMode: opts?.cursorMode,\n\t};\n",
        "execOpts",
    )

if "xiaozuCursorMode?" not in text:
    rep(
        "\tmentions?: FeishuMention[];\n\txiaozuChatId?: string;\n}) {\n"
        "\tconst { messageId, chatId, chatType, messageType, content, senderOpenId, threadId, topicKey, mentions, xiaozuChatId } = params;\n"
        "\tlet { text } = params;\n",
        "\tmentions?: FeishuMention[];\n\txiaozuChatId?: string;\n\txiaozuCursorMode?: \"ask\" | \"agent\";\n\txiaozuCursorIntent?: string;\n}) {\n"
        "\tconst { messageId, chatId, chatType, messageType, content, senderOpenId, threadId, topicKey, mentions, xiaozuChatId, xiaozuCursorMode, xiaozuCursorIntent } = params;\n"
        "\tlet { text } = params;\n",
        "handle params",
    )
    rep(
        "\treturn handleInner(text, messageId, chatId, chatType, messageType, content, senderOpenId, topicKey, xiaozuChatId);\n",
        "\treturn handleInner(text, messageId, chatId, chatType, messageType, content, senderOpenId, topicKey, xiaozuChatId, xiaozuCursorMode, xiaozuCursorIntent);\n",
        "handleInner call",
    )
    rep(
        "\ttopicKey?: string,\n\txiaozuChatId?: string,\n): Promise<void> {\n\tlet cardId: string | undefined;\n",
        "\ttopicKey?: string,\n\txiaozuChatId?: string,\n\txiaozuCursorMode?: \"ask\" | \"agent\",\n\txiaozuCursorIntent?: string,\n): Promise<void> {\n\tlet cardId: string | undefined;\n",
        "handleInner sig",
    )

if "resolvedXiaozuCursorMode" not in text:
    rep(
        "\tlet xiaozuTaskTurn: ReturnType<typeof xiaozuGroupAgent.buildTaskTurn> | undefined;\n"
        "\tif (xiaozuChatId) {\n"
        "\t\txiaozuTaskTurn = xiaozuGroupAgent.buildTaskTurn({\n"
        "\t\t\tchatId: xiaozuChatId,\n"
        "\t\t\tmessageId,\n"
        "\t\t\trequest: prompt,\n"
        "\t\t});\n"
        "\t\tprompt = xiaozuTaskTurn.prompt;\n"
        "\t}\n\n"
        "\tconst model = config.CURSOR_MODEL;\n",
        "\tlet xiaozuTaskTurn: ReturnType<typeof xiaozuGroupAgent.buildTaskTurn> | undefined;\n"
        "\tconst resolvedXiaozuCursorMode: \"ask\" | \"agent\" | undefined = xiaozuChatId\n"
        "\t\t? (xiaozuCursorMode ?? \"ask\")\n"
        "\t\t: undefined;\n"
        "\tif (xiaozuChatId) {\n"
        "\t\txiaozuTaskTurn = xiaozuGroupAgent.buildTaskTurn({\n"
        "\t\t\tchatId: xiaozuChatId,\n"
        "\t\t\tmessageId,\n"
        "\t\t\trequest: prompt,\n"
        "\t\t\tcursorMode: resolvedXiaozuCursorMode!,\n"
        "\t\t\tcursorIntent: xiaozuCursorIntent,\n"
        "\t\t});\n"
        "\t\tprompt = xiaozuTaskTurn.prompt;\n"
        "\t}\n\n"
        "\tconst model = config.CURSOR_MODEL;\n",
        "buildTaskTurn",
    )
    rep(
        "\t\tconst { result, quotaWarning, usage, sessionRenewed } = await runAgent(workspace, prompt, { onProgress, onStart, topicKey });\n"
        "\t\tconst resultWithNote = sessionRenewed\n"
        "\t\t\t? `⚠️ 原 Topic Session 无法续聊，已自动开启新会话。\\n\\n${result}`\n"
        "\t\t\t: result;\n"
        "\t\tif (xiaozuTaskTurn) xiaozuGroupAgent.completeTaskTurn(xiaozuTaskTurn, resultWithNote);\n"
        "\t\tprogressEnabled = false;\n",
        "\t\tconst { result, quotaWarning, usage, sessionRenewed } = await runAgent(workspace, prompt, { onProgress, onStart, topicKey, cursorMode: resolvedXiaozuCursorMode });\n"
        "\t\tconst resultWithNote = sessionRenewed\n"
        "\t\t\t? `⚠️ 原 Topic Session 无法续聊，已自动开启新会话。\\n\\n${result}`\n"
        "\t\t\t: result;\n"
        "\t\tlet personaResult = resultWithNote;\n"
        "\t\tif (xiaozuTaskTurn) {\n"
        "\t\t\txiaozuGroupAgent.completeTaskTurn(xiaozuTaskTurn, resultWithNote);\n"
        "\t\t\tpersonaResult = await xiaozuGroupAgent.rewriteCursorResult(resultWithNote);\n"
        "\t\t}\n"
        "\t\tprogressEnabled = false;\n",
        "run+rewrite",
    )
    text = text.replace(
        "const fullResult = quotaWarning ? `${quotaWarning}\\n\\n---\\n\\n${resultWithNote}` : resultWithNote;",
        "const fullResult = quotaWarning ? `${quotaWarning}\\n\\n---\\n\\n${personaResult}` : personaResult;",
        1,
    )
    text = text.replace(
        "replyLongMessage(messageId, chatId, resultWithNote",
        "replyLongMessage(messageId, chatId, personaResult",
        1,
    )

old_bt = (
    "\t\t\t\t\tconst behavior = await xiaozuGroupAgent.tick({\n"
    "\t\t\t\t\t\tkind: \"group_message\",\n"
    "\t\t\t\t\t\tchatId,\n"
    "\t\t\t\t\t\tmessageId,\n"
    "\t\t\t\t\t\ttext: behaviorText || `[${messageType}]`,\n"
    "\t\t\t\t\t\tmessageType,\n"
    "\t\t\t\t\t\tmentioned: mentionedBot,\n"
    "\t\t\t\t\t\tauthorized: PermissionGate.checkPermission(behaviorText, senderOpenId, permCfg).ok,\n"
    "\t\t\t\t\t});\n"
    "\t\t\t\t\tconsole.log(`[行为树] action=${behavior.action} confidence=${behavior.confidence.toFixed(2)} reason=${behavior.reason}`);\n"
    "\t\t\t\t\tif (behavior.action !== \"work\") {\n"
    "\t\t\t\t\t\tif (behavior.action === \"reply\" || behavior.action === \"propose_task\" || behavior.action === \"propose_decision\") {\n"
    "\t\t\t\t\t\t\tconst suffix = behavior.action === \"propose_task\"\n"
    "\t\t\t\t\t\t\t\t? \"\\n\\n> 这是候选任务；需要我开工时请 @我确认。\"\n"
    "\t\t\t\t\t\t\t\t: \"\";\n"
    "\t\t\t\t\t\t\tawait replyCard(\n"
    "\t\t\t\t\t\t\t\tmessageId,\n"
    "\t\t\t\t\t\t\t\t`${behavior.message}${suffix}`,\n"
    "\t\t\t\t\t\t\t\t{ title: xiaozuGroupAgent.personaName, color: behavior.action === \"propose_task\" || behavior.action === \"propose_decision\" ? \"orange\" : \"blue\" },\n"
    "\t\t\t\t\t\t\t\t{ allowTextFallback: true },\n"
    "\t\t\t\t\t\t\t);\n"
    "\t\t\t\t\t\t}\n"
    "\t\t\t\t\t\treturn;\n"
    "\t\t\t\t\t}"
)
new_bt = (
    "\t\t\t\t\tconst authorized = PermissionGate.checkPermission(behaviorText, senderOpenId, permCfg).ok;\n"
    "\t\t\t\t\tconst behavior = await xiaozuGroupAgent.tick({\n"
    "\t\t\t\t\t\tkind: \"group_message\",\n"
    "\t\t\t\t\t\tchatId,\n"
    "\t\t\t\t\t\tmessageId,\n"
    "\t\t\t\t\t\ttext: behaviorText || `[${messageType}]`,\n"
    "\t\t\t\t\t\tmessageType,\n"
    "\t\t\t\t\t\tmentioned: mentionedBot,\n"
    "\t\t\t\t\t\tauthorized,\n"
    "\t\t\t\t\t});\n"
    "\t\t\t\t\tconsole.log(`[行为树] action=${behavior.action} confidence=${behavior.confidence.toFixed(2)} reason=${behavior.reason}`);\n"
    "\t\t\t\t\tif (behavior.action === \"work\") {\n"
    "\t\t\t\t\t\tconst b = behavior as { cursorMode?: \"ask\" | \"agent\"; cursorIntent?: string };\n"
    "\t\t\t\t\t\txiaozuCursorMode = b.cursorMode ?? (authorized ? \"agent\" : \"ask\");\n"
    "\t\t\t\t\t\txiaozuCursorIntent = b.cursorIntent;\n"
    "\t\t\t\t\t}\n"
    "\t\t\t\t\tif (behavior.action !== \"work\") {\n"
    "\t\t\t\t\t\tif (behavior.action === \"reply\" || behavior.action === \"ask_cursor\" || behavior.action === \"propose_decision\" || behavior.action === \"cancel_cursor\" || behavior.action === \"propose_task\") {\n"
    "\t\t\t\t\t\t\tconst suffix = behavior.action === \"ask_cursor\"\n"
    "\t\t\t\t\t\t\t\t? \"\\n\\n> 确认后我再去查/做（无权限=只读，有权限=可改）。\"\n"
    "\t\t\t\t\t\t\t\t: \"\";\n"
    "\t\t\t\t\t\t\tawait replyCard(\n"
    "\t\t\t\t\t\t\t\tmessageId,\n"
    "\t\t\t\t\t\t\t\t`${behavior.message}${suffix}`,\n"
    "\t\t\t\t\t\t\t\t{ title: xiaozuGroupAgent.personaName, color: behavior.action === \"ask_cursor\" || behavior.action === \"propose_decision\" ? \"orange\" : \"blue\" },\n"
    "\t\t\t\t\t\t\t\t{ allowTextFallback: true },\n"
    "\t\t\t\t\t\t\t);\n"
    "\t\t\t\t\t\t}\n"
    "\t\t\t\t\t\treturn;\n"
    "\t\t\t\t\t}"
)
if old_bt in text:
    text = text.replace(old_bt, new_bt, 1)
elif "ask_cursor" in text and "xiaozuCursorIntent = b.cursorIntent" in text:
    pass
else:
    print("patch-claw-xiaozu-group-agent: 无法定位行为树分支", file=sys.stderr)
    sys.exit(1)

if 'let xiaozuCursorMode: "ask" | "agent" | undefined;' not in text:
    rep(
        "\t\t\tconst isXiaozuChat = chatType === \"group\" && xiaozuSpectatorChatIds.has(chatId);\n",
        "\t\t\tconst isXiaozuChat = chatType === \"group\" && xiaozuSpectatorChatIds.has(chatId);\n"
        "\t\t\tlet xiaozuCursorMode: \"ask\" | \"agent\" | undefined;\n"
        "\t\t\tlet xiaozuCursorIntent: string | undefined;\n",
        "decl mode",
    )
if "xiaozuCursorMode, xiaozuCursorIntent" not in text:
    rep(
        "\t\t\thandle({ text: parsedText.trim(), messageId, chatId, chatType, messageType, content, senderOpenId, threadId, topicKey, xiaozuChatId: isXiaozuChat ? chatId : undefined }).catch(console.error);\n",
        "\t\t\thandle({ text: parsedText.trim(), messageId, chatId, chatType, messageType, content, senderOpenId, threadId, topicKey, xiaozuChatId: isXiaozuChat ? chatId : undefined, xiaozuCursorMode, xiaozuCursorIntent }).catch(console.error);\n",
        "handle invoke",
    )

if "CLAW_XIAOZHU_GROUP_AGENT · CLAW_XIAOZHU_BEHAVIOR_TREE" in text and marker not in text:
    text = text.replace(
        "CLAW_XIAOZHU_GROUP_AGENT · CLAW_XIAOZHU_BEHAVIOR_TREE",
        f"CLAW_XIAOZHU_GROUP_AGENT · CLAW_XIAOZHU_BEHAVIOR_TREE · {marker}",
        1,
    )
elif marker not in text:
    text = text.replace(
        'import { createXiaozuGroupAgent } from "./xiaozu-group-agent.js"; // CLAW_XIAOZHU_GROUP_AGENT',
        f'import {{ createXiaozuGroupAgent }} from "./xiaozu-group-agent.js"; // CLAW_XIAOZHU_GROUP_AGENT · {marker}',
        1,
    )

server.write_text(text)
print("patch-claw-xiaozu-group-agent: 已应用 Cursor Ask/Agent + 结果回灌")
