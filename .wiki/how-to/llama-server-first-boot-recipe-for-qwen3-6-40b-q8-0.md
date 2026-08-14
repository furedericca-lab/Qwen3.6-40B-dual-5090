---
title: llama-server first-boot recipe for Qwen3.6-40B Q8_0
type: how-to
status: current
scope: qwen36-40b-eleanor-llamacpp
related_scopes: []
related_files:
  - scripts/llama-server-first-boot.sh
source_docs: []
tags:
  - launch
  - llama-server
last_checked: 2026-08-14
updated: 2026-08-14T18:00:00Z
---

# llama-server first-boot recipe for Qwen3.6-40B Q8_0

First-boot recipe after llama.cpp is built and GGUF is on NVMe:
`scripts/llama-server-first-boot.sh`.

The launcher supports profile-based configuration via `PROFILE`:

| Profile | MTP | Sampling | Use Case |
|---|---|---|---|
| agent (default) | n=3, p=0 | temp=0.6, top_p=0.95, top_k=20 | Hermes/Codex agents, coding |
| balanced | n=2, p=0 | temp=0.7, top_p=0.95, top_k=20 | General interaction |
| creative | MTP off | temp=1.0, top_k=40, min_p=0.05 | Creative, divergent |
| long | n=3, p=0 | temp=0.6 | 256K Q8_0 KV (experimental) |

```bash
# Agent profile (default)
scripts/llama-server-first-boot.sh

# Balanced profile
PROFILE=balanced scripts/llama-server-first-boot.sh

# Creative profile (MTP off)
PROFILE=creative scripts/llama-server-first-boot.sh
```

## Launch parameters (agent profile)

```text
--load-mode dio
-dev CUDA0,CUDA1
-sm layer
--fit on
--fit-target 2048,2048
-ctk f16 -ctv f16
-c 131072
-np 1
-b 1024 -ub 256
-fa on
--spec-type draft-mtp
--spec-draft-n-max 3
--spec-draft-n-min 0
--spec-draft-p-min 0
--temp 0.6
--top-p 0.95
--top-k 20
--min-p 0
--repeat-penalty 1.0
--host 127.0.0.1 --port 8000
```

No `--no-kv-offload` — in llama.cpp, KV offload to GPU is the default.
`--no-kv-offload` would force KV onto CPU/RAM, which contradicts the target.

## Key parameter semantics

### --fit-target 2048,2048

`--fit-target` is the **target VRAM margin per GPU after fitting all model
weights** — not a KV reservation. It tells the fit algorithm: "after placing
weights, KV, and compute buffers, try to leave about 2 GiB free per GPU."

The 128K F16 KV budget is ~6 GiB/GPU for the main model plus ~0.25 GiB/GPU
for MTP draft. With ~20 GiB weights per GPU, the allocation is:

```text
~20.1 GiB weights + ~6.0 GiB KV + ~0.1 GiB RS + ~0.25 GiB MTP ≈ 26.4 GiB
```

Leaving ~5.6 GiB for CUDA buffers, FA workspace, and the 2 GiB fit-target
margin. Using a larger fit-target (e.g. 8192) would force the fit algorithm to
offload more weights to CPU, hurting decode speed.

### --spec-draft-n-max 3 (agent profile default)

`n-max=3` with `p_min=0` is the agent profile default after profile
optimization benchmarking. At temp=0.6, n=3 produces 73.76 tok/s (2.12x
speedup vs MTP-off, stddev 0.015), which is 8.0% faster than n=2/p=0
(68.30 tok/s) and more energy-efficient (8.46 vs 8.75 J/token). The
n-max=3 drift bug (#23302) was superseded by #23335; fixed-seed testing
showed Q8_0 agreeing across no-MTP and MTP n=1-5. p_min sweep
(0/0.05/0.10/0.20) showed no effect. n=4 is slower than n=3 (73.62 vs
73.76 tok/s) with acceptance near the 50% viability threshold.

### --spec-draft-p-min 0 (all profiles)

`p_min=0` means the MTP head always drafts up to `n-max` tokens without
ever stopping early. This is the only viable setting after benchmarking
showed p_min=0/0.05/0.10/0.20 all produce identical results — the model's
MTP confidence is consistently above 0.20. Setting p_min=0.75 actively
hurts throughput by cutting draft sequences short.

### Sampling: server fallback defaults

Server sampling parameters are fallback defaults only. API callers should
pass their own sampler overrides per request. The agent profile uses Qwen3.6
official precise coding parameters: `top_k=20, min_p=0, repeat_penalty=1.0`.
`repeat-penalty 1.0` disables repetition penalty (MTP works best with it off).
For creative/RP use, use `PROFILE=creative` (temp=1.0, top_k=40, min_p=0.05)
or pass sampler overrides per-request.

### -b 1024 -ub 256 (batch/ubatch)

Ubatch was increased from 128 to 256 after benchmarking showed +20-34%
prefill improvement with zero decode regression and ~130 MiB/GPU VRAM
cost. At 66K prompt length, ub=256 delivers 2042 tok/s prefill vs 1706
tok/s for ub=128. Decode speed is unchanged (73.76 vs 73.66 tok/s).

## VRAM budget (64 GiB total)

```text
Q8_0 weights:              ~40.2 GiB  (62.8%)
Main KV (128K, F16):       ~12.0 GiB  (18.8%)
MTP draft KV:               ~0.5 GiB  ( 0.8%)
Recurrent state:             ~0.2 GiB  ( 0.3%)
CUDA runtime:                ~1.0 GiB  ( 1.6%)
Compute buffer:              ~1.5 GiB  ( 2.3%)
─────────────────────────────────────────────
Total:                      ~55.4 GiB
Headroom:                    ~8.6 GiB  (13.4%)
```

## MTP

The GGUF contains MTP tensors (`nextn_predict_layers: 1`, `blk.96.nextn.*`).
Enable with `--spec-type draft-mtp`. The `-md` flag is not needed —
`draft-mtp` uses the MTP heads embedded in the main GGUF. The fork's
`src/models/qwen35.cpp` has native qwen35 MTP/nextn support.

The launcher uses `MTP_MODE` to control MTP:

```bash
# MTP on (default)
MTP_MODE=on scripts/llama-server-first-boot.sh

# MTP off (Phase 4 baseline)
MTP_MODE=off scripts/llama-server-first-boot.sh
```

Do NOT use `$@ --spec-type none` to disable MTP. llama.cpp appends
`--spec-type` values into a bitmask rather than replacing them, so passing
both `--spec-type draft-mtp` (from the launcher) and `--spec-type none`
(via `$@`) would still enable MTP. Use `MTP_MODE=off` instead, which omits
all speculative decoding args entirely, letting llama.cpp default to
spec-type none.

## OOM ladder

1. Reduce `-ub 256` to `-ub 128` then `-ub 64` (smaller micro-batch reduces compute buffer)
2. If still compute/prefill OOM, increase `--fit-target` (2048 → 3072 or
   4096 per GPU) to allow the fitter to offload some weights to CPU
3. Switch KV to Q8_0 (`-ctk q8_0 -ctv q8_0`) — preserves 128K context
4. Only then reduce `-c 131072` to `-c 65536`

Do not sacrifice 128K context before trying Q8_0 KV.
Reducing fit-target (e.g. 2048 → 1536) is NOT an OOM recovery step — it
asks the fitter to use MORE VRAM (less margin), which is the opposite
of relief.

## First-boot results (2026-08-14)

128K startup with agent profile (n-max=3, p-min=0, ub=256):

```text
GPU0: 26282 MiB used (of 32607 MiB)
GPU1: 29050 MiB used (of 32607 MiB)
Total: ~54.1 GiB

Agent profile (n=3/p=0, temp=0.6): 73.76 tok/s decode, 2042 tok/s prefill at 66K
Balanced profile (n=2/p=0, temp=0.6): 68.30 tok/s decode
MTP-off baseline: 34.77 tok/s decode
```

Profile optimization benchmark (fixed seed, 1 warm-up excluded, 5 formal runs
each, continuous power sampling):

| Config | Mean tok/s | StdDev | Speedup | J/token | Accept Rate |
|--------|----------:|-------:|--------:|--------:|------------:|
| MTP-off | 34.77 | 0.003 | 1.00x | 17.12 | N/A |
| n=2, p=0 (t=0.6) | 68.30 | 0.055 | 1.96x | 8.75 | 72.2% |
| n=3, p=0 (t=0.6) | **73.76** | 0.015 | 2.12x | **8.46** | 60.7% |
| n=3, p=0 (t=0) | 81.67 | 0.043 | 2.35x | 7.58 | 70.7% |
| n=4, p=0 (t=0.6) | 73.62 | 0.042 | 2.12x | 8.30 | 51.7% |

Prefill speed by ubatch:

| ubatch | 8K prompt | 66K prompt |
|-------:|----------:|----------:|
| 128 | 1,940 tok/s | 1,706 tok/s |
| 256 | 2,594 tok/s | 2,042 tok/s |

No OOM, no kernel errors, no NVIDIA Xid. All API health checks pass.

## Do not

Do not use `-ngl all`: it disables auto-fit for this 40 GiB model.
Do not use `--no-kv-offload`: it forces KV to CPU, opposite of the goal.
