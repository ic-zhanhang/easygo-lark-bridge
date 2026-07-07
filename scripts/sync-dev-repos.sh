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
  "oradar_ros|easygo/src/oradar_ros|master"
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
up_to_date_count=0
lines=()

lines+=("## 本地仓库同步")
lines+=("")
lines+=("时间：$(date '+%Y-%m-%d %H:%M:%S')")
lines+=("**共检查 ${#REPOS[@]} 个仓库**，仅列出有拉取或需关注的项")
lines+=("")

# 后台服务无法交互输入 HTTP 凭证；内网 GitLab 统一改用 SSH
ensure_ssh_origin() {
  local dir="$1"
  local url path ssh_url
  url="$(git -C "${dir}" remote get-url origin 2>/dev/null)" || return 0
  if [[ "${url}" =~ ^https?://git\.standard-robots\.com/(.+)$ ]]; then
    path="${BASH_REMATCH[1]}"
    path="${path%.git}"
    ssh_url="git@git.standard-robots.com:${path}.git"
    if [[ "${url}" != "${ssh_url}" ]]; then
      git -C "${dir}" remote set-url origin "${ssh_url}"
    fi
  fi
}

sanitize_git_err() {
  local msg="$1"
  msg="${msg//fatal: /}"
  msg="${msg//Fatal: /}"
  printf '%s' "${msg}"
}

# fetch 失败且报 ref 锁/不一致时，删除陈旧远端跟踪引用后重试一次
git_fetch_with_repair() {
  local dir="$1"
  local branch="$2"
  local out
  ensure_ssh_origin "${dir}"
  out="$(git -C "${dir}" -c credential.helper= -c core.askPass= fetch origin 2>&1)" && return 0
  if [[ "${out}" != *"cannot lock ref"* && "${out}" != *"unable to update local ref"* ]]; then
    printf 'FAILED:%s' "$(sanitize_git_err "${out//$'\n'/; }")"
    return 0
  fi
  git -C "${dir}" update-ref -d "refs/remotes/origin/${branch}" 2>/dev/null || true
  rm -f "${dir}/.git/refs/remotes/origin/${branch}" 2>/dev/null || true
  if out="$(git -C "${dir}" -c credential.helper= -c core.askPass= fetch origin 2>&1)"; then
    return 0
  fi
  printf 'FAILED:%s' "$(sanitize_git_err "${out//$'\n'/; }")"
  return 0
}

pull_one() {
  local name="$1"
  local rel="$2"
  local branch="$3"
  local dir
  dir="$(cd "${RUNTIME_DIR}/${rel}" && pwd)"

  append_repo_lines() {
    lines+=("### ${name} (\`${branch}\`)")
    while [[ $# -gt 0 ]]; do
      lines+=("$1")
      shift
    done
    lines+=("")
  }

  if ! git -C "${dir}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    append_repo_lines "- ⚠️ 跳过：不是 git 仓库"
    has_issues=1
    return
  fi

  if [[ -n "$(git -C "${dir}" status --porcelain)" ]]; then
    append_repo_lines \
      "- ⚠️ **未 pull**：工作区有未提交改动，已跳过以免覆盖" \
      "- 当前：\`$(git -C "${dir}" status -sb | head -1)\`"
    has_issues=1
    return
  fi

  local fetch_err
  fetch_err="$(git_fetch_with_repair "${dir}" "${branch}")"
  if [[ "${fetch_err}" == FAILED:* ]]; then
    local err_msg
    err_msg="$(sanitize_git_err "${fetch_err#FAILED:}")"
    if [[ "${err_msg}" == *"could not read Username"* ]]; then
      append_repo_lines "- ❌ fetch 失败：HTTP 远端无凭证（请改用 SSH 或配置 credential helper）"
    else
      append_repo_lines "- ❌ fetch 失败：\`${err_msg}\`"
    fi
    has_issues=1
    return
  fi

  if ! git -C "${dir}" checkout "${branch}" >/dev/null 2>&1; then
    if git -C "${dir}" show-ref --verify --quiet "refs/remotes/origin/${branch}"; then
      git -C "${dir}" checkout -B "${branch}" "origin/${branch}" >/dev/null 2>&1
    else
      append_repo_lines "- ❌ 无法切换到 \`${branch}\`（远端无 origin/${branch}）"
      has_issues=1
      return
    fi
  fi

  local old_head new_head behind count
  old_head="$(git -C "${dir}" rev-parse HEAD)"
  behind="$(git -C "${dir}" rev-list --count "HEAD..origin/${branch}" 2>/dev/null || echo 0)"

  local pull_out
  if pull_out="$(git -C "${dir}" pull --ff-only origin "${branch}" 2>&1)"; then
    :
  else
    local pull_lines=("- ❌ pull 失败：\`${pull_out//$'\n'/; }\`")
    if [[ "${behind}" -gt 0 ]]; then
      pull_lines+=("- （pull 前落后 **${behind}** 提交，列表如下）")
      while IFS= read -r line; do
        pull_lines+=("  - ${line}")
      done < <(git -C "${dir}" log --oneline "HEAD..origin/${branch}" | head -8)
    fi
    append_repo_lines "${pull_lines[@]}"
    has_issues=1
    return
  fi

  new_head="$(git -C "${dir}" rev-parse HEAD)"

  if [[ "${old_head}" != "${new_head}" ]]; then
    has_updates=1
    count="$(git -C "${dir}" rev-list --count "${old_head}..${new_head}")"
    local update_lines=("- 📥 **本次拉取了 ${count} 个新提交**（\`${old_head:0:8}\` → \`${new_head:0:8}\`）")
    while IFS= read -r line; do
      update_lines+=("  - ${line}")
    done < <(git -C "${dir}" log --oneline "${old_head}..${new_head}" | head -8)
    if [[ "${count}" -gt 8 ]]; then
      update_lines+=("  - …及其他 $((count - 8)) 条")
    fi
    append_repo_lines "${update_lines[@]}"
  elif [[ "${behind}" -gt 0 ]]; then
    append_repo_lines "- ⚠️ pull 完成但 HEAD 未变；pull 前落后 **${behind}** 提交（异常，请人工检查）"
    has_issues=1
  else
    up_to_date_count=$((up_to_date_count + 1))
  fi
}

for entry in "${REPOS[@]}"; do
  IFS='|' read -r name rel branch <<< "${entry}"
  pull_one "${name}" "${rel}" "${branch}"
done

if [[ "${has_updates}" -eq 1 ]]; then
  lines+=("---")
  lines+=("**小结**：有仓库拉取了新提交。")
elif [[ "${has_issues}" -eq 1 ]]; then
  lines+=("---")
  lines+=("**小结**：有仓库需要人工处理。")
else
  lines+=("---")
  lines+=("**小结**：全部 ${#REPOS[@]} 个仓库已是最新。")
fi

if [[ "${up_to_date_count}" -gt 0 && ( "${has_updates}" -eq 1 || "${has_issues}" -eq 1 ) ]]; then
  lines+=("")
  lines+=("其余 **${up_to_date_count}** 个仓库已是最新，未列出。")
fi

printf '%s\n' "${lines[@]}"

# 供调用方判断是否推送飞书：有更新或有问题则非 OK
if [[ "${has_updates}" -eq 1 || "${has_issues}" -eq 1 ]]; then
  exit 2
fi
exit 0
