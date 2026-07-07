#!/usr/bin/env bash
# 秧秧 Claw — systemd 用户服务（Linux 常开主机）
set -euo pipefail

PACK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="${PACK_ROOT}/config/easygo.env"

if [[ -f "${CONFIG_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${CONFIG_FILE}"
fi

CLAW_INSTALL_DIR="${CLAW_INSTALL_DIR:-${PACK_ROOT}/claw}"
RUNTIME_DIR="${RUNTIME_DIR:-${EASYGO_CLAW_ROOT:-${PACK_ROOT}/runtime}}"

UNIT_NAME="${SYSTEMD_UNIT:-lark-assistant.service}"
LABEL="${SERVICE_LABEL:-com.ic.lark-assistant}"
SERVICE_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
UNIT_PATH="${SERVICE_DIR}/${UNIT_NAME}"
BUN_BIN="$(command -v bun 2>/dev/null || echo "$HOME/.bun/bin/bun")"
LOG_FILE="${RUNTIME_DIR}/logs/feishu-cursor.log"

mkdir -p "${RUNTIME_DIR}/logs" "${SERVICE_DIR}"

generate_unit() {
  cat > "$UNIT_PATH" <<UNIT
[Unit]
Description=Feishu Cursor Claw (${LABEL})
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=${CLAW_INSTALL_DIR}
Environment=HOME=${HOME}
Environment=PATH=${HOME}/.bun/bin:${HOME}/.local/bin:/usr/local/bin:/usr/bin:/bin
ExecStart=${BUN_BIN} run ${CLAW_INSTALL_DIR}/start.ts
Restart=on-failure
RestartSec=5
StandardOutput=append:${LOG_FILE}
StandardError=append:${LOG_FILE}

[Install]
WantedBy=default.target
UNIT
  echo "  unit: ${UNIT_PATH}"
  echo "  日志: ${LOG_FILE}"
}

cmd_install() {
  echo "安装秧秧 Claw systemd 用户服务..."
  generate_unit
  systemctl --user daemon-reload
  systemctl --user enable --now "${UNIT_NAME}"
  echo "  服务已启用并启动"
  echo "  提示: 若希望登出后仍运行，执行: loginctl enable-linger \$USER"
}

cmd_uninstall() {
  systemctl --user disable --now "${UNIT_NAME}" 2>/dev/null || true
  rm -f "$UNIT_PATH"
  systemctl --user daemon-reload
  echo "  服务已卸载"
}

cmd_start() {
  systemctl --user start "${UNIT_NAME}" && echo "  已启动"
}

cmd_stop() {
  systemctl --user stop "${UNIT_NAME}" && echo "  已停止"
}

cmd_restart() {
  systemctl --user restart "${UNIT_NAME}" && echo "  已重启"
}

cmd_status() {
  echo "秧秧 Claw (${UNIT_NAME})"
  echo "  仓库: ${PACK_ROOT}"
  systemctl --user status "${UNIT_NAME}" --no-pager 2>/dev/null || echo "  状态: 未安装"
  echo "  日志: ${LOG_FILE}"
}

cmd_logs() {
  [[ -f "${LOG_FILE}" ]] && tail -f "${LOG_FILE}" || echo "  日志不存在: ${LOG_FILE}"
}

case "${1:-}" in
  install)   cmd_install ;;
  uninstall) cmd_uninstall ;;
  start)     cmd_start ;;
  stop)      cmd_stop ;;
  restart)   cmd_restart ;;
  status)    cmd_status ;;
  logs)      cmd_logs ;;
  *)
    echo "用法: bash ${PACK_ROOT}/scripts/claw-service-linux.sh <install|status|logs|...>"
    echo "日志: ${LOG_FILE}"
    ;;
esac
