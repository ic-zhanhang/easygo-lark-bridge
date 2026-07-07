# 秧秧 Runtime 模板

**秧秧** — EasyGo Linux 常开主机飞书遥控 Bot。

| 项 | 说明 |
|----|------|
| 机器 | Linux 常开主机 + `easygo-dev-main` 容器 |
| 擅长 | 编包、Gazebo 仿真、长任务、飞书改代码 |
| 心跳 | 08:00–23:00 每 2h；`git pull` 23 仓，仅有变化/异常才推飞书 |
| 协作 | Mac 达妮娅 push → 秧秧 pull 继续编 / 仿真 |

```bash
BRIDGE_PROFILE=linux bash scripts/install.sh
```

差异：`dev-environment.mdc`、`agent-identity.mdc`、`soul.mdc`（秧秧人设）。

**飞书应用简介（可粘贴）：**

> EasyGo Linux 常开主机遥控。飞书 @我编包、跑仿真、改代码；定时 pull 同步仓库，有拉取或异常才推送。重量级任务在本机跑。
