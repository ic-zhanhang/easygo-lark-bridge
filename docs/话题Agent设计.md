# 话题 Agent 设计：Topic Session、并行、仿真互斥

本文描述 EasyGo 飞书双 Bot（达妮娅 / 秧秧）的**目标行为**与**使用方式**。域语言见 [CONTEXT.md](../CONTEXT.md)。实现落在 `scripts/patch-claw-*.sh` 与 `templates/claw/`、`runtime/` 规则中。

---

## 1. 设计目标

| 目标 | 做法 |
|------|------|
| 同话题续聊 | **Topic Session**：`thread_id` ↔ Cursor `sessionId`，默认 `--resume` |
| 多人同时使用 | 不同飞书话题最多 **3** 路并行；同话题串行 |
| 上下文单通道 | **Relay**：不写/不读 `runtime/topics/*.jsonl` 旁路历史 |
| 入口收敛 | **Group Topic Only**：仅群话题 @；入站私聊拒；出站通知可走私聊 |
| 仿真（Linux） | **整台机器** 同时只跑 **1** 个仿真（主机进程检测） |

---

## 2. 架构概览

```
飞书群（话题模式）
  │
  ├─ 话题 A ──► Topic Session A（--resume）
  ├─ 话题 B ──► Topic Session B
  └─ 话题 C ──► Topic Session C     （最多 3 个话题并行）

同一话题内多条 @ ──► 排队，一条接一条

斜杠 /help /新对话 /reset /心跳 … ──► Claw 代码处理，不进 Agent
```

绑定持久化：`runtime/state/topic-sessions.json`。

---

## 3. 斜杠命令（代码处理）

| 命令 | 行为 |
|------|------|
| `/help` | 仅列 EasyGo 实用命令 |
| `/新对话` `/reset` | 清除当前话题 Topic Session |
| `/心跳 …` | 心跳管理（含 `立即`） |
| `/终止` | 终止当前任务 |
| 其他 `/…` | 拒绝并提示见 `/help` |

---

## 4. 并发与仿真

| 类型 | 规则 |
|------|------|
| 普通任务 | 最多 3 个 **不同话题** 并行；同话题串行 |
| **仿真（Linux 秧秧）** | 主机已有仿真则拒绝再启 |

---

## 5. 使用方式（可贴群公告）

1. 在群里 **开一个话题**，表示一件事。
2. 在这个话题里 **@我**，直接说你要我做什么。
3. 同一件事请 **继续留在同一个话题** 里 @我（会续聊）。
4. 需要干净会话时发 `/新对话` 或 `/reset`。

---

## 6. 实现清单

- [x] Group Topic Only（无话题短提示；入站私聊拒绝）
- [x] Topic Session 绑定 + `--resume`
- [x] 锁键 `thread:{thread_id}`，并行 ≤3，同话题串行
- [x] Linux 仿真主机互斥
- [x] Relay：无 topics jsonl 旁路
- [x] EasyGo 斜杠白名单 + `/新对话`/`/reset`
- [x] 规则 / 文档与 CONTEXT 对齐

---

## 7. 相关文档

- [CONTEXT.md](../CONTEXT.md)
- [Linux安装.md](./Linux安装.md)
- [集成指南.md](./集成指南.md)
