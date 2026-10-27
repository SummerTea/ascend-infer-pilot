#!/usr/bin/env bash
# Run verify_bindgen.sh locally or inside a Docker container (generic wrapper).
set -eo pipefail

BINDGEN="${ATB_BINDGEN_PATH:-}"
DOCKER_NAME="${DOCKER_NAME:-}"
VERIFY_SCRIPT="${ATB_BINDGEN_VERIFY_SCRIPT:-verify_bindgen.sh}"

if [[ -z "$BINDGEN" || ! -d "$BINDGEN" ]]; then
  echo "[ERROR] ATB_BINDGEN_PATH 未设置或目录无效" >&2
  exit 1
fi

SCRIPT_PATH="${BINDGEN}/scripts/${VERIFY_SCRIPT}"
if [[ ! -f "$SCRIPT_PATH" ]]; then
  echo "[ERROR] verification script not found: $SCRIPT_PATH" >&2
  exit 1
fi

run_local() {
  bash "$SCRIPT_PATH"
}

if [[ -n "$DOCKER_NAME" ]]; then
  # Pass through common bindgen / ATB env vars into the container.
  docker exec "$DOCKER_NAME" env \
    ATB_REPO_PATH="${ATB_REPO_PATH:-}" \
    ATB_BINDGEN_PATH="${ATB_BINDGEN_PATH:-}" \
    CANN_PATH="${CANN_PATH:-}" \
    ASCEND_HOME_PATH="${ASCEND_HOME_PATH:-}" \
    ASCEND_RT_VISIBLE_DEVICES="${ASCEND_RT_VISIBLE_DEVICES:-}" \
    TORCH_VERSION="${TORCH_VERSION:-}" \
    CMAKE_BUILD_PARALLEL="${CMAKE_BUILD_PARALLEL:-}" \
    ATB_CXX_ABI_FLAG="${ATB_CXX_ABI_FLAG:-}" \
    SKIP_TORCH_ALIGN="${SKIP_TORCH_ALIGN:-}" \
    SKIP_NPU_FORWARD_TESTS="${SKIP_NPU_FORWARD_TESTS:-}" \
    ATB_BINDGEN_VERIFY_LOG="${ATB_BINDGEN_VERIFY_LOG:-}" \
    bash "$SCRIPT_PATH"
else
  run_local
fi
