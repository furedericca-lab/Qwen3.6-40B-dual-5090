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

- [ ] T012 [QA] Record GPU and RAM footprint
  - DoD: `nvidia-smi` shows per-GPU VRAM usage; `free -h` shows host RAM usage.
    Confirm no OOM, no swap thrashing.
  - Evidence: `nvidia-smi --query-gpu=memory.used,memory.total` and `free -h`.

- [ ] T013 [Security] Verify localhost-only bind
  - DoD: Server is reachable on `127.0.0.1:8000` and not on `0.0.0.0` or LAN
    interface unless separately approved.
  - Evidence: `ss -tlnp | grep 8000` confirms bind address.

Checkpoint: Server is running stably at 128K and ready for behavior probes.

## OOM Recovery

If 128K startup fails with OOM, follow the ladder before reporting failure:

1. Reduce `-b 512 -ub 128` to `-b 256 -ub 64`
2. Reduce `-c 131072` to `-c 65536`
3. Record the failure and escalate
