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
| Phase 1: Build and preflight | In Progress | 50% | Good | 0 |
| Phase 2: First-boot 128K startup | Not Started | 0% | Unknown | 0 |
| Phase 3: Behavior probes | Not Started | 0% | Unknown | 0 |
| Phase 4: MTP comparison | Not Started | 0% | Unknown | 0 |

## Phase Entry Links
1. [phase-1-qwen36-40b-eleanor-llamacpp.md](phase-1-qwen36-40b-eleanor-llamacpp.md)
2. [phase-2-qwen36-40b-eleanor-llamacpp.md](phase-2-qwen36-40b-eleanor-llamacpp.md)
3. [phase-3-qwen36-40b-eleanor-llamacpp.md](phase-3-qwen36-40b-eleanor-llamacpp.md)
4. [phase-4-qwen36-40b-eleanor-llamacpp.md](phase-4-qwen36-40b-eleanor-llamacpp.md)

## Phase Execution Records

### Phase 1 partial — 2026-08-14
- Phase: 1
- Batch date: 2026-08-14
- Completed tasks: T001 (llama.cpp compiled sm_120a), T002 (GGUF metadata verified)
- Evidence commands:
  - `llama-server --list-devices` shows CUDA0/CUDA1 RTX 5090
  - GGUF metadata: qwen35 arch, 97 blocks, Q8_0, nextn_predict_layers=1, 1290 tensors
- Issues/blockers: None
- Resolutions: N/A
- Checkpoint confirmed: No (T003, T004 pending)

## Final Release Gate
- Scope constraints preserved.
- Quality/security gates passed.
- Remaining risks documented.
