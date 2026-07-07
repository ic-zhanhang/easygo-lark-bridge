# Linux 安装：秧秧（常开主机）

同一 git 仓库，在 Linux 上 clone 后按 **linux** profile 安装。

## 前置

| 项 | 要求 |
|----|------|
| 工作区 | `~/workspace/easygo`、`~/workspace/standard-fe/easygo` 已 clone |
| Bun | `curl -fsSL https://bun.sh/install \| bash` |
| Cursor Agent CLI | `~/.local/bin/agent` 可执行 |
| 飞书 | **秧秧** 独立应用（与 Mac 达妮娅不同 `FEISHU_APP_ID`） |

## 安装

```bash
cd ~/workspace
git clone git@git.standard-robots.com:<你>/easygo-lark-bridge.git ic-lark-assistant
cd ic-lark-assistant

cp config/easygo.env.linux.example config/easygo.env
# 填写 FEISHU_APP_SECRET、CURSOR_API_KEY、ALLOWED_OPERATOR_OPEN_IDS

bash scripts/install-linux.sh
bash scripts/verify-agent-workspace.sh
bash scripts/claw-service-linux.sh install
```

`install-linux.sh` = `BRIDGE_PROFILE=linux bash scripts/install.sh`。

## 与 Mac（达妮娅）的区别

| | Mac | Linux |
|--|-----|-------|
| Profile | `mac`（默认） | `linux` |
| Bot | 达妮娅 | 秧秧 |
| 模板 | `templates/runtime-mac/` | `templates/runtime-linux/` |
| 自启 | `claw-service.sh`（launchd） | `claw-service-linux.sh`（systemd） |
| 心跳 | 10:00–22:00 | 08:00–23:00 |

## 登出后仍运行

```bash
loginctl enable-linger "$USER"
```

## 验证

```bash
bash scripts/claw-service-linux.sh status
bash scripts/claw-service-linux.sh logs
```

飞书群里 @秧秧 发一条短指令，应有卡片回复。

## 更新桥接包

```bash
cd ~/workspace/ic-lark-assistant
git pull
BRIDGE_PROFILE=linux bash scripts/install.sh
bash scripts/claw-service-linux.sh restart
```

`config/easygo.env` 不会被 git 覆盖。
