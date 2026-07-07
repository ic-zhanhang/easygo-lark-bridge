#!/usr/bin/env bash
# 拉取 runtime 可见的开发仓库，输出 Markdown 摘要（供心跳 / 飞书推送）
set -euo pipefail

PACK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME_DIR="${RUNTIME_DIR:-${PACK_ROOT}/runtime}"

if [[ ! -d "${RUNTIME_DIR}/easygo" ]]; then
  echo "❌ 未找到 runtime/easygo，请检查 RUNTIME_DIR=${RUNTIME_DIR}"
  exit 1
fi

# name|相对 runtime 的路径|目标分支
REPOS=(
  "easygo|easygo|main"
  "frontend|frontend|dev"
  "easygo-lark-bridge|..|main"
  "amps_motor_driver_ros2|easygo/src/amps_motor_driver_ros2|main"
  "ch020_imu_driver|easygo/src/ch020_imu_driver|main"
  "easygo-app|easygo/src/easygo-app|main"
  "easygo_body_filter|easygo/src/easygo_body_filter|main"
  "easygo_bringup|easygo/src/easygo_bringup|main"
  "easygo_description|easygo/src/easygo_description|main"
  "easygo_log_formatter|easygo/src/easygo_log_formatter|main"
  "easygo_sim_bringup|easygo/src/easygo_sim_bringup|main"
  "kinco_driver_ros2|easygo/src/kinco_driver_ros2|main"
  "navigation2|easygo/src/navigation2|main"
  "oasis_description|easygo/src/oasis_description|main"
  "oradar_ros|easygo/src/oradar_ros|main"
  "orbbec_driver_ros2|easygo/src/orbbec_driver_ros2|main"
  "pager100_lora_bridge|easygo/src/pager100_lora_bridge|main"
  "perception|easygo/src/perception|main"
  "slam|easygo/src/slam|main"
  "smit_lidar_driver_ros2|easygo/src/smit_lidar_driver_ros2|main"
  "sros_disk_cleaner|easygo/src/sros_disk_cleaner|main"
  "tws_battery_driver_ros2|easygo/src/tws_battery_driver_ros2|main"
  "Vda5050_ROS2|easygo/src/Vda5050_ROS2|main"
)

has_updates=0
has_issues=0
lines=()

lines+=("## 本地仓库同步")
lines+=("")
lines+=("时间：$(date '+%Y-%m-%d %H:%M:%S')")
lines+=("**共 ${#REPOS[@]} 个仓库**（easygo、frontend、飞书桥接 + src 下 20 个子仓）")
lines+=("")

# fetch 失败且报 ref 锁/不一致时，删除陈旧远端跟踪引用后重试一次
git_fetch_with_repair() {
  local dir="$1"
  local branch="$2"
  local out
  out="$(git -C "${dir}" -c credential.helper= -c core.askPass= fetch origin 2>&1)" && return 0
  if [[ "${out}" != *"cannot lock ref"* && "${out}" != *"unable to update local ref"* ]]; then
    printf 'FAILED:%s' "${out//$'\n'/; }"
    return 0
  fi
  git -C "${dir}" update-ref -d "refs/remotes/origin/${branch}" 2>/dev/null || true
  rm -f "${dir}/.git/refs/remotes/origin/${branch}" 2>/dev/null || true
  if out="$(git -C "${dir}" -c credential.helper= -c core.askPass= fetch origin 2>&1)"; then
    return 0
  fi
  printf 'FAILED:%s' "${out//$'\n'/; }"
  return 0
}

pull_one() {
  local name="$1"
  local rel="$2"
  local branch="$3"
  local dir
  dir="$(cd "${RUNTIME_DIR}/${rel}" && pwd)"

  if ! git -C "${dir}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    lines+=("### ${name}")
    lines+=("- ⚠️ 跳过：不是 git 仓库")
    lines+=("")
    has_issues=1
    return
  fi

  lines+=("### ${name} (\`${branch}\`)")

  if [[ -n "$(git -C "${dir}" status --porcelain)" ]]; then
    lines+=("- ⚠️ **未 pull**：工作区有未提交改动，已跳过以免覆盖")
    lines+=("- 当前：\`$(git -C "${dir}" status -sb | head -1)\`")
    lines+=("")
    has_issues=1
    return
  fi

  local fetch_err
  fetch_err="$(git_fetch_with_repair "${dir}" "${branch}")"
  if [[ "${fetch_err}" == FAILED:* ]]; then
    lines+=("- ❌ \`git fetch\` 失败：\`${fetch_err#FAILED:}\`")
    lines+=("")
    has_issues=1
    return
  fi

  local old_head
  old_head="$(git -C "${dir}" rev-parse HEAD)"

  if ! git -C "${dir}" checkout "${branch}" >/dev/null 2>&1; then
    if git -C "${dir}" show-ref --verify --quiet "refs/remotes/origin/${branch}"; then
      git -C "${dir}" checkout -B "${branch}" "origin/${branch}" >/dev/null 2>&1
    else
      lines+=("- ❌ 无法切换到 \`${branch}\`（远端无 origin/${branch}）")
      lines+=("")
      has_issues=1
      return
    fi
  fi

  local pull_out
  if pull_out="$(git -C "${dir}" pull --ff-only origin "${branch}" 2>&1)"; then
    :
  else
    lines+=("- ❌ pull 失败：\`${pull_out//$'\n'/; }\`")
    lines+=("")
    has_issues=1
    return
  fi

  local new_head
  new_head="$(git -C "${dir}" rev-parse HEAD)"

  if [[ "${old_head}" == "${new_head}" ]]; then
    lines+=("- ✅ 已是最新（无新提交）")
  else
    has_updates=1
    local count
    count="$(git -C "${dir}" rev-list --count "${old_head}..${new_head}")"
    lines+=("- 📥 **拉取了 ${count} 个新提交**（\`${old_head:0:8}\` → \`${new_head:0:8}\`）")
    while IFS= read -r line; do
      lines+=("  - ${line}")
    done < <(git -C "${dir}" log --oneline "${old_head}..${new_head}" | head -8)
    if [[ "${count}" -gt 8 ]]; then
      lines+=("  - …及其他 $((count - 8)) 条")
    fi
  fi

  lines+=("")
}

for entry in "${REPOS[@]}"; do
  IFS='|' read -r name rel branch <<< "${entry}"
  pull_one "${name}" "${rel}" "${branch}"
done

if [[ "${has_updates}" -eq 1 ]]; then
  lines+=("---")
  lines+=("**小结**：有仓库从远端拉取了新提交，详见上文。")
elif [[ "${has_issues}" -eq 1 ]]; then
  lines+=("---")
  lines+=("**小结**：本次无成功拉取的新提交，但有仓库需要人工处理。")
else
  lines+=("---")
  lines+=("**小结**：全部仓库已是最新。")
fi

printf '%s\n' "${lines[@]}"

# 供调用方判断是否推送飞书：有更新或有问题则非 OK
if [[ "${has_updates}" -eq 1 || "${has_issues}" -eq 1 ]]; then
  exit 2
fi
exit 0
