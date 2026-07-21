# 04 — Relay：去掉 topics 旁路

**What to build:** 对话上下文只走 Topic Session；Claw 不再维护或注入 `runtime/topics/*.jsonl` 旁路历史。当前消息的图片/附件下载仍可用，但不依赖话题日志文件。

**Blocked by:** 01 — Topic Session 续聊

**Status:** done

- [x] 用户 @ 与 Bot 回复不再写入 `runtime/topics/*.jsonl`
- [x] 不再因「读话题历史」类自然语言把 jsonl 拼进 prompt
- [x] 清理/定时删除 topics 文件的逻辑随旁路一并停用或移除
- [x] 当前消息附件仍可下载并交给当次 Agent 任务（不经 jsonl 作上下文源）
- [x] 旧 topics 文件若残留，也不被注入 prompt
