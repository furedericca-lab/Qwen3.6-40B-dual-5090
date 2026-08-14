---
title: Switch from vLLM to llama.cpp deployment
type: decision
status: accepted
scope: qwen36-40b-eleanor-llamacpp
related_scopes: []
related_files: []
source_docs:
  - .scopes/archive/qwen36-40b-eleanor-llamacpp/qwen36-40b-eleanor-llamacpp-contracts.md
tags:
  - deployment
  - llama-cpp
  - vllm
  - migration
last_checked: 2026-08-14
updated: 2026-08-14T10:00:00Z
decision_date: 2026-08-14
---

# Switch from vLLM to llama.cpp deployment

The project switched from vLLM/MXFP8 to llama.cpp/Q8_0 GGUF. The vLLM route was
archived because Phase 3 could not fit 64K KV cache on dual RTX 5090 at 0.90
GPU utilization. The new route uses a pre-built Q8_0 GGUF (qwen35 architecture,
97 blocks, MTP enabled) served by llama.cpp fork efb81ab which has native qwen35
support. Target is 128K context with MTP. Build uses CUDA sm_120a, Clang 21,
CUDA 13.3.

## Key parameter decisions

### --fit-target 2048,4096 (not 2048,2048)

`--fit-target` specifies the **target VRAM margin per GPU after fitting** — not
a KV reservation. The initial `2048,2048` was symmetric but resulted in
asymmetric VRAM usage: GPU1 had only ~2,799 MiB free (bottleneck) while GPU0
had ~5,725 MiB free. The min(free) determines OOM risk.

Sweep of fit-target values showed `2048,4096` maximizes min(free) at 4,033
MiB (+44% vs baseline), with both GPUs within 500 MiB of each other (4,033
vs 4,491). Decode regression is <0.2%. The asymmetric target shifts layers
to equalize headroom across GPUs.

### No --no-kv-offload

`--no-kv-offload` was included based on a misunderstanding of its semantics.
In llama.cpp, KV offload to GPU is the **default** — `--no-kv-offload`
**disables** GPU KV and forces KV to CPU/RAM. Since the target is all-KV-on-GPU,
this flag was removed. The default behavior (KV on GPU) is what we want.

### --spec-type draft-mtp --spec-draft-n-max 3 --spec-draft-p-min 0 (all profiles)

`n-max=3` with `p_min=0` is the default MTP configuration for all three
profiles (agent, general, long). At temp=0.6, n=3 produces 73.76 tok/s
(2.12x speedup, stddev 0.015), which is 8.0% faster than n=2/p=0
(68.30 tok/s). At temp=0.7, n=3 produces 75.02 tok/s, 8.6% faster than
n=2/p=0 (69.10 tok/s). Both exceed the 5% threshold. n=3 is also more
energy-efficient at both temperatures (8.46 vs 8.75 J/token at 0.6,
8.36 vs 9.08 J/token at 0.7). p_min sweep (0/0.05/0.10/0.20) showed no
effect — the model's MTP confidence is consistently above 0.20. n=4 is
slower than n=3 (73.62 vs 73.76 tok/s) with acceptance near the 50%
viability threshold. The n-max=3 drift bug (#23302) was superseded by
#23335; fixed-seed testing showed Q8_0 agreeing across no-MTP and MTP n=1-5.

### Sampling: server fallback defaults only

Server sampling parameters are fallback defaults. API callers should pass
their own sampler overrides per request. All three profiles use Qwen3.6
official precise coding parameters (top_p=0.95, top_k=20, min_p=0,
repeat_penalty=1.0). `repeat-penalty 1.0` disables repetition penalty, which
is recommended when using MTP. Q8_0 does not benefit from repeat penalty;
DavidAU's 1.05-1.1 recommendation targets lower quants. Only increase to
1.02-1.05 via per-request override if looping is stably reproduced — never
globally. Creative work does not get a separate profile; use per-request
sampler overrides (temp=1.0, top_k=40, min_p=0.05). If temp>1, disable MTP
via `MTP_MODE=off`.

### Ubatch 256 (increased from 128)

Ubatch was increased from 128 to 256 after benchmarking showed +20-34%
prefill improvement with zero decode regression. At 66K prompt length,
ub=256 delivers 2042 tok/s prefill vs 1706 tok/s for ub=128 (+20%).
Decode speed is unchanged (73.76 vs 73.66 tok/s). VRAM cost is ~130 MiB/GPU.

### Reasoning-preserve (agent and general profiles)

`--reasoning auto --reasoning-format deepseek --reasoning-preserve` is enabled
for agent and general profiles. It preserves reasoning traces across turns
instead of stripping them. Benchmark: -2.4% prompt tokens, -6.8% wall time,
decode speed neutral (73.8 vs 74.6 tok/s). Net positive for agent/coding
workloads.

### Cache-reuse (unsupported)

`--cache-reuse 256` is unsupported for this model. The Qwen3.5 hybrid
architecture (24 dense attention + 72 SSM layers) does not support
cache-reuse in current llama.cpp. The server log reports: "cache_reuse is
not supported by this context, it will be disabled." The prompt cache
feature is enabled but non-functional without cache-reuse.

### Long profile: 256K Q8_0 KV

The long profile uses `-c 262144 -ctk q8_0 -ctv q8_0` for 256K context.
This is viable with documented trade-offs: short decode 43.83 tok/s (vs 92
at 128K, -52%), retrieval validated up to ~172K tokens, decode at 120K+
tokens is 10-13 tok/s. 128K Q8_0 KV itself has zero quality loss vs F16.

### MTP_MODE launcher variable (not $@ --spec-type none)

The launcher uses `MTP_MODE=on|off` instead of passing `--spec-type none`
through `$@`. This is because llama.cpp **appends** `--spec-type` values into a
bitmask rather than replacing the previous value. If the launcher already sets
`--spec-type draft-mtp` and `$@` adds `--spec-type none`, both are in the
bitmask and MTP remains enabled. The `MTP_MODE=off` approach omits all
speculative decoding args entirely, which is the only reliable way to get a
clean MTP-off baseline for Phase 4 A/B testing.
