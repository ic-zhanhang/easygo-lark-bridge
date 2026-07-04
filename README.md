# easygo-lark-bridge

EasyGo 飞书遥控 Cursor Agent — **全部在 `workspace/easygo-lark-bridge/` 一棵树内**。

```
easygo-lark-bridge/          ← 本 git 仓库（你在 Cursor 里已打开）
├── claw/                    feishu-cursor-claw（install 克隆，不入库）
├── runtime/                 Agent workspace + 日志/收件/会话（不入库）
│   ├── easygo/   → ../../easygo
│   ├── frontend/ → ../../standard-fe/easygo
│   ├── bridge/   → ..
│   ├── inbox/
│   ├── logs/feishu-cursor.log
│   └── .cursor/sessions/
├── inbox → runtime/inbox    Claw 硬编码路径
├── projects.json
├── config/  scripts/  templates/  docs/
```

> 术语：[CONTEXT.md](./CONTEXT.md) · 安装：[docs/集成指南.md](./docs/集成指南.md)

## 快速开始

```bash
cp config/easygo.env.example config/easygo.env
# 填写 ALLOWED_OPERATOR_OPEN_ID、FEISHU_APP_SECRET、CURSOR_API_KEY

bash scripts/install.sh
bash scripts/claw-service.sh install   # 可选：开机自启
```

飞书 **私聊** Bot `ic`，Claw 在 `claw/` 里跑，Agent 在 `runtime/` 里改 easygo / frontend 代码。

## 查看消息与日志

| 内容 | 位置 |
|------|------|
| 飞书聊天 | 飞书 App → 与 `ic` 私聊 |
| 服务日志 | `runtime/logs/feishu-cursor.log` |
| 对话记录 | `runtime/.cursor/sessions/*.jsonl` |
| 附件 | `runtime/inbox/` |

```bash
bash scripts/claw-service.sh logs
```

## 关联

| 名称 | 路径 |
|------|------|
| Cursor workspace | `../easygo-dev.code-workspace` |
| 后端 | `../easygo` |
| 前端 | `../standard-fe/easygo` |
