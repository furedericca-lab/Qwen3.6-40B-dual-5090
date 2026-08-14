#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$repo_root/config/runtime.env"

CUDA_HOME=${CUDA_HOME:-/usr/local/cuda-13.3}
export CUDA_HOME
export PATH="$CUDA_HOME/bin:$PATH"

if [[ ! -x "$repo_root/.venv/bin/vllm" ]]; then
  printf 'vLLM is not installed in %s; run scripts/bootstrap-vllm.sh first\n' "$repo_root/.venv" >&2
  exit 1
fi

MODEL_DIR="$MODEL_DIR" "$repo_root/.venv/bin/python" "$repo_root/scripts/verify-fp8-checkpoint.py"
"$repo_root/scripts/validate-runtime-config.py"

gpu_count=$(nvidia-smi --query-gpu=index --format=csv,noheader | wc -l)
if [[ "$gpu_count" -ne "$TENSOR_PARALLEL_SIZE" ]]; then
  printf 'expected %s visible GPUs, found %s\n' "$TENSOR_PARALLEL_SIZE" "$gpu_count" >&2
  exit 1
fi

mkdir -p "$repo_root/logs"
exec "$repo_root/.venv/bin/vllm" serve "$MODEL_DIR" \
  --served-model-name "$SERVED_MODEL_NAME" \
  --host "$HOST" \
  --port "$PORT" \
  --tensor-parallel-size "$TENSOR_PARALLEL_SIZE" \
  --gpu-memory-utilization "$GPU_MEMORY_UTILIZATION" \
  --dtype "$DTYPE" \
  --kv-cache-dtype "$KV_CACHE_DTYPE" \
  --language-model-only \
  --max-model-len "$MAX_MODEL_LEN" \
  --max-num-seqs "$MAX_NUM_SEQS" \
  --max-num-batched-tokens "$MAX_NUM_BATCHED_TOKENS" \
  --enable-chunked-prefill \
  --max-parallel-loading-workers "$MAX_PARALLEL_LOADING_WORKERS" \
  --reasoning-parser "$REASONING_PARSER" \
  --enable-auto-tool-choice \
  --tool-call-parser "$TOOL_CALL_PARSER" \
  "$@"
