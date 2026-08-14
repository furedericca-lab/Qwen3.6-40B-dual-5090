---
description: Milestones for qwen36-40b-profile-optimization scope.
---

# Qwen3.6-40B Profile Optimization Milestones

## Phase 1: Benchmark tooling and temp=0.6 validation

Goal: Fix benchmark tool, re-run n2/n3 at production temperature, confirm
agent profile default.

- [ ] T001 Fix benchmark-mtp.sh: exclude warm-up, continuous power sampling, P95 latency
- [ ] T002 Benchmark n=2/p=0 at temp=0.6 with fixed tool
- [ ] T003 Benchmark n=3/p=0 at temp=0.6 with fixed tool
- [ ] T004 Decide agent profile default (n=2 or n=3)
- [ ] T005 Profile-based launcher: add PROFILE env var support
- [ ] T006 Update all docs to reflect new profile architecture

Checkpoint: Agent profile has a validated default; launcher supports profiles.

## Phase 2: MTP and ubatch optimization

Goal: Find optimal p_min for n=3, test n=4, optimize ubatch for prefill.

- [ ] T007 p_min sweep for n=3: p=0/0.05/0.10/0.20
- [ ] T008 Test n=4/p=0 and n=4/p=best-p_min if n=3 p_min sweep is promising
- [ ] T009 ubatch sweep: ub=128/256/512 at 8K and 66K prompt lengths
- [ ] T010 Record final MTP and ubatch recommendations per profile

Checkpoint: MTP and ubatch parameters are optimized per profile.

## Phase 3: Agent acceleration features

Goal: Add reasoning preserve and prompt cache reuse for agent workloads.

- [ ] T011 Enable --reasoning auto --reasoning-format deepseek --reasoning-preserve
- [ ] T012 Test --cache-reuse 256 with 10-turn agent benchmark
- [ ] T013 Record agent acceleration evidence

Checkpoint: Agent profile has full acceleration feature set.

## Phase 4: Long-context profile

Goal: Test 256K Q8_0 KV context as a separate profile.

- [ ] T014 Test 256K context with Q8_0 KV (-c 262144 -ctk q8_0 -ctv q8_0)
- [ ] T015 Run retrieval benchmarks at 32K/64K/128K/220K+
- [ ] T016 Record long-context quality and capacity evidence

Checkpoint: Long-context profile validated or documented as not viable.

## Phase 5: Documentation and archive

Goal: Finalize all docs, update wiki, archive scope.

- [ ] T017 Update AGENTS.md, README.md, contracts with final profile specs
- [ ] T018 Update wiki how-to and decisions with optimization results
- [ ] T019 Archive scope

Checkpoint: All optimization work documented and archived.
