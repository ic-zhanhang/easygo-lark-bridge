#!/usr/bin/env bash
# EasyGo 版 Claw 服务管理：日志与状态文件统一落在 easygo-claw/
set -euo pipefail

PACK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="${PACK_ROOT}/config/easygo.env"

if [[ -f "${CONFIG_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${CONFIG_FILE}"
fi

: "${EASYGO_CLAW_ROOT:=/Users/ic/workspace/easygo-claw}"
: "${CLAW_INSTALL_DIR:=/Users/ic/tools/feishu-cursor-claw}"

LABEL="com.easygo.lark-claw"
PLIST="$HOME/Library/LaunchAgents/${LABEL}.plist"
BUN_BIN="$(command -v bun 2>/dev/null || echo "$HOME/.bun/bin/bun")"
LOG_FILE="${EASYGO_CLAW_ROOT}/logs/feishu-cursor.log"

mkdir -p "${EASYGO_CLAW_ROOT}/logs"

generate_plist() {
  cat > "$PLIST" <<PEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>${LABEL}</string>
	<key>ProgramArguments</key>
	<array>
		<string>${BUN_BIN}</string>
		<string>run</string>
		<string>${CLAW_INSTALL_DIR}/start.ts</string>
	</array>
	<key>WorkingDirectory</key>
	<string>${CLAW_INSTALL_DIR}</string>
	<key>EnvironmentVariables</key>
	<dict>
		<key>HOME</key>
		<string>${HOME}</string>
		<key>PATH</key>
		<string>$(dirname "${BUN_BIN}"):${HOME}/.local/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
	</dict>
	<key>RunAtLoad</key>
	<true/>
	<key>KeepAlive</key>
	<true/>
	<key>StandardOutPath</key>
	<string>${LOG_FILE}</string>
	<key>StandardErrorPath</key>
	<string>${LOG_FILE}</string>
	<key>ProcessType</key>
	<string>Background</string>
</dict>
</plist>
PEOF
  echo "  plist: ${PLIST}"
  echo "  日志:  ${LOG_FILE}"
}

cmd_install() {
  echo "安装 EasyGo Claw 开机自启..."
  generate_plist
  launchctl bootout "gui/$(id -u)/${LABEL}" 2>/dev/null || true
  launchctl bootstrap "gui/$(id -u)" "$PLIST" 2>/dev/null || true
  echo "  服务已安装并启动"
}

cmd_uninstall() {
  launchctl bootout "gui/$(id -u)/${LABEL}" 2>/dev/null || true
  rm -f "$PLIST"
  echo "  服务已卸载"
}

cmd_start() {
  launchctl kickstart -k "gui/$(id -u)/${LABEL}" 2>/dev/null && echo "  已启动" || echo "  请先 install"
}

cmd_stop() {
  launchctl kill SIGTERM "gui/$(id -u)/${LABEL}" 2>/dev/null && echo "  已停止" || echo "  未在运行"
}

cmd_restart() { cmd_stop; sleep 2; cmd_start; }

cmd_status() {
  echo "EasyGo Claw 服务 (${LABEL})"
  if launchctl print "gui/$(id -u)/${LABEL}" &>/dev/null; then
    echo "  状态: 已安装"
    echo "  日志: ${LOG_FILE}"
    echo "  数据: ${EASYGO_CLAW_ROOT}"
  else
    echo "  状态: 未安装 → bash ${PACK_ROOT}/scripts/claw-service.sh install"
  fi
}

cmd_logs() {
  if [[ -f "${LOG_FILE}" ]]; then
    tail -f "${LOG_FILE}"
  else
    echo "  日志尚不存在: ${LOG_FILE}"
  fi
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
    cat <<EOF
用法: bash ${PACK_ROOT}/scripts/claw-service.sh <install|uninstall|start|stop|restart|status|logs>

日志: ${LOG_FILE}
数据: ${EASYGO_CLAW_ROOT}/{inbox,logs,state,.cursor/sessions}
EOF
    ;;
esac
