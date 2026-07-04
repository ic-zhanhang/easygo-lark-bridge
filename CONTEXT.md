# EasyGo Lark Bridge

EasyGo 工程通过手机飞书遥控本地 Cursor Agent 的**部署与配置层**：运行时采用 `feishu-cursor-claw`，本仓提供 EasyGo 专属的项目路由、心跳检查与安装说明。

## Language

**Claw**:
开源项目 `feishu-cursor-claw`——飞书 WebSocket 收消息、调用 Cursor Agent CLI、回传进度卡片的常驻服务；B 类能力的实际运行时。
_Avoid_: 自研 listener、bot-listener、bridge 核心

**Bridge（桥接）**:
用户感知的「飞书遥控 EasyGo 工程」能力整体，由 Claw 运行时 + 本仓 EasyGo 配置共同构成；本仓不重复实现 Claw 已有能力。
_Avoid_: 纯文档仓、MCP Server

**Deployment Pack（部署包）**:
本仓库：安装脚本、`templates/`、`config/easygo.env`；Claw 运行时安装在 `~/tools/feishu-cursor-claw`，两者分离（选项 A）。
_Avoid_: 方案调研、自研 listener 源码、vendor 整个 Claw

**Integration Guide（集成指南）**:
描述如何配置外部工具或本 Bridge 的操作文档；可存在于 `docs/`，但不替代 Bridge 本身的可运行代码。
_Avoid_: 技术方案、README 即产品

**A 类能力**:
在 Cursor 会话内由 AI 操作飞书（读文档、发消息等）；依赖 Cursor 前台或 Agent 会话，不由 Bridge 常驻进程承担。
_Avoid_: 桥接、遥控

**Workspace Root**:
本机存放多个独立工程的父目录 `/Users/ic/workspace`；Claw 的 `projects.json` 可指向此处以满足目录型 path 要求，但 Agent 默认可见其下全部 sibling 项目，需额外隔离手段。
_Avoid_: 把 Workspace Root 等同于 EasyGo Workspace

**Agent Scope（Agent 视野）**:
一次 Claw 遥控任务中 Agent 允许读写的目录边界；EasyGo 采用 **D 策略**：基线用 `easygo-claw/` symlink 专用目录（物理隔离），并行验证 Agent CLI 是否支持 `.code-workspace` 文件路径，成功后再升级 Claw 配置。
_Avoid_: 仅靠 rules 约束整个 Workspace Root、靠用户每次手动指定路径

**EasyGo Claw Root**:
路径 `/Users/ic/workspace/easygo-claw/`：仅含指向 EasyGo 三 repo 的 symlink 及 Claw 模板（`.cursor/`、`HEARTBEAT.md` 等）；`projects.json` 的 `default_project` 指向此处，而非整个 Workspace Root。
_Avoid_: `/Users/ic/workspace` 作为 Claw path

**EasyGo Workspace**:
用户在本机 Cursor 中打开的多根工作区文件 `easygo-dev.code-workspace`，包含后端 `easygo`、前端 `standard-fe/easygo`、以及本部署包 `easygo-lark-bridge` 三个根目录；Claw 默认遥控目标应对齐此工作区，而非单个 repo 目录。
_Avoid_: workspace 根目录、仅后端目录

**Interactive Remote Task（交互遥控任务）**:
用户通过飞书向 Claw 发送自然语言指令，Claw 调用 Cursor Agent 在 EasyGo Claw Root 内改代码，完成后将结果回复到飞书；这是 Bridge 的**主要用途**。
_Avoid_: 定时推送、HEARTBEAT、状态查询（这些是辅助能力）

**Task Completion Reply（任务完成回复）**:
Interactive Remote Task 结束后发到飞书的结构化摘要：结论一句话、修改文件列表、Git 状态（是否 commit/push）、以及需用户确认的下一步。
_Avoid_: 仅一句结论、贴完整 diff

**Project Route（项目路由）**:
Claw 通过 `projects.json` 将飞书消息映射到本地目录；EasyGo 场景默认只需一条 `easygo` 路由指向 EasyGo Claw Root，日常无需 `project:` 前缀。
_Avoid_: 按 repo 拆分（除非确有独立遥控需求）
