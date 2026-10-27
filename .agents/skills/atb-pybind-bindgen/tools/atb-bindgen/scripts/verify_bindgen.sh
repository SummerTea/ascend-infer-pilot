#!/usr/bin/env bash
# End-to-end ATB pybind bindgen verification (consistency → build → install → unittest).
# Run inside NPU-capable environment (bare metal or Docker). Configure via env vars below.
set -eo pipefail
set +u

ATB_REPO="${ATB_REPO_PATH:-}"
BINDGEN="${ATB_BINDGEN_PATH:-}"
CANN_ROOT="${CANN_PATH:-${ASCEND_HOME_PATH:-/usr/local/Ascend/ascend-toolkit}}"
CANN_SET_ENV="${CANN_SET_ENV:-${CANN_ROOT}/set_env.sh}"
LOG="${ATB_BINDGEN_VERIFY_LOG:-/tmp/atb_bindgen_verify.log}"
TORCH_VERSION="${TORCH_VERSION:-2.10.0}"
BUILD_PARALLEL="${CMAKE_BUILD_PARALLEL:-1}"
NPU_DEVICE="${ASCEND_RT_VISIBLE_DEVICES:-2}"
ATB_CXX_ABI_FLAG="${ATB_CXX_ABI_FLAG:---cxx_abi=1}"

if [[ -z "$ATB_REPO" || ! -d "$ATB_REPO" ]]; then
  echo "[ERROR] ATB_REPO_PATH 未设置或目录无效" >&2
  exit 1
fi
if [[ -z "$BINDGEN" || ! -d "$BINDGEN" ]]; then
  echo "[ERROR] ATB_BINDGEN_PATH 未设置或目录无效" >&2
  exit 1
fi

: >"$LOG"
step() { echo "$@" | tee -a "$LOG"; }
fail() { echo "[FAIL] $*" | tee -a "$LOG" >&2; exit 1; }

step "========== ATB bindgen verification =========="
step "ATB_REPO=$ATB_REPO BINDGEN=$BINDGEN $(date)"

# --- 1. CANN + driver ---
if [[ ! -f "$CANN_SET_ENV" ]]; then
  CANN_SET_ENV="/usr/local/Ascend/ascend-toolkit/set_env.sh"
fi
if [[ ! -f "$CANN_SET_ENV" ]]; then
  fail "CANN set_env.sh not found (set CANN_PATH or ASCEND_HOME_PATH)"
fi
# shellcheck disable=SC1090
source "$CANN_SET_ENV"
export LD_LIBRARY_PATH="/usr/local/Ascend/driver/lib64/common:/usr/local/Ascend/driver/lib64/driver:${LD_LIBRARY_PATH:-}"

step "[STEP 1] npu-smi"
if command -v npu-smi >/dev/null 2>&1; then
  npu-smi info 2>&1 | sed -n '1,14p' | tee -a "$LOG"
else
  step "[WARN] npu-smi not found, skip device listing"
fi

# --- 2. Align torch / torch_npu (optional skip) ---
if [[ "${SKIP_TORCH_ALIGN:-0}" != "1" ]]; then
  step "[STEP 2] Align torch/torch_npu (target ${TORCH_VERSION})"
  pip install -q "torch-npu==${TORCH_VERSION}" "torch==${TORCH_VERSION}" 2>&1 | tail -3 | tee -a "$LOG"
else
  step "[STEP 2] SKIP_TORCH_ALIGN=1, skip torch align"
fi
python3 -c "
import torch, torch_npu
torch.npu.set_device(0)
print('torch', torch.__version__, 'torch_npu', torch_npu.__version__)
print('npu_available', torch.npu.is_available(), 'device_count', torch.npu.device_count())
" 2>&1 | tee -a "$LOG"

# --- 3. Consistency check ---
step "[STEP 3] validate_consistency.py"
cd "$BINDGEN"
python3 validate_consistency.py --repo "$ATB_REPO" 2>&1 | tee -a "$LOG"

if [[ ! -f "${ATB_REPO}/output/atb/set_env.sh" ]]; then
  fail "missing ${ATB_REPO}/output/atb/set_env.sh — build testframework first or set ATB_REPO_PATH to a compiled tree"
fi

# --- 4. Build torch_atb ---
step "[STEP 4] Build torch_atb (parallel=${BUILD_PARALLEL})"
cd "$ATB_REPO"
# shellcheck disable=SC1091
source output/atb/set_env.sh ${ATB_CXX_ABI_FLAG}

export PYTHON_INCLUDE_PATH="$(python3 -c 'from sysconfig import get_paths; print(get_paths()["include"])')"
export PYTORCH_INSTALL_PATH="$(python3 -c 'import torch, os; print(os.path.dirname(os.path.abspath(torch.__file__)))')"
export PYTORCH_NPU_INSTALL_PATH="$(python3 -c 'import torch_npu, os; print(os.path.dirname(os.path.abspath(torch_npu.__file__)))')"
export LD_LIBRARY_PATH="${PYTORCH_INSTALL_PATH}/../torch.libs:${LD_LIBRARY_PATH:-}"

TORCH_BUILD_DIR="${ATB_REPO}/build/src/torch_atb"
rm -rf "${TORCH_BUILD_DIR}"
mkdir -p "${TORCH_BUILD_DIR}"

cmake -S "${ATB_REPO}/src/torch_atb" -B "${TORCH_BUILD_DIR}" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=OFF 2>&1 | tee -a "$LOG"
cmake --build "${TORCH_BUILD_DIR}" --parallel "${BUILD_PARALLEL}" 2>&1 | tee -a "$LOG"
cmake --install "${TORCH_BUILD_DIR}" 2>&1 | tee -a "$LOG"

step "[STEP 4b] Pack whl"
cd "${ATB_REPO}/output"
mkdir -p whl
cp -rf "${ATB_REPO}/pyproject.toml" .
mkdir -p ./torch_atb
cp -rf "${ATB_REPO}/torch_atb/"* ./torch_atb/
cp -rf ./atb/cxx_abi_1/* ./torch_atb/
pip wheel --no-deps --no-build-isolation --wheel-dir ./whl . 2>&1 | tail -8 | tee -a "$LOG"
for whl in ./whl/*py3*.whl; do
  [[ -f "$whl" ]] || continue
  py_tag="$(python3 -c 'import sys; print(f"cp{sys.version_info.major}{sys.version_info.minor}")')"
  new="${whl/py3/${py_tag}}"
  mv "$whl" "$new"
  step "WHL: $new"
done
rm -rf ./torch_atb ./torch_atb.egg-info ./pyproject.toml ./build 2>/dev/null || true

WHL=$(ls -1 "${ATB_REPO}/output/whl/"torch_atb-*.whl 2>/dev/null | head -1)
if [[ -z "$WHL" ]]; then
  fail "no torch_atb whl under ${ATB_REPO}/output/whl/"
fi
step "[STEP 5] Install $WHL"
pip install --force-reinstall "$WHL" 2>&1 | tail -5 | tee -a "$LOG"

step "[STEP 6] import torch_atb"
# shellcheck disable=SC1091
source "${ATB_REPO}/output/atb/set_env.sh" ${ATB_CXX_ABI_FLAG}
export LD_LIBRARY_PATH="${PYTORCH_INSTALL_PATH}/../torch.libs:${LD_LIBRARY_PATH:-}"
python3 -c "
import torch_atb
p = torch_atb.SplitParam()
p.split_dim = 0
p.split_num = 2
print('SplitParam OK', p)
op = torch_atb.Operation(p)
print('Operation OK', op)
" 2>&1 | tee -a "$LOG"

step "[STEP 7] op_param_test TestGeneratedParams"
cd "${ATB_REPO}/tests/apitest"
PARAM_LOG="/tmp/bindgen_param_unittest.log"
python3 -m unittest torch_atb_test.op_test.op_param_test.TestGeneratedParams -v 2>&1 | tee "$PARAM_LOG" | tee -a "$LOG" | tail -15
grep -q "^OK$" "$PARAM_LOG" || fail "TestGeneratedParams failed (see $PARAM_LOG)"

if [[ "${SKIP_NPU_FORWARD_TESTS:-0}" == "1" ]]; then
  step "[STEP 8] SKIP_NPU_FORWARD_TESTS=1, skip bindgen forward golden"
else
  step "[STEP 8] bindgen forward golden tests (NPU device ${NPU_DEVICE})"
  export ASCEND_RT_VISIBLE_DEVICES="${NPU_DEVICE}"
  BINDGEN_LOG="/tmp/bindgen_unittest.log"
  python3 -m unittest discover -s torch_atb_test/op_test -p "*_bindgen_test.py" -v 2>&1 | tee "$BINDGEN_LOG" | tee -a "$LOG" | tail -30
  if ! grep -q "^OK$" "$BINDGEN_LOG"; then
    fail "bindgen forward tests failed (see $BINDGEN_LOG)"
  fi
  step "========== SUMMARY =========="
  grep -E "^(OK|FAIL|ERROR|Ran |FAILED)" "$BINDGEN_LOG" | tail -15 | tee -a "$LOG"
fi

step "Full log: $LOG"
step "========== PASS =========="
