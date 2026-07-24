// CLAW_XIAOZHU_SPECTATOR — 「小组」群旁观日志：入站落盘（含媒体），不起 Agent
import { appendFileSync, existsSync, mkdirSync, readFileSync, writeFileSync } from "fs";
import { dirname, extname, resolve } from "path";

/** 默认「小组」chat_id；可用 config/easygo.env 的 XIAOZHU_CHAT_ID 覆盖（逗号分隔可多个） */
export const DEFAULT_XIAOZHU_CHAT_ID = "oc_0a2bd151890eede76f4595a89e5f21c2";

export interface SpectatorEntry {
	ts: string;
	message_id: string;
	chat_id: string;
	chat_type: string;
	thread_id?: string;
	sender_open_id: string;
	sender_name?: string;
	message_type: string;
	text: string;
	/** 飞书 image_key / file_key */
	media_key?: string;
	/** 本机相对 runtime 的路径，或绝对路径 */
	media_path?: string;
	file_name?: string;
	source?: string;
}

export function shanghaiDateKey(d = new Date()): string {
	return new Intl.DateTimeFormat("en-CA", {
		timeZone: "Asia/Shanghai",
		year: "numeric",
		month: "2-digit",
		day: "2-digit",
	}).format(d);
}

export function shanghaiIso(d = new Date()): string {
	const parts = new Intl.DateTimeFormat("en-CA", {
		timeZone: "Asia/Shanghai",
		year: "numeric",
		month: "2-digit",
		day: "2-digit",
		hour: "2-digit",
		minute: "2-digit",
		second: "2-digit",
		hour12: false,
	}).formatToParts(d);
	const get = (t: string) => parts.find((p) => p.type === t)?.value ?? "00";
	return `${get("year")}-${get("month")}-${get("day")}T${get("hour")}:${get("minute")}:${get("second")}+08:00`;
}

export function spectatorLogPath(workspace: string, dateKey = shanghaiDateKey()): string {
	return resolve(workspace, "文档", "小组旁观", `${dateKey}.jsonl`);
}

export function spectatorMediaDir(workspace: string, dateKey = shanghaiDateKey()): string {
	return resolve(workspace, "文档", "小组旁观", "media", dateKey);
}

function safeKey(s: string): string {
	return s.replace(/[^a-zA-Z0-9._-]+/g, "_").slice(0, 120);
}

/** 稳定文件名：同一 message+key 重复下载会覆盖/跳过 */
export function spectatorMediaFilePath(
	workspace: string,
	messageId: string,
	fileKey: string,
	ext: string,
	dateKey = shanghaiDateKey(),
): string {
	let e = ext || "";
	if (e && !e.startsWith(".")) e = `.${e}`;
	if (!e) e = ".bin";
	const base = `${safeKey(messageId)}__${safeKey(fileKey)}${e}`;
	return resolve(spectatorMediaDir(workspace, dateKey), base);
}

export function resolveSpectatorChatIds(envText?: string): Set<string> {
	let raw = (process.env.XIAOZHU_CHAT_ID || "").trim();
	if (!raw && envText) {
		for (const line of envText.split("\n")) {
			const t = line.trim();
			if (!t || t.startsWith("#")) continue;
			const eq = t.indexOf("=");
			if (eq < 0) continue;
			const k = t.slice(0, eq).trim();
			if (k !== "XIAOZHU_CHAT_ID") continue;
			let v = t.slice(eq + 1).trim();
			if (
				(v.startsWith('"') && v.endsWith('"')) ||
				(v.startsWith("'") && v.endsWith("'"))
			) {
				v = v.slice(1, -1);
			}
			raw = v;
			break;
		}
	}
	if (!raw) raw = DEFAULT_XIAOZHU_CHAT_ID;
	return new Set(
		raw
			.split(",")
			.map((s) => s.trim())
			.filter(Boolean),
	);
}

export function loadSpectatorChatIdsFromPack(clawDir = import.meta.dirname): Set<string> {
	const envPath = resolve(clawDir, "..", "config", "easygo.env");
	try {
		if (existsSync(envPath)) return resolveSpectatorChatIds(readFileSync(envPath, "utf-8"));
	} catch {
		/* ignore */
	}
	return resolveSpectatorChatIds();
}

export function guessMediaExt(
	messageType: string,
	fileName?: string,
	fileKey?: string,
): string {
	if (fileName) {
		const e = extname(fileName);
		if (e) return e;
	}
	if (messageType === "image") return ".png";
	if (messageType === "audio") return ".ogg";
	if (messageType === "sticker") return ".png";
	if (messageType === "media" || messageType === "video") return ".mp4";
	if (fileKey?.startsWith("img_")) return ".png";
	return ".bin";
}

export function mediaKindForMessage(messageType: string): "image" | "file" {
	return messageType === "image" || messageType === "sticker" ? "image" : "file";
}

/** 下载并写入旁观 media 目录；已存在则跳过 */
export async function saveSpectatorMedia(
	workspace: string,
	messageId: string,
	fileKey: string,
	ext: string,
	fetchBuffer: () => Promise<Uint8Array | Buffer>,
	dateKey = shanghaiDateKey(),
): Promise<string> {
	const path = spectatorMediaFilePath(workspace, messageId, fileKey, ext, dateKey);
	if (existsSync(path)) return path;
	mkdirSync(dirname(path), { recursive: true });
	const buf = await fetchBuffer();
	writeFileSync(path, buf);
	return path;
}

export function appendSpectatorLine(workspace: string, entry: SpectatorEntry): string {
	const path = spectatorLogPath(workspace);
	mkdirSync(dirname(path), { recursive: true });
	appendFileSync(path, `${JSON.stringify(entry)}\n`, "utf-8");
	return path;
}

/**
 * 读取当天最近的旁观记录。原始 JSONL 是审计事实源；这里只做有界窗口，
 * 避免把整天群聊塞进本地模型或执行模型。
 */
export function readRecentSpectatorEntries(
	workspace: string,
	options?: {
		chatId?: string;
		limit?: number;
		dateKey?: string;
	},
): SpectatorEntry[] {
	const path = spectatorLogPath(workspace, options?.dateKey);
	if (!existsSync(path)) return [];
	const limit = Math.max(1, Math.min(100, options?.limit ?? 20));
	try {
		const lines = readFileSync(path, "utf-8").split("\n");
		const result: SpectatorEntry[] = [];
		for (let i = lines.length - 1; i >= 0 && result.length < limit; i--) {
			const line = lines[i]?.trim();
			if (!line) continue;
			try {
				const entry = JSON.parse(line) as SpectatorEntry;
				if (options?.chatId && entry.chat_id !== options.chatId) continue;
				if (!entry.message_id || !entry.chat_id) continue;
				result.push(entry);
			} catch {
				// 单行损坏不影响其余历史。
			}
		}
		return result.reverse();
	} catch {
		return [];
	}
}

export function maybeAppendSpectator(
	workspace: string,
	chatIds: Set<string>,
	ev: {
		chatId: string;
		chatType: string;
		messageId: string;
		messageType: string;
		text: string;
		senderOpenId: string;
		threadId?: string;
		mediaKey?: string;
		mediaPath?: string;
		fileName?: string;
		senderName?: string;
		source?: string;
	},
): string | null {
	if (ev.chatType !== "group") return null;
	if (!chatIds.has(ev.chatId)) return null;
	const path = appendSpectatorLine(workspace, {
		ts: shanghaiIso(),
		message_id: ev.messageId,
		chat_id: ev.chatId,
		chat_type: ev.chatType,
		thread_id: ev.threadId || undefined,
		sender_open_id: ev.senderOpenId || "",
		sender_name: ev.senderName || undefined,
		message_type: ev.messageType || "text",
		text: (ev.text || "").slice(0, 8000),
		media_key: ev.mediaKey || undefined,
		media_path: ev.mediaPath || undefined,
		file_name: ev.fileName || undefined,
		source: ev.source,
	});
	return path;
}

/** 是否需要为旁观下载媒体 */
export function shouldDownloadSpectatorMedia(
	chatIds: Set<string>,
	chatId: string,
	chatType: string,
	messageType: string,
	imageKey?: string,
	fileKey?: string,
): { key: string; kind: "image" | "file"; extHint: string } | null {
	if (chatType !== "group" || !chatIds.has(chatId)) return null;
	const key = imageKey || fileKey;
	if (!key) return null;
	const downloadable = new Set(["image", "file", "audio", "media", "video", "sticker"]);
	if (!downloadable.has(messageType) && !imageKey && !fileKey) return null;
	if (!downloadable.has(messageType) && !(imageKey || fileKey)) return null;
	// 有 key 就下（含 text 里偶发附件的情况）
	const kind = imageKey || messageType === "image" || messageType === "sticker" ? "image" : "file";
	return { key, kind, extHint: guessMediaExt(messageType, undefined, key) };
}

if (import.meta.main) {
	const args = process.argv.slice(2);
	if (args[0] !== "--self-check") {
		console.error("用法: bun run xiaozu-spectator.ts --self-check [workspace]");
		process.exit(2);
	}
	const ws = resolve(args[1] || resolve(import.meta.dirname, "..", "runtime"));
	const ids = loadSpectatorChatIdsFromPack();
	const mediaPath = await saveSpectatorMedia(
		ws,
		"om_selfcheck",
		"img_selfcheck",
		".txt",
		async () => Buffer.from("spectator-media-ok\n"),
	);
	const path = maybeAppendSpectator(ws, ids, {
		chatId: [...ids][0]!,
		chatType: "group",
		messageId: `selfcheck_${Date.now()}`,
		messageType: "image",
		text: "[Image: selfcheck]",
		senderOpenId: "ou_selfcheck",
		mediaKey: "img_selfcheck",
		mediaPath,
		source: "self-check",
	});
	if (!path || !existsSync(path) || !existsSync(mediaPath)) {
		console.error("self-check 失败");
		process.exit(1);
	}
	console.log(`self-check OK → ${path}`);
	console.log(`media OK → ${mediaPath}`);
}
