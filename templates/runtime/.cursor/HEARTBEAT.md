# EasyGo 心跳检查

在活跃时段内执行以下检查，将摘要发送到飞书。若无异常可简短报告「无异常」。

## 检查项

1. **Git 状态** — `easygo/` 与 `frontend/`：
   - 当前分支
   - 是否有未提交变更
   - 相对 origin 领先/落后 commit 数

2. **GitLab CI** — 若环境变量 `GITLAB_PRIVATE_TOKEN` 可用：
   - 后端 `SROS/platforms/easygo` 当前分支最近 pipeline 状态
   - 前端 `standard-fe/easygo` 当前分支最近 pipeline 状态
   - API 基址：`http://git.standard-robots.com/api/v4`

3. **开放 MR** — 同一 GitLab 实例上与我相关的 open MR（我创建或 assign 给我）

## 约束

- **只读检查**：不要修改任何代码或配置
- **范围**：仅关注 `easygo/`、`frontend/`、`bridge/` 三个 symlink 目录
- **输出**：每个 repo 一小节，失败/异常项优先
