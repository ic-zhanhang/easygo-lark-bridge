# 05 — 规则与文档对齐

**What to build:** 达妮娅/秧秧 runtime 规则与仓库文档与 `CONTEXT.md` 一致：读者看到的是 Topic Session + Relay + Session Continuity，而不再是「每条独立 / 按需读 topics」。

**Blocked by:** 01 — Topic Session 续聊; 02 — Slash：帮助与重置; 03 — Group Topic Only + Outbound Notify; 04 — Relay：去掉 topics 旁路

**Status:** done

- [x] mac/linux runtime 规则中「无 resume」「读 topics 历史」表述已改为 Topic Session / Relay
- [x] `AGENTS.md` 与相关 Bot 使用说明与代码行为一致
- [x] `docs/话题Agent设计.md`、README 使用说明与 `CONTEXT.md` 无矛盾
- [x] 不再把 `runtime/topics/*.jsonl` 或「按需读历史」写成目标行为
