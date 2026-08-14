---
description: Execution and verification checklist for qwen36-40b-eleanor-llamacpp 4-phase plan.
---

# Phases Checklist: qwen36-40b-eleanor-llamacpp

## Input
- Canonical docs under:
  - `.scopes/qwen36-40b-eleanor-llamacpp`
  - `.scopes/qwen36-40b-eleanor-llamacpp/task-plans`

## Rules
- Use this file as the single progress and audit hub.
- Update status, evidence commands, and blockers after each implementation batch.
- Do not mark a phase complete without evidence.

## Global Status Board
| Phase | Status | Completion | Health | Blockers |
|---|---|---|---|---|
| Phase 1: Build and preflight | Complete | 100% | Good | 0 |
| Phase 2: First-boot 128K startup | Not Started | 0% | Unknown | 0 |
| Phase 3: Behavior probes | Not Started | 0% | Unknown | 0 |
| Phase 4: MTP comparison | Not Started | 0% | Unknown | 0 |

## Phase Entry Links
1. [phase-1-qwen36-40b-eleanor-llamacpp.md](phase-1-qwen36-40b-eleanor-llamacpp.md)
2. [phase-2-qwen36-40b-eleanor-llamacpp.md](phase-2-qwen36-40b-eleanor-llamacpp.md)
3. [phase-3-qwen36-40b-eleanor-llamacpp.md](phase-3-qwen36-40b-eleanor-llamacpp.md)
4. [phase-4-qwen36-40b-eleanor-llamacpp.md](phase-4-qwen36-40b-eleanor-llamacpp.md)

## Phase Execution Records

### Phase 1 complete — 2026-08-14
- Phase: 1
- Batch date: 2026-08-14
- Completed tasks: T001 (llama.cpp compiled sm_120a), T002 (GGUF metadata verified, head_dim=256, 24 dense attn layers + 1 MTP draft), T003 (clean boot state recorded), T004 (launcher script written)
- Evidence commands:
  - `llama-server --list-devices` shows CUDA0/CUDA1 RTX 5090
  - GGUF metadata: qwen35 arch, 97 blocks, Q8_0, nextn_predict_layers=1, 1290 tensors, head_dim=256, 24 dense/72 SSM layers + 1 MTP draft layer
  - `uname -r` = 7.0.0-28-generic, taint=4096 (DKMS O), no BAD_PAGE/Oops/NVIDIA-Xid
  - `nvidia-smi` shows both GPUs idle (2 MiB used), `free -h` shows 40 GiB free
  - `bash -n scripts/llama-server-first-boot.sh` passes
- Parameter analysis: 128K F16 KV budget = ~12.0 GiB main KV (24 dense layers * 4 kv heads * 256 head_dim * 131072 * 2 bytes * 2 for K+V) + ~0.5 GiB MTP draft KV. --fit-target set to 2048,2048 (runtime VRAM margin per GPU, not KV reservation). --no-kv-offload REMOVED: in llama.cpp KV offload to GPU is the default; --no-kv-offload would force KV to CPU. MTP: --spec-type draft-mtp --spec-draft-n-max 2 (n-max=3 has a known Qwen3.6 output drift bug, n-max=2 is author-recommended), --spec-draft-n-min 0, --spec-draft-p-min 0.75. Sampling: --top-k 20 --min-p 0 --repeat-penalty 1.0 (Eleanor author recommendation for coding). MTP_MODE: MTP on/off controlled via MTP_MODE env var, not $@ --spec-type none (llama.cpp appends spec types into a bitmask, so draft-mtp + none still enables MTP).
- Issues/blockers: None
- Resolutions: N/A
- Checkpoint confirmed: Yes — binary, artifact, system, and launcher are ready for Phase 2

## Final Release Gate
- Scope constraints preserved.
- Quality/security gates passed.
- Remaining risks documented.
