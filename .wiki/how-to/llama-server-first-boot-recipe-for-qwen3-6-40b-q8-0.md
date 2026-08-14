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
| agent (default) | n=3, p=0 | temp=0.6, top_p=0.95, top_k=20 | Agent/Coding, reasoning-preserve |
| general | n=3, p=0 | temp=0.7, top_p=0.95, top_k=20 | Chat, analysis, reasoning-preserve |
| long | n=3, p=0 | temp=0.6 | 256K Q8_0 KV, retrieval up to ~172K tokens |

Creative work does not get a separate profile — use per-request sampler
overrides (e.g. temp=1.0, top_k=40, min_p=0.05). If temp>1, disable MTP
via `MTP_MODE=off`.

```bash
# Agent profile (default)
scripts/llama-server-first-boot.sh

# General profile
PROFILE=general scripts/llama-server-first-boot.sh

# Long profile
PROFILE=long scripts/llama-server-first-boot.sh
```

## Launch parameters (agent profile)

```text
--load-mode dio
-dev CUDA0,CUDA1
-sm layer
--fit on
--fit-target 2048,4096
-ctk f16 -ctv f16
-c 131072
-np 1
-b 1024 -ub 256
-fa on
--spec-type draft-mtp
--spec-draft-n-max 3
--spec-draft-n-min 0
--spec-draft-p-min 0
--reasoning auto
--reasoning-format deepseek
--reasoning-preserve
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

### --fit-target 2048,4096

`--fit-target` is the **target VRAM margin per GPU after fitting all model
weights** — not a KV reservation. It tells the fit algorithm: "after placing
weights, KV, and compute buffers, try to leave about 2 GiB free on GPU0 and
4 GiB free on GPU1."

The asymmetric target balances the layer split. At `2048,2048`, the default
layer assignment gives GPU1 ~2,799 MiB free (bottleneck) while GPU0 has
~5,725 MiB free. At `2048,4096`, the fitter shifts layers to equalize the
headroom: GPU0 ~4,033 MiB free, GPU1 ~4,491 MiB free. This maximizes
`min(GPU0_free, GPU1_free)` — the metric that determines OOM risk — by 44%.
Decode regression is <0.2%.

### --spec-draft-n-max 3 (agent profile default)

n=3/p=0 is the default MTP configuration for all profiles. At temp=0.6,
n=3 produces 73.76 tok/s (2.12x speedup, stddev 0.015), which is 8.0%
faster than n=2/p=0 (68.30 tok/s). At temp=0.7, n=3 produces 75.02 tok/s,
8.6% faster than n=2/p=0 (69.10 tok/s). Both exceed the 5% threshold.
n=3 is also more energy-efficient at both temperatures (8.46 vs 8.75 J/token
at 0.6, 8.36 vs 9.08 J/token at 0.7). The n-max=3 drift bug (#23302) was
superseded by #23335; fixed-seed testing showed Q8_0 agreeing across no-MTP
and MTP n=1-5. p_min sweep (0/0.05/0.10/0.20) showed no effect. n=4 is
slower than n=3 (73.62 vs 73.76 tok/s) with acceptance near the 50%
viability threshold.

### --spec-draft-p-min 0 (all profiles)

`p_min=0` means the MTP head always drafts up to `n-max` tokens without
ever stopping early. This is the only viable setting after benchmarking
showed p_min=0/0.05/0.10/0.20 all produce identical results — the model's
MTP confidence is consistently above 0.20. Setting p_min=0.75 actively
hurts throughput by cutting draft sequences short.

### Sampling: server fallback defaults

Server sampling parameters are fallback defaults only. API callers should
pass their own sampler overrides per request. All three profiles use Qwen3.6
official precise coding parameters: `top_k=20, min_p=0, repeat_penalty=1.0`.
`repeat-penalty 1.0` disables repetition penalty (MTP works best with it off).
For creative/RP use, pass sampler overrides per-request (temp=1.0, top_k=40,
min_p=0.05). If temp>1, also disable MTP via `MTP_MODE=off`.

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
2. If still compute/prefill OOM, increase `--fit-target` (e.g. 4096 → 5120 per GPU)
3. Switch KV to Q8_0 (`-ctk q8_0 -ctv q8_0`) — preserves 128K context
4. Only then reduce `-c 131072` to `-c 65536`

Do not sacrifice 128K context before trying Q8_0 KV.
Reducing fit-target (e.g. 2048 → 1536) is NOT an OOM recovery step — it
asks the fitter to use MORE VRAM (less margin), which is the opposite
of relief.

## First-boot results (2026-08-14)

128K startup with agent profile (n-max=3, p-min=0, ub=256, fit-target 2048,4096):

```text
GPU0: 28118 MiB used (of 32607 MiB), 4033 MiB free
GPU1: 27660 MiB used (of 32607 MiB), 4491 MiB free
Total: ~54.4 GiB, min(free) = 4033 MiB

Agent profile (n=3/p=0, temp=0.6): 73.76 tok/s decode, 2042 tok/s prefill at 66K
General profile (n=3/p=0, temp=0.7): 75.02 tok/s decode, 8.36 J/token
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
| n=2, p=0 (t=0.7) | 69.10 | 0.029 | 1.98x | 9.08 | 74.2% |
| n=3, p=0 (t=0.7) | **75.02** | 0.059 | 2.16x | **8.36** | 63.2% |

Prefill speed by ubatch:

| ubatch | 8K prompt | 66K prompt |
|-------:|----------:|----------:|
| 128 | 1,940 tok/s | 1,706 tok/s |
| 256 | 2,594 tok/s | 2,042 tok/s |

No OOM, no kernel errors, no NVIDIA Xid. All API health checks pass.

## Reasoning Preserve

Agent and general profiles include `--reasoning auto --reasoning-format
deepseek --reasoning-preserve`. This preserves reasoning traces across
turns instead of stripping them. Benchmark: -2.4% prompt tokens, -6.8%
wall time, decode speed neutral (73.8 vs 74.6 tok/s).

Cache-reuse (`--cache-reuse 256`) is unsupported — the Qwen3.5 hybrid
architecture does not support it in current llama.cpp.

## Long Profile (256K Q8_0 KV)

```text
-c 262144 -ctk q8_0 -ctv q8_0
GPU0: 29654 MiB used, 2497 MiB free
GPU1: 27112 MiB used, 5039 MiB free

Short decode: 43.83 tok/s (vs 92 at 128K)
Retrieval validated up to ~172K tokens
Decode at 120K+ tokens: 10-13 tok/s
```

## Do not

Do not use `-ngl all`: it disables auto-fit for this 40 GiB model.
Do not use `--no-kv-offload`: it forces KV to CPU, opposite of the goal.
