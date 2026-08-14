---
description: Deployment contract for Qwen3.6-40B-Eleanor Q8_0 GGUF on dual RTX 5090 via llama.cpp.
---

# Qwen3.6-40B-Eleanor llama.cpp Deployment Contract

## Context

The project transitions from the archived vLLM/MXFP8 route to a llama.cpp GGUF
deployment. The model is a pre-built Q8_0 GGUF of Qwen3.6-40B-Eleanor (a Qwen3.5
hybrid SSM+Attention architecture) with MTP enabled. The runtime target is
llama.cpp on dual RTX 5090 with 128K context.

## Artifact Contract

| Field | Value |
|---|---|
| Runtime artifact | `/data/linux-fast/models/Qwen3.6-40B-Eleanor-GGUF/Qwen3.6-40B-FF6core-Deck-Eleanor-H-Uncen-NEO-MAX-MTP-Q8_0.gguf` |
| Size | `43,180,558,336` bytes (approximately 40.2 GiB) |
| Owner / mode | `root:build` / `0444` |
| Architecture | `qwen35` |
| File type | `7` (Q8_0) |
| Block count | `97` (96 transformer layers + 1 MTP layer) |
| Tensor count | `1290` |
| Native context length | `262144` (256K) |
| Embedding length | `5120` |
| Attention heads / KV heads | `24 / 4` |
| SSM state size / inner size | `128 / 6144` |
| SSM group count | `16` |
| MTP | `nextn_predict_layers: 1` (4 MTP tensors in `blk.96.nextn.*`) |
| Imatrix | embedded (181 chunks, 744 entries) |
| RoPE freq base | `10000000` |
| Full attention interval | `4` |

The artifact is the sole deployment model. It is read-only and must not be
overwritten, renamed, or deleted without explicit user authorization.

## Runtime Contract

`scripts/llama-server-first-boot.sh` is the canonical launcher. It must use:

```text
--load-mode dio
-dev CUDA0,CUDA1
-sm layer
--fit on
--fit-target 2048,2048
-no-kv-offload
-ctk f16 -ctv f16
-c 131072
-np 1
-b 512 -ub 128
-fa on
--host 127.0.0.1 --port 8000
```

Do not use `-ngl all`; it disables auto-fit and requests an impossible
per-device allocation for a 40 GiB model. Bind remains localhost-only unless
separately approved.

### OOM Ladder

If 128K context does not fit, follow this order:

1. Reduce `-b` / `-ub` (batch / micro-batch size)
2. Reduce `-c` to 65536
3. Only then consider limited CPU offload

Do not jump to context reduction before trying batch reduction.

## Hardware Constraints

- Dual RTX 5090: 2 x 32607 MiB VRAM (approximately 64 GiB total)
- System RAM: approximately 45 GiB
- The Q8_0 model weights are approximately 40 GiB, fitting within dual-GPU VRAM
  with approximately 24 GiB headroom for KV cache and compute
- KV cache for 128K context with F16: estimated 8-16 GiB across both GPUs
- F16 KV offload to system RAM (`--no-kv-offload` is the default, but the flag
  explicitly prevents unexpected offload behavior)

## Build Contract

The `llama.cpp` submodule (fork `furedericca-lab/llama.cpp`, commit `efb81ab`)
is the sole runtime binary source. It has native `qwen35` architecture support
(`src/models/qwen35.cpp`) including MTP/nextn layers and hybrid SSM+attention.

Build requirements:

```text
CMAKE_CUDA_ARCHITECTURES=120a  (RTX 5090 / Blackwell)
GGML_CUDA=ON
CMAKE_BUILD_TYPE=Release
```

The built binary is `llama.cpp/build/bin/llama-server`. It is not tracked by Git
(build directory is ignored). Rebuild after any submodule update.

## Acceptance Evidence

Required for Phase 3 completion:

- 128K dual-5090 startup without OOM
- `/health` returns OK
- `/v1/models` lists the model
- Raw completion probe (e.g. "The capital of France is")
- Chinese language probe
- JSON structured output probe
- Python code generation probe
- No Xid, BAD_PAGE, Oops, GPF, or unexplained SIGSEGV in the current boot

Required for Phase 4 (MTP):

- MTP-on vs MTP-off comparison with equivalent smoke probes
- MTP acceleration evidence (tok/s improvement) without quality degradation

## Verification

```bash
scripts/llama-server-first-boot.sh
curl -fsS http://127.0.0.1:8000/health
curl -fsS http://127.0.0.1:8000/v1/models
```

Before startup, require idle GPUs, sufficient RAM, and a clean current-boot
kernel/Xid journal:

```bash
uname -r
cat /proc/sys/kernel/tainted
journalctl -k -b --no-pager | grep -iE 'BAD_PAGE|Oops|general protection|Xid'
```

## Escalation Triggers

- Artifact identity, size, mode, or tensor metadata differs from the contract.
- Any current-boot Xid, BAD_PAGE, Oops, GPF, or unexplained process SIGSEGV.
- Health/API failure, repeated-symbol output, invalid structured output, or
  long-prefill decode collapse.
- A request to change context, offload, KV, bind address, or deployment model.
- 128K context does not fit even after batch reduction.

## Requirement Boundary Notes

- The pre-built Q8_0 GGUF is the accepted artifact; no GGUF conversion or
  requantization is planned.
- The archived vLLM scope is historical only; it does not constrain this scope.
- MTP is enabled by default per user requirement; disabling it is only for
  Phase 4 comparison, not a runtime change.
