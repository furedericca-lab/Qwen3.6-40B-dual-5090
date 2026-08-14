# Qwen3.6-40B-Eleanor on Dual RTX 5090

This repository contains the reproducible local build and deployment control
plane for `Qwen3.6-40B-Eleanor`. Model payloads stay outside Git.
`llama.cpp/`, `llm-compressor/`, and `compressed-tensors/` are pinned upstream
submodules.

Durable operating and incident knowledge is under `.wiki/`. Read
`.wiki/debugging/buffered-upstream-verifier-bad-page.md` before any full-payload
source verification or buffered-I/O trigger investigation.

## Current baseline

- Source: local BF16 `Qwen3_5ForConditionalGeneration` checkpoint at
  `/data/linux-fast/models/Qwen3.6-40B-Eleanor`, with 17 primary safetensors
  shards and an MTP shard.
- Deployment: GGUF quantized checkpoint served by llama.cpp across two RTX 5090
  GPUs.
- GPUs: two NVIDIA RTX 5090 cards.

## Previous work (archived)

The original MXFP8 W8A8 + vLLM TP=2 deployment scope has been archived to
`.scopes/archive/qwen3.6-40b-eleanor-deployment/`. That route reached Phase 2
(Golden MXFP8 build passed) but Phase 3 (64K MTP-off boot) was blocked by
insufficient KV cache capacity at 0.90 GPU memory utilization. The deployment
has pivoted to llama.cpp with GGUF quantization.
