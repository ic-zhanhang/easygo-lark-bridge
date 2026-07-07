#!/usr/bin/env bash
# 从 config/easygo.env 同步权限分级 → runtime/.cursor/rules/authorized-operator.mdc
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

# 聊天权限名单（兼容旧键名 ALLOWED_OPERATOR_*）
if [[ -n "${CHAT_OPERATOR_OPEN_IDS:-}" ]]; then
  IDS_RAW="${CHAT_OPERATOR_OPEN_IDS}"
  NAMES_RAW="${CHAT_OPERATOR_NAMES:-}"
elif [[ -n "${ALLOWED_OPERATOR_OPEN_IDS:-}" ]]; then
  IDS_RAW="${ALLOWED_OPERATOR_OPEN_IDS}"
  NAMES_RAW="${ALLOWED_OPERATOR_NAMES:-}"
elif [[ -n "${ALLOWED_OPERATOR_OPEN_ID:-}" ]]; then
  IDS_RAW="${ALLOWED_OPERATOR_OPEN_ID}"
  NAMES_RAW="${ALLOWED_OPERATOR_NAMES:-}"
else
  echo "错误: 请设置 CHAT_OPERATOR_OPEN_IDS 或 ALLOWED_OPERATOR_OPEN_IDS" >&2
  exit 1
fi

AUTHORIZER_OPEN_ID="${AUTHORIZER_OPEN_ID:-${ALLOWED_OPERATOR_OPEN_ID:-}}"
if [[ -z "${AUTHORIZER_OPEN_ID}" ]]; then
  AUTHORIZER_OPEN_ID="${IDS_RAW%%,*}"
fi
AUTHORIZER_NAME="${AUTHORIZER_NAME:-杨展航}"

python3 - "${TEMPLATE}" "${TARGET}" "${IDS_RAW}" "${NAMES_RAW}" "${AUTHORIZER_OPEN_ID}" "${AUTHORIZER_NAME}" <<'PY'
import sys
from pathlib import Path

template_path, target_path, ids_raw, names_raw, authorizer_id, authorizer_name = sys.argv[1:7]
ids = [x.strip() for x in ids_raw.split(",") if x.strip()]
names = [x.strip() for x in names_raw.split(",") if x.strip()] if names_raw else []

authorizer_id = authorizer_id.strip()
if authorizer_id not in ids:
    ids = [authorizer_id] + [x for x in ids if x != authorizer_id]

chat_lines = []
for i, oid in enumerate(ids):
    if oid == authorizer_id:
        continue
    label = names[i] if i < len(names) and names[i] else f"用户{i + 1}"
    chat_lines.append(f"- `{oid}` — {label}")

chat_block = "\n".join(chat_lines) if chat_lines else "（暂无）"
all_lines = []
for i, oid in enumerate(ids):
    label = names[i] if i < len(names) and names[i] else f"用户{i + 1}"
    suffix = "（授权人）" if oid == authorizer_id else "（仅聊天）"
    all_lines.append(f"- `{oid}` — {label}{suffix}")

text = Path(template_path).read_text()
replacements = {
    "{{AUTHORIZER_OPEN_ID}}": authorizer_id,
    "{{AUTHORIZER_NAME}}": authorizer_name,
    "{{AUTHORIZER_LABEL}}": authorizer_name,
    "{{AUTHORIZED_CHAT_OPERATORS_LIST}}": chat_block,
    "{{ALL_CHAT_OPERATORS_LIST}}": "\n".join(all_lines),
    "{{AUTHORIZED_OPERATORS_LIST}}": "\n".join(all_lines),
}

for key, val in replacements.items():
    if key in text:
        text = text.replace(key, val)

required = ("{{AUTHORIZER_OPEN_ID}}",)
if any(k in text for k in required):
    raise SystemExit(f"模板仍缺少占位符")

Path(target_path).parent.mkdir(parents=True, exist_ok=True)
Path(target_path).write_text(text)
print(f"已同步 → {target_path}")
print(f"  L1 授权人: {authorizer_id} — {authorizer_name}")
print(f"  L2 聊天权限: {len(ids)} 人（含授权人），额外 {len(chat_lines)} 人")
for line in chat_lines:
    print(f"    {line}")
PY
