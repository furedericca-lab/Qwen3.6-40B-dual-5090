---
description: Task list for qwen36-40b-eleanor-llamacpp phase 1: build and preflight.
---

# Tasks: qwen36-40b-eleanor-llamacpp Phase 1

## Phase 1: Build llama.cpp and verify preflight

Goal: Compile the pinned llama.cpp fork with CUDA for RTX 5090 and verify the
GGUF artifact metadata and system readiness.

Definition of Done: `llama-server` binary exists, sees both GPUs, and the GGUF
artifact metadata matches the contract.

Tasks:

- [x] T001 [Infra] Build llama.cpp with CUDA sm_120a
  - DoD: `llama.cpp/build/bin/llama-server` exists and `--list-devices` shows
    CUDA0 and CUDA1 as RTX 5090.
  - Evidence: build exit 0; `llama-server --list-devices` output recorded.

- [x] T002 [QA] Verify GGUF artifact metadata
  - DoD: GGUF header confirms `qwen35` architecture, 97 blocks, Q8_0 file type,
    `nextn_predict_layers: 1`, 1290 tensors, embedded imatrix.
  - Evidence: `gguf_reader` metadata dump recorded.
  - Extended: Verified `head_dim=256` (from `attn_k.weight` shape `5120x1024`),
    24 dense attention backbone layers (at indices 3,7,11,...,95), 1 MTP draft
    layer (blk.96.nextn, separate KV ~0.5 GiB at 128K), 72 SSM layers. Main model
    KV cache budget for 128K F16 calculated at ~12.0 GiB total (~6.0 GiB/GPU).

- [x] T003 [Infra] Record clean boot state
  - DoD: Kernel version, taint (0 or 4096), no BAD_PAGE/Oops/Xid in current
    boot journal; idle GPUs; sufficient RAM.
  - Evidence: `uname -r` = 7.0.0-28-generic, taint=4096 (DKMS O), no
    BAD_PAGE/Oops/NVIDIA-Xid in journal; both GPUs idle (2 MiB used);
    40 GiB RAM free.

- [x] T004 [Docs] Write launcher script
  - DoD: `scripts/llama-server-first-boot.sh` exists, is executable, and matches
    the runtime contract (128K, MTP, dual-GPU, layer split, DIO, F16 KV).
  - Evidence: `bash -n` syntax check passes; script content matches contract.
  - Parameters: `--fit-target 2048,2048` (target VRAM margin per GPU after
    fitting, not KV reservation), `--spec-type draft-mtp --spec-draft-n-max 2
    --spec-draft-n-min 0 --spec-draft-p-min 0.75` (n-max=2 because n-max=3
    has a Qwen3.6 output drift bug, p-min=0.75 to prune low-confidence drafts).
    No `--no-kv-offload` (KV offload to GPU is the default; --no-kv-offload
    would force KV to CPU/RAM).

Checkpoint: Binary, artifact, and system are ready for Phase 2 startup test.
