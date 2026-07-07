# EasyGo Lark Bridge

`workspace/easygo-lark-bridge/` — 飞书 @ → Claw → Cursor Agent，在 `runtime/` 内操作 EasyGo。

## 双 Bot 部署

| Bot | Profile | 机器 | 一句话 | 模板 |
|-----|---------|------|--------|------|
| **达妮娅** | `mac` | Mac 移动机 | 私人写码遥控 + 本机 git 同步心跳 | `templates/runtime-mac/` |
| **秧秧** | `linux` | Linux 常开主机 | 编包 / 仿真主场 + git 同步心跳 | `templates/runtime-linux/` |

同一 git 仓库 clone 两次即可；`FEISHU_APP_ID` 必须不同。职责边界是**本机能做什么**，不是前端/后端分工。

## Language

**Bridge Root**: `workspace/easygo-lark-bridge/` — claw、runtime、scripts、templates。

**Claw**: `claw/` 内 `feishu-cursor-claw` 克隆体。

**Runtime**: `runtime/` — Agent `--workspace`；symlink `easygo/`、`frontend/`。

**BRIDGE_PROFILE**: `mac` | `linux` — 选择 runtime 模板与心跳策略。

**Authorized Operator**: open_id 白名单；群聊须 @Bot。

**Single-task scope**: 每条飞书消息独立会话（无 `--resume`）；rules 禁止预扫全仓。

## 文档

- [docs/集成指南.md](./docs/集成指南.md) — Mac
- [docs/Linux安装.md](./docs/Linux安装.md) — Linux
