# EasyGo 心跳检查（秧秧 · Linux）

**调度**：**08:00–23:00**，约 **每 2 小时** 一次（主机常开）。无事回复 `HEARTBEAT_OK`。

## 检查项

1. **Git 状态** — `easygo/`、`frontend/`、`easygo/src/*/` 子仓库
2. **GitLab CI** — 若 `GITLAB_PRIVATE_TOKEN` 可用
3. **开放 MR** — 与我相关的 open MR
4. **可选** — `easygo-dev-main` 容器是否在跑（`docker ps`）

## 约束

- **只读**；范围仅 `easygo/`、`frontend/`
- 异常优先
