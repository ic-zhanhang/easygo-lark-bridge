# EasyGo 心跳检查

**调度**：工作日 **10:00–22:00**，约 **每 2 小时** 一次（深夜不跑）。

## 目标

在本机 **执行 `git pull` 更新开发仓库**，再通过飞书说明各仓库从远端拉取了哪些 commit。不是只读扫描。

## 第一步（必须）：运行同步脚本

在 `runtime/` 目录执行：

```bash
bash ../scripts/sync-dev-repos.sh
```

- 脚本会 **fetch + checkout 目标分支 + ff-only pull**
- 将脚本 **完整 Markdown 输出** 作为飞书回复正文（可略作口吻润色，**不要删减 commit 列表**）
- 脚本退出码 `0` 且小结为「全部最新」→ 可再检查下方可选项；若仍无事，回复 `HEARTBEAT_OK`
- 脚本退出码 `2`（有拉取或有问题）→ **必须推送飞书，禁止 `HEARTBEAT_OK`**

## 仓库与分支（固定，不要猜）

| 仓库名 | 路径 | 分支 |
|--------|------|------|
| easygo | `easygo/` | **main** |
| frontend | `frontend/` | **dev** |
| easygo-lark-bridge | 飞书桥接本体（`runtime/..`） | **main** |
| amps_motor_driver_ros2 | `easygo/src/amps_motor_driver_ros2/` | main |
| ch020_imu_driver | `easygo/src/ch020_imu_driver/` | main |
| easygo-app | `easygo/src/easygo-app/` | main |
| easygo_body_filter | `easygo/src/easygo_body_filter/` | main |
| easygo_bringup | `easygo/src/easygo_bringup/` | main |
| easygo_description | `easygo/src/easygo_description/` | main |
| easygo_log_formatter | `easygo/src/easygo_log_formatter/` | main |
| easygo_sim_bringup | `easygo/src/easygo_sim_bringup/` | main |
| kinco_driver_ros2 | `easygo/src/kinco_driver_ros2/` | main |
| navigation2 | `easygo/src/navigation2/` | main |
| oasis_description | `easygo/src/oasis_description/` | main |
| oradar_ros | `easygo/src/oradar_ros/` | main |
| orbbec_driver_ros2 | `easygo/src/orbbec_driver_ros2/` | main |
| pager100_lora_bridge | `easygo/src/pager100_lora_bridge/` | main |
| perception | `easygo/src/perception/` | main |
| slam | `easygo/src/slam/` | main |
| smit_lidar_driver_ros2 | `easygo/src/smit_lidar_driver_ros2/` | main |
| sros_disk_cleaner | `easygo/src/sros_disk_cleaner/` | main |
| tws_battery_driver_ros2 | `easygo/src/tws_battery_driver_ros2/` | main |
| Vda5050_ROS2 | `easygo/src/Vda5050_ROS2/` | main |

**规则**：除 `frontend` 用 **dev** 外，其余全部 **main**。工作区有未提交改动时脚本会跳过该仓库并告警。

## 第二步（可选）

若 `GITLAB_PRIVATE_TOKEN` 可用，可补充（无则跳过）：

1. **GitLab CI** — 后端 `SROS/platforms/easygo`、前端 `standard-fe/easygo` 当前分支最近 pipeline
2. **开放 MR** — 与我相关的 open MR

API：`http://git.standard-robots.com/api/v4`

## 何时 `HEARTBEAT_OK`

仅当：同步脚本报告 **全部最新**、无跳过/失败、且（若查了）CI/MR 也无异常。

## 约束

- **允许**：`git fetch` / `git pull --ff-only`（脚本已做）
- **禁止**：`git push`、改代码、改配置
- **范围**：仅上表仓库
- **飞书卡片**：遵守 `agent-identity.mdc`，列表优先，控制长度
