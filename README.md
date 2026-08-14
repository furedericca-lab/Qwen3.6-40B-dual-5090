# Qwen3.6-40B-Eleanor llama.cpp Dual-5090 Deployment

This repository deploys the Qwen3.6-40B-Eleanor model on dual RTX 5090 GPUs
using llama.cpp with a pre-built Q8_0 GGUF, 128K context, and MTP enabled.

The previous vLLM/MXFP8 deployment route is archived under
`.scopes/archive/qwen3.6-40b-eleanor-deployment/`. It is a historical record
only.

## Current Status

| Phase | Status | Description |
|---|---|---|
| 1. Build and preflight | In Progress | llama.cpp compiled with CUDA sm_120a; GGUF metadata verified |
| 2. First-boot 128K startup | Not Started | `llama-server` loads at 128K context on dual 5090 |
| 3. Behavior probes | Not Started | Raw, chat, Chinese, JSON, Python, and long-prefill probes |
| 4. MTP comparison | Not Started | MTP-on vs MTP-off throughput and quality comparison |

## Deployment Artifact

The sole deployment model is a pre-built Q8_0 GGUF:

```text
/data/linux-fast/models/Qwen3.6-40B-Eleanor-GGUF/Qwen3.6-40B-FF6core-Deck-Eleanor-H-Uncen-NEO-MAX-MTP-Q8_0.gguf
```

It is `43,180,558,336` bytes (approximately 40.2 GiB), read-only. Its GGUF
metadata reports `qwen35` architecture, 97 blocks (96 transformer + 1 MTP
layer), Q8_0 quantization, `nextn_predict_layers: 1`, 1290 tensors, and an
embedded imatrix (181 chunks). The native context length is 262144 (256K).

## Checkout

Clone with submodules:

```bash
git clone --recurse-submodules <repo-url>
cd Qwen3.6-40B-dual-5090
```

For an existing checkout:

```bash
git submodule sync --recursive
git submodule update --init --recursive
```

`llama.cpp` tracks the project fork at
`https://github.com/furedericca-lab/llama.cpp.git` and is pinned by the parent
repository gitlink at commit `efb81ab`. Do not update it independently without
also validating and committing the new parent pin.

## Build llama.cpp

The pinned fork has native `qwen35` architecture support. Build with CUDA for
RTX 5090 (Blackwell, sm_120a):

```bash
cd llama.cpp
cmake -S . -B build -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DGGML_CUDA=ON \
  -DCMAKE_CUDA_ARCHITECTURES=120a \
  -DLLAMA_CURL=OFF
cmake --build build --target llama-server -j$(nproc)
```

Verify the build:

```bash
./build/bin/llama-server --version
./build/bin/llama-server --list-devices
```

Both RTX 5090 GPUs should appear as CUDA0 and CUDA1.

## Dual-5090 Runtime Baseline

After the binary is built and the GGUF artifact is verified, start the
localhost-only runtime:

```bash
scripts/llama-server-first-boot.sh
```

The script uses direct I/O (`--load-mode dio`), automatic two-GPU layer
fitting with a 2 GiB margin per GPU (`--fit on --fit-target 2048,2048`), F16 KV
cache, 128K context (`-c 131072`), single slot, flash attention, and MTP
enabled. It listens on `127.0.0.1:8000` only.

Do not use `-ngl all` for this 40 GiB model: it disables fitting and attempts
an impossible per-GPU allocation. The equivalent explicit runtime profile is:

```bash
llama-server \
  -m /data/linux-fast/models/Qwen3.6-40B-Eleanor-GGUF/Qwen3.6-40B-FF6core-Deck-Eleanor-H-Uncen-NEO-MAX-MTP-Q8_0.gguf \
  --load-mode dio \
  -dev CUDA0,CUDA1 \
  -sm layer \
  --fit on \
  --fit-target 2048,2048 \
  --no-kv-offload \
  -ctk f16 \
  -ctv f16 \
  -c 131072 \
  -np 1 \
  -b 512 \
  -ub 128 \
  -fa on \
  --host 127.0.0.1 \
  --port 8000
```

### OOM Ladder

If 128K context does not fit:

1. Reduce batch: `-b 256 -ub 64`
2. Reduce context: `-c 65536`
3. Only then consider limited CPU offload

## Verification

```bash
# Health check
curl -fsS http://127.0.0.1:8000/health

# Model listing
curl -fsS http://127.0.0.1:8000/v1/models

# Raw completion
curl -fsS http://127.0.0.1:8000/v1/completions \
  -H 'Content-Type: application/json' \
  -d '{"prompt": "The capital of France is", "max_tokens": 10, "temperature": 0}'
```

Before startup, verify a clean boot:

```bash
uname -r
cat /proc/sys/kernel/tainted
journalctl -k -b --no-pager | grep -iE 'BAD_PAGE|Oops|general protection|Xid'
nvidia-smi
free -h
```

## Project Sources

- Active deployment scope: `.scopes/qwen36-40b-eleanor-llamacpp/`
- Archived vLLM/MXFP8 scope: `.scopes/archive/qwen3.6-40b-eleanor-deployment/`
- Durable project knowledge: `.wiki/`
- Operator and safety rules: `AGENTS.md`
- Canonical launcher: `scripts/llama-server-first-boot.sh`
