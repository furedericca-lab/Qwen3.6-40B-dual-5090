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

exec "$server" \
  -m "$model" \
  --load-mode dio \
  -dev CUDA0,CUDA1 \
  -sm layer \
  --fit on \
  --fit-target 2048,2048 \
  -ctk f16 \
  -ctv f16 \
  -c 131072 \
  -np 1 \
  -b 512 \
  -ub 128 \
  -fa on \
  --spec-type draft-mtp \
  --spec-draft-n-max 2 \
  --spec-draft-n-min 0 \
  --spec-draft-p-min 0.75 \
  --temp 0.6 \
  --top-p 0.95 \
  --top-k 20 \
  --min-p 0 \
  --repeat-penalty 1.0 \
  --host 127.0.0.1 \
  --port 8000 \
  "$@"
