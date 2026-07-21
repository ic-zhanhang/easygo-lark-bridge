# easygo-lark-bridge

EasyGo 飞书遥控 Cursor Agent — **双 Bot、双机**：

- **达妮娅**（Mac）：移动写码遥控 + 本机 git 同步心跳
- **秧秧**（Linux）：编包 / 仿真主场 + git 同步心跳

```
easygo-lark-bridge/          ← 本 git 仓库
├── claw/                    feishu-cursor-claw（install 克隆，不入库）
├── runtime/                 Agent workspace（不入库）
├── templates/
│   ├── runtime-mac/         达妮娅模板 + Mac dev-environment
│   └── runtime-linux/       秧秧模板 + Linux dev-environment
├── config/  scripts/  docs/
```

> 术语：[CONTEXT.md](./CONTEXT.md) · Mac：[docs/集成指南.md](./docs/集成指南.md) · Linux：[docs/Linux安装.md](./docs/Linux安装.md)

## Mac（达妮娅）

```bash
cp config/easygo.env.example config/easygo.env
bash scripts/install.sh
bash scripts/claw-service.sh install   # launchd
```

## Linux（秧秧）

```bash
git clone <本仓库> ~/workspace/easygo-lark-bridge
cp config/easygo.env.linux.example config/easygo.env
bash scripts/install-linux.sh
bash scripts/claw-service-linux.sh install   # systemd
```

两台机器用**不同飞书 App**；同一仓库、不同 `config/easygo.env`。

## 使用

飞书群**话题**内 @达妮娅 或 @秧秧；同话题续聊（Topic Session）。`/新对话` 或 `/reset` 重置当前话题会话。

| Bot | 机器 | 日志 |
|-----|------|------|
| 达妮娅 | Mac | `runtime/logs/feishu-cursor.log` |
| 秧秧 | Linux | 同上（在 Linux clone 目录内） |

```bash
bash scripts/claw-service.sh logs          # Mac
bash scripts/claw-service-linux.sh logs    # Linux
```
