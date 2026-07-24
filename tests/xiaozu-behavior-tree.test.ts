import { describe, expect, test } from "bun:test";
import {
	createXiaozuBehaviorTree,
	type GroupMessageTick,
} from "../templates/claw/xiaozu-behavior-tree.ts";

function message(overrides: Partial<GroupMessageTick> = {}): GroupMessageTick {
	return {
		kind: "group_message",
		chatId: "oc_1",
		messageId: "om_1",
		text: "帮我检查一下代码",
		messageType: "text",
		mentioned: true,
		authorized: true,
		...overrides,
	};
}

describe("Xiaozu behavior tree", () => {
	test("an authorized mention selects work before social classification", async () => {
		let socialCalls = 0;
		const tree = createXiaozuBehaviorTree({
			classifySocial: async () => {
				socialCalls++;
				return { action: "reply", confidence: 1, reason: "social", message: "不该调用" };
			},
		});

		const result = await tree.tick(message());

		expect(result).toEqual({
			action: "work",
			confidence: 1,
			reason: "mentioned_authorized",
			message: "",
		});
		expect(socialCalls).toBe(0);
	});

	test("a substantive unauthorized mention goes to social classification without work", async () => {
		let socialCalls = 0;
		const tree = createXiaozuBehaviorTree({
			classifySocial: async () => {
				socialCalls++;
				return {
					action: "reply",
					confidence: 0.92,
					reason: "social_reply",
					message: "我可以先聊聊，但不能替你执行。",
				};
			},
		});

		const result = await tree.tick(message({ authorized: false }));

		expect(result.action).toBe("reply");
		expect(result.message).toBe("我可以先聊聊，但不能替你执行。");
		expect(result.action).not.toBe("work");
		expect(socialCalls).toBe(1);
	});

	test("a trivial unauthorized mention still selects hard silence", async () => {
		let socialCalls = 0;
		const tree = createXiaozuBehaviorTree({
			classifySocial: async () => {
				socialCalls++;
				return { action: "reply", confidence: 1, reason: "social", message: "不该调用" };
			},
		});

		const result = await tree.tick(message({ authorized: false, text: "收到" }));

		expect(result.action).toBe("silence");
		expect(result.reason).toBe("hard_silence");
		expect(socialCalls).toBe(0);
	});

	test("a trivial unmentioned message selects hard silence", async () => {
		let socialCalls = 0;
		const tree = createXiaozuBehaviorTree({
			classifySocial: async () => {
				socialCalls++;
				return { action: "reply", confidence: 1, reason: "social", message: "不该调用" };
			},
		});

		const result = await tree.tick(message({
			mentioned: false,
			authorized: false,
			text: "收到",
		}));

		expect(result.reason).toBe("hard_silence");
		expect(socialCalls).toBe(0);
	});

	test("a substantive unmentioned message calls the social leaf exactly once", async () => {
		let socialCalls = 0;
		const tree = createXiaozuBehaviorTree({
			classifySocial: async () => {
				socialCalls++;
				return {
					action: "propose_task",
					confidence: 0.91,
					reason: "clear_task",
					message: "需要我整理的话 @我。",
					task: { id: "candidate-1" },
				};
			},
		});

		const result = await tree.tick(message({
			mentioned: false,
			authorized: false,
			text: "谁整理一下今天的回归结果？",
		}));

		expect(result.action).toBe("propose_task");
		expect(result.task).toEqual({ id: "candidate-1" });
		expect(socialCalls).toBe(1);
	});

	test("a failed social leaf falls back to silence", async () => {
		const tree = createXiaozuBehaviorTree({
			classifySocial: async () => {
				throw new Error("local model offline");
			},
		});

		const result = await tree.tick(message({
			mentioned: false,
			authorized: false,
			text: "大家觉得这个方案怎么样？",
		}));

		expect(result.action).toBe("silence");
		expect(result.reason).toBe("social_leaf_error");
	});
});
