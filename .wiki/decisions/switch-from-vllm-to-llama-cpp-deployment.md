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
updated: 2026-08-14T07:19:57Z
decision_date: 2026-08-14
---

# Switch from vLLM to llama.cpp deployment

The project switched from vLLM/MXFP8 to llama.cpp/Q8_0 GGUF. The vLLM route archived because Phase 3 could not fit 64K KV cache on dual RTX 5090 at 0.90 GPU utilization. The new route uses a pre-built Q8_0 GGUF (qwen35 architecture, 97 blocks, MTP enabled) served by llama.cpp fork efb81ab which has native qwen35 support. Target is 128K context with MTP. Build uses CUDA sm_120a, Clang 21, CUDA 13.3.
