Status: done

# Spec: Topic Session + Relay（EasyGo Lark Bridge）

## Problem Statement

作为 EasyGo 的授权操作者，我希望在飞书群**话题里 @ Bot** 时，对话能像普通 Cursor 续聊一样延续上下文，而不是每条消息都开全新会话、再靠本机 `topics/*.jsonl` 旁路补历史。当前实现把「无 resume」和「本地话题日志 + 按需读历史」绑在一起，导致：上下文双通道、规则与代码行为打架、私聊入口与群话题入口混杂，且与已定域语言（`CONTEXT.md`）不一致。

## Solution

把飞书群话题 `thread_id` 与 Cursor Agent `sessionId` 做成一对一的 **Topic Session**；同话题内后续 @ 默认 `--resume`。对话上下文只走这条会话（**Relay**），Claw 不再维护或注入旁路聊天记录。人对 Bot 的指令**仅**走群聊话题内 @；心跳等 **Outbound Notify** 仍可走私聊推送，但不创建会话。斜杠命令（`/help`、`/新对话`/`/reset` 等）由代码直接处理。话题并行与 Linux 仿真互斥保持现有策略。

## User Stories

1. As an Authorized Operator，I want 在飞书群里开一个话题并 @ Bot，so that 这件事有独立的对话空间。
2. As an Authorized Operator，I want 同一话题里第二次 @ Bot 时自动续上一次会话，so that 我不用重复交代背景。
3. As an Authorized Operator，I want 不同话题各自独立会话，so that 并行事项不会串上下文。
4. As an Authorized Operator，I want 主群里无话题直接 @ Bot 时被拒绝或被提示去开话题，so that 我不会误以为 Bot 在「听主群闲聊」。
5. As an Authorized Operator，I want 私聊发给 Bot 的指令不被当作对话入口，so that 所有工作指令都收敛到群话题。
6. As an Authorized Operator，I want 心跳同步摘要仍能私聊推给我，so that 仓库有拉取/异常时我能收到通知，而不会把这条私聊当成可续聊会话。
7. As an Authorized Operator，I want 非白名单发送者 @ Bot 时被代码直接拒绝，so that 权限不依赖 AI 判断。
8. As an Authorized Operator，I want `/help` 只列出 EasyGo 实用斜杠命令，so that 我不被上游无关命令干扰。
9. As an Authorized Operator，I want `/新对话` 与 `/reset` 清除当前话题的 Topic Session，so that 我能显式开干净会话。
10. As an Authorized Operator，I want 斜杠命令不进入 Agent，so that 重置/帮助行为确定、不经 AI「理解」。
11. As an Authorized Operator，I want 未列入 help 的斜杠被拒绝并提示看 `/help`，so that 不会出现幽灵命令仍可用。
12. As an Authorized Operator，I want resume 失败时系统自动新开会话并告知我，so that 任务不会静默丢上下文。
13. As an Authorized Operator，I want Bot 不要再写/读 `runtime/topics/*.jsonl` 作为对话历史通道，so that 上下文只有 Topic Session 一条路。
14. As an Authorized Operator，I want 发图片时仍能被下载并交给当前 Agent 任务使用，so that 看图改代码等能力保留，但不依赖话题 jsonl。
15. As an Authorized Operator，I want 同一话题内多条 @ 串行处理，so that 不会抢同一 session。
16. As an Authorized Operator，I want 最多 3 个不同话题并行，so that 多人/多事可同时推进且机器不被打满。
17. As an Authorized Operator，I want Linux 上整机同时只跑 1 个仿真，so that Gazebo/资源不会被第二个话题撞坏。
18. As an Authorized Operator，I want 仿真互斥与话题数量无关（看本机是否已有仿真在跑），so that 规则简单可靠。
19. As an Authorized Operator，I want 在同一 Topic Session 内 Agent 可以沿用本会话已有上下文，so that 行为与普通 Cursor 续聊一致。
20. As an Authorized Operator，I want Agent 仍禁止未要求时预扫全仓，so that 续聊不会变成「每条都全仓摸一遍」。
21. As an Authorized Operator，I want 心跳任务与出站通知不共享任何 Topic Session，so that 后台任务不污染工作对话。
22. As an Authorized Operator，I want 达妮娅（Mac）与秧秧（Linux）各自本机维护会话绑定，so that 双 Bot 部署互不串会话。
23. As an Authorized Operator，I want 改完桥接后 Mac push、Linux pull+install 仍按既有部署流程，so that 双机行为一致。
24. As an a maintainer，I want `verify-claw-patches` 在去掉/替换 `no-resume` 与 jsonl 旁路后仍能通过，so that 上游 pin 升级可回归。
25. As an a maintainer，I want runtime 规则（`topic-agent`、`single-task-scope`、`AGENTS.md` 等）与代码行为一致，so that Agent 不会按旧「每条独立、读 topics」说明书行事。
26. As an Authorized Operator，I want 会话绑定由代码维护（thread↔session），so that 我不依赖 AI 去「记住 sessionId」。
27. As an Authorized Operator，I want 不按时效自动断会话，so that 除非我显式重置或 resume 失败，否则上下文一直在。
28. As an Authorized Operator，I want 一个话题不自动绑一个 git 分支，so that 问答/查状态不无故开分支；改代码仍按现有 Agent 习惯处理。

## Implementation Decisions

- **域语言以 `CONTEXT.md` 为准**：Topic Session、Group Topic Only、Outbound Notify、Operator Gate、Relay、Session Continuity、Slash Command、Topic Parallelism、Sim Mutex；实现与文档不得再描述「每条消息独立会话」或「按需读 topics 历史」为目标行为。
- **主行为变更在 Claw 适配层**：入站 `handle` / 会话恢复 / 斜杠拦截；通过现有 `scripts/patch-claw-*.sh` +（如有）`templates/claw/` 模块注入，保持「上游 pin + patch 链」策略（见上游 Claw 维护策略）。
- **废除 `patch-claw-no-resume` 的目标语义**：群话题路径改为按 Topic Session `--resume`；不再全局禁用 resume。心跳/出站任务仍不 resume 到任何用户 Topic Session。
- **Topic Session 映射**：键为飞书群 `thread_id`（话题）；值为 Cursor Agent `sessionId`。同话题后续 @ 使用该绑定 resume；无绑定时新建并持久化绑定；`/新对话`/`/reset` 清除该话题绑定。
- **Group Topic Only**：群聊无 `thread_id` → 代码拒绝或短提示开话题，不进入 Agent。入站私聊指令同样不进入 Agent（可短拒或静默忽略，以实现时统一文案为准）；Outbound Notify 出站私聊不受此限。
- **Relay**：删除/停用 `runtime/topics/*.jsonl` 的写入、清理、以及「自然语言触发读历史并拼进 prompt」逻辑。媒体下载与当前消息附件路径注入可保留，但不得依赖话题 jsonl 文件作为上下文源。
- **Slash Command**：群话题内以 `/` 开头由代码处理；至少支持 `/help`、`/新对话`、`/reset`（后两者同义，仅清当前话题绑定）。`/help` 白名单制；未列命令拒绝并提示见 `/help`。现有实用命令（如 `/心跳 立即`）若仍需要，列入 help。
- **Operator Gate**：继续用 `CHAT_OPERATOR_*` 代码白名单；默认仅杨展航；不把多人 L2 授权流程作为本 spec 必做项。
- **Topic Parallelism**：保留最多 3 不同话题并行、同话题串行（现有 topic lock / parallel slot）。
- **Sim Mutex**：保留 Linux 主机进程检测；仿真意图时若已有仿真在跑则卡片提示占用，不启动第二个。
- **Runtime 规则对齐**：更新 mac/linux 模板中 `topic-agent`、`single-task-scope`、`AGENTS.md`、相关 README/设计文档，去掉「无 resume / 读 topics」表述，改为 Topic Session + Relay 表述；`docs/话题Agent设计.md` 与 README 使用说明同步。
- **双机**：同一仓库两套 clone；行为由 `BRIDGE_PROFILE` 与本机会话存储隔离；不跨机共享 Topic Session。
- **ADR**：布局仍遵循 ADR 0002（单树 `easygo-lark-bridge/`）；本变更不推翻 symlink runtime 视野隔离。

## Testing Decisions

**好测试只断言外部行为**：给定入站消息（或调度输入），观察是否进 Agent、用哪个 session / 是否 resume、飞书回复文案、prompt 是否含旁路历史；不断言内部私有函数名或文件路径实现细节（会话存储介质可测其可观测效果：重置后不再 resume 到旧 session）。

### 主接缝：`handle` 入站结果

覆盖用例（示例级，实现时可整理为 fixture）：

- 群话题 @ + 白名单 → 进入 Agent；首次建 Topic Session，再次同话题 → resume 同一 session
- 群无话题 @ → 不进 Agent，有短提示/拒绝
- 入站私聊指令 → 不进 Agent（非 Outbound）
- 非白名单 → 拒绝，不进 Agent
- `/help`、`/新对话`、`/reset`、未知斜杠 → 不进 Agent，文案符合约定；重置后同话题下次为新 session
- resume 失败路径 → 新开 session 并告知用户
- 任意自然语言「读话题历史」→ prompt **不含** jsonl 旁路后缀；无 topics 写入副作用（若旧文件残留，也不被注入）

优先复用/扩展现有 patch 校验思路：对注入后的 Claw 模块做单元级或轻量集成测试；`verify-claw-patches.sh` 仍作为「patch 能打上」的烟雾回归。

### 次接缝

1. **Topic Parallelism 调度**：4 个不同话题并发时最多 3 个同时占槽；同话题第二条在第一条完成前排队。
2. **Sim Mutex**：模拟「主机已有仿真进程」时，仿真意图消息得到占用提示且不启动第二实例。
3. **Outbound Notify**：心跳推送走私聊到授权人；不创建/不绑定 Topic Session；不影响已有话题会话。

Prior art：仓库现有以 `scripts/verify-claw-patches.sh` 校验 patch 链；业务行为测试需新建（当前无成熟 test runner 覆盖 `handle`），优先在 Claw 侧可导出的纯函数/模块上测，再辅以少量集成。

## Out of Scope

- 开放多人 L2 授权流程或用 AI 做权限判断
- 跨 Mac/Linux 共享 Topic Session 或话题存储
- 一话题自动绑定 git 分支 / worktree（仍非本 spec 强制代码能力）
- 私聊作为人对 Bot 的正式对话入口
- 按时效自动过期/断开 Topic Session
- Fork 上游 Claw、取消全部 patch 链（仍按现有维护策略渐进）
- 改 EasyGo 业务仓功能本身（仿真内容、前端页面等）
- 更换飞书 App / 双 Bot 身份模型

## Further Notes

- `CONTEXT.md` 中本组 Language 条目是验收准绳；实现完成后应删除或改写与之矛盾的旧文档段落（尤其 `docs/话题Agent设计.md` § 本机 jsonl / 按需读历史，以及 runtime「无 resume」规则）。
- 迁移期：本机若已有 `runtime/topics/*.jsonl`，可保留文件不删，但代码路径不得再读写它们作为上下文；避免双通道。
- 发布位置：本地 markdown tracker — `.scratch/topic-session-relay/PRD.md`（本文件）。
- 建议后续用 `/to-tickets` 拆实现工单（替换 no-resume、会话映射、去掉 jsonl、斜杠、规则/文档对齐、测试）。
