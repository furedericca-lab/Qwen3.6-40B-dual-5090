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
updated: 2026-08-14T10:00:00Z
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
--spec-draft-p-min 0.75
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

### --spec-draft-n-max 2 (baseline, not final)

Qwen3.6 had a reported bug where `n-max=3` changed deterministic output
(llama.cpp issue #23302), but the issue was closed after testing showed
Q8_0 is unaffected at n=1-5. `n-max=2` remains the conservative first-boot
baseline. Phase 4 will benchmark four configurations: n=2/3 × p_min=0/0.75.
The Eleanor author recommends `n-max=2` and reports ~60% acceptance at
2 tokens.

### --spec-draft-p-min 0.75 (baseline)

Stops drafting early when the MTP head confidence drops below 0.75. Default
is 0.0 (never stop early). Setting 0.75 reduces wasted computation on
low-confidence drafts. This is a baseline value — Phase 4 will compare
p_min=0 vs p_min=0.75 at both n=2 and n=3 to find the optimal combination.

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

1. Reduce `--fit-target` (2048 → 1536 per GPU)
2. Reduce `-ub 128` to `-ub 64`
3. Switch KV to Q8_0 (`-ctk q8_0 -ctv q8_0`) — preserves 128K context
4. Only then reduce `-c 131072` to `-c 65536`

Do not sacrifice 128K context before trying Q8_0 KV.

## Do not

Do not use `-ngl all`: it disables auto-fit for this 40 GiB model.
Do not use `--no-kv-offload`: it forces KV to CPU, opposite of the goal.
