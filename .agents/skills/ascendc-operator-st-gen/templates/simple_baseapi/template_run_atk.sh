#!/usr/bin/bash
# 模板：ATK ST 启动脚本 — 替换环境路径与 CASE_JSON
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# TODO: 按环境修改
source /path/to/ascend-toolkit/set_env.sh
source "$(conda info --base)/etc/profile.d/conda.sh"
conda activate hey

cd "${SCRIPT_DIR}"

CMD="${1:-task}"
DEVICE="${DEVICE:-0}"
CASE_JSON="${2:-${SCRIPT_DIR}/smoke_case.json}"

case "${CMD}" in
  case)
    atk case -f aclnn_{{OP_SNAKE}}.yaml -p "${SCRIPT_DIR}" -s 1234
    ;;
  task)
    atk node --backend pyaclnn --devices "${DEVICE}" -o "${SCRIPT_DIR}" \
      node --backend cpu \
      task -c "${CASE_JSON}" --task accuracy -p "${SCRIPT_DIR}" -s 0 -e 1 -cp
    ;;
  *)
    echo "Usage: $0 {case|task [json]}"
    exit 1
    ;;
esac
