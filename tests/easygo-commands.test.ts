import { describe, expect, test } from "bun:test";
import {
	gateInboundMessage,
	parseEasyGoSlash,
	easyGoHelpText,
	unknownSlashReply,
	formatCursorContext,
	parseAgentTranscriptJsonl,
	formatTranscriptTurns,
	cursorProjectSlug,
	p2pTopicKey,
	NO_THREAD_REPLY,
	P2P_INBOUND_REPLY,
	RESET_REPLY,
} from "../templates/claw/easygo-commands.ts";
import { getTopicKey } from "../templates/claw/topic-agent.ts";

const L1 = "ou_authorizer";
const L2 = "ou_other";
const authorizers = new Set([L1]);

describe("Group Topic Only inbound gate", () => {
	test("group with thread_id is allowed with topicKey", () => {
		const r = gateInboundMessage("group", "thr-1");
		expect(r).toEqual({ action: "allow", topicKey: "thr-1" });
	});

	test("group without thread_id is rejected with tip", () => {
		const r = gateInboundMessage("group", undefined);
		expect(r.action).toBe("reject");
		if (r.action === "reject") {
			expect(r.reason).toBe("no_thread");
			expect(r.reply).toBe(NO_THREAD_REPLY);
		}
	});

	test("designated main group gets one stable shared topicKey", () => {
		const r = gateInboundMessage("group", undefined, {
			mainGroupTopicKey: "xiaozu:oc_123",
		});
		expect(r).toEqual({ action: "allow", topicKey: "xiaozu:oc_123" });
	});

	test("non-authorizer p2p inbound is rejected", () => {
		const r = gateInboundMessage("p2p", undefined, {
			senderOpenId: L2,
			authorizerOpenIds: authorizers,
		});
		expect(r.action).toBe("reject");
		if (r.action === "reject") {
			expect(r.reason).toBe("p2p_inbound");
			expect(r.reply).toBe(P2P_INBOUND_REPLY);
		}
	});

	test("p2p without authorizer list is rejected", () => {
		const r = gateInboundMessage("p2p", undefined, { senderOpenId: L1 });
		expect(r.action).toBe("reject");
	});

	test("authorizer p2p inbound is allowed with p2p topicKey", () => {
		const r = gateInboundMessage("p2p", undefined, {
			senderOpenId: L1,
			authorizerOpenIds: authorizers,
		});
		expect(r).toEqual({ action: "allow", topicKey: p2pTopicKey(L1) });
		expect(r.action === "allow" && r.topicKey).toBe(`p2p:${L1}`);
	});

	test("authorizer private chatType also allowed", () => {
		const r = gateInboundMessage("private", undefined, {
			senderOpenId: L1,
			authorizerOpenIds: [L1],
		});
		expect(r).toEqual({ action: "allow", topicKey: `p2p:${L1}` });
	});

	test("getTopicKey only returns group thread_id", () => {
		expect(getTopicKey("group", "thr-9", "ou_x")).toBe("thr-9");
		expect(getTopicKey("group", undefined, "ou_x")).toBeUndefined();
		expect(getTopicKey("p2p", undefined, "ou_x")).toBeUndefined();
	});
});

describe("EasyGo slash commands", () => {
	test("help", () => {
		expect(parseEasyGoSlash("/help")).toEqual({ kind: "help" });
		expect(parseEasyGoSlash("/帮助")).toEqual({ kind: "help" });
		const help = easyGoHelpText();
		expect(help).toContain("/新对话");
		expect(help).toContain("/reset");
		expect(help).toContain("/上下文");
		expect(help).toContain("/会话历史");
		expect(help).toContain("/心跳");
		expect(help).toContain("授权人也可私聊");
		expect(help).not.toContain("/记忆");
		expect(help).not.toContain("- `/会话` —");
	});

	test("reset aliases", () => {
		expect(parseEasyGoSlash("/新对话")).toEqual({ kind: "reset" });
		expect(parseEasyGoSlash("/reset")).toEqual({ kind: "reset" });
		expect(parseEasyGoSlash("/new")).toEqual({ kind: "reset" });
		expect(RESET_REPLY).toContain("Topic Session");
	});

	test("context aliases", () => {
		expect(parseEasyGoSlash("/上下文")).toEqual({ kind: "context" });
		expect(parseEasyGoSlash("/context")).toEqual({ kind: "context" });
		expect(parseEasyGoSlash("/会话历史")).toEqual({ kind: "context" });
		expect(parseEasyGoSlash("/上下文 @达妮娅")).toEqual({ kind: "context" });
		const body = formatCursorContext({ topicKey: "xiaozu:oc_1", sessionId: "sess-1" });
		expect(body).toContain("xiaozu:oc_1");
		expect(body).toContain("sess-1");
		expect(body).toContain("对话内容");
		expect(formatCursorContext({})).toContain("下次 @");
		expect(formatCursorContext({ topicKey: "p2p:ou_x" })).toContain("下次私聊");
		expect(easyGoHelpText()).toContain("对话内容");
	});

	test("parse and format agent transcript", () => {
		const raw = [
			JSON.stringify({
				role: "user",
				message: {
					content: [
						{
							type: "text",
							text: "<timestamp>t</timestamp>\n<user_query>\n你好\n</user_query>",
						},
					],
				},
			}),
			JSON.stringify({
				role: "assistant",
				message: { content: [{ type: "text", text: "先看一下…" }] },
			}),
			JSON.stringify({
				role: "assistant",
				message: { content: [{ type: "text", text: "……嗯，好了。" }] },
			}),
			JSON.stringify({
				role: "assistant",
				message: { content: [{ type: "text", text: "" }] },
			}),
		].join("\n");
		const turns = parseAgentTranscriptJsonl(raw);
		expect(turns).toEqual([
			{ role: "user", text: "你好" },
			{ role: "assistant", text: "……嗯，好了。" },
		]);
		const md = formatTranscriptTurns(turns);
		expect(md).toContain("**你**");
		expect(md).toContain("你好");
		expect(md).toContain("**助手**");
		expect(md).toContain("……嗯，好了。");
		expect(cursorProjectSlug("/Users/ic/workspace/easygo-lark-bridge/runtime")).toBe(
			"Users-ic-workspace-easygo-lark-bridge-runtime",
		);
	});

	test("heartbeat passthrough", () => {
		const r = parseEasyGoSlash("/心跳 立即");
		expect(r.kind).toBe("heartbeat");
	});

	test("stop passthrough", () => {
		expect(parseEasyGoSlash("/终止").kind).toBe("stop");
	});

	test("unknown upstream slash rejected", () => {
		const r = parseEasyGoSlash("/记忆 foo");
		expect(r).toEqual({ kind: "unknown", cmd: "/记忆" });
		expect(unknownSlashReply("/记忆")).toContain("/help");
	});

	test("not slash", () => {
		expect(parseEasyGoSlash("帮我看 CI")).toEqual({ kind: "not_slash" });
	});
});
