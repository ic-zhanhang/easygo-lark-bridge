#!/usr/bin/env bash
# Linux 秧秧 — 等价于 BRIDGE_PROFILE=linux install.sh
set -euo pipefail
PACK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export BRIDGE_PROFILE=linux
exec bash "${PACK_ROOT}/scripts/install.sh" "$@"
