# 秧秧 Runtime 模板

Linux 主机 · 飞书 Bot **秧秧** 的 Agent workspace 模板。

与 `runtime-mac/`（达妮娅 / Mac）共用同一套桥接仓库，安装时：

```bash
BRIDGE_PROFILE=linux bash scripts/install.sh
```

差异主要在：

- `dev-environment.mdc` — 仅 Linux 本机环境
- `soul.mdc` / `agent-identity.mdc` — 秧秧人设
- `single-task-scope.mdc` — 单条 @ 消息、不预扫全仓
