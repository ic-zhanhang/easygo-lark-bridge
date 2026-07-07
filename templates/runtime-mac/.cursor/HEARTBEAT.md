# EasyGo 心跳检查（达妮娅 · Mac）

**调度**：**10:00–22:00**，约 **每 2 小时** 一次。

Claw 心跳会 **直接执行** `../scripts/sync-dev-repos.sh`（不经过 Agent 猜命令），拉取本地仓库后推飞书。

完整仓库列表与分支规则见同目录 `HEARTBEAT.md`（与 `templates/runtime/.cursor/HEARTBEAT.md` 同步）。

- **frontend** → `dev`
- **其余全部** → `main`
