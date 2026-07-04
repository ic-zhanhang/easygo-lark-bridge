# scripts/

| 脚本 | 用途 |
|------|------|
| [install.sh](./install.sh) | 克隆 `claw/`、创建 `runtime/`、迁移旧 `~/tools` 布局 |
| [claw-service.sh](./claw-service.sh) | launchd 自启，日志 → `runtime/logs/` |
| [verify-agent-workspace.sh](./verify-agent-workspace.sh) | 验证 Agent `--workspace runtime/` |

```bash
cp config/easygo.env.example config/easygo.env
bash scripts/install.sh
```
