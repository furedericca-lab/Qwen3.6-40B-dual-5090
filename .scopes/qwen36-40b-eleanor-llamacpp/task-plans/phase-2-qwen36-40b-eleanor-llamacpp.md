---
description: Task list for qwen36-40b-eleanor-llamacpp phase 2: first boot and startup.
---

# Tasks: qwen36-40b-eleanor-llamacpp Phase 2

## Phase 2: First-boot 128K startup

Goal: Launch `llama-server` at 128K context on dual RTX 5090 and verify it loads
without OOM or stability events.

Definition of Done: Server is running, `/health` returns OK, `/v1/models` lists
the model, and GPU memory usage is recorded.

Tasks:

- [ ] T010 [Infra] Launch llama-server at 128K context
  - DoD: `scripts/llama-server-first-boot.sh` starts and the model loads
    successfully at `-c 131072` on dual 5090.
  - Evidence: Server startup log showing successful load, layer split, and VRAM
    usage per GPU.

- [ ] T011 [QA] Verify API health
  - DoD: `curl http://127.0.0.1:8000/health` returns `{"status": "ok"}` or
    equivalent; `curl http://127.0.0.1:8000/v1/models` lists the model.
  - Evidence: curl outputs recorded.

- [ ] T012 [QA] Record GPU and RAM footprint and llama.cpp allocation log
  - DoD: `nvidia-smi` shows per-GPU VRAM usage; `free -h` shows host RAM usage.
    The llama-server startup log is saved, including: model buffer, KV buffer,
    recurrent/RS buffer, compute buffer, MTP/draft buffer, and fit result per GPU.
    Confirm no OOM, no swap thrashing.
  - Evidence: `nvidia-smi --query-gpu=memory.used,memory.total` and `free -h`.
    Startup allocation log saved (model buffer, KV buffer, RS buffer, compute
    buffer, draft/MTP buffer, fit result per GPU).

- [ ] T013 [Security] Verify localhost-only bind
  - DoD: Server is reachable on `127.0.0.1:8000` and not on `0.0.0.0` or LAN
    interface unless separately approved.
  - Evidence: `ss -tlnp | grep 8000` confirms bind address.

Checkpoint: Server is running stably at 128K and ready for behavior probes.

## OOM Recovery

If 128K startup fails with OOM, follow the ladder before reporting failure:

A. If auto-fit is slightly too conservative and more usable VRAM is needed,
   reduce the reserved fit margin:
   `--fit-target 2048,2048` → `1536,1536`

B. If compute/prefill OOM:
   `-ub 128` → `-ub 64`

C. If KV allocation does not fit:
   `-ctk f16 -ctv f16` → `-ctk q8_0 -ctv q8_0` (preserves 128K context)

D. Only then reduce context:
   `-c 131072` → `-c 65536`

Do not jump to context reduction before trying fit-target, batch, and KV
precision adjustments. Preserving 128K context is preferred over F16 KV.
