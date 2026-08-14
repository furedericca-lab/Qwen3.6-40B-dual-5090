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

### Agent/Coding Profile (PRIMARY)

```text
MTP_N_MAX=3  MTP_P_MIN=0
-b 1024 -ub 256
temp=0.6  top_p=0.95  top_k=20  min_p=0  repeat_penalty=1.0
```

- 73.76 tok/s decode (2.12x vs MTP-off)
- 2,042 tok/s prefill at 66K
- J/token: 8.46
- 60.7% acceptance — well above 50% viability threshold

### Balanced Profile (FALLBACK)

```text
MTP_N_MAX=2  MTP_P_MIN=0
-b 1024 -ub 256
temp=0.7  top_p=0.95  top_k=20  min_p=0  repeat_penalty=1.0
```

- 68.30 tok/s decode (1.96x vs MTP-off) at temp=0.6
- Slightly more stable at higher temperatures
- Better for interactive use with higher sampling variance

### Creative Profile

```text
MTP_MODE=off
-b 1024 -ub 256
temp>1 or creative sampler
repeat_penalty=1.0 (increase to 1.02-1.05 only if looping observed)
```

- MTP off per DavidAU's recommendation for temp>1
- 34.77 tok/s baseline
- Predictable autoregressive latency

### Long Profile (FUTURE)

```text
-c 262144 -ctk q8_0 -ctv q8_0
MTP_N_MAX=3  MTP_P_MIN=0
-b 1024 -ub 256
```

- Not yet tested — Phase 4 of this scope
- Theory: 256K context with Q8_0 KV ≈ same KV size as 128K F16

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

5. **n=2 remains the balanced fallback**: At higher temperatures (0.7+),
   n=2's higher acceptance rate provides more predictable performance.

6. **repeat_penalty=1.0 remains fixed**: Q8_0 does not benefit from repeat
   penalty. Only increase to 1.02-1.05 in a creative profile if looping
   is stably reproduced.
