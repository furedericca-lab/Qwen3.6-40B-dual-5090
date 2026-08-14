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
| Attention heads / KV heads | `24 / 4` (GQA 6:1) |
| Head dimension | `256` (derived from `attn_k.weight` shape `5120x1024`) |
| SSM state size / inner size | `128 / 6144` |
| SSM group count | `16` |
| Dense attention layers | `24` (backbone at indices 3,7,11,...,95, every 4 layers) |
| SSM/linear attention layers | `72` (use recurrent state, no KV cache) |
| MTP draft KV | `1` additional layer (blk.96.nextn), ~0.5 GiB at 128K F16 |
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
-ctk f16 -ctv f16
-c 131072
-np 1
-b 512 -ub 128
-fa on
--spec-type draft-mtp
--spec-draft-n-max 2
--spec-draft-n-min 0
--spec-draft-p-min 0.75
--temp 0.6
--top-p 0.95
--top-k 20
--min-p 0
--repeat-penalty 1.0
--host 127.0.0.1 --port 8000
```

Do not use `-ngl all`; it disables auto-fit and requests an impossible
per-device allocation for a 40 GiB model. Bind remains localhost-only unless
separately approved. Do not use `--no-kv-offload`; in llama.cpp, KV offload to
GPU is the default, and `--no-kv-offload` would force KV onto CPU/RAM, which
contradicts the target of keeping all KV on GPU.

### OOM Ladder

If 128K context does not fit, follow this order:

1. Reduce `--fit-target` (e.g. 2048 → 1536 per GPU)
2. Reduce `-ub 128` to `-ub 64`
3. Switch KV precision from F16 to Q8_0 (`-ctk q8_0 -ctv q8_0`) while keeping 128K context
4. Only then reduce `-c` from 131072 to 65536

Do not jump to context reduction before trying fit-target, batch, and KV
precision adjustments. Preserving 128K context is preferred over F16 KV.

## Hardware Constraints

- Dual RTX 5090: 2 x 32607 MiB VRAM (approximately 64 GiB total)
- System RAM: approximately 45 GiB
- The Q8_0 model weights are approximately 40.2 GiB, fitting within dual-GPU VRAM
  with approximately 8 GiB headroom after KV cache and compute

### KV Cache Budget (128K, F16)

The qwen35 architecture is hybrid: 72 of 96 transformer layers use SSM (linear
attention with recurrent state, no KV cache), and 24 layers use dense attention
(backbone at indices 3,7,11,...,95). The MTP layer (blk.96.nextn) adds one
additional KV-contributing layer for draft context. Only the dense-attention
layers consume KV cache.

Verified GGUF metadata for KV sizing:

```text
head_count:     24
head_count_kv:  4          (GQA 6:1)
head_dim:       256        (derived from attn_k.weight shape 5120x1024)
dense_attn_layers: 24      (backbone at indices 3,7,11,...,95)
mtp_draft_layers: 1        (blk.96.nextn, additional KV for draft context)
context_length: 131072     (128K target)
KV precision:   f16        (2 bytes per element)
```

Main-model KV cache (24 dense layers, F16, 128K context):

```text
K: 24 layers * 4 heads * 256 dim * 131072 tokens * 2 bytes = 6,442,450,432 bytes (~6.0 GiB)
V: same as K                                                = 6,442,450,432 bytes (~6.0 GiB)
Total main KV:                                              ~12.0 GiB (~6.0 GiB per GPU)
```

MTP draft KV (1 layer, F16, 128K context):

```text
K+V: 1 layer * 4 heads * 256 dim * 131072 tokens * 2 * 2 bytes  ~0.5 GiB
```

### VRAM Allocation (64 GiB total)

```text
Model weights Q8_0:       ~40.2 GiB  (62.8%)
Main KV (128K, F16):      ~12.0 GiB  (18.8%)
MTP draft KV:             ~0.5 GiB   ( 0.8%)
Recurrent state:          ~0.2 GiB   ( 0.3%)
CUDA runtime:             ~1.0 GiB   ( 1.6%)
Compute buffer:           ~1.5 GiB   ( 2.3%)
──────────────────────────────────────────────
Total:                    ~55.4 GiB
Headroom:                 ~8.6 GiB   (13.4%)
```

`--fit-target 2048,2048` means each GPU should retain approximately 2 GiB of
VRAM as a safety margin after fitting weights, KV, compute buffers, and all
runtime allocations. This is not a "KV reservation" — it is the desired
remaining margin. The 128K F16 KV budget of ~6 GiB/GPU is well within the
available space when weights are split across two GPUs (~20 GiB weights + ~6 GiB
KV + ~0.1 GiB RS + ~0.25 GiB MTP draft ≈ 26.4 GiB, leaving ~5.6 GiB for CUDA
buffers, FA workspace, and the 2 GiB fit-target margin).

Do not use `--no-kv-offload`. In llama.cpp, KV offload to GPU is the default;
`--no-kv-offload` would force KV onto CPU/RAM, contradicting the goal of
keeping all KV on GPU.

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
- The GGUF contains one MTP/nextn layer (`nextn_predict_layers: 1`). Runtime
  MTP is explicitly enabled with `--spec-type draft-mtp`; the llama.cpp default
  speculative decoding type is `none`. `n-max=2` is the Phase 2 baseline — the
  original n-max=3 Qwen3.6 output drift bug (llama.cpp #23302) was closed after
  testing showed Q8_0 is unaffected at n=1-5, but n-max=2 remains the
  conservative first-boot choice. Phase 4 will benchmark four configurations:
  n=2/3 × p_min=0/0.75. Disabling MTP for Phase 4 comparison uses
  `MTP_MODE=off` in the launcher, which omits all speculative args entirely.
  Do NOT use `--spec-type none` via `$@` to disable MTP — llama.cpp appends
  spec types into a bitmask, so passing both `draft-mtp` and `none` still
  enables MTP.
