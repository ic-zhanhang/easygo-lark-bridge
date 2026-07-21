import { describe, expect, test } from "bun:test";
import {
	gateInboundMessage,
	parseEasyGoSlash,
	easyGoHelpText,
	unknownSlashReply,
	NO_THREAD_REPLY,
	P2P_INBOUND_REPLY,
	RESET_REPLY,
} from "../templates/claw/easygo-commands.ts";
import { getTopicKey } from "../templates/claw/topic-agent.ts";

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

	test("p2p inbound is rejected", () => {
		const r = gateInboundMessage("p2p", undefined);
		expect(r.action).toBe("reject");
		if (r.action === "reject") {
			expect(r.reason).toBe("p2p_inbound");
			expect(r.reply).toBe(P2P_INBOUND_REPLY);
		}
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
		expect(help).toContain("/心跳");
		expect(help).not.toContain("/记忆");
		expect(help).not.toContain("/会话");
	});

	test("reset aliases", () => {
		expect(parseEasyGoSlash("/新对话")).toEqual({ kind: "reset" });
		expect(parseEasyGoSlash("/reset")).toEqual({ kind: "reset" });
		expect(parseEasyGoSlash("/new")).toEqual({ kind: "reset" });
		expect(RESET_REPLY).toContain("Topic Session");
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
