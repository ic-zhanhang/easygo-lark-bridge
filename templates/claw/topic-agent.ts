// CLAW_TOPIC_AGENT — 话题并行槽位、Linux 仿真主机互斥（Relay：无 topics jsonl）
import { spawnSync } from "child_process";

export const MAX_TOPIC_PARALLEL = 3;

/**
 * Topic Session 的 topicKey：仅群聊 thread_id。
 * 私聊不产生 topicKey（入站由 Group Topic Only 拒绝）。
 */
export function getTopicKey(chatType: string, threadId: string | undefined, _senderOpenId?: string): string | undefined {
	if (chatType === "group") return threadId || undefined;
	return undefined;
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

/** 测试用：清空并行槽（勿在生产路径调用） */
export function __resetTopicParallelSlotsForTests(): void {
	activeTopicSlots.clear();
	topicSlotWaiters.length = 0;
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
