---
description: Optimize Qwen3.6-40B-Eleanor deployment with profile-based launcher, rigorous benchmarking, and runtime tuning.
---

# Qwen3.6-40B Profile Optimization Contract

## Context

The base deployment (archived `.scopes/archive/qwen36-40b-eleanor-llamacpp/`)
is complete and verified: llama.cpp on dual RTX 5090, Q8_0 GGUF, 128K F16 KV,
MTP n=2/p=0 production default. This scope transitions from "one set of
parameters for everything" to a profile-based architecture with rigorous
benchmark tooling and systematic runtime optimization.

## Canonical Hardware/Runtime Baseline (Immutable)

These parameters are proven stable and must not change during this scope:

```text
--load-mode dio
-dev CUDA0,CUDA1
-sm layer
--fit on
--fit-target 2048,2048
-ctk f16 -ctv f16
-c 131072
-np 1
-b 512 -ub 128
-fa on
--host 127.0.0.1 --port 8000
```

Do not modify: `-ngl`, `--no-kv-offload`, CPU weight offload, or fit-target
reduction as OOM recovery.

## Profiles

| Profile | MTP | Sampling | Use Case | Positioning |
|---|---|---|---|---|
| agent | n=3, p=0 (candidate) | temp=0.6, top_p=0.95, top_k=20 | Hermes/Codex agents, coding | Primary optimization target |
| balanced | n=2, p=0 | temp=0.7, top_p=0.95, top_k=20 | General interaction | Stable fallback |
| thinking | winner of n2/n3 at temp=1.0 | temp=1.0, top_p=0.95, top_k=20 | Analysis, reasoning | Needs temp=1.0 benchmark |
| creative | MTP off | temp>1 or creative sampler | Creative, divergent | DavidAU: MTP off for temp>1 |
| long | 256K Q8_0 KV + MTP winner | profile sampling | Long-context retrieval | Functional extension |

Server sampling parameters become fallback defaults only. API callers should
pass their own sampler overrides per request.

## Optimization Targets (Priority Order)

1. **Fix benchmark tool**: exclude warm-up from stats, continuous power sampling
2. **temp=0.6 n2 vs n3**: confirm n=3 is >=8% faster at production temperature
3. **Agent profile default**: if n3 wins at temp=0.6, make it the default
4. **p_min sweep**: test p=0/0.05/0.10/0.20 for n=3, add n=4 if promising
5. **ubatch sweep**: ub=128/256/512 for prefill optimization
6. **reasoning + cache-reuse**: `--reasoning auto --reasoning-format deepseek --reasoning-preserve --cache-reuse 256`
7. **256K Q8 KV profile**: `-c 262144 -ctk q8_0 -ctv q8_0`

## Optimization Ranking Criteria

Do not rank by acceptance rate alone. Priority:

1. Final decode tok/s
2. P50/P95 decode latency
3. J/token (energy efficiency)
4. VRAM usage
5. Quality equality (no degradation)

Acceptance rate is a diagnostic metric, not an optimization target.

## Repeat Penalty Policy

Q8_0 with MTP: `repeat_penalty=1.0` always. DavidAU's 1.05-1.1 recommendation
targets lower quants. Only increase if looping is stably reproduced, and only
in a creative profile (1.02-1.05), never globally.

## Constraints

- Do not modify the archived deployment scope
- Do not modify the GGUF artifact or BF16 source
- All benchmark evidence must be reproducible from committed scripts
- The launcher script gains PROFILE support but remains backward-compatible
  (default PROFILE=agent once validated, fallback PROFILE=balanced)
