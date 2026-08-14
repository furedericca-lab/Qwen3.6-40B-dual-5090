---
description: Validate an MTP-off 64K TP=2 vLLM load of the Golden checkpoint.
---

# Tasks: Qwen3.6-40B-Eleanor MXFP8 W8A8 Deployment

## Input

- `config/runtime.env`
- `scripts/bootstrap-vllm.sh`
- `scripts/vllm-server-first-boot.sh`
- `scripts/smoke-api.sh`

## Canonical Architecture / Key Constraints

- vLLM auto-detects MXFP8 solely from checkpoint `quantization_config`; do not
  pass `--quantization mxfp8` or `--quantization compressed-tensors`.
- Initial command uses TP=2, `--dtype bfloat16`, `--kv-cache-dtype auto`,
  `--language-model-only`, 64K context, 0.90 GPU utilization, and localhost.
- MTP is off in this phase. The runtime may add `--max-cudagraph-capture-size
  128` only after the documented hybrid/Mamba cache error occurs.

## Format

- `[ID] [P?] [Component] Description`
- `[P]` means parallelizable.

## Phase 3: 64K MTP-off First Boot

Goal: prove the Golden checkpoint can load and serve a deterministic text request
within the initial dual-5090 capacity profile.

Definition of Done: server startup, `/health`, `/v1/models`, a deterministic
chat completion, and balanced TP=2 GPU telemetry are recorded.

Tasks:
- [x] T009 [Infra] Bootstrap vLLM from pinned local source
  - DoD: `scripts/bootstrap-vllm.sh` creates only ignored `.venv` and installs the local `vllm/` source with its pinned runtime dependency set.
- [ ] T010 [Config] Launch the MTP-off 64K profile
  - DoD: `scripts/vllm-server-first-boot.sh` launches `/data/linux-fast/models/Qwen3.6-40B-Eleanor-MXFP8-W8A8` with TP=2, BF16 non-quantized compute, auto KV cache, language-model-only mode, `qwen3`, and `qwen3_coder` settings.
- [ ] T011 [QA] Capture API and capacity evidence
  - DoD: `scripts/smoke-api.sh` passes, and the execution record contains the exact server command plus `nvidia-smi` memory/utilization observations for both GPUs.

Checkpoint: Phase 4 is blocked until the MTP-off 64K baseline is accepted.

## Execution Evidence

- 2026-08-13 T009 passed. `.venv` contains the local CPython 3.13 CUDA wheels
  for Torch `2.14.0a0.post20260719`, pytorch-triton
  `3.8.0+git694c0c3b.post20260719`, and torchvision
  `0.29.0a0.post20260719`, plus editable local compressed-tensors `0.18.1.dev0`
  and pinned vLLM `0.27.2rc1.dev36+g5fee0a872.cu133`. CUDA 13.3 and both RTX
  5090 devices were visible; no PyPI `triton` distribution was installed.
- 2026-08-13 T010 attempted the reviewed 0.90, TP=2, 64K, MTP-off profile.
  The service auto-detected compressed-tensors, selected the FlashInfer MXFP8
  linear kernel, loaded all 18 checkpoint shards, and then rejected the profile
  before HTTP startup: 1.15 GiB KV cache was available while one 64K request
  needs 3.23 GiB. vLLM estimated a 20,384-token maximum. This is valid baseline
  failure evidence, not a deployable service result; T010 and T011 remain open.
- 2026-08-13 capacity retries retained the same model, 64K context, TP=2,
  BF16/auto KV, MTP-off, and loopback-only bind. At 0.98, vLLM rejected both
  devices before model loading: 30.51/31.4 GiB free was below the 30.77 GiB
  requested reservation. At 0.97, vLLM auto-detected compressed-tensors,
  selected the FlashInfer MXFP8 linear kernel, loaded all 18 shards, and then
  rejected the profile before HTTP startup: 2.79 GiB KV cache was available
  while 3.23 GiB is required for one 64K request, estimating a 55,664-token
  maximum. The 0.9716 observed reservation ceiling can recover at most about
  0.05 GiB more, so no allowable utilization value reaches 64K. Both failed
  attempts released GPU memory; kernel taint remained 4096 with no Oops,
  BAD_PAGE, Xid, or SIGSEGV evidence. `config/runtime.env` therefore remains
  at the reviewed 0.90 baseline. T010 and T011 remain open; Phase 4 remains
  blocked pending an explicitly reviewed capacity change.
- 2026-08-13 single-Agent capacity profile passed the 64K allocation gate with
  TP=2, BF16/auto KV, MTP off, loopback-only bind,
  `GPU_MEMORY_UTILIZATION=0.97`, `MAX_NUM_SEQS=1`, and
  `MAX_NUM_BATCHED_TOKENS=2048` with chunked prefill enabled. vLLM auto-derived
  CUDA-graph captures `[1, 2]`; model/non-Torch memory was 20.69 GiB, peak
  activation memory 1.33 GiB, CUDA-graph memory 0.10 GiB, and the KV cache was
  8.44 GiB per GPU. It reported 171,121 total KV tokens and 2.61x maximum
  concurrency for one 65,536-token request, then bound `127.0.0.1:8000` and
  passed `/health` and `/v1/models`.
- The first deterministic completion failed with HTTP 500, so T011 remains
  open. The worker error is not a capacity failure: local pytorch-triton
  `3.8.0+git694c0c3b.post20260719` removed `tl.make_block_ptr`, which the
  pinned vLLM FLA GDN prefill kernel invokes. The engine then terminated. The
  pinned source's FlashInfer and CuteDSL GDN paths support SM90/SM10.x, while
  both local RTX 5090 devices report SM12.0 and therefore fall back to this
  Triton/FLA path. The runtime bootstrap is being rebuilt with the pinned
  vLLM CUDA 13 official Torch `2.13.0+cu130` and Triton `3.7.1` stack; this
  affects only `.venv`, not the local-wheel quantizer environment or Golden.

## Dependencies & Execution Order

- Phase 3 depends on Phase 2.
- T011 follows a successful T010.
