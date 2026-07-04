# easygo-claw 运行时目录

Claw 的消息、日志、会话等运行时数据统一放在 **easygo-claw/** 下：

```
easygo-claw/
├── easygo/              → 后端 repo（symlink）
├── frontend/            → 前端 repo（symlink）
├── lark-bridge/         → 部署包（symlink）
├── inbox/               飞书发来的图片/语音/文件
├── logs/
│   └── feishu-cursor.log   Claw 服务日志（launchd）
├── state/
│   └── sessions.json       Claw 会话索引（symlink 自 Claw 安装目录）
└── .cursor/
    └── sessions/           按日期的对话 JSONL
        └── YYYY-MM-DD.jsonl
```

`install.sh` 会把 `~/tools/inbox` symlink 到本目录的 `inbox/`。
