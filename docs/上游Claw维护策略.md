# 上游 Claw 维护策略

EasyGo 桥接对 [feishu-cursor-claw](https://github.com/nongjun/feishu-cursor-claw) 通过 `scripts/patch-claw-*.sh` 注入定制。上游任意改动可能导致 patch 匹配失败。

## 当前策略

1. **版本锁定**：`install.sh` 将上游 checkout 到 `CLAW_UPSTREAM_COMMIT`（见 `scripts/claw-upstream-pin.txt`）。
2. **安装前校验**：`scripts/verify-claw-patches.sh` 在临时目录克隆上游并依次跑全部 patch，CI / 本地改 patch 后应先跑此脚本。
3. **定制模块化**：业务逻辑优先放在 `templates/claw/*.ts`，由 patch **复制 + 少量 import 注入**，避免大块 sed 改 `server.ts`。
4. **渐进 fork**：待 patch 数量稳定后，fork 上游仓库，把 EasyGo 模块合进 fork，逐步删除 patch 链。

## 改 patch 的流程

```bash
# 1. 校验当前 patch 链
bash scripts/verify-claw-patches.sh

# 2. 本机重装
BRIDGE_PROFILE=linux bash scripts/install.sh

# 3. 重启服务
bash scripts/claw-service-linux.sh restart
```

## 升级上游

1. 在临时目录 checkout 目标 commit，跑 `verify-claw-patches.sh`。
2. 修复失败的 patch 脚本。
3. 更新 `scripts/claw-upstream-pin.txt` 中的 commit hash。
4. Mac push → Linux pull + install（见 `.cursor/rules/deploy-workflow.mdc`）。
