# 06 — 次接缝回归：并行 + 仿真互斥

**What to build:** 在 Topic Session / Relay 改动落地后，授权操作者仍享受：最多 3 个不同话题并行、同话题串行；Linux 上整机同时只允许 1 个仿真。

**Blocked by:** 01 — Topic Session 续聊; 04 — Relay：去掉 topics 旁路

**Status:** done

- [x] 不同话题最多 3 路并行仍成立（可验证）
- [x] 同一话题内任务仍串行
- [x] Linux 仿真意图在主机已有仿真时得到占用提示且不启第二实例
- [x] 仿真互斥与话题数量无关（主机进程检测语义不变）
- [x] `verify-claw-patches`（或等价烟雾）在相关 patch 调整后仍可通过
