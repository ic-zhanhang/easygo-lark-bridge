# EasyGo 心跳检查

**调度**：工作日 **10:00–22:00**，约 **每 2 小时** 一次（深夜不跑）。

**何时回复 `HEARTBEAT_OK`**：仅当下面全部满足——各 repo 工作区干净、相对远端 **无 behind/ahead**、无失败 CI、无待处理 MR。**只要有一个 repo behind 远端，就必须发摘要，禁止 `HEARTBEAT_OK`。**

在活跃时段内执行以下检查，将摘要发送到飞书。

## 检查项

1. **Git 状态** — `easygo/`、`frontend/`、`easygo/src/*/` 子仓库：
   - **每个 repo 必须先** `git fetch origin`（只更新远端跟踪分支，不改工作区），再 `git status -sb`
   - 不 fetch 无法发现远端新提交，**禁止**只看本地 `git status` 就报「已同步」
   - 各 repo 当前分支、是否有未提交变更、相对 origin 领先/落后提交数
   - **前端** `frontend/`：对比 **`origin/dev`**（不是 main）
   - **后端根** `easygo/`：对比当前分支的 `origin/<branch>`
   - **后端 src/**：扫描 `easygo/src/*/` 独立 git 仓库，优先报 dirty / ahead / behind
   - **behind ≥ 1** 时必须在摘要中写明「落后 N 提交，建议 pull」

2. **GitLab CI** — 若环境变量 `GITLAB_PRIVATE_TOKEN` 可用：
   - 后端 `SROS/platforms/easygo` 当前分支最近 pipeline 状态
   - 前端 `standard-fe/easygo` 当前分支最近 pipeline 状态
   - API 基址：`http://git.standard-robots.com/api/v4`

3. **开放 MR** — 同一 GitLab 实例上与我相关的 open MR（我创建或 assign 给我）

## 约束

- **只读检查**：不要修改任何代码或配置
- **范围**：仅关注 `easygo/`、`frontend/`
- **输出**：每个 repo 一小节，失败/异常项优先
