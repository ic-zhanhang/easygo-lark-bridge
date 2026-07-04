#!/usr/bin/env bash
# EasyGo Lark Bridge — 安装 feishu-cursor-claw 并部署 EasyGo 专属配置
set -euo pipefail

PACK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="${PACK_ROOT}/config/easygo.env"
CONFIG_EXAMPLE="${PACK_ROOT}/config/easygo.env.example"

die() { echo "错误: $*" >&2; exit 1; }
info() { echo "==> $*"; }

load_config() {
  # shellcheck disable=SC1090
  source "${CONFIG_FILE}"
  : "${WORKSPACE_ROOT:?WORKSPACE_ROOT 未设置}"
  : "${EASYGO_CLAW_ROOT:?EASYGO_CLAW_ROOT 未设置}"
  : "${CLAW_INSTALL_DIR:?CLAW_INSTALL_DIR 未设置}"
  : "${ALLOWED_OPERATOR_OPEN_ID:?ALLOWED_OPERATOR_OPEN_ID 未设置}"
  : "${FEISHU_APP_ID:?FEISHU_APP_ID 未设置}"
  : "${FEISHU_APP_SECRET:?FEISHU_APP_SECRET 未设置}"
  : "${CURSOR_API_KEY:?CURSOR_API_KEY 未设置}"
}

ensure_config() {
  if [[ ! -f "${CONFIG_FILE}" ]]; then
    cp "${CONFIG_EXAMPLE}" "${CONFIG_FILE}"
    echo "已创建 ${CONFIG_FILE}"
    echo "请填写 FEISHU_APP_SECRET、CURSOR_API_KEY、ALLOWED_OPERATOR_OPEN_ID 后重新运行。"
    exit 0
  fi
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "未找到命令: $1"
}

install_claw() {
  if [[ -d "${CLAW_INSTALL_DIR}/.git" ]]; then
    info "Claw 已存在，跳过 clone: ${CLAW_INSTALL_DIR}"
  else
    info "克隆 feishu-cursor-claw → ${CLAW_INSTALL_DIR}"
    mkdir -p "$(dirname "${CLAW_INSTALL_DIR}")"
    git clone https://github.com/nongjun/feishu-cursor-claw.git "${CLAW_INSTALL_DIR}"
  fi

  info "安装 Claw 依赖 (bun install)"
  (cd "${CLAW_INSTALL_DIR}" && bun install)
}

setup_easygo_claw_root() {
  info "创建 EasyGo Claw Root: ${EASYGO_CLAW_ROOT}"
  mkdir -p "${EASYGO_CLAW_ROOT}"

  link_repo() {
    local name="$1"
    local target="$2"
    local link="${EASYGO_CLAW_ROOT}/${name}"
    if [[ -L "${link}" ]]; then
      echo "  已存在 symlink: ${name}"
    elif [[ -e "${link}" ]]; then
      die "${link} 已存在且不是 symlink，请手动处理"
    else
      ln -s "${target}" "${link}"
      echo "  创建 symlink: ${name} → ${target}"
    fi
  }

  link_repo "easygo" "${WORKSPACE_ROOT}/easygo"
  link_repo "frontend" "${WORKSPACE_ROOT}/standard-fe/easygo"
  link_repo "lark-bridge" "${WORKSPACE_ROOT}/easygo-lark-bridge"

  info "部署 EasyGo .cursor 模板"
  mkdir -p "${EASYGO_CLAW_ROOT}/.cursor/rules"
  rsync -a "${PACK_ROOT}/templates/easygo-claw/.cursor/" "${EASYGO_CLAW_ROOT}/.cursor/"

  info "写入 Authorized Operator open_id"
  sed -i '' "s/{{ALLOWED_OPERATOR_OPEN_ID}}/${ALLOWED_OPERATOR_OPEN_ID}/g" \
    "${EASYGO_CLAW_ROOT}/.cursor/rules/authorized-operator.mdc"
}

setup_runtime_dirs() {
  local tools_root inbox_link sessions_link

  tools_root="$(dirname "${CLAW_INSTALL_DIR}")"
  inbox_link="${tools_root}/inbox"
  sessions_link="${CLAW_INSTALL_DIR}/.sessions.json"

  info "统一运行时目录 → ${EASYGO_CLAW_ROOT}"
  mkdir -p "${EASYGO_CLAW_ROOT}/inbox" \
           "${EASYGO_CLAW_ROOT}/logs" \
           "${EASYGO_CLAW_ROOT}/state" \
           "${EASYGO_CLAW_ROOT}/.cursor/sessions"

  # Claw 硬编码 inbox = dirname(claw)/inbox，用 symlink 指到 easygo-claw/inbox
  if [[ -e "${inbox_link}" && ! -L "${inbox_link}" ]]; then
    if [[ -n "$(ls -A "${inbox_link}" 2>/dev/null)" ]]; then
      info "迁移 ${inbox_link}/* → ${EASYGO_CLAW_ROOT}/inbox/"
      mv "${inbox_link}"/* "${EASYGO_CLAW_ROOT}/inbox/" 2>/dev/null || true
    fi
    rmdir "${inbox_link}" 2>/dev/null || die "${inbox_link} 非空目录，请手动合并到 ${EASYGO_CLAW_ROOT}/inbox/"
  fi
  ln -sfn "${EASYGO_CLAW_ROOT}/inbox" "${inbox_link}"
  echo "  inbox → ${EASYGO_CLAW_ROOT}/inbox"

  # Claw 会话索引 .sessions.json 也收拢到 easygo-claw/state/
  if [[ -e "${sessions_link}" && ! -L "${sessions_link}" ]]; then
    mv "${sessions_link}" "${EASYGO_CLAW_ROOT}/state/sessions.json"
  fi
  ln -sfn "${EASYGO_CLAW_ROOT}/state/sessions.json" "${sessions_link}"
  echo "  sessions.json → ${EASYGO_CLAW_ROOT}/state/sessions.json"

  # 迁移旧 /tmp 日志（若存在）
  if [[ -f /tmp/feishu-cursor.log && ! -f "${EASYGO_CLAW_ROOT}/logs/feishu-cursor.log" ]]; then
    mv /tmp/feishu-cursor.log "${EASYGO_CLAW_ROOT}/logs/feishu-cursor.log"
    echo "  已迁移 /tmp/feishu-cursor.log"
  fi

  mkdir -p "${EASYGO_CLAW_ROOT}/logs"
  touch "${EASYGO_CLAW_ROOT}/logs/feishu-cursor.log"
}

setup_claw_config() {
  local projects_dest
  projects_dest="$(dirname "${CLAW_INSTALL_DIR}")/projects.json"

  info "写入 Claw projects.json → ${projects_dest}"
  cp "${PACK_ROOT}/templates/claw/projects.json" "${projects_dest}"
  # 若用户自定义了 EASYGO_CLAW_ROOT，替换 path
  if [[ "${EASYGO_CLAW_ROOT}" != "/Users/ic/workspace/easygo-claw" ]]; then
    python3 - <<PY
import json, pathlib
p = pathlib.Path("${projects_dest}")
data = json.loads(p.read_text())
data["projects"]["easygo"]["path"] = "${EASYGO_CLAW_ROOT}"
p.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
PY
  fi

  if [[ ! -f "${CLAW_INSTALL_DIR}/.env" ]]; then
    info "创建 Claw .env"
    cp "${PACK_ROOT}/templates/claw/.env.example" "${CLAW_INSTALL_DIR}/.env"
  fi

  info "合并密钥到 Claw .env"
  python3 - <<PY
from pathlib import Path

env_path = Path("${CLAW_INSTALL_DIR}/.env")
lines = env_path.read_text().splitlines() if env_path.exists() else []
values = {
    "CURSOR_API_KEY": "${CURSOR_API_KEY}",
    "FEISHU_APP_ID": "${FEISHU_APP_ID}",
    "FEISHU_APP_SECRET": "${FEISHU_APP_SECRET}",
    "CURSOR_MODEL": "${CURSOR_MODEL:-composer-2.5}",
}
seen = set()
out = []
for line in lines:
    key = line.split("=", 1)[0].strip() if "=" in line else ""
    if key in values:
        out.append(f"{key}={values[key]}")
        seen.add(key)
    else:
        out.append(line)
for key, val in values.items():
    if key not in seen:
        out.append(f"{key}={val}")
env_path.write_text("\n".join(out) + "\n")
PY

  # GitLab token 供 HEARTBEAT Agent 使用（写入 launchd 环境需用户自行 export 或扩展 service）
  if [[ -n "${GITLAB_PRIVATE_TOKEN:-}" ]]; then
    info "检测到 GITLAB_PRIVATE_TOKEN，可在 Claw 运行环境中 export 供 HEARTBEAT 使用"
  fi
}

print_next_steps() {
  cat <<EOF

安装完成。

下一步：
  1. 验证 Agent CLI:
       bash ${PACK_ROOT}/scripts/verify-agent-workspace.sh

  2. 前台试跑 Claw:
       cd ${CLAW_INSTALL_DIR} && bun run server.ts

  3. 飞书私聊 Bot 发一条测试指令（请用私聊，不要用群聊）

  4. 注册开机自启（日志在 easygo-claw/logs/）:
       bash ${PACK_ROOT}/scripts/claw-service.sh install
       bash ${PACK_ROOT}/scripts/claw-service.sh status

运行时数据目录: ${EASYGO_CLAW_ROOT}/{inbox,logs,state,.cursor/sessions}

EOF
}

main() {
  info "EasyGo Lark Bridge 安装"
  ensure_config
  load_config

  require_cmd git
  require_cmd bun
  require_cmd rsync
  require_cmd python3

  if [[ ! -d "${WORKSPACE_ROOT}/easygo" ]]; then
    die "未找到后端 repo: ${WORKSPACE_ROOT}/easygo"
  fi
  if [[ ! -d "${WORKSPACE_ROOT}/standard-fe/easygo" ]]; then
    die "未找到前端 repo: ${WORKSPACE_ROOT}/standard-fe/easygo"
  fi

  install_claw
  setup_easygo_claw_root
  setup_runtime_dirs
  setup_claw_config
  print_next_steps
}

main "$@"
