# ADR 0001: EasyGo Claw Root 通过 symlink 隔离 Agent 视野

## 状态

已接受（2026-07-05）

## 背景

- EasyGo 在 Cursor 中通过 `easygo-dev.code-workspace` 打开（后端 + 前端 + 桥接部署包）。
- `feishu-cursor-claw` 的 `projects.json` 要求 **目录型 path**，并在该 path 下初始化 `.cursor/` 模板。
- `/Users/ic/workspace` 下还有二十多个 sibling 项目；若 Claw path 指向 workspace 根，Agent 可能误操作其他 repo。

## 决策

1. Claw 运行时安装在 `~/tools/feishu-cursor-claw`（与 EasyGo 配置分离，便于 `git pull` 升级）。
2. 创建 **`/Users/ic/workspace/easygo-claw/`**，内含三个 symlink 指向 EasyGo 相关 repo，作为 Claw 的 `default_project` path。
3. EasyGo 专属 `.cursor/` 模板（HEARTBEAT、rules）部署在 `easygo-claw/.cursor/`。
4. **升级路径**：安装后运行 `scripts/verify-agent-workspace.sh`；若 `agent --workspace easygo-dev.code-workspace` 可用，再评估给 Claw 提 PR，使 template 目录与 agent workspace 分离。

## 备选方案

| 方案 | 未采用原因 |
|------|------------|
| path = `/Users/ic/workspace` + rules 约束 | 物理视野仍过大，依赖 Agent 自律 |
| path = 单个 repo（如 `easygo/`） | 默认看不到前端 repo |
| path = `.code-workspace` 文件 | Claw `ensureWorkspace()` 假设目录，直接填文件路径会失败 |
| Fork Claw 到本仓 | 与上游同步成本高 |

## 后果

- 用户 Cursor 仍打开 `easygo-dev.code-workspace` 写代码；飞书遥控走 `easygo-claw/`，两套入口、同一套真实 repo。
- 本仓 `easygo-lark-bridge` 定位为 **Deployment Pack**，不含 Claw 源码。
