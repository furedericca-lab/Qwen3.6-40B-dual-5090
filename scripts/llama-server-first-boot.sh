#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
server="$repo_root/llama.cpp/build/bin/llama-server"
model=/data/linux-fast/models/Qwen3.6-40B-Eleanor-GGUF/Qwen3.6-40B-FF6core-Deck-Eleanor-H-Uncen-NEO-MAX-MTP-Q8_0.gguf

if [[ ! -x "$server" ]]; then
  printf 'llama-server is not built: %s\n' "$server" >&2
  printf 'Build it with: cd llama.cpp && cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DGGML_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES=120a && cmake --build build --target llama-server\n' >&2
  exit 1
fi

if [[ ! -f "$model" ]]; then
  printf 'runtime model is not available: %s\n' "$model" >&2
  exit 1
fi

# Profile selection: agent (default), general, long
PROFILE="${PROFILE:-agent}"

# Common baseline (immutable hardware/runtime params)
common_args=(
  -m "$model"
  --load-mode dio
  -dev CUDA0,CUDA1
  -sm layer
  --fit on
  --fit-target 2048,4096
  -ctk f16 -ctv f16
  -c 131072
  -np 1
  -b 1024
  -ub 256
  -fa on
  --host 127.0.0.1
  --port 8000
)

# Per-profile overrides
spec_args=()
sampling_args=()
context_args=()

case "$PROFILE" in
  agent)
    # Primary profile: MTP n=3/p=0, reasoning-preserve, coding/agent sampling
    # Validated: 73.76 tok/s decode, 2042 tok/s prefill at 66K, J/token=8.46
    MTP_N_MAX=${MTP_N_MAX:-3}
    MTP_P_MIN=${MTP_P_MIN:-0}
    spec_args=(
      --spec-type draft-mtp
      --spec-draft-n-max "$MTP_N_MAX"
      --spec-draft-n-min 0
      --spec-draft-p-min "$MTP_P_MIN"
    )
    sampling_args=(
      --temp 0.6
      --top-p 0.95
      --top-k 20
      --min-p 0
      --repeat-penalty 1.0
    )
    reasoning_args=(
      --reasoning auto
      --reasoning-format deepseek
      --reasoning-preserve
    )
    ;;
  general)
    # General profile: MTP n=3/p=0, chat/analysis sampling
    MTP_N_MAX=${MTP_N_MAX:-3}
    MTP_P_MIN=${MTP_P_MIN:-0}
    spec_args=(
      --spec-type draft-mtp
      --spec-draft-n-max "$MTP_N_MAX"
      --spec-draft-n-min 0
      --spec-draft-p-min "$MTP_P_MIN"
    )
    sampling_args=(
      --temp 0.7
      --top-p 0.95
      --top-k 20
      --min-p 0
      --repeat-penalty 1.0
    )
    reasoning_args=(
      --reasoning auto
      --reasoning-format deepseek
      --reasoning-preserve
    )
    ;;
  long)
    # Long-context profile: 256K context with Q8_0 KV
    # Retrieval validated up to ~172K tokens; decode -52% vs 128K at short prompts
    context_args=(
      -c 262144
      -ctk q8_0
      -ctv q8_0
    )
    MTP_N_MAX=${MTP_N_MAX:-3}
    MTP_P_MIN=${MTP_P_MIN:-0}
    spec_args=(
      --spec-type draft-mtp
      --spec-draft-n-max "$MTP_N_MAX"
      --spec-draft-n-min 0
      --spec-draft-p-min "$MTP_P_MIN"
    )
    sampling_args=(
      --temp 0.6
      --top-p 0.95
      --top-k 20
      --min-p 0
      --repeat-penalty 1.0
    )
    reasoning_args=()
    ;;
  *)
    echo "PROFILE must be agent, general, or long, got: $PROFILE" >&2
    exit 2
    ;;
esac

# MTP_MODE override: if set to off, remove all speculative args regardless of profile
MTP_MODE=${MTP_MODE:-on}
if [[ "$MTP_MODE" == "off" ]]; then
  spec_args=()
fi

exec "$server" \
  "${common_args[@]}" \
  "${context_args[@]}" \
  "${spec_args[@]}" \
  "${sampling_args[@]}" \
  "${reasoning_args[@]}" \
  "$@"
