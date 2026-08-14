---
description: Build and verify the permanent offline MXFP8 W8A8 Golden checkpoint.
---

# Tasks: Qwen3.6-40B-Eleanor MXFP8 W8A8 Deployment

## Input

- `config/quantize.env`
- `scripts/bootstrap-quantizer.sh`
- `scripts/build-fp8-checkpoint.py`
- `scripts/build-fp8-checkpoint.sh`
- `scripts/verify-fp8-checkpoint.py`

## Canonical Architecture / Key Constraints

- Output is `/data/linux-fast/models/Qwen3.6-40B-Eleanor-MXFP8-W8A8`; it must
  not exist before the run and is never overwritten.
- Use `model_free_ptq(... scheme="MXFP8", device=["cuda:0", "cuda:1"],
  max_workers=2)` with a same-filesystem staging directory.
- Preserve BF16 `lm_head`, `embed_tokens`, `conv1d`, `in_proj_a`, `in_proj_b`,
  `mtp`, visual/vision modules, and norms. Do not add speculative layer ignores.

## Format

- `[ID] [P?] [Component] Description`
- `[P]` means parallelizable.

## Phase 2: Golden MXFP8 W8A8 Build

Goal: produce one durable compressed-tensors MXFP8 W8A8 checkpoint from the
frozen BF16 source.

Definition of Done: output metadata identifies compressed-tensors MXFP8 W8A8
with group size 32 and uint8 scales; required BF16 exclusions and MTP are
present; the output direct-I/O SHA256 manifest is complete.

Tasks:
- [x] T005 [Infra] Bootstrap the local quantizer from pinned submodules
  - DoD: `scripts/bootstrap-quantizer.sh` creates only ignored `.quantize-venv` and installs local `compressed-tensors/` then local `llm-compressor/` with the compatible release pins.
- [x] T006 [Backend] Execute the staged model-free MXFP8 build
  - DoD: `scripts/build-fp8-checkpoint.sh` exits zero, never modifies the BF16 source, and atomically promotes only the configured MXFP8 output path.
- [x] T007 [QA] Verify output schema and preservation rules
  - DoD: `scripts/verify-fp8-checkpoint.py` proves `quant_method=compressed-tensors`, float E4M3 8-bit symmetric group-32 weights, uint8 scales, dynamic group-32 MXFP8 input activations, and required ignored paths including MTP.
- [x] T008 [QA] Freeze the Golden MXFP8 manifest
  - DoD: a reviewed direct-I/O manifest tool verifies every Golden payload and records its manifest SHA256. Ordinary `sha256sum` is prohibited.

Checkpoint: Phase 3 is blocked until T005-T008 pass and the output is not modified afterwards.

## Execution Evidence

- T005: `.quantize-venv` uses local Torch `2.14.0a0.post20260719` and
  pytorch-triton `3.8.0+git694c0c3b.post20260719` from `~/torch/dist`; two RTX
  5090 GPUs were CUDA-visible.
- T006: `scripts/build-fp8-checkpoint.sh` exited zero on the clean
  `c4a24a76-ed5e-45d3-ba5a-413869a6a010` boot. `model_free_ptq` distributed 18
  shards across `cuda:0,cuda:1` and atomically promoted the permanent output.
- T007: `scripts/verify-fp8-checkpoint.py` found 18 weight files, 15 MTP
  tensors, `mxfp8-quantized` compressed-tensors metadata, persistent
  group-32 uint8 weight scales, dynamic group-32 input activations, and every
  reviewed BF16 ignore rule.
- T008: `scripts/write-direct-sha256-manifest.py` passed with aligned O_DIRECT
  reads for 30 Golden files. Manifest SHA256:
  `61a2e80f1ee6ac33fc2d39901b630ef8d5350cdded586a061bc03d46f3ae76c9`.

## Dependencies & Execution Order

- Phase 2 depends on Phase 1.
- T007 follows T006; T008 follows T007.
