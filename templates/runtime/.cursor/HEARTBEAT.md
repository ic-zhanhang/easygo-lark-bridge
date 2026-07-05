# EasyGo 心跳检查

在活跃时段内执行以下检查，将摘要发送到飞书。若无异常可简短报告「无异常」。

## 检查项

1. **Git 状态** — `easygo/`、`frontend/`、`easygo/src/*/` 子仓库：
   - 各 repo 当前分支、是否有未提交变更、是否与 origin 同步
   - **前端** `frontend/`：相对 **`origin/dev`** 领先/落后（不是 main）
   - **后端根** `easygo/`：当前分支与 remote 状态
   - **后端 src/**：扫描 `easygo/src/*/` 独立 git 仓库，优先报 dirty / ahead / behind 异常项

2. **GitLab CI** — 若环境变量 `GITLAB_PRIVATE_TOKEN` 可用：
   - 后端 `SROS/platforms/easygo` 当前分支最近 pipeline 状态
   - 前端 `standard-fe/easygo` 当前分支最近 pipeline 状态
   - API 基址：`http://git.standard-robots.com/api/v4`

3. **开放 MR** — 同一 GitLab 实例上与我相关的 open MR（我创建或 assign 给我）

## 约束

- **只读检查**：不要修改任何代码或配置
- **范围**：仅关注 `easygo/`、`frontend/`
- **输出**：每个 repo 一小节，失败/异常项优先
