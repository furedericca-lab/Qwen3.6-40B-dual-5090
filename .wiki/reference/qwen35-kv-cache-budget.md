---
title: Qwen3.6-40B qwen35 KV cache budget calculation
type: reference
status: current
scope: qwen36-40b-eleanor-llamacpp
related_scopes: []
related_files:
  - scripts/llama-server-first-boot.sh
source_docs:
  - .scopes/qwen36-40b-eleanor-llamacpp/qwen36-40b-eleanor-llamacpp-contracts.md
tags:
  - kv-cache
  - vram
  - qwen35
last_checked: 2026-08-14
updated: 2026-08-14T08:30:00Z
---

# Qwen3.6-40B qwen35 KV cache budget calculation

The Qwen3.6-40B-Eleanor GGUF uses the `qwen35` architecture: a hybrid model
with both SSM (linear attention) and dense attention layers. Only dense
attention layers consume KV cache, so the budget is smaller than a pure
transformer of equivalent size.

## Architecture facts (from GGUF metadata)

- Total transformer layers: 96 (indices 0-95)
- MTP layer: 1 (index 96, `blk.96.nextn.*`)
- Dense attention layers: 25 (indices 3,7,11,15,...,95 every 4 layers = 24
  backbone, plus MTP layer 96 = 25 total)
- SSM/linear attention layers: 72 (use recurrent state, no KV cache)
- Full attention interval: 4
- `head_count`: 24
- `head_count_kv`: 4 (GQA ratio 6:1)
- `head_dim`: 256 (derived from `blk.3.attn_k.weight` shape `5120x1024`;
  GGML stores K weights as `(n_embd, head_dim * n_head_kv)` = `(5120, 1024)`)

## KV cache formula (F16)

For a given context length `C`:

```
K_bytes = dense_attn_layers * n_head_kv * head_dim * C * 2
V_bytes = dense_attn_layers * n_head_kv * head_dim * C * 2
Total   = K_bytes + V_bytes
       = 2 * dense_attn_layers * n_head_kv * head_dim * C * 2
       = 4 * 25 * 4 * 256 * C
       = 102400 * C
```

## Reference values

| Context | Total KV (F16) | Per GPU (2 GPUs) |
|---|---|---|
| 32K (32768) | ~3.1 GiB | ~1.6 GiB |
| 64K (65536) | ~6.3 GiB | ~3.1 GiB |
| 128K (131072) | ~12.5 GiB | ~6.3 GiB |
| 256K (262144) | ~25.0 GiB | ~12.5 GiB |

## --fit-target sizing

`--fit-target` reserves space per GPU for KV cache plus compute buffers. With
128K context requiring ~6.3 GiB/GPU for KV alone, `--fit-target 8192,8192`
provides ~1.8 GiB/GPU compute buffer headroom. For 256K context, use at least
`--fit-target 14336,14336` (14 GiB/GPU for KV + compute).

## SSM recurrent state

The 72 SSM layers use recurrent state instead of KV cache. State size per
layer is `ssm_state_size * ssm_inner_size` = `128 * 6144` = 786,432 elements.
At F32 this is ~3 MiB per layer, ~216 MiB total — negligible compared to KV
cache but counted in the VRAM budget.
