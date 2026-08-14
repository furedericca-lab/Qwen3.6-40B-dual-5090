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
| Phase 2: First-boot 128K startup | Complete | 100% | Good | 0 |
| Phase 3: Behavior probes | Complete | 100% | Good | 0 |
| Phase 4: MTP comparison | Complete | 100% | Good | 0 |

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
- Parameter analysis: 128K F16 KV budget = ~12.0 GiB main KV (24 dense layers * 4 kv heads * 256 head_dim * 131072 * 2 bytes * 2 for K+V) + ~0.5 GiB MTP draft KV. --fit-target set to 2048,2048 (runtime VRAM margin per GPU, not KV reservation). --no-kv-offload REMOVED: in llama.cpp KV offload to GPU is the default; --no-kv-offload would force KV to CPU. MTP: --spec-type draft-mtp --spec-draft-n-max 2 (n-max=3 Qwen3.6 drift bug #23302 was closed — Q8_0 unaffected at n=1-5; n-max=2 is the conservative baseline, not final), --spec-draft-n-min 0, --spec-draft-p-min 0.75 (baseline value, Phase 4 will test p_min=0 vs 0.75). Sampling: --top-k 20 --min-p 0 --repeat-penalty 1.0 (Qwen3.6 official coding params). MTP_MODE: MTP on/off controlled via MTP_MODE env var, not $@ --spec-type none (llama.cpp appends spec types into a bitmask, so draft-mtp + none still enables MTP).
- Issues/blockers: None
- Resolutions: N/A
- Checkpoint confirmed: Yes — binary, artifact, system, and launcher are ready for Phase 2

### Phase 2+3 complete — 2026-08-14
- Phase: 2+3
- Batch date: 2026-08-14
- Upstream sync: llama.cpp fork efb81ab merged with upstream/master 885c5bb (42 commits), merge commit 94e82e8ae. No conflicts. DIO patches preserved. Recompiled and verified.
- Completed tasks: T010 (128K startup successful, GPU0=26144 MiB, GPU1=28896 MiB), T011 (/health OK, /v1/models lists model with n_ctx=131072), T012 (GPU/RAM footprint recorded, MTP draft acceptance 90-96%, gen 46-72 tok/s, prompt 85-434 tok/s), T013 (localhost-only bind confirmed on 127.0.0.1:8000)
- Behavior probes (Phase 3 inline): math (2+3=5, correct), Chinese (quantum computing explanation, fluent), JSON (valid object, correct), Python (merge_sorted_lists, correct), summary (3 bullet points, accurate)
- Evidence commands:
  - `llama-server --list-devices` shows CUDA0/CUDA1 RTX 5090
  - `curl http://127.0.0.1:8000/health` returns `{"status": "ok"}`
  - `curl http://127.0.0.1:8000/v1/models` returns model metadata: n_ctx=131072, n_params=39497296128, ftype=Q8_0
  - `nvidia-smi`: GPU0=26144 MiB, GPU1=28896 MiB, both idle after shutdown
  - `free -h`: 5.6 GiB used, 37 GiB free, 328 KiB swap
  - `ss -tlnp | grep 8000`: 127.0.0.1:8000 only
  - `cat /proc/sys/kernel/tainted`: 4096 (DKMS O only, no BAD_PAGE)
  - `sudo dmesg | grep -iE 'BAD_PAGE|Oops|Xid'`: only RTL8125B NIC XID, no GPU errors
  - MTP draft acceptance: 93.75% (math), 90.74% (Chinese), 96.25% (JSON), 95.15% (Python), 92.80% (summary)
  - Generation speed: 46.9-71.8 tok/s (varies by task), mean ~52 tok/s at n-max=2
  - system_fingerprint: b10439-94e82e8ae (confirms merge commit build)
- Issues/blockers: None
- Resolutions: N/A
- Checkpoint confirmed: Yes — server runs stably at 128K with MTP, all probes pass

## Final Release Gate
- Scope constraints preserved.
- Quality/security gates passed.
- Remaining risks documented.

### Phase 4 complete — 2026-08-14
- Phase: 4
- Batch date: 2026-08-14
- Completed tasks: T030 (MTP-off baseline: 34.71 tok/s), T031 (MTP-on baseline n=2/p=0.75: 63.10 tok/s), T032 (quality verified across all configs), T033 (4-config throughput comparison), T034 (docs updated to production default n=2/p=0)
- Evidence commands:
  - `ls evidence/mtp-comparison/` shows 5 configurations x 5 probes + RESULTS.md
  - MTP-off mean: 34.71 tok/s (baseline)
  - n=2/p=0 mean: 73.52 tok/s (2.12x, 82.9% acceptance) ← production default
  - n=2/p=0.75 mean: 63.10 tok/s (1.82x, 94.1% acceptance)
  - n=3/p=0 mean: 78.60 tok/s (2.26x, 69.9% acceptance)
  - n=3/p=0.75 mean: 69.90 tok/s (2.01x, 93.5% acceptance)
  - All quality probes pass: correct math, fluent Chinese, valid JSON, correct Python, accurate summary
  - Kernel taint 4096 (normal), no BAD_PAGE/Oops/Xid across all runs
  - VRAM: 52-54 GiB total depending on config, all within dual-5090 budget
- Issues/blockers: None
- Resolutions: N/A
- Checkpoint confirmed: Yes — all 4 phases complete, production default is n=2/p=0
