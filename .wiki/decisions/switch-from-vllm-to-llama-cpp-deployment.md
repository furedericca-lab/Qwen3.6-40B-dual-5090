---
title: Switch from vLLM to llama.cpp deployment
type: decision
status: accepted
scope: qwen36-40b-eleanor-llamacpp
related_scopes: []
related_files: []
source_docs:
  - .scopes/qwen36-40b-eleanor-llamacpp/qwen36-40b-eleanor-llamacpp-contracts.md
tags:
  - deployment
  - llama-cpp
  - vllm
  - migration
last_checked: 2026-08-14
updated: 2026-08-14T08:30:00Z
decision_date: 2026-08-14
---

# Switch from vLLM to llama.cpp deployment

The project switched from vLLM/MXFP8 to llama.cpp/Q8_0 GGUF. The vLLM route was
archived because Phase 3 could not fit 64K KV cache on dual RTX 5090 at 0.90
GPU utilization. The new route uses a pre-built Q8_0 GGUF (qwen35 architecture,
97 blocks, MTP enabled) served by llama.cpp fork efb81ab which has native qwen35
support. Target is 128K context with MTP. Build uses CUDA sm_120a, Clang 21,
CUDA 13.3.

## Key parameter decisions

- `--fit-target 8192,8192`: Corrected from initial `2048,2048` after
  calculating the 128K F16 KV cache budget. The qwen35 architecture has 25
  dense attention layers (not 97) consuming KV cache, with `head_dim=256` and
  `n_head_kv=4`. Total 128K F16 KV is ~12.5 GiB (~6.25 GiB/GPU). The original
  2048 MiB/GPU would only support ~32K context.

- `--spec-type draft-mtp --spec-draft-n-max 3`: Enables MTP speculative
  decoding using the GGUF-embedded `nextn_predict_layers: 1` tensors
  (`blk.96.nextn.*`). The fork's `src/models/qwen35.cpp` has native nextn
  support. The reference project (DeepSeek V4) used a noMTP GGUF and did not
  need this flag.

- `--no-kv-offload`: With only 45 GiB system RAM and 40 GiB model weights
  loaded via DIO, CPU KV offload would cause severe memory pressure. All KV
  stays on GPU.
