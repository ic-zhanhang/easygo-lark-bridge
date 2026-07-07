# EasyGo 心跳检查（达妮娅 · Mac）

**调度**：**10:00–22:00**，约 **每 2 小时** 一次。无事回复 `HEARTBEAT_OK`。

## 检查项

1. **Git 状态** — `easygo/`、`frontend/`、`easygo/src/*/` 子仓库
2. **GitLab CI** — 若 `GITLAB_PRIVATE_TOKEN` 可用
3. **开放 MR** — 与我相关的 open MR

## 约束

- **只读**；范围仅 `easygo/`、`frontend/`
- 异常优先；无异常可简短报告
