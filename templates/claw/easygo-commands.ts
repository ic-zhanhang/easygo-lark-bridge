// CLAW_EASYGO_COMMANDS — Group Topic Only 入站门控 + EasyGo 斜杠命令
/** 群话题缺失时的短提示 */
export const NO_THREAD_REPLY =
	"请在**话题**里 @我，我才能处理这条消息。开一个话题再发一次即可。";

/** 入站私聊拒绝文案（Outbound Notify 不受此限） */
export const P2P_INBOUND_REPLY =
	"我不在私聊里接指令。请到飞书群的**话题**里 @我。";

export const RESET_REPLY =
	"已重置本话题会话。下一条消息会开启新的 Topic Session。";

export const UNKNOWN_SLASH_REPLY_PREFIX = "未知指令";

export type InboundGateResult =
	| { action: "reject"; reason: "no_thread" | "p2p_inbound"; reply: string }
	| { action: "allow"; topicKey: string };

/**
 * Group Topic Only：仅群聊 + thread_id 可进 Agent。
 * 私聊入站拒绝；无话题群聊拒绝。
 */
export function gateInboundMessage(
	chatType: string,
	threadId: string | undefined,
	options?: { mainGroupTopicKey?: string },
): InboundGateResult {
	if (chatType === "p2p" || chatType === "private") {
		return { action: "reject", reason: "p2p_inbound", reply: P2P_INBOUND_REPLY };
	}
	if (chatType === "group") {
		if (!threadId && options?.mainGroupTopicKey) {
			return { action: "allow", topicKey: options.mainGroupTopicKey };
		}
		if (!threadId) {
			return { action: "reject", reason: "no_thread", reply: NO_THREAD_REPLY };
		}
		return { action: "allow", topicKey: threadId };
	}
	return { action: "reject", reason: "p2p_inbound", reply: P2P_INBOUND_REPLY };
}

/** EasyGo 允许的斜杠命令族（其余 / 一律拒绝） */
export type EasyGoSlashKind =
	| { kind: "help" }
	| { kind: "reset" }
	| { kind: "context" }
	| { kind: "heartbeat"; raw: string }
	| { kind: "stop"; raw: string }
	| { kind: "unknown"; cmd: string }
	| { kind: "not_slash" };

export function parseEasyGoSlash(text: string): EasyGoSlashKind {
	const trimmed = text.trim();
	if (!trimmed.startsWith("/")) return { kind: "not_slash" };

	// 允许尾随 @提及/空白：飞书常写成「/上下文 @达妮娅」
	if (/^\/(help|帮助|指令)(\s|$)/i.test(trimmed)) return { kind: "help" };
	if (/^\/(new|新对话|新会话|reset)(\s|$)/i.test(trimmed)) return { kind: "reset" };
	if (/^\/(context|上下文|会话上下文)(\s|$)/i.test(trimmed)) return { kind: "context" };
	if (/^\/(心跳|heartbeat|hb)([\s:：].*)?$/i.test(trimmed)) {
		return { kind: "heartbeat", raw: trimmed };
	}
	if (/^\/(stop|终止|停止)\s*$/i.test(trimmed)) {
		return { kind: "stop", raw: trimmed };
	}

	const cmd = trimmed.split(/[\s:：]/)[0] || trimmed;
	return { kind: "unknown", cmd };
}

export function easyGoHelpText(): string {
	return [
		"**EasyGo 实用指令**",
		"",
		"- `/help` `/帮助` — 显示本帮助",
		"- `/新对话` `/reset` — 重置当前话题的 Topic Session",
		"- `/上下文` `/context` — 查看当前 Cursor 会话绑定与小组注入预览",
		"- `/终止` `/stop` — 终止正在执行的任务",
		"",
		"**心跳**",
		"- `/心跳` — 查看心跳状态",
		"- `/心跳 开启` / `/心跳 关闭`",
		"- `/心跳 执行`（或 `/心跳 立即`）— 马上跑一次同步",
		"- `/心跳 间隔 分钟数`",
		"",
		"人对 Bot 的指令请在群**话题**里 @我；心跳摘要仍可能私聊推送（不可续聊）。",
	].join("\n");
}

export function formatCursorContext(input: {
	topicKey?: string;
	sessionId?: string;
}): string {
	const topic = input.topicKey ? `\`${input.topicKey}\`` : "无";
	const session = input.sessionId
		? `\`${input.sessionId}\``
		: "无（下次 @ 会新建同话题会话）";
	return [
		"**Cursor 会话**",
		`- topicKey：${topic}`,
		`- sessionId：${session}`,
		"- 清窗：`/新对话` 或 `/reset`（同话题下一条 @ 开新对话）",
		"",
		"说明：这里只能看到桥接侧的会话绑定；Cursor 内部完整 transcript 不在本命令展开。",
	].join("\n");
}

export function unknownSlashReply(cmd: string): string {
	return `${UNKNOWN_SLASH_REPLY_PREFIX} \`${cmd}\`\n\n发送 \`/help\` 查看 EasyGo 可用指令。`;
}
