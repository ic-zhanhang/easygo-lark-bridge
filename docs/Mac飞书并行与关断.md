# Mac 飞书：达妮娅整窗接管（关断 claw）

> 范围：仅 Mac 达妮娅。Linux 秧秧继续用 bridge。

## 模型（重要）

飞书群对话窗 = **本地达妮娅 Qwen**，与桌宠同一人格与记忆体系。

```text
飞书消息
  → chat_once（千问人格 / 按群 namespace 记忆）
  → 紫色互动卡片回复
  → ask 时等群友「确认」
  → start_channel_work（Cursor 幕后执行）
  → 完成：Qwen compose_result → 再发紫卡

不另起 Speak Gate / 旁路改写模型。
```

## 关断步骤

1. 配好凭证（env 优先）：

```bash
export FEISHU_APP_ID=...
export FEISHU_APP_SECRET=...
export XIAOZHU_CHAT_ID=oc_0a2bd151890eede76f4595a89e5f21c2
export DANYA_FEISHU_ENABLED=true
# 可选：CHAT_OPERATOR 对应 open_id 写入 settings.yaml feishu.operator_open_ids
```

2. **先停本机 claw**（同一 App 只能一条长连接）：

```bash
cd ~/workspace/easygo-lark-bridge
bash scripts/claw-service.sh stop
```

3. 启动达妮娅飞书：

```bash
cd ~/danya-assistant
danya feishu --with-desktop
```

4. 验收清单：

- [ ] 小组群闲聊有紫卡回复（达妮娅口吻）
- [ ] ask → 回复「确认」→ 启动 Cursor → 完成后紫卡叙述
- [ ] `danya memory list` 可见 `[来源:飞书小组群:…]`
- [ ] 工作日 13:30 日报窗口（无精华则不发）

## 已迁入

| 能力 | 落点 |
|---|---|
| WS 收消息 | `feishu_runtime` |
| Tick / 人格 | `feishu_channel` → `chat_once` |
| 紫卡 | `feishu_cards` |
| Cursor 确认 | `feishu_group_state` + `app.start_channel_work` |
| 完成叙述 | 既有 `compose_result` → proactive → 推群 |
| 小组日报 | `feishu_digest`（13:30 工作日） |
| 记忆 | ADR 0007 namespace |

## 相关

- 达妮娅 ADR 0006 / 0007
- `POST /api/channels/feishu/tick`（并行期仍可用；关断后进程内调用）
