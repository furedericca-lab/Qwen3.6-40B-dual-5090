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
updated: 2026-08-14T07:20:19Z
---

# llama-server first-boot recipe for Qwen3.6-40B Q8_0

First-boot recipe after llama.cpp is built and GGUF is on NVMe: scripts/llama-server-first-boot.sh. Uses --load-mode dio, -dev CUDA0,CUDA1, -sm layer, --fit on --fit-target 2048,2048, --no-kv-offload, -ctk f16 -ctv f16, -c 131072, -np 1, -b 512 -ub 128, -fa on. OOM ladder: reduce batch first (-b 256 -ub 64), then context to 65536, only then consider limited CPU offload. The GGUF is qwen35 architecture (hybrid SSM+attention) with native MTP (nextn_predict_layers=1). Do not use -ngl all: it disables auto-fit for this 40 GiB model.
