// CLAW_TOPIC_AGENT — 话题存储、并行槽位、Linux 仿真主机互斥
import { appendFileSync, existsSync, mkdirSync, readdirSync, readFileSync, statSync, unlinkSync } from "fs";
import { spawnSync } from "child_process";
import { resolve } from "path";

export const MAX_TOPIC_PARALLEL = 3;
export const TOPIC_RETENTION_MS = 3 * 24 * 60 * 60 * 1000;

export interface TopicMessageRecord {
	ts: string;
	message_id?: string;
	role: "user" | "assistant";
	sender_open_id?: string;
	text: string;
	image_path?: string;
	message_type?: string;
}

export function sanitizeTopicKey(key: string): string {
	return key.replace(/[^a-zA-Z0-9._-]/g, "_");
}

export function getTopicKey(chatType: string, threadId: string | undefined, senderOpenId?: string): string | undefined {
	if (chatType === "group") return threadId || undefined;
	if (senderOpenId) return `p2p-${senderOpenId}`;
	return undefined;
}

export function topicsDir(workspace: string): string {
	const dir = resolve(workspace, "topics");
	mkdirSync(dir, { recursive: true });
	return dir;
}

export function getTopicFilePath(workspace: string, topicKey: string): string {
	return resolve(topicsDir(workspace), `${sanitizeTopicKey(topicKey)}.jsonl`);
}

export function appendTopicMessage(workspace: string, topicKey: string, record: TopicMessageRecord): void {
	const file = getTopicFilePath(workspace, topicKey);
	const line = `${JSON.stringify(record)}\n`;
	appendFileSync(file, line, "utf-8");
}

export function cleanupOldTopicFiles(workspace: string): void {
	const dir = topicsDir(workspace);
	const cutoff = Date.now() - TOPIC_RETENTION_MS;
	for (const f of readdirSync(dir)) {
		if (!f.endsWith(".jsonl")) continue;
		const p = resolve(dir, f);
		try {
			if (statSync(p).mtimeMs < cutoff) unlinkSync(p);
		} catch {}
	}
}

export function shouldLoadTopicHistory(prompt: string): boolean {
	return /读.*话题|话题.*所有|所有消息|读完.*话题|看看.*话题|回顾.*话题|结合.*话题.*消息/i.test(prompt);
}

/** 群话题默认带上下文；私聊仍需明确要求才附话题文件 */
export function shouldAttachTopicHistory(chatType: string, prompt: string): boolean {
	if (chatType === "group") return true;
	return shouldLoadTopicHistory(prompt);
}

/** 内联进 Agent prompt 的话题上下文上限（字符），超长则保留最近部分 */
export const TOPIC_CONTEXT_MAX_CHARS = 60_000;

function formatTopicHistoryInline(workspace: string, topicKey: string): string {
	const file = getTopicFilePath(workspace, topicKey);
	if (!existsSync(file)) return "（本地尚无历史）";
	const lines = readFileSync(file, "utf-8").split("\n").filter((l) => l.trim());
	const blocks: string[] = [];
	for (const line of lines) {
		try {
			const e = JSON.parse(line) as TopicMessageRecord;
			const who = e.role === "user" ? "用户" : "Bot";
			const img = e.image_path ? `\n[图片: ${e.image_path}]` : "";
			const text = (e.text || "").trim();
			if (!text && !e.image_path) continue;
			blocks.push(`[${who}] ${text}${img}`);
		} catch {
			/* skip bad line */
		}
	}
	let body = blocks.join("\n\n");
	if (body.length > TOPIC_CONTEXT_MAX_CHARS) {
		body = body.slice(body.length - TOPIC_CONTEXT_MAX_CHARS);
		const cut = body.indexOf("\n\n[");
		if (cut > 0 && cut < 800) body = body.slice(cut + 2);
		body = `…（较早记录已截断）\n\n${body}`;
	}
	return body || "（本地尚无有效历史条目）";
}

/**
 * 把本话题历史直接注入 prompt（不依赖 Agent 再 Read）。
 * 从根本上保证：每次任务只带当前话题上下文，不附其它话题。
 */
export function topicHistoryPromptSuffix(workspace: string, topicKey: string): string {
	const file = getTopicFilePath(workspace, topicKey);
	const body = formatTopicHistoryInline(workspace, topicKey);
	return `

[本话题上下文 — 唯一有效对话历史]
归档文件: ${file}
硬性规则：
1. 仅依据下方本话题记录 + 当前用户消息理解意图并回复。
2. 禁止读取其它 topics/*.jsonl、MEMORY、agent-transcripts、其它群聊/私聊记录来补充「对话上下文」。
3. 下文已内联本话题全文（过长则截断较早部分）；无需再 Read 该 jsonl，除非用户明确要求核对原文。
4. 查代码/文档/跑命令仍按任务需要；那不属于「对话上下文」。

${body}

[本话题上下文结束]`;
}

const activeTopicSlots = new Set<string>();
const topicSlotWaiters: Array<() => void> = [];

export async function acquireTopicParallelSlot(topicKey: string): Promise<() => void> {
	await new Promise<void>((resolveWait) => {
		const tryAcquire = () => {
			if (activeTopicSlots.has(topicKey) || activeTopicSlots.size < MAX_TOPIC_PARALLEL) {
				activeTopicSlots.add(topicKey);
				resolveWait();
				return;
			}
			topicSlotWaiters.push(tryAcquire);
		};
		tryAcquire();
	});
	let released = false;
	return () => {
		if (released) return;
		released = true;
		activeTopicSlots.delete(topicKey);
		const next = topicSlotWaiters.shift();
		if (next) next();
	};
}

export function topicLockKey(topicKey: string | undefined, workspaceFallbackKey: string): string {
	return topicKey ? `thread:${topicKey}` : workspaceFallbackKey;
}

export function isSimLaunchIntent(prompt: string): boolean {
	return /仿真|sim_easygo|ros2\s+launch.*sim|gazebo|Caterpiller|启动.*sim/i.test(prompt);
}

export function isSimRunningOnHost(): boolean {
	try {
		if (spawnSync("pgrep", ["-f", "sim_easygo.launch"], { encoding: "utf-8" }).status === 0) return true;
		if (spawnSync("pgrep", ["-f", "gz sim"], { encoding: "utf-8" }).status === 0) return true;
		const d = spawnSync("docker", ["exec", "easygo-dev-main", "pgrep", "-f", "gz"], { encoding: "utf-8" });
		if (d.status === 0) return true;
	} catch {}
	return false;
}

export function simHostBusyMessage(): string {
	return "本机已有仿真正在运行。Linux 同时只能跑一个仿真，请等当前仿真结束后再启动。";
}

/** 从用户消息文本提取图片路径（handleInner 下载后写入） */
export function extractImagePathFromText(text: string): string | undefined {
	const m = text.match(/\[附件图片:\s*([^\]]+)\]/);
	return m?.[1]?.trim();
}
