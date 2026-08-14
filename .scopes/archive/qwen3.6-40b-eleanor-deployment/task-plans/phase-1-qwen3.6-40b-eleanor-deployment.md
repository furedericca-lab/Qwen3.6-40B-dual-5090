---
description: Freeze the BF16 source and validate pinned offline build inputs.
---

# Tasks: Qwen3.6-40B-Eleanor MXFP8 W8A8 Deployment

## Input

- `config/quantize.env`
- `scripts/check-model.py`
- `scripts/validate-quantize-config.py`
- `vllm/`, `llm-compressor/`, and `compressed-tensors/`

## Canonical Architecture / Key Constraints

- The source is `/data/linux-fast/models/Qwen3.6-40B-Eleanor`; it must remain
  unmodified.
- The source is bound to its remote commit through
  `scripts/verify-source-upstream-direct.py`; ordinary full-shard source
  manifests are prohibited.
- The first quantizer run is model-free, source-local, two-GPU, and never loads
  the complete model through `transformers`.

## Format

- `[ID] [P?] [Component] Description`
- `[P]` means parallelizable.

## Phase 1: Freeze and Preflight

Goal: establish immutable source provenance and reproducible local dependency inputs.

Definition of Done: direct-I/O source identity evidence, pinned submodule state, checkpoint
preflight, and configuration validation all pass without creating environments or
modifying checkpoint data.

Tasks:
- [ ] T001 [QA] Freeze the BF16 source manifest
  - DoD: `scripts/verify-source-upstream-direct.py --revision 7905312899185973580867f69d20d4cfc374ccaa` passes with aligned direct I/O. The buffered incident verifier and ordinary `sha256sum` are prohibited.
- [ ] T002 [P] [Infra] Verify pinned local dependencies
  - DoD: `git submodule status --recursive` resolves `vllm`, `llm-compressor`, and `compressed-tensors` to the contract commits with no dirty nested worktrees.
- [ ] T003 [Config] Validate source and profiles
  - DoD: `scripts/check-model.py`, `scripts/validate-quantize-config.py`, and `scripts/validate-runtime-config.py` pass after their MXFP8/64K implementation is complete.
- [ ] T004 [QA] Verify Blackwell capability before compression
  - DoD: `nvidia-smi --query-gpu=name,compute_cap --format=csv,noheader` records two RTX 5090 GPUs with capability at least 10.0.

Checkpoint: Phase 2 is blocked until all Phase 1 evidence is recorded.

## Dependencies & Execution Order

- Phase 1 blocks all later phases.
- T002 and T004 may run in parallel with T001; T003 follows the final profile implementation.
