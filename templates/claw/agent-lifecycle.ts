/**
 * CLAW_AGENT_LIFECYCLE — Agent 子进程追踪 + 优雅关停
 * 从 server.ts 拆出，降低单体体积；SIGTERM 时通知活跃卡片后退出。
 */

export interface AgentHandle {
	pid: number;
	kill: () => void;
	cardId?: string;
}

const childPids = new Set<number>();
const activeAgents = new Map<string, AgentHandle>();

let shuttingDown = false;
let cardNotifier: ((cardId: string, markdown: string) => Promise<void>) | undefined;

export function isShuttingDown(): boolean {
	return shuttingDown;
}

export function trackChildPid(pid: number): void {
	childPids.add(pid);
}

export function untrackChildPid(pid: number): void {
	childPids.delete(pid);
}

export function registerAgent(lockKey: string, handle: AgentHandle): void {
	activeAgents.set(lockKey, handle);
	if (handle.pid) childPids.add(handle.pid);
}

export function unregisterAgent(lockKey: string): void {
	const h = activeAgents.get(lockKey);
	if (h?.pid) childPids.delete(h.pid);
	activeAgents.delete(lockKey);
}

export function getActiveAgent(lockKey: string): AgentHandle | undefined {
	return activeAgents.get(lockKey);
}

export function setAgentCardId(lockKey: string, cardId: string): void {
	const h = activeAgents.get(lockKey);
	if (h) h.cardId = cardId;
}

/** server.ts 在 updateCard 可用后调用一次 */
export function initGracefulShutdown(
	notifyCard: (cardId: string, markdown: string) => Promise<void>,
	opts?: { maxWaitMs?: number },
): void {
	cardNotifier = notifyCard;
	const maxWaitMs = opts?.maxWaitMs ?? 12_000;

	async function onSigterm(): Promise<void> {
		if (shuttingDown) return;
		shuttingDown = true;
		console.log(`[关停] 收到 SIGTERM，活跃 Agent ${activeAgents.size} 个`);

		const cards = [...activeAgents.values()]
			.map((h) => h.cardId)
			.filter((id): id is string => Boolean(id));

		if (cardNotifier && cards.length > 0) {
			const msg =
				"⚠️ **服务正在重启**\n\n当前任务已中断。请稍后重新发送消息，我会接着处理。";
			await Promise.allSettled(
				cards.map((id) =>
					cardNotifier!(id, msg).catch((e) =>
						console.warn(`[关停] 通知卡片 ${id.slice(0, 12)} 失败:`, e),
					),
				),
			);
		}

		for (const [, h] of activeAgents) {
			try {
				h.kill();
			} catch {}
		}

		const deadline = Date.now() + maxWaitMs;
		while (activeAgents.size > 0 && Date.now() < deadline) {
			await new Promise((r) => setTimeout(r, 200));
		}

		for (const pid of childPids) {
			try {
				process.kill(pid, "SIGTERM");
			} catch {}
		}

		await new Promise((r) => setTimeout(r, 500));
		for (const pid of childPids) {
			try {
				process.kill(pid, "SIGKILL");
			} catch {}
		}

		process.exit(0);
	}

	process.on("SIGTERM", () => {
		onSigterm().catch((e) => {
			console.error("[关停] 异常:", e);
			process.exit(1);
		});
	});
}
