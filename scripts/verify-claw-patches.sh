#!/usr/bin/env bash
# 在临时目录克隆/检出锁定版上游，依次跑全部 patch，用于 CI 或改 patch 前自检
set -euo pipefail

PACK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PIN_FILE="${PACK_ROOT}/scripts/claw-upstream-pin.txt"
TMP_DIR="$(mktemp -d /tmp/claw-patch-verify.XXXXXX)"
CLAW_DIR="${TMP_DIR}/claw"

cleanup() { rm -rf "${TMP_DIR}"; }
trap cleanup EXIT

PIN="$(tr -d '[:space:]' < "${PIN_FILE}")"
[[ -n "${PIN}" ]] || { echo "错误: ${PIN_FILE} 为空" >&2; exit 1; }

echo "==> 校验 patch 链 (上游 ${PIN:0:12}…)"
git clone --depth 50 https://github.com/nongjun/feishu-cursor-claw.git "${CLAW_DIR}"
(cd "${CLAW_DIR}" && git checkout "${PIN}")
(cd "${CLAW_DIR}" && bun install --silent)

export CLAW_INSTALL_DIR="${CLAW_DIR}"
export PACK_ROOT

PATCHES=(
  patch-claw-dedupe.sh
  patch-claw-profile-linux.sh
  patch-claw-no-resume.sh
  patch-claw-group-mention.sh
  patch-claw-hide-sender-openid.sh
  patch-claw-agent-timeout.sh
  patch-claw-heartbeat-sync.sh
  patch-claw-heartbeat-cmd.sh
  patch-claw-heartbeat-p2p-authorizer.sh
  patch-claw-topic-agent.sh
  patch-claw-group-topic-gate-fix.sh
  patch-claw-types-after-gate.sh
  patch-claw-reply-card-retry.sh
  patch-claw-card-delivery-fix.sh
  patch-claw-mention-id-fix.sh
  patch-claw-bot-openid-retry.sh
  patch-claw-permission-gate.sh
  patch-claw-group-quiet-reply.sh
  patch-claw-progress-done-guard.sh
  patch-claw-group-topic-context-progress.sh
  patch-claw-env-unify.sh
  patch-claw-permission-grant.sh
  patch-claw-agent-lifecycle.sh
  patch-claw-shutdown-no-fail.sh
  patch-claw-memory-fts-only.sh
  patch-claw-memory-scope.sh
  patch-claw-runtime-tuning.sh
  patch-claw-agent-startup-grace.sh
)

failed=0
for p in "${PATCHES[@]}"; do
  script="${PACK_ROOT}/scripts/${p}"
  if [[ ! -f "${script}" ]]; then
    echo "  ✗ 缺少 ${p}" >&2
    failed=1
    continue
  fi
  echo "  · ${p}"
  if ! bash "${script}"; then
    echo "  ✗ ${p} 失败" >&2
    failed=1
  fi
done

if [[ "${failed}" -ne 0 ]]; then
  echo "==> patch 校验失败" >&2
  exit 1
fi

echo "==> 全部 ${#PATCHES[@]} 个 patch 校验通过"
