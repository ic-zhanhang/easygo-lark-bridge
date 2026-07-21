#!/usr/bin/env bash
# EasyGo Claw 服务管理（日志在 easygo-lark-bridge/runtime/logs/）
set -euo pipefail

PACK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="${PACK_ROOT}/config/easygo.env"

if [[ -f "${CONFIG_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${CONFIG_FILE}"
fi

CLAW_INSTALL_DIR="${CLAW_INSTALL_DIR:-${PACK_ROOT}/claw}"
RUNTIME_DIR="${RUNTIME_DIR:-${EASYGO_CLAW_ROOT:-${PACK_ROOT}/runtime}}"

LABEL="com.easygo.lark-claw"
PLIST="$HOME/Library/LaunchAgents/${LABEL}.plist"
BUN_BIN="$(command -v bun 2>/dev/null || echo "$HOME/.bun/bin/bun")"
LOG_FILE="${RUNTIME_DIR}/logs/feishu-cursor.log"

mkdir -p "${RUNTIME_DIR}/logs"

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

# Agent 改完桥接后请用这个，勿在任务中途直接 restart（会 SIGTERM 杀掉自己）
cmd_restart_defer() {
  local sec="${1:-20}"
  if ! [[ "${sec}" =~ ^[0-9]+$ ]] || [[ "${sec}" -lt 3 ]]; then
    echo "用法: bash $0 restart-defer [秒数≥3]" >&2
    exit 1
  fi
  nohup bash -c "sleep ${sec}; launchctl kill SIGTERM \"gui/\$(id -u)/${LABEL}\" 2>/dev/null; sleep 2; launchctl kickstart -k \"gui/\$(id -u)/${LABEL}\" 2>/dev/null" >/dev/null 2>&1 &
  disown 2>/dev/null || true
  echo "  已安排 ${sec}s 后重启 ${LABEL}（当前任务可先跑完）"
}

cmd_status() {
  echo "EasyGo Claw (${LABEL})"
  echo "  仓库: ${PACK_ROOT}"
  if launchctl print "gui/$(id -u)/${LABEL}" &>/dev/null; then
    echo "  状态: 已安装"
    echo "  日志: ${LOG_FILE}"
  else
    echo "  状态: 未安装"
  fi
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
  restart-defer) cmd_restart_defer "${2:-20}" ;;
  status)    cmd_status ;;
  logs)      cmd_logs ;;
  *)
    echo "用法: bash ${PACK_ROOT}/scripts/claw-service.sh <install|status|logs|restart|restart-defer|...>"
    echo "日志: ${LOG_FILE}"
    ;;
esac
