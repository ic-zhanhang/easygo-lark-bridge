# EasyGo Lark Bridge

`workspace/easygo-lark-bridge/` 一棵树内完成飞书遥控 EasyGo：配置仓 + Claw 引擎 + Agent runtime。

## Language

**Bridge Root（桥接根目录）**:
路径 `workspace/easygo-lark-bridge/`：本 git 仓库，同时容纳 `claw/`（上游引擎）、`runtime/`（Agent 工作区）、安装脚本与模板。
_Avoid_: ~/tools、workspace 外的 easygo-claw

**Claw**:
目录 `claw/` 内的 `feishu-cursor-claw` 克隆体——飞书 WebSocket → Cursor Agent CLI。
_Avoid_: ~/tools/feishu-cursor-claw

**Runtime（运行时目录）**:
目录 `runtime/`——Agent `--workspace` 指向此处；含 symlink（easygo/frontend/bridge）、inbox、logs、会话。
_Avoid_: easygo-claw、Workspace Root 作为 Agent path

**Bridge（桥接）**:
飞书私聊 → Claw → Agent 在 runtime/ 改 EasyGo 代码 → 飞书回复。
_Avoid_: 纯文档仓

**Workspace Root**:
`/Users/ic/workspace`——存放 easygo、standard-fe 等 repo；runtime 通过 symlink 引用，Agent 不直接在此根目录漫游。
_Avoid_: 把 Claw 安装到 Workspace Root 外

**EasyGo Workspace**:
`easygo-dev.code-workspace`——Cursor 内写代码用的 multi-root；与飞书遥控的 `runtime/` 互补。
_Avoid_: 与 Runtime 混为一谈

**Interactive Remote Task（交互遥控任务）**:
飞书私聊下发指令，Agent 在 runtime/ 内执行；Bridge 的主要用途。
_Avoid_: HEARTBEAT、状态查询

**Authorized Operator（授权操作者）**:
唯一可私聊触发改代码的用户（open_id 白名单）。
_Avoid_: 群聊遥控

**Task Completion Reply（任务完成回复）**:
完成后飞书结构化摘要：结论、修改文件、Git 状态、待确认项。
_Avoid_: 完整 diff

**Project Route（项目路由）**:
`projects.json` 将消息路由到 `runtime/`；默认无需 `project:` 前缀。
_Avoid_: 按 repo 拆分
