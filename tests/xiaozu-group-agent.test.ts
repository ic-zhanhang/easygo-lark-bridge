import { afterEach, describe, expect, test } from "bun:test";
import { mkdtempSync, rmSync } from "fs";
import { tmpdir } from "os";
import { resolve } from "path";
import {
	createXiaozuGroupAgent,
	loadXiaozuGroupState,
	type XiaozuGroupAgentConfig,
} from "../templates/claw/xiaozu-group-agent.ts";
import {
	appendSpectatorLine,
	type SpectatorEntry,
} from "../templates/claw/xiaozu-spectator.ts";

const workspaces: string[] = [];
afterEach(() => {
	for (const path of workspaces.splice(0)) rmSync(path, { recursive: true, force: true });
});

function workspace(): string {
	const path = mkdtempSync(resolve(tmpdir(), "xiaozu-group-agent-"));
	workspaces.push(path);
	return path;
}

function config(overrides: Partial<XiaozuGroupAgentConfig> = {}): XiaozuGroupAgentConfig {
	return {
		enabled: true,
		baseUrl: "http://127.0.0.1:11434",
		model: "qwen2.5:14b",
		personaName: "达妮娅",
		timeoutMs: 1000,
		minConfidence: 0.78,
		cooldownMs: 90_000,
		contextMessages: 20,
		...overrides,
	};
}

function line(
	chatId: string,
	messageId: string,
	text: string,
	ts = "2026-07-24T10:00:00+08:00",
): SpectatorEntry {
	return {
		ts,
		message_id: messageId,
		chat_id: chatId,
		chat_type: "group",
		sender_open_id: "ou_test",
		message_type: "text",
		text,
	};
}

describe("Qwen Speak Gate", () => {
	test("an authorized mention ticks to work without calling Qwen", async () => {
		let calls = 0;
		const agent = createXiaozuGroupAgent({
			workspace: workspace(),
			config: config(),
			model: async () => {
				calls++;
				return {};
			},
		});

		const result = await agent.tick({
			kind: "group_message",
			chatId: "oc_1",
			messageId: "om_work",
			text: "帮我检查代码",
			messageType: "text",
			mentioned: true,
			authorized: true,
		});

		expect(result.action).toBe("work");
		expect(calls).toBe(0);
	});

	test("an unauthorized mention is sent to Qwen as social-only input", async () => {
		let calls = 0;
		let userPrompt = "";
		const agent = createXiaozuGroupAgent({
			workspace: workspace(),
			config: config(),
			model: async (request) => {
				calls++;
				userPrompt = request.user;
				return {
					action: "reply",
					confidence: 0.93,
					reason: "social_only",
					message: "我可以和你讨论，但不能替你执行。",
					common_ground: "",
					decisions: [],
					open_questions: [],
					task_title: "",
				};
			},
		});

		const result = await agent.tick({
			kind: "group_message",
			chatId: "oc_1",
			messageId: "om_social_only",
			text: "帮我看看这个思路怎么样",
			messageType: "text",
			mentioned: true,
			authorized: false,
		});

		expect(result.action).toBe("reply");
		expect(result.action).not.toBe("work");
		expect(calls).toBe(1);
		expect(userPrompt).toContain('"mentioned":true');
		expect(userPrompt).toContain('"execution_allowed":false');
	});

	test("hard silence does not call the model", async () => {
		let calls = 0;
		const agent = createXiaozuGroupAgent({
			workspace: workspace(),
			config: config(),
			model: async () => {
				calls++;
				return {};
			},
		});
		const result = await agent.tick({
			kind: "group_message",
			chatId: "oc_1",
			messageId: "om_1",
			text: "收到",
			messageType: "text",
			mentioned: false,
			authorized: false,
		});
		expect(result.action).toBe("silence");
		expect(result.reason).toBe("hard_silence");
		expect(calls).toBe(0);
	});

	test("does not auto-write long-term memory on social reply", async () => {
		const ws = workspace();
		let minute = 0;
		const agent = createXiaozuGroupAgent({
			workspace: ws,
			config: config(),
			now: () => new Date(`2026-07-24T02:0${minute++}:00.000Z`),
			model: async () => ({
				action: "reply",
				confidence: 0.92,
				reason: "can clarify",
				message: "我补一句：先锁接口，再并行实现。",
				common_ground: "先锁定接口，再并行实现。",
				decisions: ["今天先定接口"],
				open_questions: [],
				task_title: "",
				decision_title: "",
			}),
		});
		appendSpectatorLine(ws, line("oc_1", "om_1", "前后端要不要先对接口？"));
		const first = await agent.tick({ kind: "group_message", chatId: "oc_1", messageId: "om_1", text: "前后端要不要先对接口？", messageType: "text", mentioned: false, authorized: false });
		const second = await agent.tick({ kind: "group_message", chatId: "oc_1", messageId: "om_2", text: "我建议今天就定下来", messageType: "text", mentioned: false, authorized: false });
		expect(first.action).toBe("reply");
		expect(second.action).toBe("silence");
		expect(second.reason).toBe("cooldown");
		const state = loadXiaozuGroupState(ws, "oc_1");
		
		expect(state.decisions).toEqual([]);
		expect(state.decision_candidates).toEqual([]);
	});

	test("propose_decision creates candidate card and confirm writes long-term memory", async () => {
		const ws = workspace();
		const agent = createXiaozuGroupAgent({
			workspace: ws,
			config: config(),
			model: async () => ({
				action: "propose_decision",
				confidence: 0.95,
				reason: "杨展航和宋锦涛都强调按使用者拆分",
				message: "",
				task_title: "",
				decision_title: "按使用者拆前端视角",
			}),
		});
		const proposed = await agent.tick({
			kind: "group_message",
			chatId: "oc_1",
			messageId: "om_p1",
			text: "前端要按使用/部署/调试拆开",
			messageType: "text",
			mentioned: false,
			authorized: false,
		});
		expect(proposed.action).toBe("propose_decision");
		expect(proposed.message).toContain("候选决定");
		expect(proposed.message).toContain("按使用者拆前端视角");
		expect(loadXiaozuGroupState(ws, "oc_1").decision_candidates[0]?.status).toBe("pending");
		expect(loadXiaozuGroupState(ws, "oc_1").decisions).toEqual([]);

		const confirmed = await agent.tick({
			kind: "group_message",
			chatId: "oc_1",
			messageId: "om_ok",
			text: "确认记入",
			messageType: "text",
			mentioned: true,
			authorized: true,
		});
		expect(confirmed.action).toBe("reply");
		expect(confirmed.reason).toBe("decision_confirmed");
		expect(confirmed.message).toContain("已记入");
		const state = loadXiaozuGroupState(ws, "oc_1");
		expect(state.decisions).toEqual(["按使用者拆前端视角"]);
		expect(state.decision_candidates).toEqual([]);
	});

	test("reject candidate does not write long-term memory", async () => {
		const ws = workspace();
		const agent = createXiaozuGroupAgent({
			workspace: ws,
			config: config(),
			model: async () => ({
				action: "propose_decision",
				confidence: 0.95,
				reason: "可能是闲聊",
				message: "",
				task_title: "",
				decision_title: "今天天气不错也要记",
			}),
		});
		await agent.tick({
			kind: "group_message",
			chatId: "oc_1",
			messageId: "om_bad",
			text: "今天天气不错",
			messageType: "text",
			mentioned: false,
			authorized: false,
		});
		const rejected = await agent.tick({
			kind: "group_message",
			chatId: "oc_1",
			messageId: "om_no",
			text: "@达妮娅 不是原则",
			messageType: "text",
			mentioned: true,
			authorized: true,
		});
		expect(rejected.reason).toBe("decision_rejected");
		const state = loadXiaozuGroupState(ws, "oc_1");
		expect(state.decisions).toEqual([]);
		
		expect(state.decision_candidates[0]?.status).toBe("rejected");
	});

	test("task intent only creates a candidate and never executes", async () => {
		const ws = workspace();
		const agent = createXiaozuGroupAgent({
			workspace: ws,
			config: config(),
			model: async () => ({
				action: "propose_task",
				confidence: 0.95,
				reason: "clear work item",
				message: "这可以整理成一项任务，需要我做的话 @我确认。",
				common_ground: "需要整理回归结果。",
				decisions: [],
				open_questions: [],
				task_title: "整理今天的回归测试结果",
			}),
		});
		const result = await agent.tick({
			kind: "group_message",
			chatId: "oc_1",
			messageId: "om_task",
			text: "谁整理一下今天的回归测试结果？",
			messageType: "text",
			mentioned: false,
			authorized: false,
		});
		expect(result.action).toBe("propose_task");
		expect(result.task?.status).toBe("candidate");
		expect(loadXiaozuGroupState(ws, "oc_1").tasks[0]?.status).toBe("candidate");

		const turn = agent.buildTaskTurn({
			chatId: "oc_1",
			messageId: "om_confirm",
			request: "你来做这个吧",
		});
		expect(turn.taskId).toBe(result.task?.id);
		expect(turn.prompt).toContain("候选任务");
		agent.completeTaskTurn(turn, "已经整理好回归测试结果");
		expect(loadXiaozuGroupState(ws, "oc_1").tasks[0]?.status).toBe("done");
	});

	test("low-confidence task intent stays silent and is not added to the ledger", async () => {
		const ws = workspace();
		const agent = createXiaozuGroupAgent({
			workspace: ws,
			config: config(),
			model: async () => ({
				action: "propose_task",
				confidence: 0.4,
				reason: "unclear",
				message: "也许可以做。",
				common_ground: "",
				decisions: [],
				open_questions: ["是否真的需要做？"],
				task_title: "猜测出来的任务",
			}),
		});
		const result = await agent.tick({
			kind: "group_message",
			chatId: "oc_1",
			messageId: "om_guess",
			text: "这个以后可能看看",
			messageType: "text",
			mentioned: false,
			authorized: false,
		});
		expect(result.action).toBe("silence");
		expect(loadXiaozuGroupState(ws, "oc_1").tasks).toHaveLength(0);
	});

	test("busy local model drops excess decisions instead of growing an unbounded queue", async () => {
		let releaseFirst: () => void = () => {};
		let markStarted: () => void = () => {};
		const firstStarted = new Promise<void>((resolve) => { markStarted = resolve; });
		const firstGate = new Promise<void>((resolve) => { releaseFirst = resolve; });
		let calls = 0;
		const agent = createXiaozuGroupAgent({
			workspace: workspace(),
			config: config(),
			model: async () => {
				calls++;
				if (calls === 1) {
					markStarted();
					await firstGate;
				}
				return {
					action: "silence",
					confidence: 0.9,
					reason: "no value",
					message: "",
					common_ground: "",
					decisions: [],
					open_questions: [],
					task_title: "",
				};
			},
		});
		const first = agent.tick({ kind: "group_message", chatId: "oc_1", messageId: "om_1", text: "第一条实质消息", messageType: "text", mentioned: false, authorized: false });
		await firstStarted;
		const second = agent.tick({ kind: "group_message", chatId: "oc_1", messageId: "om_2", text: "第二条实质消息", messageType: "text", mentioned: false, authorized: false });
		const third = await agent.tick({ kind: "group_message", chatId: "oc_1", messageId: "om_3", text: "第三条实质消息", messageType: "text", mentioned: false, authorized: false });
		expect(third.reason).toBe("backpressure");
		releaseFirst();
		await Promise.all([first, second]);
		expect(calls).toBe(2);
	});
});
describe("incremental execution context", () => {
	test("watermark prevents replaying old group chat after successful work", () => {
		const ws = workspace();
		const agent = createXiaozuGroupAgent({
			workspace: ws,
			config: config({ cooldownMs: 0 }),
			model: async () => ({}),
			now: () => new Date("2026-07-24T02:00:00.000Z"),
		});
		appendSpectatorLine(ws, line("oc_1", "om_old", "旧讨论：接口叫 A"));
		appendSpectatorLine(ws, line("oc_1", "om_work", "请把接口改成 B", "2026-07-24T10:01:00+08:00"));
		const first = agent.buildTaskTurn({
			chatId: "oc_1",
			messageId: "om_work",
			request: "请把接口改成 B",
		});
		expect(first.prompt).toContain("旧讨论：接口叫 A");
		agent.completeTaskTurn(first, "接口已经改成 B");

		appendSpectatorLine(ws, line("oc_1", "om_new", "顺便补一个测试", "2026-07-24T10:02:00+08:00"));
		const second = agent.buildTaskTurn({
			chatId: "oc_1",
			messageId: "om_new",
			request: "顺便补一个测试",
		});
		expect(second.prompt).not.toContain("旧讨论：接口叫 A");
		expect(second.prompt).toContain("接口已经改成 B");
		expect(second.prompt).toContain("当前 @ 请求");
	});
});


describe("Cursor context inspection", () => {
	test("shows session binding, watermark, and pending inject preview", () => {
		const ws = workspace();
		const agent = createXiaozuGroupAgent({
			workspace: ws,
			config: config(),
			model: async () => ({
				action: "silence",
				confidence: 0.9,
				reason: "n/a",
				message: "",
				common_ground: "先定接口",
				decisions: [],
				open_questions: [],
				task_title: "",
			}),
		});
		appendSpectatorLine(ws, line("oc_1", "om_a", "讨论接口"));
		appendSpectatorLine(ws, line("oc_1", "om_b", "先锁 OpenAPI"));
		const turn = agent.buildTaskTurn({ chatId: "oc_1", messageId: "om_b", request: "按刚才说的改" });
		agent.completeTaskTurn(turn, "已改完");
		appendSpectatorLine(ws, line("oc_1", "om_c", "再补个错误码"));
		const body = agent.describeCursorContext("oc_1", {
			topicKey: "xiaozu:oc_1",
			sessionId: "sess-xyz",
		});
		expect(body).toContain("xiaozu:oc_1");
		expect(body).toContain("sess-xyz");
		expect(body).toContain("om_b");
		expect(body).toContain("再补个错误码");
		expect(body).not.toContain("讨论接口");
	});
});
