# scripts/

| 脚本 | 用途 |
|------|------|
| [install.sh](./install.sh) | 安装 Claw + runtime（`BRIDGE_PROFILE=mac\|linux`） |
| [install-linux.sh](./install-linux.sh) | `BRIDGE_PROFILE=linux` 快捷入口 |
| [claw-service.sh](./claw-service.sh) | Mac launchd（达妮娅） |
| [claw-service-linux.sh](./claw-service-linux.sh) | Linux systemd 用户服务（秧秧） |
| [verify-agent-workspace.sh](./verify-agent-workspace.sh) | 验证 Agent CLI |

```bash
# Mac
cp config/easygo.env.example config/easygo.env
bash scripts/install.sh

# Linux
cp config/easygo.env.linux.example config/easygo.env
bash scripts/install-linux.sh
```
