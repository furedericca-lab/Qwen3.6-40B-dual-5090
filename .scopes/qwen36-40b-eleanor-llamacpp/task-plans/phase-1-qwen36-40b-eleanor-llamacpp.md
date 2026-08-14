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

- [ ] T003 [Infra] Record clean boot state
  - DoD: Kernel version, taint (0 or 4096), no BAD_PAGE/Oops/Xid in current
    boot journal; idle GPUs; sufficient RAM.
  - Evidence: `uname -r`, `cat /proc/sys/kernel/tainted`, `journalctl -k -b`,
    `nvidia-smi`, `free -h` outputs recorded.

- [ ] T004 [Docs] Write launcher script
  - DoD: `scripts/llama-server-first-boot.sh` exists, is executable, and matches
    the runtime contract (128K, MTP, dual-GPU, layer split, DIO, F16 KV).
  - Evidence: `bash -n` syntax check passes; script content matches contract.

Checkpoint: Binary, artifact, and system are ready for Phase 2 startup test.
