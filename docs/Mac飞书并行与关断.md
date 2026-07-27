# Mac 飞书：并行中继 → 关断 claw

> 范围：仅 Mac 达妮娅。Linux 秧秧继续用 bridge，本文件不适用于 Linux。

## 当前阶段：并行

```text
飞书 ──► claw（WS / 权限 / 卡片 / Cursor）
            │
            │  POST /api/channels/feishu/tick
            ▼
       danya-assistant（人格 / 记忆 / 决策）
            │
            ▼
       claw 执行 replyCard / ask→Cursor
```

- claw **必须仍在跑**（`com.easygo.lark-claw`）
- 达妮娅 API **必须在跑**（桌宠或 `danya desktop --port 18765`）
- `DANYA_BRIDGE_ENABLED=true`
- 失败时 Speak Gate 回落 Ollama

## 关断条件（都满足再停 claw）

1. 达妮娅内具备飞书长连接收消息（替代 claw WS）
2. 达妮娅能发互动卡片 / 文本回复（替代 `replyCard`）
3. 权限门与小组旁观策略已迁入或显式放弃
4. 定时「小组日报」有替代调度
5. 私聊 Cursor 遥控路径有替代或确认不再需要经 claw
6. 并行期观察 ≥ 数日无回归

关断命令（届时再执行）：

```bash
bash scripts/claw-service.sh stop
# 或 launchctl bootout gui/$(id -u) com.easygo.lark-claw
```

## 相关

- 达妮娅 ADR：`danya-assistant` → `.aw/adr/0006-feishu-mac-parallel-relay.md`
- 通道 API：`POST /api/channels/feishu/tick`
