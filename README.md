# Qwen3.6-40B-Eleanor llama.cpp Dual-5090 Deployment

This repository deploys the Qwen3.6-40B-Eleanor model on dual RTX 5090 GPUs
using llama.cpp with a pre-built Q8_0 GGUF, 128K context, and MTP enabled.

**Deployment complete** — all 4 phases finished. Three profiles:
agent (default, n=3/p=0, temp=0.6, 73.76 tok/s, reasoning-preserve), general
(n=3/p=0, temp=0.7, 75.02 tok/s, reasoning-preserve), long (256K Q8_0 KV,
~44 tok/s short decode, retrieval up to ~172K tokens). The deployment scope is
archived under `.scopes/archive/qwen36-40b-eleanor-llamacpp/`. Profile
optimization scope is at `.scopes/qwen36-40b-profile-optimization/`.

The previous vLLM/MXFP8 deployment route is archived under
`.scopes/archive/qwen3.6-40b-eleanor-deployment/`. It is a historical record
only.

## Current Status

| Phase | Status | Description |
|---|---|---|
| 1. Build and preflight | Complete | llama.cpp compiled with CUDA sm_120a; GGUF metadata verified |
| 2. First-boot 128K startup | Complete | 128K startup OK, GPU0=26144 MiB, GPU1=28896 MiB, MTP 90-96% acceptance |
| 3. Behavior probes | Complete | Math, Chinese, JSON, Python, summary probes all pass |
| 4. MTP comparison | Complete | Agent: n=3/p=0, 73.76 tok/s; General: n=3/p=0, 75.02 tok/s |

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
repository gitlink at merge commit `94e82e8ae` (fork `efb81ab` + upstream
`885c5bb`, 42 upstream commits including speculative/MTP improvements). Do not
update it independently without also validating and committing the new parent
pin.

## Build llama.cpp

The submodule has native `qwen35` architecture support and includes 42 upstream
commits merged on top of the fork's DIO and DeepSeek V4 patches. Build with
CUDA for RTX 5090 (Blackwell, sm_120a):

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

The script uses profile-based configuration via the `PROFILE` environment
variable. The default is `agent` (MTP n=3/p=0, temp=0.6, reasoning-preserve).
Other profiles: `general` (n=3/p=0, temp=0.7, reasoning-preserve),
`long` (256K Q8_0 KV, retrieval up to ~172K tokens). Creative work does not
get a separate profile — use per-request sampler overrides. The script uses
direct I/O (`--load-mode dio`), automatic two-GPU layer fitting with
asymmetric margin (`--fit on --fit-target 2048,4096`), F16 KV cache, 128K
context (`-c 131072`), single slot, flash attention, batch 1024/ubatch 256,
MTP enabled, and reasoning-preserve for agent/general. It listens on
`127.0.0.1:8000` only.

Do not use `-ngl all` for this 40 GiB model: it disables fitting and attempts
an impossible per-GPU allocation. The equivalent explicit runtime profile is:

```bash
llama-server \
  -m /data/linux-fast/models/Qwen3.6-40B-Eleanor-GGUF/Qwen3.6-40B-FF6core-Deck-Eleanor-H-Uncen-NEO-MAX-MTP-Q8_0.gguf \
  --load-mode dio \
  -dev CUDA0,CUDA1 \
  -sm layer \
  --fit on \
  --fit-target 2048,4096 \
  -ctk f16 \
  -ctv f16 \
  -c 131072 \
  -np 1 \
  -b 1024 \
  -ub 256 \
  -fa on \
  --spec-type draft-mtp \
  --spec-draft-n-max 3 \
  --spec-draft-n-min 0 \
  --spec-draft-p-min 0 \
  --reasoning auto \
  --reasoning-format deepseek \
  --reasoning-preserve \
  --temp 0.6 \
  --top-p 0.95 \
  --top-k 20 \
  --min-p 0 \
  --repeat-penalty 1.0 \
  --host 127.0.0.1 \
  --port 8000
```

Do not use `--no-kv-offload` — in llama.cpp, KV offload to GPU is the
default; `--no-kv-offload` would force KV onto CPU/RAM.

### OOM Ladder

If 128K context does not fit:

1. Reduce micro-batch: `-ub 128` then `-ub 64`
2. Relax `--fit-target` (increase 4096 → 5120 per GPU) to offload weights to CPU
3. Switch KV to Q8_0: `-ctk q8_0 -ctv q8_0` (preserves 128K context)
4. Reduce context: `-c 65536`
5. Only then consider limited CPU offload

For the long profile (256K Q8_0 KV), the OOM ladder is:
1. Reduce micro-batch: `-ub 128`
2. Relax `--fit-target` per GPU
3. Reduce context: `-c 196608` or `-c 131072`

Reducing fit-target (e.g. 2048 → 1536) is NOT an OOM recovery step — it asks
the fitter to use MORE VRAM (less margin), which is the opposite of relief.

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

- Archived deployment scope: `.scopes/archive/qwen36-40b-eleanor-llamacpp/`
- Profile optimization scope: `.scopes/qwen36-40b-profile-optimization/`
- Archived vLLM/MXFP8 scope: `.scopes/archive/qwen3.6-40b-eleanor-deployment/`
- Durable project knowledge: `.wiki/`
- Operator and safety rules: `AGENTS.md`
- Canonical launcher: `scripts/llama-server-first-boot.sh`
