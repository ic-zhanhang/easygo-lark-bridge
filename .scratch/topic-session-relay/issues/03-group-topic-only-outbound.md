# 03 — Group Topic Only + Outbound Notify

**What to build:** 人对 Bot 的指令只走群聊话题内 @；无话题群消息与入站私聊不进 Agent。心跳等 Bot→授权人的主动私聊推送仍可用，且不创建 Topic Session。

**Blocked by:** None — can start immediately

**Status:** done

- [x] 群聊无 `thread_id` 时 @ Bot：不进 Agent，短提示开话题或等价拒绝
- [x] 入站私聊指令：不进 Agent（统一短拒或静默策略，行为确定）
- [x] 心跳等 Outbound Notify 仍可私聊推送到授权人
- [x] 出站私聊不创建、不绑定 Topic Session，不影响已有话题会话
- [x] 主接缝可验证上述入站拒绝与出站仍可达
