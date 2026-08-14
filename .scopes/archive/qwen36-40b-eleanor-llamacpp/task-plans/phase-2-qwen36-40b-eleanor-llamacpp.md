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

- [x] T010 [Infra] Launch llama-server at 128K context
  - DoD: `scripts/llama-server-first-boot.sh` starts and the model loads
    successfully at `-c 131072` on dual 5090.
  - Evidence: Server startup log showing successful load, MTP draft context
    creation, layer split. GPU0=26144 MiB, GPU1=28896 MiB. Kernel taint 4096.
    Build: merge commit 94e82e8ae, system_fingerprint b10439-94e82e8ae.

- [x] T011 [QA] Verify API health
  - DoD: `curl http://127.0.0.1:8000/health` returns `{"status": "ok"}`;
    `curl http://127.0.0.1:8000/v1/models` lists the model with n_ctx=131072,
    n_params=39497296128, ftype=Q8_0.
  - Evidence: curl outputs recorded.

- [x] T012 [QA] Record GPU and RAM footprint and llama.cpp allocation log
  - DoD: GPU0=26144 MiB, GPU1=28896 MiB (total ~55 GiB). System RAM: 5.6 GiB
    used, 37 GiB free. No swap thrashing (328 KiB swap used).
    MTP draft acceptance: 90-96% across 5 probes, mean draft len 2.4-2.8.
    Generation speed: 46-72 tok/s (varies by task). Prompt speed: 85-434 tok/s.
  - Evidence: nvidia-smi, free -h, server timing logs saved.

- [x] T013 [Security] Verify localhost-only bind
  - DoD: `ss -tlnp | grep 8000` confirms 127.0.0.1:8000 only.
  - Evidence: ss output recorded.

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
