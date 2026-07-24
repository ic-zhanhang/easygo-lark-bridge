#!/usr/bin/env bun
/**
 * 小组行为树仿真：不接飞书 / Ollama / Cursor，只跑 Priority Selector。
 *
 *   bun scripts/sim-xiaozu-behavior-tree.ts
 */
import {
	createXiaozuBehaviorTree,
	isHardSilentMessage,
	type GroupMessageTick,
} from "../templates/claw/xiaozu-behavior-tree.ts";

type Scenario = {
	name: string;
	event: Omit<GroupMessageTick, "kind" | "chatId" | "messageId" | "messageType">;
	/** 若走到 Social Leaf，假 Qwen 返回什么 */
	social?: { action: "silence" | "reply" | "propose_task"; message?: string };
};

const scenarios: Scenario[] = [
	{
		name: "① 有人 @ 且有权限",
		event: { text: "@达妮娅 帮我检查回归日志", mentioned: true, authorized: true },
	},
	{
		name: "② 有人 @ 但没权限",
		event: { text: "@达妮娅 帮我改代码", mentioned: true, authorized: false },
		social: {
			action: "reply",
			message: "我可以聊聊怎么做，但不能替你执行。",
		},
	},
	{
		name: "② 硬静默：附和",
		event: { text: "好的", mentioned: false, authorized: false },
	},
	{
		name: "② 硬静默：表情",
		event: { text: "👍", mentioned: false, authorized: false },
	},
	{
		name: "③ 实质讨论 → Qwen 提议任务",
		event: {
			text: "谁整理一下今天的回归结果？",
			mentioned: false,
			authorized: false,
		},
		social: {
			action: "propose_task",
			message: "需要我整理的话 @我。",
		},
	},
	{
		name: "③ 明确提问 → Qwen 短答",
		event: {
			text: "仿真默认端口是多少？",
			mentioned: false,
			authorized: false,
		},
		social: { action: "reply", message: "WebApp 一般是 18088。" },
	},
	{
		name: "③ 闲聊 → Qwen 也选静默",
		event: {
			text: "中午吃什么？",
			mentioned: false,
			authorized: false,
		},
		social: { action: "silence" },
	},
];

function predictBranch(event: GroupMessageTick): string {
	if (event.mentioned && event.authorized) return "① Sequence: @+授权 → work";
	if (isHardSilentMessage(event.text)) return "② Sequence: 硬静默 → silence";
	return event.mentioned
		? "③ Social Leaf: @未授权 → 交给假 Qwen"
		: "③ Social Leaf: 交给假 Qwen";
}

async function main() {
	console.log("小组行为树仿真（真实 createXiaozuBehaviorTree）\n");
	console.log("Priority Selector 规则：从左到右试，第一个成功就停。\n");

	for (const [i, scenario] of scenarios.entries()) {
		let socialCalls = 0;
		const tree = createXiaozuBehaviorTree({
			classifySocial: async () => {
				socialCalls++;
				const s = scenario.social ?? { action: "silence" as const };
				return {
					action: s.action,
					confidence: 0.9,
					reason: "sim_qwen",
					message: s.message ?? "",
					task:
						s.action === "propose_task"
							? { id: "candidate-sim", title: scenario.event.text }
							: undefined,
				};
			},
		});

		const event: GroupMessageTick = {
			kind: "group_message",
			chatId: "oc_sim",
			messageId: `om_${i}`,
			messageType: "text",
			...scenario.event,
		};

		const decision = await tree.tick(event);
		const branch = predictBranch(event);

		console.log("─".repeat(60));
		console.log(scenario.name);
		console.log(`  消息: 「${event.text}」`);
		console.log(`  输入: mentioned=${event.mentioned} authorized=${event.authorized}`);
		console.log(`  预期分支: ${branch}`);
		console.log(
			`  决策: action=${decision.action} reason=${decision.reason}` +
				(decision.message ? ` message=「${decision.message}」` : ""),
		);
		console.log(`  Social Leaf 调用次数: ${socialCalls}`);
	}

	console.log("─".repeat(60));
	console.log("\n读法：①② 是代码硬规则；其余消息（含无权限 @）落到 ③，交给本地 Qwen。");
	console.log("work 只表示「选中干活行为」；真调 Cursor 在树外适配器里。");
}

await main();
