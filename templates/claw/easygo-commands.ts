// CLAW_EASYGO_COMMANDS — 入站门控 + EasyGo 斜杠命令
/** 群话题缺失时的短提示 */
export const NO_THREAD_REPLY =
	"请在**话题**里 @我，我才能处理这条消息。开一个话题再发一次即可。";

/** 非授权人私聊拒绝（Outbound Notify / L1 私聊不受此限） */
export const P2P_INBOUND_REPLY =
	"……嗯，私聊只接**授权人**的指令。其他人请到飞书群的**话题**里 @我。";

export const RESET_REPLY =
	"已重置本会话。下一条消息会开启新的 Topic Session。";

export const UNKNOWN_SLASH_REPLY_PREFIX = "未知指令";

export type InboundGateResult =
	| { action: "reject"; reason: "no_thread" | "p2p_inbound"; reply: string }
	| { action: "allow"; topicKey: string };

export type GateInboundOptions = {
	mainGroupTopicKey?: string;
	/** 私聊发送者 open_id；仅当属于 authorizerOpenIds 时放行 */
	senderOpenId?: string;
	authorizerOpenIds?: Set<string> | readonly string[];
};

/** 授权人私聊的稳定 topicKey */
export function p2pTopicKey(openId: string): string {
	return `p2p:${openId}`;
}

function isAuthorizer(
	senderOpenId: string | undefined,
	authorizerOpenIds: GateInboundOptions["authorizerOpenIds"],
): boolean {
	if (!senderOpenId || !authorizerOpenIds) return false;
	if (authorizerOpenIds instanceof Set) return authorizerOpenIds.has(senderOpenId);
	return authorizerOpenIds.includes(senderOpenId);
}

/**
 * 入站门控：群话题 / 小组主群 / 授权人私聊可进 Agent。
 * 其它私聊拒绝；无话题群聊拒绝。
 */
export function gateInboundMessage(
	chatType: string,
	threadId: string | undefined,
	options?: GateInboundOptions,
): InboundGateResult {
	if (chatType === "p2p" || chatType === "private") {
		if (isAuthorizer(options?.senderOpenId, options?.authorizerOpenIds)) {
			return { action: "allow", topicKey: p2pTopicKey(options!.senderOpenId!) };
		}
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
	if (/^\/(context|上下文|会话上下文|会话历史)(\s|$)/i.test(trimmed)) return { kind: "context" };
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
		"- `/新对话` `/reset` — 重置当前 Topic Session（群话题或授权人私聊）",
		"- `/上下文` `/会话历史` `/context` — 查看当前 Cursor 会话绑定",
		"- `/终止` `/stop` — 终止正在执行的任务",
		"",
		"**心跳**",
		"- `/心跳` — 查看心跳状态",
		"- `/心跳 开启` / `/心跳 关闭`",
		"- `/心跳 执行`（或 `/心跳 立即`）— 马上跑一次同步",
		"- `/心跳 间隔 分钟数`",
		"",
		"群聊请在**话题**里 @我；授权人也可私聊续聊（同 Cursor 会话）。心跳摘要仍可能私聊推送。",
	].join("\n");
}

export function formatCursorContext(input: {
	topicKey?: string;
	sessionId?: string;
}): string {
	const isP2p = !!input.topicKey?.startsWith("p2p:");
	const topic = input.topicKey ? `\`${input.topicKey}\`` : "无";
	const session = input.sessionId
		? `\`${input.sessionId}\``
		: isP2p
			? "无（下次私聊会新建会话）"
			: "无（下次 @ 会新建同话题会话）";
	return [
		"**Cursor 会话**",
		`- topicKey：${topic}`,
		`- sessionId：${session}`,
		"- 清窗：`/新对话` 或 `/reset`",
		"",
		"说明：这里只能看到桥接侧的会话绑定；Cursor 内部完整 transcript 不在本命令展开。",
	].join("\n");
}

export function unknownSlashReply(cmd: string): string {
	return `${UNKNOWN_SLASH_REPLY_PREFIX} \`${cmd}\`\n\n发送 \`/help\` 查看 EasyGo 可用指令。`;
}
