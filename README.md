# easygo-lark-bridge

EasyGo 工程通过手机飞书遥控本地 Cursor Agent 的 **Deployment Pack**。

运行时采用 [feishu-cursor-claw](https://github.com/nongjun/feishu-cursor-claw)；本仓提供 EasyGo 专属安装脚本、Agent 视野隔离、HEARTBEAT 与 workspace rules。

> 领域术语见 [CONTEXT.md](./CONTEXT.md) · 落地步骤见 [docs/集成指南.md](./docs/集成指南.md)

## 做什么

**主要能力（Interactive Remote Task）**

```
飞书私聊 Bot → Claw → Cursor Agent → 在 EasyGo 代码库改代码 → 结构化摘要回飞书
```

**辅助能力（Heartbeat Check）**

定时检查两 repo Git 状态、GitLab CI、开放 MR，推送到飞书。

## 架构

```
手机飞书 ──WebSocket──→ ~/tools/feishu-cursor-claw
                              │
                    agent CLI (--workspace)
                              │
                              ▼
              /Users/ic/workspace/easygo-claw/     ← symlink 隔离根 + 运行时数据
              ├── easygo/          → ../easygo
              ├── frontend/        → ../standard-fe/easygo
              ├── lark-bridge/     → ../easygo-lark-bridge
              ├── inbox/           飞书附件收件
              ├── logs/feishu-cursor.log  服务日志
              ├── state/sessions.json     会话索引
              └── .cursor/sessions/       对话 JSONL
```

你在 Cursor 中仍打开 `easygo-dev.code-workspace` 写代码；飞书遥控走 `easygo-claw/`，不暴露 workspace 下其他项目。

## 快速开始

```bash
# 1. 配置
cp config/easygo.env.example config/easygo.env
# 填写: ALLOWED_OPERATOR_OPEN_ID, FEISHU_APP_SECRET, CURSOR_API_KEY

# 2. 安装（克隆 Claw + 创建 easygo-claw/ + 写入 projects.json）
bash scripts/install.sh

# 3. 验证 Agent workspace 支持
bash scripts/verify-agent-workspace.sh

# 4. 前台试跑
cd ~/tools/feishu-cursor-claw && bun run server.ts
# 飞书私聊 Bot 发指令测试

# 5. 开机自启（日志在 easygo-claw/logs/）
bash scripts/claw-service.sh install
bash scripts/claw-service.sh logs   # 查看日志
```

## 安全

- **仅 Bot 私聊**触发改代码；群聊 @Bot 不执行
- **仅 Authorized Operator**（`config/easygo.env` 中的 open_id）可下发任务

## 目录

| 路径 | 说明 |
|------|------|
| [CONTEXT.md](./CONTEXT.md) | 领域术语表 |
| [docs/集成指南.md](./docs/集成指南.md) | 分步安装与验证 |
| [docs/adr/0001-*.md](./docs/adr/0001-easygo-claw-root-via-symlinks.md) | symlink 隔离决策 |
| `templates/` | EasyGo `.cursor` 与 Claw `projects.json` 模板 |
| `config/easygo.env.example` | 本机路径与密钥配置 |
| `scripts/install.sh` | 一键部署 |
| `scripts/claw-service.sh` | 开机自启（日志写入 `easygo-claw/logs/`） |

## 关联工程

| 名称 | 路径 |
|------|------|
| Cursor workspace | `/Users/ic/workspace/easygo-dev.code-workspace` |
| 后端 | `../easygo` |
| 前端 | `../standard-fe/easygo` |
| Claw 运行时 | `~/tools/feishu-cursor-claw` |
| 运行时数据 | `~/workspace/easygo-claw/{inbox,logs,state,.cursor/sessions}` |
| 项目路由配置 | `~/tools/projects.json`（与 Claw 仓库同级） |

## Cursor 内读飞书（A 类，可选）

不在本 Bridge 范围内。电脑前在 Cursor 会话内操作飞书，请用 `lark-openapi-mcp` + 已有 `lark-cli` skills。
