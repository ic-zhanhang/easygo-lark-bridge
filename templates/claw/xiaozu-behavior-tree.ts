// CLAW_XIAOZHU_BEHAVIOR_TREE — 每条「小组」群消息 Tick 一次，只选择行为

export type BehaviorAction =
	| "silence"
	| "reply"
	| "propose_task"
	| "propose_decision"
	| "ask_cursor"
	| "confirm_cursor"
	| "cancel_cursor"
	| "work";

export interface BehaviorDecision {
	action: BehaviorAction;
	confidence: number;
	reason: string;
	message: string;
	task?: unknown;
}

export interface GroupMessageTick {
	kind: "group_message";
	chatId: string;
	messageId: string;
	text: string;
	messageType: string;
	mentioned: boolean;
	authorized: boolean;
	/** 去 @ 后无实质正文：应恢复对话，禁止闷声 */
	bareMention?: boolean;
}

export interface XiaozuBehaviorDependencies {
	classifySocial: (event: GroupMessageTick) => Promise<BehaviorDecision>;
}

type NodeStatus = "success" | "failure" | "running";
interface NodeResult {
	status: NodeStatus;
	decision?: BehaviorDecision;
}
interface BehaviorNode {
	tick(event: GroupMessageTick): Promise<NodeResult>;
}

function condition(predicate: (event: GroupMessageTick) => boolean): BehaviorNode {
	return {
		async tick(event) {
			return { status: predicate(event) ? "success" : "failure" };
		},
	};
}

function action(run: (event: GroupMessageTick) => Promise<BehaviorDecision> | BehaviorDecision): BehaviorNode {
	return {
		async tick(event) {
			return { status: "success", decision: await run(event) };
		},
	};
}

function sequence(children: BehaviorNode[]): BehaviorNode {
	return {
		async tick(event) {
			let decision: BehaviorDecision | undefined;
			for (const child of children) {
				const result = await child.tick(event);
				if (result.status !== "success") return result;
				if (result.decision) decision = result.decision;
			}
			return { status: "success", decision };
		},
	};
}

function prioritySelector(children: BehaviorNode[]): BehaviorNode {
	return {
		async tick(event) {
			for (const child of children) {
				const result = await child.tick(event);
				if (result.status !== "failure") return result;
			}
			return { status: "failure" };
		},
	};
}

function decision(
	actionName: BehaviorAction,
	reason: string,
	message = "",
): BehaviorDecision {
	return { action: actionName, confidence: 1, reason, message };
}

export function isHardSilentMessage(text: string): boolean {
	const normalized = text.replace(/<at\b[^>]*>.*?<\/at>/gis, "").trim();
	if (!normalized || normalized.startsWith("/") || normalized.length <= 1) return true;
	return /^(嗯+|哦+|哈+|哈哈哈*|好+|好的|收到|了解|行|可以|ok|okay|thx|thanks|谢谢|辛苦了|[👍👌🙏😂🤣❤️❤]+)[!！。.，,\s]*$/i.test(
		normalized,
	);
}

/**
 * Interface: one group-message event in, one selected behavior out.
 * The tree owns no memory or task state; leaf adapters may call external modules.
 *
 * Dialogue always goes to Qwen (after hard-silence). Cursor `work` is NOT selected
 * here — only the group-agent layer may promote an authorized candidate confirmation
 * to work before calling this tree.
 */
export function createXiaozuBehaviorTree(dependencies: XiaozuBehaviorDependencies) {
	const root = prioritySelector([
		sequence([
			condition((event) => isHardSilentMessage(event.text)),
			action(() => decision("silence", "hard_silence")),
		]),
		action(async (event) => {
			try {
				return await dependencies.classifySocial(event);
			} catch {
				return decision("silence", "social_leaf_error");
			}
		}),
	]);

	return {
		async tick(event: GroupMessageTick): Promise<BehaviorDecision> {
			const result = await root.tick(event);
			return result.decision ?? decision("silence", "no_behavior");
		},
	};
}
