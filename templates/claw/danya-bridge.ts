// CLAW_DANYA_BRIDGE — 本机达妮娅助手（danya-assistant desktop API）客户端
import { existsSync, readFileSync } from "fs";
import { homedir } from "os";
import { resolve } from "path";

export interface DanyaSession {
	host: string;
	port: number;
	token: string;
	url: string;
}

export interface DanyaChatRequest {
	text: string;
	threadId?: string;
	workspaceScope?: "everyday" | "domain";
	timeoutMs?: number;
}

export interface DanyaChatResponse {
	reply: string | null;
	pending_approval: {
		type?: string;
		risk_level?: string;
		task_brief?: string;
		message?: string;
	} | null;
	mood?: string | null;
}

const DEFAULT_SESSION = resolve(
	homedir(),
	"Library/Application Support/danya-pet/chat-session.json",
);

export function defaultDanyaSessionPath(): string {
	return DEFAULT_SESSION;
}

export function loadDanyaSession(sessionFile?: string): DanyaSession | null {
	const path = sessionFile?.trim() || DEFAULT_SESSION;
	if (!existsSync(path)) return null;
	try {
		const raw = JSON.parse(readFileSync(path, "utf-8")) as Record<string, unknown>;
		const host = typeof raw.host === "string" ? raw.host : "127.0.0.1";
		const port = typeof raw.port === "number" ? raw.port : Number(raw.port);
		const token = typeof raw.token === "string" ? raw.token : "";
		if (!Number.isFinite(port) || port <= 0 || !token) return null;
		const url =
			typeof raw.url === "string" && raw.url
				? raw.url.replace(/\/+$/, "")
				: `http://${host}:${port}`;
		return { host, port, token, url };
	} catch {
		return null;
	}
}

export async function danyaHealth(
	session: DanyaSession,
	timeoutMs = 5_000,
): Promise<boolean> {
	const controller = new AbortController();
	const timer = setTimeout(() => controller.abort(), timeoutMs);
	try {
		const res = await fetch(`${session.url}/api/health`, {
			headers: { "X-Danya-Token": session.token },
			signal: controller.signal,
		});
		return res.ok;
	} catch {
		return false;
	} finally {
		clearTimeout(timer);
	}
}

export async function danyaChat(
	session: DanyaSession,
	req: DanyaChatRequest,
): Promise<DanyaChatResponse> {
	const timeoutMs = req.timeoutMs ?? 120_000;
	const controller = new AbortController();
	const timer = setTimeout(() => controller.abort(), timeoutMs);
	try {
		const res = await fetch(`${session.url}/api/chat`, {
			method: "POST",
			headers: {
				"content-type": "application/json",
				"X-Danya-Token": session.token,
			},
			signal: controller.signal,
			body: JSON.stringify({
				text: req.text,
				thread_id: req.threadId || "lark:bridge",
				workspace_scope: req.workspaceScope || "everyday",
			}),
		});
		const body = (await res.json()) as DanyaChatResponse & { error?: string };
		if (!res.ok) {
			throw new Error(body.error || `danya HTTP ${res.status}`);
		}
		return {
			reply: typeof body.reply === "string" ? body.reply : body.reply ?? null,
			pending_approval: body.pending_approval ?? null,
			mood: body.mood ?? null,
		};
	} finally {
		clearTimeout(timer);
	}
}

/** 从 reply 里抽出 JSON 对象；失败抛错。 */
export function extractJsonObject(raw: string): unknown {
	const trimmed = raw.trim();
	if (!trimmed) throw new Error("danya 空回复");
	try {
		return JSON.parse(trimmed);
	} catch {
		const start = trimmed.indexOf("{");
		const end = trimmed.lastIndexOf("}");
		if (start >= 0 && end > start) {
			return JSON.parse(trimmed.slice(start, end + 1));
		}
		throw new Error("danya 未返回 JSON 对象");
	}
}

export function loadPersonaMarkdown(personaFile: string, maxChars = 6_000): string {
	const path = personaFile.trim();
	if (!path || !existsSync(path)) return "";
	try {
		return readFileSync(path, "utf-8").replace(/\0/g, "").trim().slice(0, maxChars);
	} catch {
		return "";
	}
}


export interface FeishuTickRequest {
	chatId: string;
	messageId?: string;
	text: string;
	mentioned?: boolean;
	authorized?: boolean;
	hasPendingCursor?: boolean;
	pendingCursorIntent?: string;
	nearMessages?: Array<{ ts?: string; text?: string }>;
	threadId?: string;
	timeoutMs?: number;
}

export interface FeishuTickDecision {
	action: string;
	confidence: number;
	reason: string;
	message: string;
	cursor_intent: string;
	decision_title: string;
}

/** 并行期正式通道：claw → 达妮娅结构化 Tick。 */
export async function feishuTick(
	session: DanyaSession,
	req: FeishuTickRequest,
): Promise<FeishuTickDecision> {
	const timeoutMs = req.timeoutMs ?? 120_000;
	const controller = new AbortController();
	const timer = setTimeout(() => controller.abort(), timeoutMs);
	try {
		const res = await fetch(`${session.url}/api/channels/feishu/tick`, {
			method: "POST",
			headers: {
				"content-type": "application/json",
				"X-Danya-Token": session.token,
			},
			signal: controller.signal,
			body: JSON.stringify({
				chat_id: req.chatId,
				message_id: req.messageId || "",
				text: req.text,
				mentioned: Boolean(req.mentioned),
				authorized: Boolean(req.authorized),
				has_pending_cursor: Boolean(req.hasPendingCursor),
				pending_cursor_intent: req.pendingCursorIntent || "",
				near_messages: req.nearMessages || [],
				thread_id: req.threadId || `lark:xiaozu:${req.chatId}`,
			}),
		});
		const body = (await res.json()) as FeishuTickDecision & { error?: string };
		if (!res.ok) {
			throw new Error(body.error || `danya tick HTTP ${res.status}`);
		}
		return {
			action: typeof body.action === "string" ? body.action : "silence",
			confidence: typeof body.confidence === "number" ? body.confidence : 0,
			reason: typeof body.reason === "string" ? body.reason : "",
			message: typeof body.message === "string" ? body.message : "",
			cursor_intent: typeof body.cursor_intent === "string" ? body.cursor_intent : "",
			decision_title: typeof body.decision_title === "string" ? body.decision_title : "",
		};
	} finally {
		clearTimeout(timer);
	}
}
