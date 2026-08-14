# MTP Benchmark Results — 2026-08-14

## Methodology

Rigorous benchmark with controlled conditions:
- **Fixed seed**: `seed=42` for all runs
- **Temperature**: `0` (greedy decoding, deterministic)
- **Same prompt**: ML supervised vs unsupervised learning explanation (43 prompt tokens)
- **Same max_tokens**: 200
- **Warm-up**: 1 run before formal measurement
- **Formal runs**: 5 per configuration
- **Metrics**: mean, median, stddev, min, max of decode tok/s
- **Power**: GPU power draw recorded via nvidia-smi

All tests on dual RTX 5090 (CUDA sm_120a), Q8_0 GGUF, 128K F16 KV context,
llama.cpp merge commit 94e82e8ae. Server restarted between each configuration.

## Decode Speed Summary (tok/s)

| Config       | Mean | Median | StdDev | Min | Max | Speedup |
|-------------|-----:|-------:|-------:|----:|----:|--------:|
| MTP-off     | 34.71 | 34.72 | 0.01 | 34.70 | 34.72 | 1.00x |
| n=2, p=0    | 71.20 | 71.21 | 0.03 | 71.14 | 71.24 | 2.05x |
| n=2, p=0.75 | 60.18 | 60.19 | 0.04 | 60.13 | 60.22 | 1.73x |
| n=3, p=0    | 81.35 | 81.24 | 0.29 | 81.19 | 81.95 | 2.34x |
| n=3, p=0.75 | 66.61 | 66.52 | 0.71 | 65.91 | 67.43 | 1.92x |

### Profile optimization benchmarks (temp=0.6 and temp=0.7)

| Config | Temp | Mean | StdDev | Speedup | J/token | Accept Rate |
|--------|------|-----:|-------:|--------:|--------:|------------:|
| MTP-off | 0 | 34.77 | 0.003 | 1.00x | 17.12 | N/A |
| n=2, p=0 | 0.6 | 68.30 | 0.055 | 1.96x | 8.75 | 72.2% |
| n=3, p=0 | 0.6 | 73.76 | 0.015 | 2.12x | 8.46 | 60.7% |
| n=3, p=0 | 0 | 81.67 | 0.043 | 2.35x | 7.58 | 70.7% |
| n=4, p=0 | 0.6 | 73.62 | 0.042 | 2.12x | 8.30 | 51.7% |
| n=2, p=0 | 0.7 | 69.10 | 0.029 | 1.98x | 9.08 | 74.2% |
| n=3, p=0 | 0.7 | 75.02 | 0.059 | 2.16x | 8.36 | 63.2% |

## Draft Acceptance (per run)

| Config       | draft_n | accepted | Accept Rate |
|-------------|--------:|---------:|------------:|
| MTP-off     | 0 | 0 | N/A |
| n=2, p=0    | 156 | 121 | 77.6% |
| n=2, p=0.75 | 116 | 109 | 94.0% |
| n=3, p=0    | 191 | 135 | 70.7% |
| n=3, p=0.75 | 129-131 | 120-122 | 93.1% |

## GPU Power Draw

| Config       | GPU0 (W) | GPU1 (W) | Total (W) |
|-------------|---------:|---------:|----------:|
| MTP-off     | 283.69 | 309.65 | 593.3 |
| n=2, p=0    | 277.65 | 331.93 | 609.6 |
| n=2, p=0.75 | 256.54 | 314.42 | 570.96 |
| n=3, p=0    | 278.93 | 364.54 | 643.47 |
| n=3, p=0.75 | 252.76 | 316.67 | 569.43 |

## GPU VRAM Usage

| Config       | GPU0 MiB | GPU1 MiB | Total GiB |
|-------------|--------:|--------:|----------:|
| MTP-off     | 25,920 | 27,562 | ~52.1 |
| n=2, p=0    | 26,166 | 28,938 | ~53.9 |
| n=2, p=0.75 | 26,154 | 28,916 | ~53.9 |
| n=3, p=0    | 26,270 | 29,028 | ~54.1 |
| n=3, p=0.75 | 26,270 | 29,028 | ~54.1 |

## Analysis

### n=3, p=0 is the fastest configuration

At 81.35 tok/s (2.34x speedup), n=3/p=0 is **14.3% faster** than n=2/p=0
(71.20 tok/s, 2.05x). The lower acceptance rate (70.7% vs 77.6%) is already
reflected in the final tok/s — the wasted compute on rejected drafts is
accounted for. The VRAM cost is negligible (+0.2 GiB for n=3 vs n=2).

However, n=3/p=0 has:
- Higher power draw: 643.5W vs 609.6W total (+5.5%)
- Slightly higher variance: stddev 0.29 vs 0.03 (still very stable)
- More wasted draft compute: 56 rejected tokens per 200 generated vs 35

### p_min=0.75 reduces throughput

For both n=2 and n=3, p_min=0.75 improves acceptance (94% vs 78%, 93% vs 71%)
but paradoxically reduces throughput because it stops drafting early on
low-confidence tokens, shortening the average verified-tokens-per-step.

### Production recommendation

**All profiles use n=3, p=0** — confirmed at both temp=0.6 (8.0% faster
than n=2) and temp=0.7 (8.6% faster than n=2). n=3 is also more
energy-efficient at both temperatures.

Three profiles: agent (temp=0.6), general (temp=0.7), long (256K Q8_0 KV).
Creative work uses per-request sampler overrides, not a separate profile.

## Comparison with Quick Probe Results

The earlier quick-probe results (5 different workloads, 1 run each, varying
temperatures) showed:

| Config       | Quick Mean | Benchmark Mean | Delta |
|-------------|----------:|--------------:|------:|
| MTP-off     | 34.71 | 34.71 | 0.0% |
| n=2, p=0    | 73.52 | 71.20 | -3.2% |
| n=2, p=0.75 | 63.10 | 60.18 | -4.6% |
| n=3, p=0    | 78.60 | 81.35 | +3.5% |
| n=3, p=0.75 | 69.90 | 66.61 | -4.7% |

Differences are expected — the quick probe used varying temperatures, different
prompts, and single runs. The benchmark uses fixed seed, temperature 0, and
repeated measurements. The benchmark values are the authoritative reference.
