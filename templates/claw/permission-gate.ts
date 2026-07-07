// CLAW_PERMISSION_GATE — 聊天权限 vs 授权权限（Claw 层硬校验，不跑 Agent）
export interface PermissionConfig {
	authorizerOpenIds: Set<string>;
	authorizerName: string;
	chatOpenIds: Set<string>;
}

export function parseOpenIdSet(raw: string | undefined): Set<string> {
	return new Set(
		(raw ?? "")
			.split(",")
			.map((s) => s.trim())
			.filter(Boolean),
	);
}

/** 是否为「授予/撤销他人聊天权限」类指令 */
export function isAuthManagementIntent(text: string): boolean {
	const t = text.replace(/\s+/g, "");
	return /授权|聊天权限|对话权限|沟通权限|开权限|加权限|添加权限|移除权限|撤销权限|取消权限|给.{1,12}(开|加|添加|移除|撤销)/.test(
		t,
	);
}

export type PermissionDeny =
	| { ok: false; code: "no_chat"; message: string; title: string }
	| { ok: false; code: "no_auth_grant"; message: string; title: string }
	| { ok: true };

export function checkPermission(
	text: string,
	senderOpenId: string | undefined,
	cfg: PermissionConfig,
): PermissionDeny {
	if (cfg.authorizerOpenIds.size === 0 && cfg.chatOpenIds.size === 0) {
		return { ok: true };
	}
	if (!senderOpenId || !cfg.chatOpenIds.has(senderOpenId)) {
		return {
			ok: false,
			code: "no_chat",
			title: "无聊天权限",
			message: `你没有聊天权限，无法 @我执行任务。如需开通，请联系 **${cfg.authorizerName}**（唯一授权人）。`,
		};
	}
	if (isAuthManagementIntent(text) && !cfg.authorizerOpenIds.has(senderOpenId)) {
		return {
			ok: false,
			code: "no_auth_grant",
			title: "无授权权限",
			message: `你已有聊天权限，但**不能**为他人开通权限。只有 **${cfg.authorizerName}** 可以授权。`,
		};
	}
	return { ok: true };
}

export function buildPermissionConfig(
	authorizerOpenIdsRaw: string,
	authorizerName: string,
	chatOpenIdsRaw: string,
): PermissionConfig {
	const authorizerOpenIds = parseOpenIdSet(authorizerOpenIdsRaw);
	const chatOpenIds = parseOpenIdSet(chatOpenIdsRaw);
	for (const id of authorizerOpenIds) chatOpenIds.add(id);
	return { authorizerOpenIds, authorizerName, chatOpenIds };
}
