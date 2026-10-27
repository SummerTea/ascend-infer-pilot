#!/usr/bin/bash
# 从 atk_output 最新任务目录提取 Pass/Fail、签名校验、run opp 错误
set -euo pipefail

ST_DIR="${1:-.}"
LOG=$(find "${ST_DIR}/atk_output" -name 'atk.log' 2>/dev/null | sort | tail -1)

if [[ -z "${LOG}" ]]; then
  echo "No atk.log under ${ST_DIR}/atk_output"
  exit 1
fi

echo "=== log: ${LOG} ==="
rg -n "精度是否达标|acc_pass_result|类型校验|run opp failed|ERROR.*case|Failed|Pass" "${LOG}" | tail -40 || true

echo ""
echo "=== summary table (last) ==="
rg "^\| cpu_0 \|" "${LOG}" | tail -3 || true
