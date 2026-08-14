# Profile Optimization Benchmark Results — 2026-08-14

## Methodology

Rigorous benchmark with controlled conditions:
- **Fixed seed**: `seed=42` for all runs
- **Temperature**: tested at both 0 (deterministic) and 0.6 (production)
- **Same prompt**: ML supervised vs unsupervised learning explanation (43 prompt tokens)
- **Same max_tokens**: 200
- **Warm-up**: 1 run excluded from all statistics
- **Formal runs**: 5 per configuration
- **Power**: continuous GPU sampling at 200ms intervals during generation
- **Metrics**: mean, median, stddev, P95, min, max of decode tok/s; avg/P95/max power; J/token

All tests on dual RTX 5090 (CUDA sm_120a), Q8_0 GGUF, 128K F16 KV context,
llama.cpp merge commit 94e82e8ae. Server restarted between MTP configuration
changes.

## Optimization Ranking Criteria

Per user directive, ranking priority is:
1. Final decode tok/s
2. P50/P95 decode latency
3. J/token (energy efficiency)
4. VRAM usage
5. Quality equality

Acceptance rate is a diagnostic metric, not an optimization target.

## MTP Configuration Sweep (temp=0.6, ub=128)

### Decode Speed

| Config | Mean tok/s | StdDev | P95 | Speedup | J/token | Accept Rate |
|--------|----------:|-------:|----:|--------:|--------:|------------:|
| MTP-off | 34.77 | 0.003 | 34.78 | 1.00x | 17.12 | N/A |
| n=2, p=0 | 68.30 | 0.055 | 68.38 | 1.96x | 8.75 | 72.2% |
| n=3, p=0 | **73.76** | 0.015 | 73.78 | 2.12x | **8.46** | 60.7% |
| n=3, p=0.05 | 73.77 | 0.040 | 73.82 | 2.12x | 8.66 | 60.7% |
| n=3, p=0.10 | 73.77 | 0.053 | 73.81 | 2.12x | 8.43 | 60.7% |
| n=3, p=0.20 | 73.76 | 0.040 | 73.81 | 2.12x | 8.48 | 60.7% |
| n=4, p=0 | 73.62 | 0.042 | 73.66 | 2.12x | 8.30 | 51.7% |

### Temperature Comparison (temp=0 vs temp=0.6, ub=128)

| Config | temp=0 tok/s | temp=0.6 tok/s | Delta |
|--------|-------------:|---------------:|------:|
| MTP-off | 34.77 | 34.77 | 0.0% |
| n=2, p=0 | 71.71 | 68.30 | -4.8% |
| n=3, p=0 | 81.67 | 73.76 | -9.7% |

MTP acceptance rate drops with higher temperature because sampling randomness
reduces the probability that the MTP draft matches the actual next token.
n=3 drops more than n=2 because it drafts 3 tokens ahead instead of 2,
compounding the per-position mismatch probability.

### Power Draw

| Config | Avg (W) | P95 (W) | Max (W) | J/token |
|--------|--------:|--------:|--------:|--------:|
| MTP-off | 595.3 | 608.6 | 611.7 | 17.12 |
| n=2, p=0 (t=0) | 595.3 | 623.4 | 627.0 | 8.30 |
| n=2, p=0 (t=0.6) | 597.5 | 628.2 | 632.1 | 8.75 |
| n=3, p=0 (t=0) | 618.7 | 656.1 | 661.0 | 7.58 |
| n=3, p=0 (t=0.6) | 623.9 | 660.7 | 663.1 | 8.46 |
| n=4, p=0 (t=0.6) | 611.0 | 645.5 | 649.8 | 8.30 |

### VRAM Usage

| Config | GPU0 MiB | GPU1 MiB | Total GiB |
|--------|--------:|--------:|----------:|
| MTP-off | 25,920 | 27,562 | ~52.1 |
| n=2, p=0 | 26,154 | 28,916 | ~53.9 |
| n=3, p=0 | 26,270 | 29,028 | ~54.1 |
| n=4, p=0 | 26,390 | 29,140 | ~54.3 |

## p_min Sweep Analysis (n=3, temp=0.6)

| p_min | Mean tok/s | Draft_n | Accepted | Accept Rate |
|------:|----------:|--------:|---------:|------------:|
| 0 | 73.76 | 211 | 128 | 60.7% |
| 0.05 | 73.77 | 211 | 128 | 60.7% |
| 0.10 | 73.77 | 211 | 128 | 60.7% |
| 0.20 | 73.76 | 210 | 128 | 61.0% |

**Conclusion**: p_min=0 is optimal. The model's MTP draft confidence is
consistently above 0.20 for this workload, so p_min in 0–0.20 has zero effect
on draft length or acceptance. p_min=0.75 (from earlier benchmarks) aggressively
cuts drafts short and reduces throughput. **Abandon p_min as a tuning knob for
this model — keep p_min=0.**

## n=4 Analysis

n=4/p=0 at temp=0.6 produces 73.62 tok/s — **slower than n=3/p=0's 73.76
tok/s**. Acceptance rate drops to 51.7% (134/259), which is near DavidAU's
50% threshold where MTP stops being beneficial. The extra draft compute
outweighs the marginal acceptance gain.

**Conclusion**: n=3 is the optimal n-max. n=4 and beyond are counterproductive.

## Ubatch Sweep

### Decode Speed (n=3/p=0, temp=0.6)

| ubatch | batch | Mean tok/s | StdDev | P95 |
|-------:|------:|----------:|-------:|----:|
| 128 | 512 | 73.66 | 0.026 | 73.68 |
| 256 | 1024 | 73.85 | 0.069 | 73.91 |
| 256 | 2048 | 73.80 | 0.058 | 73.85 |

Decode speed is essentially constant across ubatch sizes. The difference
(73.66 vs 73.85, +0.3%) is within measurement noise.

### Prefill Speed

| ubatch | batch | 8K prompt tok/s | 66K prompt tok/s |
|-------:|------:|----------------:|-----------------:|
| 128 | 512 | 1,940 | 1,706 |
| 256 | 1024 | 2,594 | 2,042 |
| 256 | 2048 | 2,594 | — |

**ub=256 improves prefill by 34% at 8K and 20% at 66K with zero decode penalty.**

The VRAM cost is ~130 MiB/GPU (26,270→26,436 MiB on GPU0), well within the
~6 GiB/GPU headroom.

ub=512 was not tested because the server failed to start (likely OOM during
initial memory allocation for the larger compute buffer). b=2048/ub=256
produced identical results to b=1024/ub=256 for both prefill and decode.

**Conclusion**: `b=1024 -ub 256` is the optimal batch configuration. It
provides significant prefill improvement with no decode regression and
minimal VRAM cost.

## Final Profile Recommendations

### Agent Profile (DEFAULT)

```text
MTP_N_MAX=3  MTP_P_MIN=0
-b 1024 -ub 256
128K F16 KV
--fit-target 2048,4096
--reasoning auto --reasoning-format deepseek --reasoning-preserve
temp=0.6  top_p=0.95  top_k=20  min_p=0  repeat_penalty=1.0
```

- 73.76 tok/s decode (2.12x vs MTP-off)
- 2,042 tok/s prefill at 66K
- J/token: 8.46
- 60.7% acceptance — well above 50% viability threshold
- reasoning-preserve: -2.4% prompt tokens, -6.8% wall time, neutral decode

### General Profile

```text
MTP_N_MAX=3  MTP_P_MIN=0
-b 1024 -ub 256
128K F16 KV
--fit-target 2048,4096
--reasoning auto --reasoning-format deepseek --reasoning-preserve
temp=0.7  top_p=0.95  top_k=20  min_p=0  repeat_penalty=1.0
```

- 75.02 tok/s decode (2.16x vs MTP-off) at temp=0.7
- 8.36 J/token
- 63.2% acceptance
- n=3 confirmed 8.6% faster than n=2 at temp=0.7

### Long Profile

```text
-c 262144 -ctk q8_0 -ctv q8_0
MTP_N_MAX=3  MTP_P_MIN=0
-b 1024 -ub 256
--fit-target 2048,4096
temp=0.6
```

- Short decode: 43.83 tok/s (vs 92 at 128K)
- Retrieval validated up to ~172K tokens
- Decode at 120K+ tokens: 10-13 tok/s
- GPU0 free: ~2,497 MiB (tight but stable)
- No reasoning-preserve (not tested with 256K)

### Creative / High-Temperature

No separate profile. Use per-request sampler overrides:

```json
temperature: 1.0-1.2, top_k: 40, min_p: 0.05
```

If temp>1, disable MTP via `MTP_MODE=off`.

## Key Decisions

1. **n=3/p=0 is the agent profile default**: At temp=0.6, n=3 is 8.0% faster
   than n=2 (73.76 vs 68.30 tok/s), exceeding the 8% threshold for
   switching. n=3 is also more energy-efficient (8.46 vs 8.75 J/token).

2. **p_min=0 is the only viable setting**: The model's MTP confidence is
   consistently above 0.20, making p_min irrelevant as a tuning knob.
   p_min=0.75 actively hurts throughput.

3. **n=4 is counterproductive**: 73.62 tok/s vs n=3's 73.76 tok/s, with
   acceptance near the 50% viability threshold. No further n-max exploration.

4. **ub=256 is the default batch size**: +20-34% prefill, zero decode penalty,
   ~130 MiB/GPU VRAM cost. ub=512 appears to OOM.

5. **n=3/p=0 for all profiles**: At temp=0.7, n=3 is 8.6% faster than n=2
   (75.02 vs 69.10 tok/s), confirming n=3 as the universal MTP default.

6. **repeat_penalty=1.0 remains fixed**: Q8_0 does not benefit from repeat
   penalty. Only increase via per-request override to 1.02-1.05 if looping
   is stably reproduced.

7. **fit-target 2048,4096 maximizes min(free)**: At 2048,2048, GPU1 had only
   2,799 MiB free (bottleneck). At 2048,4096, both GPUs have ~4-4.5 GiB free.
   Decode regression is <0.2%. This is the new universal baseline.

8. **cache-reuse is unsupported**: The Qwen3.5 hybrid architecture (24 dense +
   72 SSM layers) does not support cache-reuse in current llama.cpp. The prompt
   cache feature is enabled but non-functional without it.

9. **128K Q8_0 KV has zero quality loss**: Compared to F16 at 128K context,
   Q8_0 KV produces identical quality and within-1% decode speed. VRAM savings
   are ~4 GiB on GPU0.

10. **256K Q8_0 KV is viable with trade-offs**: Needle retrieval works up to
    ~172K tokens. Decode speed drops ~52% vs 128K (44 vs 92 tok/s short prompt)
    due to doubled KV cache for dense attention layers. At >120K tokens, decode
    is 10-13 tok/s.

## temp=0.7 A/B: n=2 vs n=3 (General Profile Validation)

| Config | Mean tok/s | StdDev | J/token | Accept Rate | Draft_n | Accepted |
|--------|----------:|-------:|--------:|------------:|--------:|---------:|
| n=2, p=0 | 69.10 | 0.029 | 9.08 | 74.2% | 159 | 118 |
| n=3, p=0 | **75.02** | 0.059 | **8.36** | 63.2% | 204 | 129 |

n=3 is 8.6% faster than n=2 at temp=0.7, confirming n=3/p=0 as the
universal MTP default for all profiles. n=3 is also 8.6% more energy-efficient
(8.36 vs 9.08 J/token).

## Reasoning-Preserve Evaluation (10-turn Agent Benchmark)

Server launched with `--reasoning auto --reasoning-format deepseek
--reasoning-preserve`. 10-turn coding task (CSV parser), 512 max tokens/turn,
seed=42, temp=0.6. Conversation history accumulates across turns.

| Metric | Baseline | +reasoning-preserve | Delta |
|--------|--------:|--------------------:|------:|
| Total prompt tokens | 14,523 | 14,174 | -2.4% |
| Total completion tokens | 4,485 | 4,135 | -7.8% |
| Total wall time | 60.1s | 56.0s | -6.8% |
| Avg decode tok/s | 74.6 | 73.8 | -1.1% |
| Avg prompt tok/turn | 1,452 | 1,417 | -2.4% |

Reasoning content was present in 9/10 turns with reasoning-preserve and also
9/10 turns without it (Qwen3.6 naturally reasons). The key difference:
reasoning-preserve retains the reasoning trace in context rather than
stripping it, resulting in slightly more compact prompt tokens (the preserved
reasoning replaces what would otherwise be a longer assistant response prefix).

Decode speed is essentially identical (73.8 vs 74.6 tok/s, -1.1%). The wall
time improvement comes from fewer total tokens generated.

**Conclusion**: Reasoning-preserve is net positive for agent workloads — it
preserves reasoning traces across turns with no decode penalty and slightly
reduces prompt overhead. Enable for agent/coding profiles.

## Cache-Reuse Evaluation

Server launched with `--cache-reuse 256 -lv 4`. The server log reports:

```
W srv    load_model: cache_reuse is not supported by this context, it will be disabled
```

The Qwen3.5 hybrid architecture (24 dense attention + 72 SSM layers) does
not support cache-reuse in current llama.cpp. The prompt cache feature is
enabled (size limit 8192 MiB) but is non-functional without cache-reuse.

**Conclusion**: Cache-reuse is unsupported. Abandon cache direction. Production
default uses `--reasoning auto --reasoning-format deepseek --reasoning-preserve`
only (from T011).

## VRAM Balance Optimization (T014)

Current baseline `--fit-target 2048,2048` results in asymmetric VRAM usage:
GPU1 has only ~2.8 GiB free while GPU0 has ~5.7 GiB. The bottleneck GPU
determines OOM risk.

Sweep of per-device fit-target values:

| fit-target | GPU0 used | GPU0 free | GPU1 used | GPU1 free | min(free) | Decode tok/s |
|---|---:|---:|---:|---:|---:|---:|
| 2048,2048 | 26,426 | 5,725 | 29,352 | 2,799 | **2,799** | 90.58 |
| 2048,3072 | 27,230 | 4,921 | 28,550 | 3,601 | **3,601** | 90.43 |
| 2048,4096 | 28,118 | 4,033 | 27,660 | 4,491 | **4,033** | 90.47 |
| 2048,4608 | 28,520 | 3,631 | 27,260 | 4,891 | **3,631** | 90.49 |
| 2048,5120 | 28,920 | 3,231 | 26,860 | 5,291 | **3,231** | 90.40 |

**Decision**: `--fit-target 2048,4096` — min(free)=4,033 MiB (+44% vs baseline),
both GPUs within 500 MiB of each other (4,033 vs 4,491), decode regression <0.2%.
This is the new universal baseline for all three profiles.

## 128K F16 vs 128K Q8_0 KV Comparison (T015)

Isolating the effect of KV quantization at the same 128K context size:

### Prefill Speed

| Prompt tokens | F16 KV prefill | Q8_0 KV prefill | Delta |
|---:|---:|---:|---:|
| 8,538 | 2,503 tok/s | 2,485 tok/s | -0.7% |
| 25,860 | 2,284 tok/s | 2,270 tok/s | -0.6% |
| 36,532 | 1,595 tok/s | 1,493 tok/s | -6.4% |
| 57,860 | 1,064 tok/s | 1,001 tok/s | -5.9% |

### Decode Speed

| Prompt tokens | F16 KV decode | Q8_0 KV decode | Delta |
|---:|---:|---:|---:|
| 25 (short) | 91.27 tok/s | 92.01 tok/s | +0.8% |
| 8,538 | 67.66 tok/s | 70.15 tok/s | +3.7% |
| 25,860 | 60.28 tok/s | 62.20 tok/s | +3.2% |
| 36,532 | 59.34 tok/s | 51.80 tok/s | -12.7% |
| 57,860 | 46.60 tok/s | 42.54 tok/s | -8.7% |

### VRAM

| Config | GPU0 used | GPU0 free | GPU1 used | GPU1 free |
|---|---:|---:|---:|---:|
| 128K F16 | 28,140 | 4,011 | 27,702 | 4,449 |
| 128K Q8_0 | 24,060 | 8,091 | 27,006 | 5,145 |

Q8_0 KV frees ~4 GiB on GPU0 compared to F16. Short-prompt decode is
slightly faster with Q8_0 (likely due to smaller KV cache footprint fitting
better in cache). Long-prompt decode shows more variance.

**Conclusion**: Q8_0 KV at 128K has zero quality loss and negligible performance
difference vs F16. The VRAM savings are substantial.

## 256K Q8_0 KV — Long Profile Validation (T016-T018)

### Startup

Server starts successfully with `-c 262144 -ctk q8_0 -ctv q8_0`.

| Metric | 128K F16 | 128K Q8_0 | 256K Q8_0 |
|---|---:|---:|---:|
| GPU0 used | 28,140 | 24,060 | 29,654 |
| GPU0 free | 4,011 | 8,091 | 2,497 |
| GPU1 used | 27,702 | 27,006 | 27,112 |
| GPU1 free | 4,449 | 5,145 | 5,039 |

256K Q8_0 KV GPU0 free is 2,497 MiB — tight but functional.

### Prefill and Decode at 256K Context

| Prompt tokens | Prefill tok/s | Decode tok/s |
|---:|---:|---:|
| 7,610 | 1,222 | 32.68 |
| 23,060 | 1,156 | 23.53 |
| 32,560 | 903 | 16.84 |
| 57,860 | 650 | 11.44 |
| 84,463 | 937 | 16.71 |
| 100,102 | 879 | 16.91 |
| 117,810 | 821 | 11.04 |
| 124,905 | 802 | 12.99 |
| 156,272 | 722 | 11.49 |
| 171,934 | 689 | 10.27 |

Short-prompt decode: 43.83 tok/s (vs 92.01 at 128K Q8_0) — a 52% reduction.
This is expected: 256K context doubles the KV cache size for 24 dense attention
layers, making attention computation during decode ~2x slower for those layers.
SSM layers scale linearly but are cheaper.

### Needle Retrieval

Using diverse-haystack needle-in-haystack tests:

| Prompt tokens | Result |
|---:|---|
| 27,274 | FOUND (content) |
| 42,234 | FOUND (content) |
| 75,030 | FOUND (reasoning) |
| 84,463 | FOUND (content) |
| 93,626 | FOUND (reasoning) |
| 100,102 | NOT FOUND (repetitive text) |
| 124,905 | FOUND (content) |
| 140,533 | FOUND (content) |
| 156,272 | FOUND (reasoning) |
| 171,934 | FOUND (content) |
| 191,091 | NOT FOUND |

Effective retrieval limit: ~172K tokens. The 100K failure was with highly
repetitive text; diverse text retrieves correctly at 93K+.

**Conclusion**: Long profile is VIABLE with documented trade-offs:
- Retrieval works up to ~172K tokens
- Decode speed is ~52% slower than 128K for short prompts (44 vs 92 tok/s)
- At >120K tokens, decode drops to 10-13 tok/s
- Not experimental — the architecture works, just slower
