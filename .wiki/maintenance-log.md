---
title: Maintenance Log
type: maintenance-log
status: current
updated: 2026-08-14T08:30:00Z
---

# Maintenance Log

Append-only history for wiki updates caused by scope work, implementation closeout, or knowledge refresh.

## 2026-08-13T13:15:31Z [qwen3.6-40b-eleanor-deployment]

- Summary: Recorded the buffered verifier as the BAD_PAGE trigger workload and added fresh-boot bounded probe instrumentation.
- Pages: debugging/buffered-upstream-verifier-bad-page.md
- Verification: python3 -m py_compile scripts/*.py; scripts/run-buffered-io-probe.sh --probe --only model-00001-of-00017.safetensors --max-bytes-per-file 1048576
- Residual risk: The host root cause is still unproven; no probe may run until reboot clears BAD_PAGE.

## 2026-08-14T07:20:33Z [qwen36-40b-eleanor-llamacpp]

- Summary: Scaffolded new llama.cpp deployment scope. Compiled llama.cpp fork efb81ab with CUDA sm_120a. Removed vLLM scripts, configs, and submodules. Created launcher and updated AGENTS.md, README.md.
- Pages: none

## 2026-08-14T08:30:00Z [qwen36-40b-eleanor-llamacpp]

- Summary: Analyzed launch parameters for 128K context. Corrected --fit-target from 2048,2048 to 8192,8192 based on verified KV cache budget (25 dense attn layers, head_dim=256, n_head_kv=4, 128K F16 KV = ~12.5 GiB). Added MTP enablement via --spec-type draft-mtp --spec-draft-n-max 3. Updated scope contracts, milestones, phase-1 tasks, and wiki pages.
- Pages: how-to/llama-server-first-boot-recipe-for-qwen3-6-40b-q8-0.md, reference/qwen35-kv-cache-budget.md, decisions/switch-from-vllm-to-llama-cpp-deployment.md
- Verification: bash -n scripts/llama-server-first-boot.sh; KV budget cross-checked against GGUF tensor shapes
- Residual risk: --fit-target and --no-kv-offload combination not yet runtime-verified; Phase 2 startup is the validation gate.

## 2026-08-14T10:00:00Z [qwen36-40b-eleanor-llamacpp]

- Summary: Three critical parameter corrections. (1) Removed --no-kv-offload: its semantics are opposite to intent — it disables GPU KV offload, forcing KV to CPU/RAM. The default (KV on GPU) is the target. (2) Reverted --fit-target from 8192,8192 to 2048,2048: --fit-target is the target VRAM margin after fitting, not a KV reservation. 8192,8192 would request 16 GiB total margin, forcing ~7-8 GiB weights to CPU. (3) Changed --spec-draft-n-max from 3 to 2: n-max=3 has a reported Qwen3.6 output drift bug (llama.cpp #23302), author recommends n-max=2. Added --spec-draft-n-min 0, --spec-draft-p-min 0.75, --top-k 20, --min-p 0, --repeat-penalty 1.0. Corrected dense attention layer count: 24 backbone (not 25), MTP draft KV is separate (~0.5 GiB). Main model 128K F16 KV = ~12.0 GiB (not 12.5). Updated OOM ladder: fit-target → ubatch → KV Q8_0 → context reduction.
- Pages: how-to/llama-server-first-boot-recipe-for-qwen3-6-40b-q8-0.md, reference/qwen35-kv-cache-budget.md, decisions/switch-from-vllm-to-llama-cpp-deployment.md
- Verification: bash -n scripts/llama-server-first-boot.sh; contracts.md cross-checked
- Residual risk: All parameter corrections are pre-runtime; Phase 2 startup is the validation gate.
