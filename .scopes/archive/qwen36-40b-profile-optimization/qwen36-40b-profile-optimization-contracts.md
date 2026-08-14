---
description: Optimize Qwen3.6-40B-Eleanor deployment with profile-based launcher, rigorous benchmarking, and runtime tuning.
---

# Qwen3.6-40B Profile Optimization Contract

## Context

The base deployment (archived `.scopes/archive/qwen36-40b-eleanor-llamacpp/`)
is complete and verified: llama.cpp on dual RTX 5090, Q8_0 GGUF, 128K F16 KV,
MTP n=2/p=0 production default. This scope transitions from "one set of
parameters for everything" to a 3-profile architecture with rigorous benchmark
tooling and systematic runtime optimization.

## Canonical Hardware Baseline (Immutable)

These parameters are proven stable and must not change during this scope:

```text
--load-mode dio
-dev CUDA0,CUDA1
-sm layer
--fit on
--fit-target 2048,4096
-fa on
--host 127.0.0.1 --port 8000
```

Do not modify: `-ngl`, `--no-kv-offload`, CPU weight offload, or fit-target
reduction as OOM recovery.

## Tunable Runtime Baseline (Frozen)

```text
-ctk f16 -ctv f16
-c 131072
-np 1
-b 1024 -ub 256
```

These were optimized during Phase 1-2 and are now frozen. `b=1024` and `ub=256`
are the validated defaults for all profiles.

## Three-Profile Architecture

| Profile | MTP | Sampling | Use Case |
|---|---|---|---|
| agent (default) | n=3, p=0 | temp=0.6, top_p=0.95, top_k=20 | Agent/Coding, reasoning-preserve |
| general | n=3, p=0 | temp=0.7, top_p=0.95, top_k=20 | Chat, analysis, reasoning-preserve |
| long | n=3, p=0 | temp=0.6 | 256K Q8_0 KV, retrieval up to ~172K |

All three profiles share the same MTP configuration (n=3/p=0). The only
differences are sampling fallbacks and, for the long profile, context/KV type.

reasoning-preserve is enabled for agent and general profiles (net positive
for agent workloads, per T011). The long profile uses empty reasoning_args
to maximize context capacity.

Creative work does not get a separate profile. For high-temperature creative
use, API callers should pass their own sampler overrides (e.g. temp=1.0,
top_k=40, min_p=0.05). If temp>1, disable MTP via `MTP_MODE=off`.

Server sampling parameters are fallback defaults only. API callers should
pass their own sampler overrides per request.

### Profile Rationale

- **n=3/p=0 for all profiles**: At temp=0.6, n=3 is 8.0% faster than n=2
  (73.76 vs 68.30 tok/s). At temp=0.7, n=3 is 8.6% faster than n=2
  (75.02 vs 69.10 tok/s). Both exceed the 5% threshold. n=3 is also more
  energy-efficient at both temperatures (8.46 vs 8.75 J/token at 0.6,
  8.36 vs 9.08 J/token at 0.7).
- **No "balanced" or "creative" profile**: The old 4-profile scheme had
  overlap. n=3/p=0 is optimal for both agent and general use. Creative
  sampling is a per-request override, not a server profile.
- **long profile changes memory architecture**: 256K Q8_0 KV is the only
  profile that genuinely changes resource allocation. Decode speed drops ~52%
  vs 128K (44 vs 92 tok/s short prompt), and retrieval works up to ~172K tokens.
  Documented as a trade-off, no longer experimental.

## Optimization Targets (Priority Order)

1. ~~Fix benchmark tool~~ — Done (T001)
2. ~~temp=0.6 n2 vs n3~~ — Done: n=3 wins by 8.0% (T002-T004)
3. ~~Agent profile default~~ — Done: n=3/p=0 (T004-T005)
4. ~~p_min sweep~~ — Done: p_min=0 is only viable setting (T007)
5. ~~ubatch sweep~~ — Done: ub=256 frozen (T009)
6. ~~n=4 test~~ — Done: slower than n=3, excluded (T008)
7. **reasoning-preserve** — Done: net neutral or slight gain (T011)
8. **cache-reuse** — Unsupported (T012: "not supported by this context")
9. **VRAM balance** — Done: 2048,4096 maximizes min(free) at 4,033 MiB (T014)
10. **128K Q8_0 KV** — Done: zero quality/perf loss vs F16 (T015)
11. **256K Q8_0 KV** — Done: viable, retrieval up to ~172K, decode -52% vs 128K (T016-T018)

## Optimization Ranking Criteria

Do not rank by acceptance rate alone. Priority:

1. Final decode tok/s
2. P50/P95 decode latency
3. J/token (energy efficiency)
4. VRAM usage
5. Quality equality (no degradation)

Acceptance rate is a diagnostic metric, not an optimization target.

## Closed Optimization Decisions

These parameters are frozen — no further exploration needed:

```text
MTP p_min     → 0 (sweep showed no effect; model confidence always >0.20)
MTP n_max     → 3 (n=4 slower than n=3 at all tested temperatures)
ubatch        → 256 (ub=512 OOM; ub=128 gives -20-34% prefill)
batch         → 1024 (b=2048 showed no benefit)
repeat_penalty → 1.0
fit-target    → 2048,4096 (maximizes min(GPU_free) at 4,033 MiB; +44% vs 2048,2048)
KV type       → F16 for agent/general; Q8_0 for long
context       → 128K for agent/general; 256K for long
cache-reuse   → unsupported (hybrid architecture not compatible)
```

## Repeat Penalty Policy

`repeat_penalty=1.0` always for all profiles. Q8_0 with MTP does not benefit
from repeat penalty. DavidAU's 1.05-1.1 recommendation targets lower quants.
Only increase if looping is stably reproduced, and only via per-request
override (1.02-1.05), never globally.

## Constraints

- Do not modify the archived deployment scope
- Do not modify the GGUF artifact or BF16 source
- All benchmark evidence must be reproducible from committed scripts
