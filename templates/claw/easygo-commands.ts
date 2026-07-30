// CLAW_EASYGO_COMMANDS — 入站门控 + EasyGo 斜杠命令
import { existsSync, readFileSync } from "fs";
import { homedir } from "os";
import { resolve } from "path";

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
	| { kind: "aging_alert_mute" }
	| { kind: "aging_alert_unmute" }
	| { kind: "aging_alert_status" }
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
	if (/^\/(关闭报警|关闭老化报警)(\s|$)/i.test(trimmed)) {
		return { kind: "aging_alert_mute" };
	}
	if (/^\/(打开报警|开启报警|打开老化报警|开启老化报警)(\s|$)/i.test(trimmed)) {
		return { kind: "aging_alert_unmute" };
	}
	if (/^\/(报警状态|老化报警状态)(\s|$)/i.test(trimmed)) {
		return { kind: "aging_alert_status" };
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
		"- `/上下文` `/会话历史` `/context` — 查看当前会话绑定与对话内容",
		"- `/终止` `/stop` — 终止正在执行的任务",
		"",
		"**老化报警（Linux 秧秧）**",
		"- `/关闭报警` — 静音老化异常推送（日报仍发）",
		"- `/打开报警` — 恢复老化异常推送",
		"- `/报警状态` — 查看当前是否静音",
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

export type TranscriptTurn = { role: "user" | "assistant"; text: string };

/** Cursor 把 workspace 路径编成 projects 目录名：/a/b → a-b */
export function cursorProjectSlug(workspace: string): string {
	return workspace.replace(/\\/g, "/").replace(/^\/+/, "").replace(/\//g, "-");
}

export function agentTranscriptPath(workspace: string, sessionId: string): string {
	return resolve(
		homedir(),
		".cursor",
		"projects",
		cursorProjectSlug(workspace),
		"agent-transcripts",
		sessionId,
		`${sessionId}.jsonl`,
	);
}

function extractMessageText(message: unknown): string {
	if (!message || typeof message !== "object") return "";
	const content = (message as { content?: unknown }).content;
	if (typeof content === "string") return content;
	if (!Array.isArray(content)) return "";
	const parts: string[] = [];
	for (const part of content) {
		if (typeof part === "string") parts.push(part);
		else if (part && typeof part === "object" && (part as { type?: string }).type === "text") {
			const t = (part as { text?: unknown }).text;
			if (typeof t === "string") parts.push(t);
		}
	}
	return parts.join("\n");
}

/** 解析 Cursor agent-transcripts JSONL；连续同角色合并（助手只留最后一条） */
export function parseAgentTranscriptJsonl(raw: string): TranscriptTurn[] {
	const turns: TranscriptTurn[] = [];
	for (const line of raw.split("\n")) {
		if (!line.trim()) continue;
		let obj: { role?: string; message?: unknown };
		try {
			obj = JSON.parse(line) as { role?: string; message?: unknown };
		} catch {
			continue;
		}
		const role = obj.role;
		if (role !== "user" && role !== "assistant") continue;
		let text = extractMessageText(obj.message);
		const m = text.match(/<user_query>\s*([\s\S]*?)\s*<\/user_query>/);
		if (m) text = m[1].trim();
		text = text.replace(/<timestamp>[\s\S]*?<\/timestamp>\s*/g, "").trim();
		if (!text || text === "[REDACTED]") continue;
		const last = turns[turns.length - 1];
		if (last && last.role === role) {
			last.text = role === "assistant" ? text : `${last.text}\n\n${text}`;
		} else {
			turns.push({ role, text });
		}
	}
	return turns;
}

export function formatTranscriptTurns(
	turns: TranscriptTurn[],
	opts?: { maxTurns?: number; maxChars?: number; perTurnMax?: number },
): string {
	const maxTurns = opts?.maxTurns ?? 16;
	const maxChars = opts?.maxChars ?? 10000;
	const perTurnMax = opts?.perTurnMax ?? 800;
	const slice = turns.slice(-maxTurns);
	const omitted = turns.length - slice.length;
	const lines: string[] = [];
	if (omitted > 0) lines.push(`_（更早 ${omitted} 条已省略）_`, "");
	for (const t of slice) {
		const label = t.role === "user" ? "**你**" : "**助手**";
		const body =
			t.text.length > perTurnMax ? `${t.text.slice(0, perTurnMax)}…` : t.text;
		lines.push(label, body, "");
	}
	let out = lines.join("\n").trimEnd();
	if (out.length > maxChars) {
		out = out.slice(out.length - maxChars);
		const nl = out.indexOf("\n");
		if (nl > 0 && nl < 200) out = out.slice(nl + 1);
		out = `_（前文已截断）_\n\n${out}`;
	}
	return out;
}

export function loadFormattedAgentTranscript(
	workspace: string | undefined,
	sessionId: string | undefined,
	opts?: { maxTurns?: number; maxChars?: number; perTurnMax?: number },
): string | undefined {
	if (!workspace || !sessionId) return undefined;
	const path = agentTranscriptPath(workspace, sessionId);
	if (!existsSync(path)) return undefined;
	try {
		const turns = parseAgentTranscriptJsonl(readFileSync(path, "utf-8"));
		if (!turns.length) return undefined;
		return formatTranscriptTurns(turns, opts);
	} catch {
		return undefined;
	}
}

export function formatCursorContext(input: {
	topicKey?: string;
	sessionId?: string;
	workspace?: string;
}): string {
	const isP2p = !!input.topicKey?.startsWith("p2p:");
	const topic = input.topicKey ? `\`${input.topicKey}\`` : "无";
	const session = input.sessionId
		? `\`${input.sessionId}\``
		: isP2p
			? "无（下次私聊会新建会话）"
			: "无（下次 @ 会新建同话题会话）";
	const parts = [
		"**Cursor 会话**",
		`- topicKey：${topic}`,
		`- sessionId：${session}`,
		"- 清窗：`/新对话` 或 `/reset`",
		"",
		"**对话内容**",
	];
	const transcript = loadFormattedAgentTranscript(input.workspace, input.sessionId);
	if (transcript) parts.push(transcript);
	else if (input.sessionId)
		parts.push("（未找到本地 transcript，可能尚未写入或路径不匹配）");
	else parts.push("（尚无绑定会话）");
	return parts.join("\n");
}


/** Linux 秧秧本机 observe 控制地址；Mac 未配置则不可用。 */
export function agingAlertControlUrl(): string | undefined {
	const fromEnv = (process.env.AGING_ALERT_CONTROL_URL || "").trim();
	if (fromEnv) return fromEnv.replace(/\/$/, "");
	if ((process.env.BRIDGE_PROFILE || "").trim() === "linux") {
		return "http://127.0.0.1:4194";
	}
	return undefined;
}

export type AgingAlertControlResult = {
	ok: boolean;
	muted?: boolean;
	muted_by?: string;
	message: string;
};

export async function applyAgingAlertControl(
	kind: "aging_alert_mute" | "aging_alert_unmute" | "aging_alert_status",
	opts?: { by?: string; fetchImpl?: typeof fetch },
): Promise<AgingAlertControlResult> {
	const base = agingAlertControlUrl();
	if (!base) {
		return {
			ok: false,
			message: "当前环境未配置老化报警控制（仅 Linux 秧秧可用）。",
		};
	}
	const fetcher = opts?.fetchImpl ?? fetch;
	try {
		if (kind === "aging_alert_status") {
			const res = await fetcher(`${base}/aging/alert/control`);
			const data = (await res.json()) as {
				ok?: boolean;
				muted?: boolean;
				muted_by?: string;
				message?: string;
			};
			if (!res.ok || data.ok === false) {
				return {
					ok: false,
					message: data.message || `查询失败 HTTP ${res.status}`,
				};
			}
			return {
				ok: true,
				muted: !!data.muted,
				muted_by: data.muted_by || "",
				message: data.muted
					? `老化异常报警已关闭${data.muted_by ? `（by ${data.muted_by}）` : ""}。日报仍会发送。`
					: "老化异常报警已开启。",
			};
		}
		const muted = kind === "aging_alert_mute";
		const res = await fetcher(`${base}/aging/alert/control`, {
			method: "POST",
			headers: { "Content-Type": "application/json" },
			body: JSON.stringify({ muted, by: opts?.by || "秧秧" }),
		});
		const data = (await res.json()) as {
			ok?: boolean;
			muted?: boolean;
			muted_by?: string;
			message?: string;
		};
		if (!res.ok || data.ok === false) {
			return {
				ok: false,
				message: data.message || `设置失败 HTTP ${res.status}`,
			};
		}
		return {
			ok: true,
			muted: !!data.muted,
			muted_by: data.muted_by || "",
			message: muted
				? "好，已关闭老化异常报警。需要时用 `/打开报警` 恢复。"
				: "好，已打开老化异常报警。",
		};
	} catch (error) {
		const detail = error instanceof Error ? error.message : String(error);
		return { ok: false, message: `无法连接 observe 告警服务：${detail}` };
	}
}

export function unknownSlashReply(cmd: string): string {
	return `${UNKNOWN_SLASH_REPLY_PREFIX} \`${cmd}\`\n\n发送 \`/help\` 查看 EasyGo 可用指令。`;
}
