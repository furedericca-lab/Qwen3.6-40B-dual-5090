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

## 2026-08-14T12:00:00Z [qwen36-40b-eleanor-llamacpp]

- Summary: Fixed MTP-off mechanism for Phase 4. The previous approach of using `$@ --spec-type none` to override `--spec-type draft-mtp` does NOT work — llama.cpp appends spec types into a bitmask rather than replacing them, so both draft-mtp and none would be active and MTP would remain enabled. Replaced with `MTP_MODE` environment variable: `MTP_MODE=on` (default) passes `--spec-type draft-mtp` and related flags; `MTP_MODE=off` omits all speculative args entirely, letting llama.cpp default to spec-type none. Also fixed Phase 2 OOM ladder wording: "VRAM reduction" → "reduce the reserved fit margin" (fit-target is a margin, not a reservation). Updated script, AGENTS.md, contracts.md, Phase 2/4 task plans, wiki how-to and decisions.
- Pages: how-to/llama-server-first-boot-recipe-for-qwen3-6-40b-q8-0.md, decisions/switch-from-vllm-to-llama-cpp-deployment.md
- Verification: bash -n scripts/llama-server-first-boot.sh; rg --spec-type none across scope docs
- Residual risk: None — MTP_MODE is a simple conditional, no runtime dependency.

## 2026-08-14T18:00:00Z [qwen36-40b-eleanor-llamacpp]

- Summary: Upstream sync and Phase 2+3 completion. Merged llama.cpp fork (efb81ab) with official upstream/master (885c5bb, +42 commits) into sync branch sync-upstream-20260814. Merge commit 94e82e8ae, no conflicts, all DIO patches preserved. Recompiled with CUDA sm_120a. First-boot 128K startup successful: GPU0=26144 MiB, GPU1=28896 MiB, total ~55 GiB. MTP draft acceptance 90-96% across 5 probes (math, Chinese, JSON, Python, summary). Generation speed 46.9-71.8 tok/s. Prompt speed 84.9-434.1 tok/s. All API health checks pass, localhost-only bind confirmed, kernel taint 4096 (normal), no BAD_PAGE/Oops/Xid. Updated submodule pin to merge commit 94e82e8ae.
- Pages: how-to/llama-server-first-boot-recipe-for-qwen3-6-40b-q8-0.md
- Verification: llama-server --list-devices, /health, /v1/models, nvidia-smi, free -h, ss -tlnp, dmesg
- Residual risk: None — Phase 2+3 fully verified, server stable

## 2026-08-14T14:00:00Z [qwen36-40b-eleanor-llamacpp]

- Summary: Updated MTP parameter characterization from "n-max=3 has a bug" to "n-max=2 is the conservative baseline". The original Qwen3.6 output drift bug (llama.cpp #23302) was closed after testing showed Q8_0 is unaffected at n=1-5. Phase 4 now plans a 4-configuration test matrix: n=2/3 × p_min=0/0.75. Also clarified that sampling params (top_k=20, min_p=0, repeat_penalty=1.0) are Qwen3.6 official coding parameters, not DavidAU's general-purpose profile (which uses top_k=40, min_p=0.05, repeat_penalty=1.02-1.15 for creative/RP use). Decided not to update llama.cpp submodule before Phase 2 first boot — fork is already at its own remote HEAD; upstream sync will be done on a separate branch after baseline is established.
- Pages: how-to/llama-server-first-boot-recipe-for-qwen3-6-40b-q8-0.md, decisions/switch-from-vllm-to-llama-cpp-deployment.md
- Verification: bash -n scripts/llama-server-first-boot.sh; rg 'n-max=3' across scope and wiki docs
- Residual risk: None — documentation-only update, no runtime parameter changes.
