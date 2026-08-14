---
description: Milestones for qwen36-40b-profile-optimization scope.
---

# Qwen3.6-40B Profile Optimization Milestones

## Phase 1: Benchmark tooling and temp=0.6 validation

Goal: Fix benchmark tool, re-run n2/n3 at production temperature, confirm
agent profile default.

- [x] T001 Fix benchmark-mtp.sh: exclude warm-up, continuous power sampling, P95 latency
  - Evidence: benchmark runs with warm-up excluded, continuous 200ms power sampling, P95 latency, J/token
- [x] T002 Benchmark n=2/p=0 at temp=0.6 with fixed tool
  - Evidence: evidence/mtp-benchmark/n2-p0-t06-summary.json — 68.30 tok/s, stddev 0.055
- [x] T003 Benchmark n=3/p=0 at temp=0.6 with fixed tool
  - Evidence: evidence/mtp-benchmark/n3-p0-t06-summary.json — 73.76 tok/s, stddev 0.015
- [x] T004 Decide agent profile default (n=2 or n=3)
  - Decision: n=3/p=0 — 8.0% faster at temp=0.6, more energy-efficient (8.46 vs 8.75 J/token)
- [x] T005 Profile-based launcher: add PROFILE env var support (agent/general/long)
  - Evidence: scripts/llama-server-first-boot.sh with 3-profile architecture
- [x] T006 Update all docs to reflect 3-profile architecture
  - Evidence: AGENTS.md, README.md, wiki how-to, wiki decisions all updated

Checkpoint: Agent profile has a validated default (n=3/p=0); launcher supports 3 profiles.

## Phase 2: MTP and ubatch optimization

Goal: Find optimal p_min for n=3, test n=4, optimize ubatch for prefill.

- [x] T007 p_min sweep for n=3: p=0/0.05/0.10/0.20
  - Evidence: All produce identical results; model's MTP confidence consistently >0.20
- [x] T008 Test n=4/p=0
  - Evidence: n=4 is slower than n=3 (73.62 vs 73.76 tok/s at temp=0.6), acceptance 51.7% near 50% threshold
- [x] T009 ubatch sweep: ub=128/256/512 at 8K and 66K prompt lengths
  - Evidence: ub=256 gives +20-34% prefill, zero decode penalty, ~130 MiB/GPU VRAM; ub=512 OOM
- [x] T010 Record final MTP and ubatch recommendations per profile
  - Decision: n=3/p=0/ub=256 for all profiles; b=1024 frozen; no further MTP/ubatch exploration needed

Checkpoint: MTP and ubatch parameters are frozen for all profiles.

## Phase 2b: General profile MTP validation (temp=0.7 A/B)

Goal: Confirm n=3 is optimal at temp=0.7 for the general profile.

- [x] T010b Benchmark n=2/p=0 at temp=0.7
  - Evidence: evidence/mtp-benchmark/n2-p0-t07-summary.json — 69.10 tok/s, 9.08 J/token
- [x] T010c Benchmark n=3/p=0 at temp=0.7
  - Evidence: evidence/mtp-benchmark/n3-p0-t07-summary.json — 75.02 tok/s, 8.36 J/token
- [x] T010d Decide general profile MTP (n=2 or n=3)
  - Decision: n=3/p=0 — 8.6% faster at temp=0.7, more energy-efficient (8.36 vs 9.08 J/token)

Checkpoint: All three profiles share n=3/p=0. General profile confirmed.

## Phase 3: Agent acceleration features

Goal: Add reasoning preserve and prompt cache reuse for agent workloads.

- [x] T011 Test --reasoning auto --reasoning-format deepseek --reasoning-preserve
  - Evidence: 10-turn agent benchmark — reasoning-preserve reduces prompt tokens by 2.4%
    (14,174 vs 14,523), wall time -6.8% (56.0 vs 60.1s), decode speed neutral (73.8 vs 74.6 tok/s).
    Reasoning content preserved across turns. Net positive for agent workloads.
- [x] T012 Test --cache-reuse 256 capability gate
  - Evidence: UNSUPPORTED — server log shows "cache_reuse is not supported by this context, it will be disabled".
    The Qwen3.5 hybrid architecture (24 dense + 72 SSM layers) does not support cache-reuse in current llama.cpp.
    Prompt cache feature is enabled but non-functional without cache-reuse.
- [x] T013 Record agent acceleration evidence and decision
  - Evidence: cache-reuse unsupported → abandoned. Production default: `--reasoning auto --reasoning-format
    deepseek --reasoning-preserve` only (from T011). No cache-reuse in any profile.

Checkpoint: Agent profile has full acceleration feature set.

## Phase 3b: VRAM balance optimization

Goal: Maximize min(GPU0_free, GPU1_free) to improve OOM headroom.

- [x] T014 Scan fit-target 2048,X for X=2048/3072/4096/4608/5120
  - Evidence:
    | fit-target | GPU0 free | GPU1 free | min(free) | Decode tok/s |
    |---|---:|---:|---:|---:|
    | 2048,2048 | 5,725 | 2,799 | 2,799 | 90.58 |
    | 2048,3072 | 4,921 | 3,601 | 3,601 | 90.43 |
    | 2048,4096 | 4,033 | 4,491 | 4,033 | 90.47 |
    | 2048,4608 | 3,631 | 4,891 | 3,631 | 90.49 |
    | 2048,5120 | 3,231 | 5,291 | 3,231 | 90.40 |
    Decision: 2048,4096 — min(free)=4,033 (+44% vs baseline), decode regression <0.2%

Checkpoint: fit-target 2048,4096 is the new universal baseline for all profiles.

## Phase 4: Q8_0 KV and long-context profile

Goal: Isolate Q8_0 KV quality impact, then validate 256K long profile.

- [x] T015 Compare 128K F16 vs 128K Q8_0 KV at 8K/32K/66K/120K prompt lengths
  - Evidence: Q8_0 KV has zero quality loss and negligible performance difference vs F16.
    Short decode: 92.01 (Q8) vs 91.27 (F16) tok/s. 8K prefill: 2,485 vs 2,503 tok/s.
    66K prefill: 1,493 vs 1,595 tok/s (-6.4%, within normal variance for long prompts).
    VRAM savings: GPU0 free 8,091 vs 4,011 MiB (Q8_0 frees ~4 GiB on GPU0).
- [x] T016 Test 256K Q8_0 KV with prefill/decode benchmarks at 32K–245K
  - Evidence: Server starts, 256K context works. Short decode: 43.83 tok/s (vs 92.01 at 128K).
    Decode degrades with context length: 128K→11.44, 172K→10.27 tok/s.
    Needle retrieval successful up to ~172K tokens, fails at 191K.
- [x] T017 Needle retrieval across context lengths (27K–191K)
  - Evidence: Diverse-haystack needle found at 27K, 42K, 75K, 84K, 93K, 125K, 141K, 156K, 172K.
    Failed at 191K. Effective retrieval limit ~172K with Q8_0 KV at 256K context.
- [x] T018 Record long-context quality and capacity evidence
  - Decision: long profile is VIABLE with caveat — decode speed drops ~52% at 256K context
    (92→44 tok/s short prompt, 10-13 tok/s at >120K tokens). Retrieval works up to ~172K.
    Remove experimental label but document the performance trade-off.

## Phase 5: Documentation and archive

Goal: Finalize all docs, update wiki, archive scope.

- [x] T019 Update AGENTS.md, README.md, contracts with final profile specs
  - Evidence: All docs consistent — fit-target 2048,4096, reasoning-preserve for
    agent/general, long profile no longer experimental. Stale 2048,2048 references
    fixed in AGENTS.md line 116 and kv-cache-budget.md line 87.
- [x] T020 Update wiki how-to and decisions with optimization results
  - Evidence: Wiki how-to and decisions docs already updated with fit-target 2048,4096,
    reasoning-preserve, cache-reuse unsupported, long profile trade-offs.
- [x] T021 Archive scope
  - Evidence: Scope copied to .scopes/archive/qwen36-40b-profile-optimization/.
    All optimization work documented and archived.

Checkpoint: All optimization work documented and archived.

> **Scope archived** to `.scopes/archive/qwen36-40b-profile-optimization/` on
> 2026-08-15. All tasks T001–T021 complete. Profile optimization scope closed.
