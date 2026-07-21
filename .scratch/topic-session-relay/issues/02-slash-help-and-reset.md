# 02 — Slash：帮助与重置

**What to build:** 群话题内可用斜杠命令管理会话：`/help` 只列 EasyGo 实用命令；`/新对话` 与 `/reset` 清除当前话题的 Topic Session；未知斜杠被拒绝。这些命令由代码直接处理，不进 Agent。

**Blocked by:** 01 — Topic Session 续聊

**Status:** done

- [x] `/help` 仅列出 EasyGo 实用命令（含仍需保留的如 `/心跳 立即`）
- [x] `/新对话` 与 `/reset` 同义：清除当前话题绑定，不进入 Agent，并给出确认文案
- [x] 重置后同话题下一次 @ 为新 session（不再 resume 旧会话）
- [x] 未列入 help 的斜杠命令被拒绝，并提示见 `/help`
- [x] 斜杠命令不经 AI「理解」执行
