#!/usr/bin/env bash
# EasyGo Lark Bridge — 安装 feishu-cursor-claw（全部在 workspace/easygo-lark-bridge/ 内）
set -euo pipefail

PACK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="${PACK_ROOT}/config/easygo.env"
CONFIG_EXAMPLE="${PACK_ROOT}/config/easygo.env.example"

die() { echo "错误: $*" >&2; exit 1; }
info() { echo "==> $*"; }

apply_path_defaults() {
  CLAW_INSTALL_DIR="${CLAW_INSTALL_DIR:-${PACK_ROOT}/claw}"
  RUNTIME_DIR="${RUNTIME_DIR:-${EASYGO_CLAW_ROOT:-${PACK_ROOT}/runtime}}"
  WORKSPACE_ROOT="${WORKSPACE_ROOT:-$(dirname "${PACK_ROOT}")}"
  BRIDGE_PROFILE="${BRIDGE_PROFILE:-mac}"
  case "${BRIDGE_PROFILE}" in
    mac|linux) ;;
    *) die "BRIDGE_PROFILE 须为 mac 或 linux，当前: ${BRIDGE_PROFILE}" ;;
  esac
  if [[ -d "${PACK_ROOT}/templates/runtime-${BRIDGE_PROFILE}" ]]; then
    RUNTIME_TEMPLATE="${PACK_ROOT}/templates/runtime-${BRIDGE_PROFILE}"
  elif [[ -d "${PACK_ROOT}/templates/runtime" ]]; then
    RUNTIME_TEMPLATE="${PACK_ROOT}/templates/runtime"
  else
    die "未找到 runtime 模板: templates/runtime-${BRIDGE_PROFILE}"
  fi
}

load_config() {
  # shellcheck disable=SC1090
  source "${CONFIG_FILE}"
  apply_path_defaults
  : "${WORKSPACE_ROOT:?WORKSPACE_ROOT 未设置}"
  if [[ -z "${ALLOWED_OPERATOR_OPEN_IDS:-}" && -n "${ALLOWED_OPERATOR_OPEN_ID:-}" ]]; then
    ALLOWED_OPERATOR_OPEN_IDS="${ALLOWED_OPERATOR_OPEN_ID}"
  fi
  if [[ -z "${CHAT_OPERATOR_OPEN_IDS:-}" && -n "${ALLOWED_OPERATOR_OPEN_IDS:-}" ]]; then
    CHAT_OPERATOR_OPEN_IDS="${ALLOWED_OPERATOR_OPEN_IDS}"
  fi
  if [[ -z "${CHAT_OPERATOR_NAMES:-}" && -n "${ALLOWED_OPERATOR_NAMES:-}" ]]; then
    CHAT_OPERATOR_NAMES="${ALLOWED_OPERATOR_NAMES}"
  fi
  : "${CHAT_OPERATOR_OPEN_IDS:?CHAT_OPERATOR_OPEN_IDS 未设置（或设置 ALLOWED_OPERATOR_OPEN_IDS）}"
  : "${AUTHORIZER_OPEN_ID:?AUTHORIZER_OPEN_ID 未设置（唯一授权人 open_id）}"
  : "${FEISHU_APP_ID:?FEISHU_APP_ID 未设置}"
  : "${FEISHU_APP_SECRET:?FEISHU_APP_SECRET 未设置}"
  : "${CURSOR_API_KEY:?CURSOR_API_KEY 未设置}"
}

ensure_config() {
  if [[ ! -f "${CONFIG_FILE}" ]]; then
    cp "${CONFIG_EXAMPLE}" "${CONFIG_FILE}"
    echo "已创建 ${CONFIG_FILE}"
    echo "请填写 FEISHU_APP_SECRET、CURSOR_API_KEY、ALLOWED_OPERATOR_OPEN_IDS 后重新运行。"
    exit 0
  fi
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "未找到命令: $1"
}

migrate_legacy_layout() {
  local old_claw="${HOME}/tools/feishu-cursor-claw"
  local old_runtime="${WORKSPACE_ROOT}/easygo-claw"
  local old_tools_inbox="${HOME}/tools/inbox"
  local old_projects="${HOME}/tools/projects.json"

  if [[ -d "${old_claw}" && "${CLAW_INSTALL_DIR}" != "${old_claw}" && ! -e "${CLAW_INSTALL_DIR}" ]]; then
    info "迁移 Claw: ${old_claw} → ${CLAW_INSTALL_DIR}"
    mkdir -p "$(dirname "${CLAW_INSTALL_DIR}")"
    mv "${old_claw}" "${CLAW_INSTALL_DIR}"
  fi

  if [[ -d "${old_runtime}" && "${RUNTIME_DIR}" != "${old_runtime}" ]]; then
    info "迁移 runtime 数据: ${old_runtime} → ${RUNTIME_DIR}"
    mkdir -p "${RUNTIME_DIR}"
    # 保留 inbox/logs/state/.cursor/.memory* 等运行时文件
    for item in inbox logs state .cursor .memory.sqlite .memory.sqlite-shm .memory.sqlite-wal AGENTS.md; do
      if [[ -e "${old_runtime}/${item}" ]]; then
        rm -rf "${RUNTIME_DIR}/${item}" 2>/dev/null || true
        mv "${old_runtime}/${item}" "${RUNTIME_DIR}/${item}"
      fi
    done
    # 旧 symlink 会在 setup_runtime 里重建
    rmdir "${old_runtime}" 2>/dev/null || info "  可手动删除空目录: ${old_runtime}"
  fi

  if [[ -L "${old_tools_inbox}" ]]; then
    rm -f "${old_tools_inbox}"
    echo "  已移除 ${old_tools_inbox}"
  fi
  if [[ -f "${old_projects}" ]]; then
    rm -f "${old_projects}"
    echo "  已移除 ${old_projects}"
  fi
}

install_claw() {
  if [[ -d "${CLAW_INSTALL_DIR}/.git" ]]; then
    info "Claw 已存在: ${CLAW_INSTALL_DIR}"
  else
    info "克隆 feishu-cursor-claw → ${CLAW_INSTALL_DIR}"
    mkdir -p "$(dirname "${CLAW_INSTALL_DIR}")"
    git clone https://github.com/nongjun/feishu-cursor-claw.git "${CLAW_INSTALL_DIR}"
  fi

  info "安装 Claw 依赖 (bun install)"
  (cd "${CLAW_INSTALL_DIR}" && bun install)
}

setup_runtime() {
  info "创建 runtime: ${RUNTIME_DIR}"
  mkdir -p "${RUNTIME_DIR}"

  link_repo() {
    local name="$1"
    local target="$2"
    local link="${RUNTIME_DIR}/${name}"
    if [[ -L "${link}" ]]; then
      echo "  symlink: ${name}"
    elif [[ -e "${link}" ]]; then
      die "${link} 已存在且不是 symlink"
    else
      ln -s "${target}" "${link}"
      echo "  创建 symlink: ${name} → ${target}"
    fi
  }

  link_repo "easygo" "${WORKSPACE_ROOT}/easygo"
  link_repo "frontend" "${WORKSPACE_ROOT}/standard-fe/easygo"
  # 不要 symlink bridge → 仓库根：会形成 runtime/bridge/runtime 无限循环，拖死记忆索引

  info "部署 runtime .cursor 模板 (${BRIDGE_PROFILE}: ${RUNTIME_TEMPLATE})"
  mkdir -p "${RUNTIME_DIR}/.cursor/rules"
  rsync -a "${RUNTIME_TEMPLATE}/.cursor/" "${RUNTIME_DIR}/.cursor/"

  RUNTIME_TEMPLATE="${RUNTIME_TEMPLATE}" RUNTIME_DIR="${RUNTIME_DIR}" \
    bash "${PACK_ROOT}/scripts/sync-authorized-operators.sh"
}

setup_runtime_dirs() {
  local bridge_root inbox_link sessions_link projects_dest

  bridge_root="${PACK_ROOT}"
  inbox_link="${bridge_root}/inbox"
  sessions_link="${CLAW_INSTALL_DIR}/.sessions.json"
  projects_dest="${bridge_root}/projects.json"

  info "Claw 路径（均在 easygo-lark-bridge/ 内）"
  mkdir -p "${RUNTIME_DIR}/inbox" \
           "${RUNTIME_DIR}/logs" \
           "${RUNTIME_DIR}/state" \
           "${RUNTIME_DIR}/.cursor/sessions"

  ln -sfn "${RUNTIME_DIR}/inbox" "${inbox_link}"
  echo "  ${inbox_link} → runtime/inbox"

  if [[ -e "${sessions_link}" && ! -L "${sessions_link}" ]]; then
    mv "${sessions_link}" "${RUNTIME_DIR}/state/sessions.json"
  fi
  ln -sfn "${RUNTIME_DIR}/state/sessions.json" "${sessions_link}"
  echo "  claw/.sessions.json → runtime/state/sessions.json"

  if [[ -f /tmp/feishu-cursor.log && ! -s "${RUNTIME_DIR}/logs/feishu-cursor.log" ]]; then
    mv /tmp/feishu-cursor.log "${RUNTIME_DIR}/logs/feishu-cursor.log" 2>/dev/null || true
  fi
  touch "${RUNTIME_DIR}/logs/feishu-cursor.log"

  info "写入 projects.json → ${projects_dest}"
  cp "${PACK_ROOT}/templates/claw/projects.json" "${projects_dest}"
  python3 - <<PY
import json, pathlib
p = pathlib.Path("${projects_dest}")
data = json.loads(p.read_text())
data["projects"]["easygo"]["path"] = "${RUNTIME_DIR}"
p.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
PY
}

setup_claw_config() {
  info "Claw 配置：优先使用 config/easygo.env（patch-claw-env-unify）"
  if [[ -f "${CLAW_INSTALL_DIR}/.env" && ! -L "${CLAW_INSTALL_DIR}/.env" ]]; then
    if [[ ! -f "${CONFIG_FILE}" ]]; then
      mv "${CLAW_INSTALL_DIR}/.env" "${CONFIG_FILE}"
      echo "  已迁移 claw/.env → config/easygo.env"
    else
      echo "  保留 config/easygo.env；可删除过时的 claw/.env"
    fi
  fi
  if [[ ! -f "${CONFIG_FILE}" ]]; then
    cp "${PACK_ROOT}/templates/claw/.env.example" "${CONFIG_FILE}" 2>/dev/null || cp "${CONFIG_EXAMPLE}" "${CONFIG_FILE}"
  fi

  info "合并密钥到 config/easygo.env"
  python3 - <<PY
from pathlib import Path
env_path = Path("${CONFIG_FILE}")
lines = env_path.read_text().splitlines() if env_path.exists() else []
values = {
    "CURSOR_API_KEY": "${CURSOR_API_KEY}",
    "FEISHU_APP_ID": "${FEISHU_APP_ID}",
    "FEISHU_APP_SECRET": "${FEISHU_APP_SECRET}",
    "CURSOR_MODEL": "${CURSOR_MODEL:-composer-2.5}",
    "AUTHORIZER_OPEN_ID": "${AUTHORIZER_OPEN_ID}",
    "AUTHORIZER_OPEN_IDS": "${AUTHORIZER_OPEN_IDS:-${AUTHORIZER_OPEN_ID}}",
    "AUTHORIZER_NAME": "${AUTHORIZER_NAME:-杨展航}",
    "CHAT_OPERATOR_OPEN_IDS": "${CHAT_OPERATOR_OPEN_IDS}",
    "CHAT_OPERATOR_NAMES": "${CHAT_OPERATOR_NAMES:-}",
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
  ln -sfn "${CONFIG_FILE}" "${CLAW_INSTALL_DIR}/.env"
  echo "  claw/.env → config/easygo.env"
}

print_next_steps() {
  local service_hint
  if [[ "${BRIDGE_PROFILE}" == "linux" ]]; then
    service_hint="  bash ${PACK_ROOT}/scripts/claw-service-linux.sh install"
  else
    service_hint="  bash ${PACK_ROOT}/scripts/claw-service.sh install"
  fi
  cat <<EOF

安装完成 [profile=${BRIDGE_PROFILE}]。路径在 ${PACK_ROOT}/ 内：

  claw/      feishu-cursor-claw
  runtime/   Agent workspace + 日志/收件/会话

下一步：
  bash ${PACK_ROOT}/scripts/verify-agent-workspace.sh
  cd ${CLAW_INSTALL_DIR} && bun run server.ts
${service_hint}

EOF
}

main() {
  info "EasyGo Lark Bridge 安装 (profile=${BRIDGE_PROFILE:-mac})"
  ensure_config
  load_config

  require_cmd git
  require_cmd bun
  require_cmd rsync
  require_cmd python3

  [[ -d "${WORKSPACE_ROOT}/easygo" ]] || die "未找到: ${WORKSPACE_ROOT}/easygo"
  [[ -d "${WORKSPACE_ROOT}/standard-fe/easygo" ]] || die "未找到: ${WORKSPACE_ROOT}/standard-fe/easygo"

  migrate_legacy_layout
  install_claw
  setup_runtime
  setup_runtime_dirs
  bash "${PACK_ROOT}/scripts/patch-claw-dedupe.sh"
  if [[ "${BRIDGE_PROFILE}" == "linux" ]]; then
    bash "${PACK_ROOT}/scripts/patch-claw-profile-linux.sh"
  else
    bash "${PACK_ROOT}/scripts/patch-claw-profile.sh"
  fi
  bash "${PACK_ROOT}/scripts/patch-claw-no-resume.sh"
  bash "${PACK_ROOT}/scripts/patch-claw-group-mention.sh"
  bash "${PACK_ROOT}/scripts/patch-claw-agent-timeout.sh"
  bash "${PACK_ROOT}/scripts/patch-claw-heartbeat-sync.sh"
  bash "${PACK_ROOT}/scripts/patch-claw-heartbeat-cmd.sh"
  bash "${PACK_ROOT}/scripts/patch-claw-bot-openid-retry.sh" || true
  bash "${PACK_ROOT}/scripts/patch-claw-topic-agent.sh"
  bash "${PACK_ROOT}/scripts/patch-claw-group-topic-gate-fix.sh"
  bash "${PACK_ROOT}/scripts/patch-claw-types-after-gate.sh"
  bash "${PACK_ROOT}/scripts/patch-claw-reply-card-retry.sh"
  bash "${PACK_ROOT}/scripts/patch-claw-mention-id-fix.sh"
  bash "${PACK_ROOT}/scripts/patch-claw-permission-gate.sh" || true
  bash "${PACK_ROOT}/scripts/patch-claw-group-quiet-reply.sh"
  bash "${PACK_ROOT}/scripts/patch-claw-env-unify.sh" || true
  bash "${PACK_ROOT}/scripts/patch-claw-permission-grant.sh" || true
  setup_claw_config
  print_next_steps
}

main "$@"
