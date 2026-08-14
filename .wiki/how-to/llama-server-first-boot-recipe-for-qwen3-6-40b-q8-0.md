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
updated: 2026-08-14T08:30:00Z
---

# llama-server first-boot recipe for Qwen3.6-40B Q8_0

First-boot recipe after llama.cpp is built and GGUF is on NVMe:
`scripts/llama-server-first-boot.sh`.

## Launch parameters

Uses `--load-mode dio`, `-dev CUDA0,CUDA1`, `-sm layer`, `--fit on`,
`--fit-target 8192,8192`, `--no-kv-offload`, `-ctk f16 -ctv f16`, `-c 131072`,
`-np 1`, `-b 512 -ub 128`, `-fa on`, `--spec-type draft-mtp`,
`--spec-draft-n-max 3`, `--temp 0.6`, `--top-p 0.95`, `--host 127.0.0.1
--port 8000`.

## Why --fit-target 8192,8192

The qwen35 architecture is hybrid: 72 of 96 transformer layers use SSM (linear
attention with recurrent state, no KV cache), and 25 layers use dense attention
(24 backbone at indices 3,7,11,...,95 plus MTP layer 96). Only dense-attention
layers consume KV cache.

Verified metadata: `head_count_kv=4`, `head_dim=256` (derived from
`attn_k.weight` shape `5120x1024`). Per-layer F16 KV at 128K context is
approximately 512 MiB. Total 128K F16 KV is approximately 12.5 GiB
(~6.25 GiB per GPU). The `--fit-target 8192,8192` reserves 8 GiB per GPU for
KV plus compute buffer overhead. The previous value `2048,2048` was
insufficient — it would only support approximately 32K context.

## VRAM budget (64 GiB total)

Model weights Q8_0 ~40.2 GiB (62.8%), KV cache ~12.5 GiB (19.5%), CUDA runtime
~1.0 GiB, compute buffer ~1.5 GiB, SSM recurrent state ~0.5 GiB. Total ~55.7
GiB, leaving ~8.3 GiB (13%) headroom.

## MTP

The GGUF contains MTP tensors (`nextn_predict_layers: 1`, `blk.96.nextn.*`).
Enable with `--spec-type draft-mtp --spec-draft-n-max 3`. This fork's llama.cpp
has native qwen35 MTP/nextn support in `src/models/qwen35.cpp`.

## OOM ladder

1. Reduce batch: `-b 512 -ub 128` to `-b 256 -ub 64`
2. Reduce context: `-c 131072` to `-c 65536`
3. Only then consider limited CPU offload

## Do not

Do not use `-ngl all`: it disables auto-fit for this 40 GiB model.
