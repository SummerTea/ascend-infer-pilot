#!/usr/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source /path/to/ascend-toolkit/set_env.sh
# source /path/to/custom_transformer/set_env.bash  # 若依赖 custom 包
source "$(conda info --base)/etc/profile.d/conda.sh"
conda activate hey

cd "${SCRIPT_DIR}"

DEVICE="${DEVICE:-0}"
CASE_JSON="${2:-${SCRIPT_DIR}/smoke_case.json}"
# export ATK_<OP>_CASE=smoke   # 可选：环境变量锚定 pytest 用例

atk node --backend pyaclnn --devices "${DEVICE}" -o "${SCRIPT_DIR}" \
  node --backend cpu \
  task -c "${CASE_JSON}" --task accuracy -p "${SCRIPT_DIR}" -s 0 -e 1 -cp
