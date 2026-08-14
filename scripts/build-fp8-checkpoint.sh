#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$repo_root/config/quantize.env"

if [[ ! -x "$repo_root/.quantize-venv/bin/python" ]]; then
  printf 'quantizer is not installed; run scripts/bootstrap-quantizer.sh first\n' >&2
  exit 1
fi

MODEL_DIR="$SOURCE_MODEL_DIR" "$repo_root/scripts/check-model.py"
"$repo_root/scripts/validate-quantize-config.py"
export SOURCE_MODEL_DIR FP8_MODEL_DIR FP8_STAGE_PREFIX FP8_SCHEME MAX_WORKERS CUDA_DEVICES IGNORE_MODULES_JSON
export VLLM_DIR="$repo_root/vllm"
export LLM_COMPRESSOR_DIR="$repo_root/llm-compressor"
export COMPRESSED_TENSORS_DIR="$repo_root/compressed-tensors"
export CUDA_VISIBLE_DEVICES="$CUDA_DEVICES"
exec "$repo_root/.quantize-venv/bin/python" "$repo_root/scripts/build-fp8-checkpoint.py"
