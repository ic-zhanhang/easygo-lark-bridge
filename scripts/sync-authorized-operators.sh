#!/usr/bin/env bash
# 从 config/easygo.env 同步授权名单到 runtime/.cursor/rules/authorized-operator.mdc
set -euo pipefail

PACK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="${PACK_ROOT}/config/easygo.env"

if [[ -f "${CONFIG_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${CONFIG_FILE}" 2>/dev/null || true
fi

PROFILE="${BRIDGE_PROFILE:-mac}"
if [[ -n "${RUNTIME_TEMPLATE:-}" ]]; then
  TEMPLATE_ROOT="${RUNTIME_TEMPLATE}"
elif [[ -d "${PACK_ROOT}/templates/runtime-${PROFILE}" ]]; then
  TEMPLATE_ROOT="${PACK_ROOT}/templates/runtime-${PROFILE}"
elif [[ -d "${PACK_ROOT}/templates/runtime" ]]; then
  TEMPLATE_ROOT="${PACK_ROOT}/templates/runtime"
else
  TEMPLATE_ROOT="${PACK_ROOT}/templates/runtime-mac"
fi

TEMPLATE="${TEMPLATE_ROOT}/.cursor/rules/authorized-operator.mdc"
TARGET="${RUNTIME_DIR:-${PACK_ROOT}/runtime}/.cursor/rules/authorized-operator.mdc"

if [[ ! -f "${CONFIG_FILE}" ]]; then
  echo "错误: 未找到 ${CONFIG_FILE}" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "${CONFIG_FILE}"

if [[ -n "${ALLOWED_OPERATOR_OPEN_IDS:-}" ]]; then
  IDS_RAW="${ALLOWED_OPERATOR_OPEN_IDS}"
elif [[ -n "${ALLOWED_OPERATOR_OPEN_ID:-}" ]]; then
  IDS_RAW="${ALLOWED_OPERATOR_OPEN_ID}"
else
  echo "错误: 请在 easygo.env 设置 ALLOWED_OPERATOR_OPEN_IDS（逗号分隔）" >&2
  exit 1
fi

NAMES_RAW="${ALLOWED_OPERATOR_NAMES:-}"

python3 - "${TEMPLATE}" "${TARGET}" "${IDS_RAW}" "${NAMES_RAW}" <<'PY'
import sys
from pathlib import Path

template_path, target_path, ids_raw, names_raw = sys.argv[1:5]
ids = [x.strip() for x in ids_raw.split(",") if x.strip()]
names = [x.strip() for x in names_raw.split(",") if x.strip()] if names_raw else []

lines = []
for i, oid in enumerate(ids):
    label = names[i] if i < len(names) and names[i] else f"操作者{i + 1}"
    lines.append(f"- `{oid}` — {label}")

if not lines:
    raise SystemExit("授权 open_id 列表为空")

block = "\n".join(lines)
text = Path(template_path).read_text()
if "{{AUTHORIZED_OPERATORS_LIST}}" not in text:
    raise SystemExit("模板缺少 {{AUTHORIZED_OPERATORS_LIST}} 占位符")

out = text.replace("{{AUTHORIZED_OPERATORS_LIST}}", block)
Path(target_path).parent.mkdir(parents=True, exist_ok=True)
Path(target_path).write_text(out)
print(f"已同步 {len(ids)} 位授权操作者 → {target_path}")
for line in lines:
    print(f"  {line}")
PY
