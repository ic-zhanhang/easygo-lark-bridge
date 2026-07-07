// CLAW_OPERATOR_REGISTRY — 仅记录本 Bot WebSocket 事件里的 open_id（不用外部 lark-cli）
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "fs";
import { dirname } from "path";

export type FeishuMention = { key: string; id: string | { open_id?: string }; name: string };

export interface SenderRecord {
	openId: string;
	name?: string;
	lastSeen: string;
}

export type RegistryStore = Record<string, SenderRecord>;

export function getMentionOpenId(m: FeishuMention): string | undefined {
	const id = m.id;
	if (!id) return undefined;
	if (typeof id === "string") return id;
	return id.open_id;
}

function loadStore(path: string): RegistryStore {
	if (!existsSync(path)) return {};
	try {
		return JSON.parse(readFileSync(path, "utf-8")) as RegistryStore;
	} catch {
		return {};
	}
}

function saveStore(path: string, store: RegistryStore): void {
	mkdirSync(dirname(path), { recursive: true });
	writeFileSync(path, `${JSON.stringify(store, null, 2)}\n`);
}

export function recordSender(path: string, openId: string, name?: string): void {
	if (!openId) return;
	const store = loadStore(path);
	const prev = store[openId];
	store[openId] = {
		openId,
		name: name?.replace(/^@/, "") || prev?.name,
		lastSeen: new Date().toISOString(),
	};
	saveStore(path, store);
}

export function recordMentions(
	path: string,
	mentions: FeishuMention[],
	botOpenId?: string,
): void {
	for (const m of mentions) {
		const openId = getMentionOpenId(m);
		if (!openId || (botOpenId && openId === botOpenId)) continue;
		recordSender(path, openId, m.name);
	}
}

export function lookupByName(path: string, targetName: string): SenderRecord | undefined {
	const name = targetName.replace(/^@/, "").trim();
	if (!name) return undefined;
	const store = loadStore(path);
	for (const rec of Object.values(store)) {
		if (rec.name === name) return rec;
	}
	return undefined;
}

/** 用本 Bot contact API 补全注册表里缺名字的 sender（仅 Bot 视角 open_id） */
export async function enrichMissingNames(
	path: string,
	fetchUserName: (openId: string) => Promise<string | undefined>,
): Promise<void> {
	const store = loadStore(path);
	for (const rec of Object.values(store)) {
		if (rec.name) continue;
		const name = await fetchUserName(rec.openId);
		if (name) recordSender(path, rec.openId, name);
	}
}

export function loadRegistry(path: string): RegistryStore {
	return loadStore(path);
}
