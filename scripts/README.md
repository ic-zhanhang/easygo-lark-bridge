# scripts/

| 脚本 | 用途 |
|------|------|
| [install.sh](./install.sh) | 克隆 Claw、创建 `easygo-claw/`、部署模板、统一 inbox/logs |
| [claw-service.sh](./claw-service.sh) | 开机自启，日志写入 `easygo-claw/logs/` |
| [verify-agent-workspace.sh](./verify-agent-workspace.sh) | 验证 Agent CLI workspace |

```bash
cp config/easygo.env.example config/easygo.env
# 编辑 config/easygo.env
bash scripts/install.sh
bash scripts/verify-agent-workspace.sh
```
