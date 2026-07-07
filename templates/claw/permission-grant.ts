// CLAW_PERMISSION_GRANT — L1 在 Claw 层直接改名单（open_id 来自本 Bot 事件/mention/registry）
import { readFileSync, writeFileSync } from "fs";
import { spawnSync } from "child_process";
import { resolve } from "path";
import * as OperatorRegistry from "./operator-registry.js";
import * as PermissionGate from "./permission-gate.js";

export type GrantResult =
	| { ok: true; action: "grant" | "revoke"; openId: string; name: string; message: string }
	| { ok: false; message: string };

function parseTargetName(text: string): string | undefined {
	const compact = text.replace(/\s+/g, "");
	const patterns = [
		/(?:帮(?:我|忙)?)?(?:给|为|帮)(.{1,10}?)(?:添加|加|开|开通|授予)(?:聊天|对话|沟通)?权限/,
		/(?:授权|给|为)(.{1,10}?)(?:聊天|对话|沟通)?权限/,
		/(?:移除|撤销|取消)(.{1,10}?)(?:聊天|对话|沟通)?权限/,
	];
	for (const re of patterns) {
		const m = compact.match(re);
		if (m?.[1]) return m[1].replace(/^@/, "");
	}
	return undefined;
}

function isRevokeIntent(text: string): boolean {
	return /移除|撤销|取消/.test(text.replace(/\s+/g, ""));
}

function readEnvPairs(envPath: string): Map<string, string> {
	const map = new Map<string, string>();
	for (const line of readFileSync(envPath, "utf-8").split("\n")) {
		const trimmed = line.trim();
		if (!trimmed || trimmed.startsWith("#")) continue;
		const eq = trimmed.indexOf("=");
		if (eq < 0) continue;
		map.set(trimmed.slice(0, eq).trim(), trimmed.slice(eq + 1).trim());
	}
	return map;
}

function writeEnvPairs(envPath: string, pairs: Map<string, string>): void {
	const lines = readFileSync(envPath, "utf-8").split("\n");
	const out: string[] = [];
	const written = new Set<string>();
	for (const line of lines) {
		const trimmed = line.trim();
		if (!trimmed || trimmed.startsWith("#")) {
			out.push(line);
			continue;
		}
		const eq = trimmed.indexOf("=");
		if (eq < 0) {
			out.push(line);
			continue;
		}
		const key = trimmed.slice(0, eq).trim();
		if (pairs.has(key)) {
			out.push(`${key}=${pairs.get(key)}`);
			written.add(key);
		} else {
			out.push(line);
		}
	}
	for (const [key, val] of pairs) {
		if (!written.has(key)) out.push(`${key}=${val}`);
	}
	writeFileSync(envPath, `${out.join("\n").replace(/\n+$/, "")}\n`);
}

function splitCsv(raw: string | undefined): string[] {
	return (raw ?? "")
		.split(",")
		.map((s) => s.trim())
		.filter(Boolean);
}

function resolveTarget(
	text: string,
	mentions: OperatorRegistry.FeishuMention[],
	botOpenId: string | undefined,
	registryPath: string,
): { openId: string; name: string } | { error: string } {
	for (const m of mentions) {
		const openId = OperatorRegistry.getMentionOpenId(m);
		if (!openId || (botOpenId && openId === botOpenId)) continue;
		const name = m.name?.replace(/^@/, "") || openId.slice(0, 12);
		return { openId, name };
	}

	const targetName = parseTargetName(text);
	if (!targetName) {
		return { error: "请在指令中 @ 要授权的人，或写明姓名（须曾与本 Bot 对话过）。" };
	}

	const rec = OperatorRegistry.lookupByName(registryPath, targetName);
	if (rec) {
		return { openId: rec.openId, name: rec.name ?? targetName };
	}

	return {
		error: `未在本 Bot 记录中找到「${targetName}」的 open_id。请让对方先 @我发一条消息，或在指令里 @对方。`,
	};
}

function updateOperators(
	envPath: string,
	openId: string,
	name: string,
	revoke: boolean,
): { ids: string[]; names: string[] } {
	const pairs = readEnvPairs(envPath);
	const idsKey =
		pairs.has("CHAT_OPERATOR_OPEN_IDS") || !pairs.has("ALLOWED_OPERATOR_OPEN_IDS")
			? "CHAT_OPERATOR_OPEN_IDS"
			: "ALLOWED_OPERATOR_OPEN_IDS";
	const namesKey =
		pairs.has("CHAT_OPERATOR_NAMES") || !pairs.has("ALLOWED_OPERATOR_NAMES")
			? "CHAT_OPERATOR_NAMES"
			: "ALLOWED_OPERATOR_NAMES";

	let ids = splitCsv(pairs.get(idsKey));
	let names = splitCsv(pairs.get(namesKey));
	const authorizerId = pairs.get("AUTHORIZER_OPEN_ID") ?? ids[0] ?? "";

	if (revoke) {
		const idx = ids.indexOf(openId);
		if (idx >= 0) {
			ids.splice(idx, 1);
			if (idx < names.length) names.splice(idx, 1);
		}
	} else if (!ids.includes(openId)) {
		ids.push(openId);
		names.push(name);
	} else {
		const idx = ids.indexOf(openId);
		if (idx >= 0 && idx < names.length && names[idx] !== name) names[idx] = name;
	}

	if (authorizerId && !ids.includes(authorizerId)) {
		ids.unshift(authorizerId);
		const authorizerName = pairs.get("AUTHORIZER_NAME") ?? "授权人";
		names.unshift(authorizerName);
	}

	pairs.set(idsKey, ids.join(","));
	pairs.set(namesKey, names.join(","));
	writeEnvPairs(envPath, pairs);
	return { ids, names };
}

function readBridgeProfile(envPath: string): string {
	const profile = readEnvPairs(envPath).get("BRIDGE_PROFILE")?.trim();
	if (profile === "mac" || profile === "linux") return profile;
	// 未显式配置时默认 mac（与 sync-authorized-operators.sh 一致）
	return "mac";
}

function syncRules(packRoot: string, runtimeDir: string, envPath: string): void {
	const bridgeProfile = readBridgeProfile(envPath);
	const script = resolve(packRoot, "scripts/sync-authorized-operators.sh");
	const r = spawnSync("bash", [script], {
		cwd: packRoot,
		env: {
			...process.env,
			RUNTIME_DIR: runtimeDir,
			BRIDGE_PROFILE: bridgeProfile,
		},
		stdio: "pipe",
		encoding: "utf-8",
	});
	if (r.status !== 0) {
		console.warn(`[权限] sync-authorized-operators 失败 (profile=${bridgeProfile}):`, r.stderr || r.stdout);
	}
}

export async function handlePermissionGrant(params: {
	text: string;
	mentions: OperatorRegistry.FeishuMention[];
	botOpenId?: string;
	envPath: string;
	packRoot: string;
	runtimeDir: string;
	registryPath: string;
	fetchUserName?: (openId: string) => Promise<string | undefined>;
}): Promise<GrantResult> {
	const { text, mentions, botOpenId, envPath, packRoot, runtimeDir, registryPath, fetchUserName } =
		params;
	if (!PermissionGate.isAuthManagementIntent(text)) {
		return { ok: false, message: "不是授权类指令。" };
	}

	let target = resolveTarget(text, mentions, botOpenId, registryPath);
	if ("error" in target && parseTargetName(text) && fetchUserName) {
		await OperatorRegistry.enrichMissingNames(registryPath, fetchUserName);
		target = resolveTarget(text, mentions, botOpenId, registryPath);
	}
	if ("error" in target) return { ok: false, message: target.error };

	const revoke = isRevokeIntent(text);
	updateOperators(envPath, target.openId, target.name, revoke);
	syncRules(packRoot, runtimeDir, envPath);

	const action = revoke ? "revoke" : "grant";
	const verb = revoke ? "已移除" : "已添加";
	return {
		ok: true,
		action,
		openId: target.openId,
		name: target.name,
		message: `**${target.name}** ${verb}聊天权限（L2）。\n\nopen_id: \`${target.openId}\`\n\n（来自本 Bot 事件，非外部 lark-cli）`,
	};
}
