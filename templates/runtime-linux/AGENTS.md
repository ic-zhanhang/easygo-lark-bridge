# AGENTS.md — runtime/ 飞书 Agent 工作区

`runtime/` 是 Cursor 工作目录；业务代码在 `easygo/`、`frontend/`（symlink）。

## 每次会话

1. **同一群话题**内续聊（Topic Session / `--resume`）；不同话题互不共享。
2. 读文件/跑命令**限定用户点名的路径**；未要求时不全仓扫。
3. 人设见 alwaysApply rules（`soul`、`agent-identity`、`easygo-scope`、`single-task-scope`）。
4. 仿真/SSH/容器 → 按需读 `dev-environment.mdc`。
5. **不要**读 `topics/*.jsonl` 旁路历史（Relay）。

## 布局

| 路径 | 说明 |
|------|------|
| `easygo/`、`frontend/` | 业务仓库 |
| `state/topic-sessions.json` | Topic Session 绑定（Claw 维护） |
| `文档/` | 团队习惯等本地文档 |

桥接层**不维护** `.cursor/MEMORY.md` / `.cursor/memory/`。用户说「记住」→ 写 `文档/`（仅明确要求时）。
