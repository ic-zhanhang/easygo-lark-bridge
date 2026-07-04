# ADR 0002: 单树布局 — 全部落在 easygo-lark-bridge/

## 状态

已接受（2026-07-05），取代 ADR 0001 中「Claw 在 ~/tools 与配置分离」的做法。

## 背景

- 用户要求所有相关路径在 `workspace/` 内，不接受 `~/tools/feishu-cursor-claw` 与独立的 `~/workspace/easygo-claw`。
- Claw 仍要求 `projects.json` 与 `inbox` 位于 `claw/` 的父目录（仓库根）。

## 决策

```
workspace/easygo-lark-bridge/
├── claw/           ← feishu-cursor-claw（gitignore）
├── runtime/        ← Agent workspace + 运行时数据（gitignore）
├── inbox → runtime/inbox
├── projects.json
└── config/ scripts/ templates/ docs/  ← 入库
```

- `install.sh` 自动从 `~/tools/` 与旧 `easygo-claw/` 迁移。
- `runtime/easygo|frontend|bridge` 为 symlink，保持 Agent 视野隔离。

## 后果

- 一个仓库、一个 workspace 文件夹即可理解全貌。
- `claw/` 仍可用 `git pull` 升级（在 bridge 仓内）。
- `runtime/`、`claw/` 不入库，避免提交密钥与 sqlite/日志。
