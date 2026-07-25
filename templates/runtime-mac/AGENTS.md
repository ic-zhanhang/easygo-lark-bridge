# AGENTS.md — runtime/ Agent 工作区

`runtime/` 是 Cursor 工作目录（IDE 与飞书 Agent **同一套**）；业务代码在 `easygo/`、`frontend/`（symlink）。

## 每次会话

1. 读文件/跑命令**限定用户点名的路径**；未要求时不全仓扫、不读 CI、不翻旁路日志。
2. 人设与范围：alwaysApply 仅 `soul.mdc` + `easygo-scope.mdc`（与 IDE 打开本目录一致）。
3. 飞书 Topic Session / 斜杠命令由 **Claw 代码**处理；权限名单也只在 Claw（`permission-gate`），不进 Agent prompt。
4. 仿真/SSH/容器 → 按需读 `dev-environment.mdc`。
5. **不要**读 `topics/*.jsonl` 旁路历史（Relay）。

## 布局

| 路径 | 说明 |
|------|------|
| `easygo/`、`frontend/` | 业务仓库 |
| `state/topic-sessions.json` | Topic Session 绑定（Claw 维护） |
| `文档/` | 团队习惯等本地文档 |

桥接层**不维护** `.cursor/MEMORY.md` / `.cursor/memory/`。用户说「记住」→ 写 `文档/`（仅明确要求时）。
