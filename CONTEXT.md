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

**Topic Session（话题会话）**:
飞书群话题 `thread_id` 与 Cursor Agent `sessionId` 的一对一绑定；同话题内后续 @ 进入同一会话。
_Avoid_: 每条消息独立会话（群话题）、workspace 级单一 active 会话

**Group Topic Only（仅群话题）**:
人对 Bot 的指令只走群聊话题内的 @；无 `thread_id` 时由代码拒绝或短提示开话题，不进入 Agent。不提供私聊入口。
「小组」白名单群是唯一例外：主群 @Bot 使用 `xiaozu:<chat_id>` 单一共享 Session；是否属于该群、是否有执行权限仍由代码判断。
_Avoid_: 其它主群无话题接指令、入站私聊续聊、用 AI 判断权限

**Outbound Notify（出站通知）**:
Bot → 授权人的主动推送（如心跳摘要）仍可走私聊；这不是对话入口，不创建 Topic Session。
_Avoid_: 把心跳私聊当成可续聊的会话

**Operator Gate（操作者门控）**:
Claw 用代码白名单（`CHAT_OPERATOR_*`）在调用 Agent 前校验发送者；与飞书「可用范围」叠加。当前仅杨展航，作双保险，不开放给他人。
_Avoid_: 用 AI 判断权限、多人 L2 授权流程（保留能力但默认不用）

**Relay（透传）**:
对话上下文只走 Topic Session；Claw 不维护、不注入旁路聊天记录。桥接适配（门控、会话映射、排队、飞书卡片、媒体下载）仍由代码完成。
「小组」例外使用有界增量上下文：原始消息写 JSONL，Qwen 维护短群状态，执行模型只接收上次成功水位之后的消息。
_Avoid_: 无界注入全天群聊、用 AI 判断执行权限、把模型摘要当唯一事实源

**Behavior Tick（群行为树）**:
「小组」每条群消息恰好调用一次 `tick(group_message)`；Priority Selector 依次选择 `work / silence / reply / propose_task`。行为树只选行为，不保存记忆或任务。Qwen 是无工具的 Social Leaf；异常、超时、低置信度都返回静默。只有 `@Bot + 代码权限通过` 才能选中 `work`。
无权限的 `@Bot` 仍可进入 Qwen 做社交判断，但会显式标记 `execution_allowed=false`，最多静默、回复或提出候选任务。
_Avoid_: 在 server 里并列维护另一套 if/else 行为入口、让 Qwen 判断权限或执行无权限请求、一次消息触发多个行为

**Group Memory（群记忆）**:
记忆是行为树外的独立模块：`文档/小组旁观/*.jsonl` 是可追溯事实；`state/xiaozu-groups/*.json` 存已确认决定/待确认候选/任务/水位（Qwen 不得自动写长期记忆，须候选卡「确认记入」）；Cursor Session 是当前工作推理。叶子适配器可以按需读取，但树本身不持有。
_Avoid_: 把 Blackboard 当长期记忆、让行为树管理任务生命周期、把聊天事实和执行状态混成一段 prompt

**Session Continuity（会话延续）**:
Topic Session 默认一直 `--resume`；仅当用户用斜杠命令显式重置，或 resume 失败后自动新开并告知用户。重置由代码清除会话绑定，不经 AI。
_Avoid_: 按时效自动断会话、静默丢上下文、让 AI「理解后忘掉」

**Slash Command（斜杠命令）**:
群话题内以 `/` 开头、由 Claw 代码直接处理的指令；不进入 Agent 会话。`/help` 只列出 EasyGo 实用命令；未列入的斜杠由代码直接拒绝并提示见 `/help`。会话重置：`/新对话` 与 `/reset` 同义，仅清除当前话题的 Topic Session。 `/上下文`（`/context`）查看当前话题的 Cursor session 绑定；「小组」群额外显示执行水位与下次注入预览。
_Avoid_: 用自然语言让 AI 执行重置、help 外幽灵命令仍可用、上游全量无关命令

**Single-task scope**:
在同一 Topic Session 内，Agent 可沿用本会话已有上下文（与普通 Cursor 续聊相同）；仍禁止未要求时预扫全仓。不同话题、出站通知、心跳任务互不共享会话。
_Avoid_: 「单任务 = 不续聊」、跨话题共用一个 session、resume 后仍假装每条都是新任务、一话题自动绑一个 git 分支

**Topic Parallelism（话题并行）**:
不同飞书话题最多 3 路并行；同一话题内任务串行。由 Claw 代码调度。
_Avoid_: 无上限并行、全局只跑一个话题（除非日后改）

**Sim Mutex（仿真互斥）**:
Linux 上整机同时只允许 1 个仿真；由代码检测本机是否已有仿真在跑，与话题数量无关。
_Avoid_: 靠人工记得别起第二个、按话题计数限仿真

## 文档

- [docs/集成指南.md](./docs/集成指南.md) — Mac
- [docs/Linux安装.md](./docs/Linux安装.md) — Linux
- [docs/话题Agent设计.md](./docs/话题Agent设计.md) — Topic Session、并行、仿真互斥、使用方式
- [docs/小组群聊Agent.md](./docs/小组群聊Agent.md) — 小组行为树、Qwen 社交叶子、树外记忆与任务执行
