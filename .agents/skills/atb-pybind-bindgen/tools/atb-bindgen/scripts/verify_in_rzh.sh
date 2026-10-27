#!/usr/bin/env bash
# Deprecated: use run_verify.sh + DOCKER_NAME, or verify_bindgen.sh directly.
set -eo pipefail
echo "[DEPRECATED] verify_in_rzh.sh — use scripts/run_verify.sh or scripts/verify_bindgen.sh" >&2
echo "[DEPRECATED] Set DOCKER_NAME explicitly if you need a container wrapper." >&2
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${SCRIPT_DIR}/run_verify.sh"
