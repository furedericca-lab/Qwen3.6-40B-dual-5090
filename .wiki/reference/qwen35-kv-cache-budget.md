---
title: Qwen3.6-40B qwen35 KV cache budget calculation
type: reference
status: current
scope: qwen36-40b-eleanor-llamacpp
related_scopes: []
related_files:
  - scripts/llama-server-first-boot.sh
source_docs:
  - .scopes/archive/qwen36-40b-eleanor-llamacpp/qwen36-40b-eleanor-llamacpp-contracts.md
tags:
  - kv-cache
  - vram
  - qwen35
last_checked: 2026-08-14
updated: 2026-08-14T10:00:00Z
---

# Qwen3.6-40B qwen35 KV cache budget calculation

The Qwen3.6-40B-Eleanor GGUF uses the `qwen35` architecture: a hybrid model
with both SSM (linear attention) and dense attention layers. Only dense
attention layers consume KV cache, so the budget is smaller than a pure
transformer of equivalent size.

## Architecture facts (from GGUF metadata)

- Total transformer layers: 96 (indices 0-95)
- MTP layer: 1 (index 96, `blk.96.nextn.*`)
- Dense attention layers (main model): 24 (indices 3,7,11,15,...,95, every 4
  layers = 24 backbone layers)
- MTP draft KV: 1 additional layer (blk.96.nextn) for draft context
- SSM/linear attention layers: 72 (use recurrent state, no KV cache)
- Full attention interval: 4
- `head_count`: 24
- `head_count_kv`: 4 (GQA ratio 6:1)
- `head_dim`: 256 (derived from `blk.3.attn_k.weight` shape `5120x1024`;
  GGML stores K weights as `(n_embd, head_dim * n_head_kv)` = `(5120, 1024)`)

## Main-model KV cache formula (F16)

For a given context length `C`, only the 24 dense attention layers contribute:

```
K_bytes = 24 * n_head_kv * head_dim * C * 2
V_bytes = 24 * n_head_kv * head_dim * C * 2
Total   = K_bytes + V_bytes
       = 4 * 24 * 4 * 256 * C
       = 98304 * C
```

## MTP draft KV (F16)

The single MTP layer (blk.96.nextn) also maintains a KV cache for draft
context. At 128K F16 this is approximately 0.5 GiB.

## Reference values (main model only)

| Context | Total KV (F16) | Per GPU (2 GPUs) |
|---|---|---|
| 32K (32768) | ~3.0 GiB | ~1.5 GiB |
| 64K (65536) | ~6.0 GiB | ~3.0 GiB |
| 128K (131072) | ~12.0 GiB | ~6.0 GiB |
| 256K (262144) | ~24.0 GiB | ~12.0 GiB |

Add ~0.5 GiB for MTP draft KV at 128K, ~1.0 GiB at 256K.

## --fit-target semantics

`--fit-target` specifies the **target VRAM margin per GPU after fitting all
model weights, KV, and compute buffers**. It is NOT a KV reservation — it is
the desired amount of remaining free VRAM. The fit algorithm tries to leave
this much headroom.

With 128K F16 KV requiring ~6.25 GiB/GPU (main + MTP draft), and weights
taking ~20 GiB/GPU:

```text
32 GiB/GPU
- ~20.1 GiB weights
- ~6.0 GiB main KV
- ~0.25 GiB MTP draft KV
- ~0.1 GiB RS
= ~5.5 GiB remaining for CUDA/FA/compute + fit-target margin
```

`--fit-target 2048,4096` (2 GiB margin on GPU0, 4 GiB on GPU1) is optimal — it maximizes min(free) across GPUs (+44% vs symmetric 2048,2048) while keeping <0.2% decode regression. The asymmetric split compensates for GPU1's lower KV cache pressure from SSM layers. Larger values (e.g. 8192) would force more weights to CPU, hurting decode speed.

## SSM recurrent state

The 72 SSM layers use recurrent state instead of KV cache. State size per
layer is `ssm_state_size * ssm_inner_size` = `128 * 6144` = 786,432 elements.
At F32 this is ~3 MiB per layer, ~216 MiB total — negligible compared to KV
cache but counted in the VRAM budget.

## Q8_0 KV fallback

If F16 KV does not fit at 128K, llama.cpp supports `-ctk q8_0 -ctv q8_0`
which halves the KV budget (from ~12 GiB to ~6 GiB at 128K) while preserving
the full 128K context. This is preferred over reducing context to 64K.
