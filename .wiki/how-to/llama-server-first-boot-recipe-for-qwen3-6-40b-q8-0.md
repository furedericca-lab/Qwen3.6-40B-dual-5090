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

## Launch parameters

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

### --spec-draft-n-max 2 (production default)

`n-max=2` with `p_min=0` is the production default. The n-max=3 drift bug
(#23302) was superseded by #23335; fixed-seed testing showed Q8_0 agreeing
across no-MTP and MTP n=1-5. Phase 4 rigorous benchmark (fixed seed,
temperature 0, 5 runs per config) confirmed n=3/p=0 is fastest (81.35 tok/s,
2.34x speedup) while n=2/p=0 is the balanced default (71.20 tok/s, 2.05x
speedup, stddev 0.03). Operators can set `MTP_N_MAX=3` for maximum
throughput workloads.

### --spec-draft-p-min 0 (production default)

`p_min=0` means the MTP head always drafts up to `n-max` tokens without
ever stopping early. This is the production default after Phase 4
benchmarking showed it delivers the best balance of speed and acceptance:
2.05x speedup over MTP-off with 71.20 tok/s (stddev 0.03). Setting
`p_min=0.75` would stop drafting when MTP head confidence drops below 0.75,
improving acceptance (94.0%) but paradoxically reducing throughput (1.73x)
because it cuts draft sequences short, reducing average verified-tokens-
per-step.

### Sampling: --top-k 20 --min-p 0 --repeat-penalty 1.0

Qwen3.6 official precise coding parameters. `repeat-penalty 1.0` disables
repetition penalty (MTP works best with it off). For creative/RP use, a
separate profile (top_k=40, min_p=0.05, repeat_penalty=1.02-1.15) can be
configured later.

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

1. Reduce `-ub 128` to `-ub 64` (smaller micro-batch reduces compute buffer)
2. If still compute/prefill OOM, increase `--fit-target` (2048 → 3072 or
   4096 per GPU) to allow the fitter to offload some weights to CPU
3. Switch KV to Q8_0 (`-ctk q8_0 -ctv q8_0`) — preserves 128K context
4. Only then reduce `-c 131072` to `-c 65536`

Do not sacrifice 128K context before trying Q8_0 KV.
Reducing fit-target (e.g. 2048 → 1536) is NOT an OOM recovery step — it
asks the fitter to use MORE VRAM (less margin), which is the opposite
of relief.

## First-boot results (2026-08-14)

128K startup with MTP on (n-max=2, p-min=0, production default):

```text
GPU0: 26144 MiB used (of 32607 MiB)
GPU1: 28896 MiB used (of 32607 MiB)
Total: ~55.0 GiB (matches budget estimate of ~55.4 GiB)
System RAM: 5.6 GiB used, 37 GiB free

MTP draft acceptance: 75-96% across probes
Generation speed: 63-80 tok/s (varies by task)
Prompt speed: 74-478 tok/s
system_fingerprint: b10439-94e82e8ae
```

Long prefill (66,591 prompt tokens): prefill 1,712 tok/s, decode 63.4 tok/s,
no crash or quality collapse.

Phase 4 rigorous benchmark (fixed seed, temp=0, 5 runs per config):

| Config       | Mean tok/s | StdDev | Speedup | Accept Rate |
|-------------|----------:|-------:|--------:|------------:|
| MTP-off     |     34.71 |   0.01 |   1.00x |         N/A |
| n=2, p=0    |     71.20 |   0.03 |   2.05x |       77.6% |
| n=2, p=0.75 |     60.18 |   0.04 |   1.73x |       94.0% |
| n=3, p=0    |     81.35 |   0.29 |   2.34x |       70.7% |
| n=3, p=0.75 |     66.61 |   0.71 |   1.92x |       93.1% |

No OOM, no kernel errors, no NVIDIA Xid. All API health checks pass.

## Do not

Do not use `-ngl all`: it disables auto-fit for this 40 GiB model.
Do not use `--no-kv-offload`: it forces KV to CPU, opposite of the goal.
