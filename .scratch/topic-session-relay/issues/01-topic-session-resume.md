# 01 — Topic Session 续聊

**What to build:** 在飞书群话题里 @ Bot 时，同话题后续消息默认续上同一 Cursor Agent 会话（`--resume`），不同话题互不共享；授权操作者能像普通 Cursor 续聊一样推进一件事。

**Blocked by:** None — can start immediately

**Status:** done

- [x] 群话题首次 @（白名单）创建 Topic Session，并持久绑定 `thread_id` ↔ `sessionId`
- [x] 同话题再次 @ 对该绑定执行 `--resume`，进入同一会话
- [x] 不同话题使用不同 session，互不 resume
- [x] 群话题路径不再走「每条消息强制无 resume」
- [x] 心跳 / 出站任务不 resume 到任何用户 Topic Session
- [x] 主接缝可验证：同话题两次 @ / 跨话题隔离（fixture 或等价可观测断言）
