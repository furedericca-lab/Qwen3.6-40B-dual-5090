---
title: Switch from vLLM to llama.cpp deployment
type: decision
status: accepted
scope: qwen36-40b-eleanor-llamacpp
related_scopes: []
related_files: []
source_docs:
  - .scopes/qwen36-40b-eleanor-llamacpp/qwen36-40b-eleanor-llamacpp-contracts.md
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

### --fit-target 2048,2048 (not 8192,8192)

`--fit-target` specifies the **target VRAM margin per GPU after fitting** — not
a KV reservation. The initial attempt to set `8192,8192` was based on
misunderstanding it as "8 GiB reserved for KV". In reality, asking for 16 GiB
total margin would force the fit algorithm to offload ~7-8 GiB of weights to
CPU/RAM, hurting decode speed.

The correct sizing: 128K F16 main KV is ~12.0 GiB total (24 dense attention
layers, not 25 — the MTP draft layer is separate). Per GPU this is ~6 GiB.
With ~20 GiB weights per GPU and ~6 GiB KV, there is ~5.5 GiB remaining for
CUDA/FA/compute. Setting `2048,2048` (2 GiB margin) leaves ~3.5 GiB/GPU for
runtime allocations beyond the margin — sufficient for `-ub 128` and FA.

### No --no-kv-offload

`--no-kv-offload` was included based on a misunderstanding of its semantics.
In llama.cpp, KV offload to GPU is the **default** — `--no-kv-offload`
**disables** GPU KV and forces KV to CPU/RAM. Since the target is all-KV-on-GPU,
this flag was removed. The default behavior (KV on GPU) is what we want.

### --spec-type draft-mtp --spec-draft-n-max 2 (baseline, not final)

`n-max=2` is the Phase 2 baseline. The original n-max=3 Qwen3.6 output drift
bug (llama.cpp #23302) was closed after further testing showed Q8_0 is
unaffected at n=1-5; however, n-max=2 remains the conservative first-boot
choice. Phase 4 will benchmark four configurations: n=2/3 × p_min=0/0.75.
The Eleanor author recommends n-max=2 with ~60% acceptance at 2 tokens.

Additional MTP flags: `--spec-draft-n-min 0` (draft can be as short as 0
tokens), `--spec-draft-p-min 0.75` (stop drafting when MTP head confidence
drops below 0.75, reducing wasted computation on low-confidence drafts).
p_min=0.75 is also a baseline value — Phase 4 will test it against p_min=0.

### Sampling: --top-k 20 --min-p 0 --repeat-penalty 1.0

Qwen3.6 official precise coding parameters. `repeat-penalty 1.0` disables
repetition penalty, which is recommended when using MTP. For creative/RP use,
a separate DavidAU profile (top_k=40, min_p=0.05, repeat_penalty=1.02-1.15)
can be configured later.

### OOM ladder: preserve 128K context

The OOM ladder prioritizes preserving 128K context: reduce fit-target, then
ubatch, then switch KV to Q8_0 (halves KV budget while keeping 128K), and only
then reduce context to 64K.

### MTP_MODE launcher variable (not $@ --spec-type none)

The launcher uses `MTP_MODE=on|off` instead of passing `--spec-type none`
through `$@`. This is because llama.cpp **appends** `--spec-type` values into a
bitmask rather than replacing the previous value. If the launcher already sets
`--spec-type draft-mtp` and `$@` adds `--spec-type none`, both are in the
bitmask and MTP remains enabled. The `MTP_MODE=off` approach omits all
speculative decoding args entirely, which is the only reliable way to get a
clean MTP-off baseline for Phase 4 A/B testing.
