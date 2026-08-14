---
description: Execution record for the Qwen3.6-40B-Eleanor MXFP8 W8A8 deployment.
---

# Phases Checklist: Qwen3.6-40B-Eleanor MXFP8 W8A8 Deployment

## Inputs

- `qwen3.6-40b-eleanor-deployment-contract.md`
- `qwen3.6-40b-eleanor-deployment-implementation-research-notes.md`
- `qwen3.6-40b-eleanor-deployment-scope-milestones.md`
- `qwen3.6-40b-eleanor-deployment-technical-documentation.md`
- `task-plans/phase-1-qwen3.6-40b-eleanor-deployment.md` through
  `task-plans/phase-5-qwen3.6-40b-eleanor-deployment.md`

## Status Board

| Phase | State | Completion | Health | Gate |
| --- | --- | --- | --- | --- |
| 1. Freeze and preflight | complete | 100% | source manifest and static checks passed | Phase 2 unlocked |
| 2. Golden MXFP8 build | complete | 100% | Golden output and direct-I/O manifest passed | Phase 3 unlocked |
| 3. 64K MTP-off boot | blocked | 35% | 0.90 baseline loads MXFP8 but lacks 64K KV capacity | record a post-baseline capacity profile before retry |
| 4. MTP-1 comparison | pending | 0% | baseline not measured | MTP-off/MTP-1 evidence compared |
| 5. Quality-gated V2 | deferred | 0% | no quality regression evidence | explicit evidence opens a separate candidate |

## Phase Execution Records

- 2026-08-13 Phase 1 complete: `/data/linux-fast` is ext4; the production
  output directory is absent; two RTX 5090 GPUs report compute capability 12.0
  and 32607 MiB each. The source SHA256 manifest contains 93 entries at
  `/data/linux-fast/models/Qwen3.6-40B-Eleanor-BF16.sha256`, whose SHA256 is
  `0f0b5833bc417d4d83d073d3aecc84b7335cf8ebc339b931e7b625049ba2d5b3`.
  `check-model.py`, `validate-quantize-config.py`, and
  `validate-runtime-config.py` passed. The fixed local source set is
  `vllm@5fee0a872dc31dd3476d61bb72b782b2d9d47492`,
  `llm-compressor@de46bfd53513aa87571a8b056a06aeaa5da1c69c`, and
  `compressed-tensors@ac8e2ba82f4e0d5eaa40069f8fc642738f124cd4`.
- 2026-08-13 source provenance strengthened: the user verified all 30 files in
  `/data/linux-fast/models/Qwen3.6-40B-Eleanor` byte-for-byte against
  the GitHub repository `DavidAU Qwen3.6-40B-Fable-Fusion-6-Core-Deckard-Eleanor-Heretic-Uncensored`
  commit `7905312899185973580867f69d20d4cfc374ccaa` (30 verified, zero missing
  or extra). The full source tree was then made read-only: regular files `0444`
  and directories `0555`.

### Phase 1: Freeze and Preflight

- [x] Source SHA256 manifest exists and is recorded separately from the model.
- [x] Three submodules resolve to the pinned commits.
- [x] Static source, quantization-profile, and runtime-profile validators pass.
- Evidence: 93-entry BF16 manifest; manifest SHA256
  `0f0b5833bc417d4d83d073d3aecc84b7335cf8ebc339b931e7b625049ba2d5b3`;
  remote-tree verification at `7905312899185973580867f69d20d4cfc374ccaa`;
  static validators passed; both GPUs report CC 12.0; source files/directories
  are respectively `0444`/`0555`.
- Blocker: none.
- Checkpoint: confirmed; Phase 2 is unblocked.

### Phase 2: Golden MXFP8 Build

- [x] Isolated quantizer environment installs from local pinned sources.
- [ ] `model_free_ptq` completes with `MXFP8`, two devices, two workers, and
  configured BF16 exclusions.
- [ ] Output has valid compressed-tensors W8A8 metadata, index, MTP, and SHA256 manifest.
- Evidence: `.quantize-venv` uses local `~/torch/dist` Torch
  `2.14.0a0.post20260719` and pytorch-triton `3.8.0+git694c0c3b.post20260719`;
  editable `llmcompressor 0.13.0` and `compressed-tensors 0.18.0` imported.
  Both RTX 5090 GPUs are CUDA-visible. A synthetic two-GPU `model_free_ptq`
  MXFP8 conversion emitted E4M3 weights, `torch.uint8` group-32 scales, dynamic
  group-32 input activations, `format=mxfp8-quantized`, and preserved ignored
  BF16 weights. The Torch 2.14 local build exceeds llmcompressor's declared
  `<=2.13.0` metadata bound, so this fixture is execution evidence but the
  Golden conversion remains a monitored compatibility gate.
- 2026-08-13 formal-build gate blocked: current kernel boot reports
  `bad_page+0x79/0x120` at `20:48:40`; `/proc/sys/kernel/tainted` is `4128`
  (`4096=O` external NVIDIA DKMS module plus `32=B` BAD_PAGE). The source remains read-only and its
  manifest SHA256 is unchanged; Golden output and staging directories remain
  absent; both GPUs are idle. Per the repository contract, no large checkpoint
  build or output manifest may run on this boot. Reboot, then re-run the clean
  kernel/NVIDIA, source, capacity, and quantizer gates before T006.
- 2026-08-13 trigger investigation prepared: the exact buffered remote verifier
  is now parameterized for fresh-boot bounded probes by shard, start offset,
  bytes, chunk size, and repeats. The wrapper records current-boot kernel logs,
  JSON read ranges, and optional `strace` read syscalls, then stops at the first
  new kernel signature. The first probe will use one shard and 1 MiB only;
  every later run changes one factor.
- 2026-08-13 clean-boot conversion accepted: taint remained `4096` (external
  NVIDIA DKMS module only), and the current boot had no `BAD_PAGE`, Oops, or
  NVIDIA Xid. The initial no-trace probe read 1 MiB from
  `model-00001-of-00017.safetensors` and passed without a new kernel event.
  Production direct-I/O verification then passed `30/30` source files at
  `7905312899185973580867f69d20d4cfc374ccaa`.
- 2026-08-13 Golden conversion passed: `model_free_ptq` distributed 18 shards
  across `cuda:0,cuda:1`, exited zero, and atomically promoted
  `/data/linux-fast/models/Qwen3.6-40B-Eleanor-MXFP8-W8A8`. The verifier found
  compressed-tensors `mxfp8-quantized` W8A8 metadata, group-32 uint8 scales,
  dynamic group-32 inputs, all configured BF16 exclusions including norms, and
  15 indexed MTP tensors. A direct-I/O manifest then passed for 30 output files
  at `/data/linux-fast/models/Qwen3.6-40B-Eleanor-MXFP8-W8A8.sha256`; its
  SHA256 is `61a2e80f1ee6ac33fc2d39901b630ef8d5350cdded586a061bc03d46f3ae76c9`.
- Blocker: none.
- Checkpoint: confirmed; Phase 3 is unblocked.

### Phase 3: 64K MTP-off Boot

- [x] Isolated vLLM environment installs from local pinned source.
- [ ] 64K TP=2 MTP-off server passes health, models, and deterministic chat smoke.
- [x] GPU memory usage and server command are recorded.
- Evidence: the project `.venv` uses local Torch `2.14.0a0.post20260719`,
  local `pytorch-triton 3.8.0+git694c0c3b.post20260719`, and local
  `torchvision 0.29.0a0.post20260719`; `triton` is owned only by the local
  pytorch-triton distribution. Pinned `vllm 0.27.2rc1.dev36+g5fee0a872.cu133`
  and local `compressed-tensors 0.18.1.dev0` import with the compiled CUDA
  extensions. The 2026-08-13 baseline command used TP=2, 64K, MTP off,
  BF16/auto KV, localhost, and `gpu-memory-utilization=0.90`. It loaded all 18
  MXFP8 shards, selected `FlashInferCutlassMxfp8LinearKernel`, and used 20.38
  GiB of model weights per GPU. After profiling, vLLM reported 1.15 GiB of KV
  cache against a 3.23 GiB one-request 64K requirement, estimating a 20,384
  token maximum; it exited before binding port 8000. GPU memory returned to 15
  MiB on both devices and no new kernel Oops, BAD_PAGE, Xid, or segfault was
  observed. Log: `logs/vllm-first-boot-20260813T141817Z.log`.
- Blocker: the fixed 0.90 capacity profile cannot satisfy the 64K requirement.
- Checkpoint: not confirmed.

### Phase 4: MTP-1 Comparison

- [ ] MTP-1 uses the same checkpoint and MTP-off server profile plus only the
  speculative configuration.
- [ ] Equivalent smoke and benchmark records compare MTP-off and MTP-1.
- Evidence: not run.
- Blocker: Phase 3.
- Checkpoint: not confirmed.

### Phase 5: Quality-Gated V2

- [ ] Quality evidence identifies a material MXFP8 regression, or explicitly
  closes this phase as unnecessary.
- [ ] Any HQ V2 or AutoRound candidate uses a distinct output path and scope.
- Evidence: not run.
- Blocker: Phase 4 and quality comparison.
- Checkpoint: deferred.

## Release Gate

The Golden checkpoint becomes deployable only after Phases 1-3 pass. MTP-1 is
an optional production promotion after Phase 4. Phase 5 never modifies the
Golden output.


## Archive Record

- Archived on 2026-08-14 under `.scopes/archive/qwen3.6-40b-eleanor-deployment/`.
- Archive purpose: preserve the completed qwen3.6-40b-eleanor-deployment audit trail.
- Future enhancements should use a new `repo-task-driven` scope under `.scopes/<enhancement-scope>/`.
- Archived docs should only change for factual errata or path-maintenance updates.
