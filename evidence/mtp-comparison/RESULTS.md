# MTP Comparison Results — 2026-08-14

## Test Configuration

All tests run on dual RTX 5090 (CUDA sm_120a), Q8_0 GGUF, 128K F16 KV context,
llama.cpp merge commit 94e82e8ae. Server restarted between each configuration.

## Decode Speed Comparison (tok/s)

Higher is better. Measured via `predicted_per_second` from llama-server timings.

| Probe    | MTP-off | n=2,p=0 | n=2,p=0.75 | n=3,p=0 | n=3,p=0.75 |
|----------|--------:|--------:|-----------:|--------:|-----------:|
| Math     |   34.60 |   66.71 |      62.85 |   70.50 |      61.10 |
| Chinese  |   34.73 |   70.63 |      58.68 |   62.07 |      68.40 |
| JSON     |   34.74 |   77.63 |      56.63 |   81.07 |      68.04 |
| Python   |   34.73 |   72.06 |      57.10 |   81.51 |      67.29 |
| Summary  |   34.73 |   80.60 |      80.24 |   97.84 |      84.65 |
| **Mean** | **34.71** | **73.52** | **63.10** | **78.60** | **69.90** |

## MTP Speedup vs MTP-off

| Config       | Mean tok/s | Speedup vs off | Accept Rate (mean) |
|-------------|----------:|---------------:|-------------------:|
| MTP-off     |     34.71 |          1.00x |                N/A |
| n=2, p=0    |     73.52 |          2.12x |              82.9% |
| n=2, p=0.75 |     63.10 |          1.82x |              94.1% |
| n=3, p=0    |     78.60 |          2.26x |              69.9% |
| n=3, p=0.75 |     69.90 |          2.01x |              93.5% |

## Draft Acceptance Details

| Probe    | n=2,p=0 | n=2,p=0.75 | n=3,p=0 | n=3,p=0.75 |
|----------|--------:|-----------:|--------:|-----------:|
| Math     | 75.0%   | 90.0%      | 64.5%   | 85.7%      |
| Chinese  | 76.2%   | 97.8%      | 46.1%   | 95.2%      |
| JSON     | 90.3%   | 94.2%      | 73.3%   | 92.0%      |
| Python   | 78.8%   | 93.6%      | 71.5%   | 94.5%      |
| Summary  | 94.3%   | 98.8%      | 93.9%   | 100.0%     |

## Prompt Speed (tok/s)

| Probe    | MTP-off | n=2,p=0 | n=2,p=0.75 | n=3,p=0 | n=3,p=0.75 |
|----------|--------:|--------:|-----------:|--------:|-----------:|
| Math     |   82.69 |   80.51 |      92.55 |   92.15 |      92.58 |
| Chinese  |  119.46 |  111.90 |     108.86 |  108.11 |     108.07 |
| JSON     |   28.58 |  202.48 |     200.81 |  199.18 |     199.78 |
| Python   |  175.38 |  176.99 |     176.03 |  175.48 |     176.29 |
| Summary  |   28.71 |  469.38 |     471.05 |  467.46 |     471.15 |

Note: prompt speed varies due to KV caching and prompt size; not directly
comparable across runs for different-length prompts.

## GPU VRAM Usage

| Config       | GPU0 MiB | GPU1 MiB | Total GiB |
|-------------|--------:|--------:|----------:|
| MTP-off     | 25,932  | 27,574  | ~52.3     |
| n=2, p=0    | 26,166  | 28,938  | ~53.8     |
| n=2, p=0.75 | 26,166  | 28,938  | ~53.8     |
| n=3, p=0    | 26,282  | 29,050  | ~54.0     |
| n=3, p=0.75 | 26,282  | 29,050  | ~54.0     |

MTP adds ~1.5 GiB VRAM for draft model and KV (n=2), ~1.7 GiB for n=3.
All configurations fit comfortably within dual-5090 VRAM.

## Quality Verification

All configurations produce correct, coherent output:
- Math: 2+3=5 in all configs
- Chinese: Fluent quantum computing explanation in all configs
- JSON: Valid JSON objects in all configs
- Python: Correct merge_sorted_lists in all configs
- Summary: Accurate bullet-point summaries in all configs

No repeated-symbol collapse, no empty output, no quality degradation observed
with MTP enabled at any n-max setting.

## Analysis

**Best decode speed: n=3, p=0 (78.6 tok/s, 2.26x speedup)**
- Highest raw throughput but lowest acceptance rate (69.9%)
- Generates many wasted drafts that are rejected, consuming compute

**Best acceptance rate: n=2, p=0.75 (94.1%)**
- Very high acceptance but lower speed (63.1 tok/s)
- p_min=0.75 stops drafting early on low-confidence tokens, saving compute
  but also reducing the benefit of longer draft sequences

**Best balance: n=2, p=0 (73.5 tok/s, 2.12x speedup, 82.9% acceptance)**
- Strong speedup with good acceptance rate
- Simple configuration with no p_min gating needed

**Production recommendation: n=2, p=0**
- 2.12x speedup over MTP-off is substantial and consistent
- 82.9% acceptance is healthy — not too much wasted compute
- n=3 adds speed for some tasks but the acceptance drop (to ~70%) means
  more wasted compute and less predictable behavior
- p_min=0.75 improves acceptance but paradoxically reduces throughput because
  it cuts draft sequences short, reducing the average verified-tokens-per-step

**Alternative for latency-sensitive tasks: n=3, p=0**
- 2.26x speedup is the fastest, suitable for batch or non-interactive use
  where wasted compute on rejected drafts is acceptable
