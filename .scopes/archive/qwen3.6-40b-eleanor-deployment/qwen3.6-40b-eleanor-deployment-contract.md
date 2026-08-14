# Qwen3.6-40B-Eleanor MXFP8 W8A8 Deployment Contract

## Context

This repository controls an offline, permanent quantization and local vLLM
deployment of `Qwen3.6-40B-Eleanor` on two RTX 5090 GPUs. The immutable source
is `/data/linux-fast/models/Qwen3.6-40B-Eleanor`; the single production output
is `/data/linux-fast/models/Qwen3.6-40B-Eleanor-MXFP8-W8A8`.

Pinned source dependencies are `vllm/` at
`5fee0a872dc31dd3476d61bb72b782b2d9d47492`, `llm-compressor/` at
`de46bfd53513aa87571a8b056a06aeaa5da1c69c` (`0.13.0`), and
`compressed-tensors/` at `ac8e2ba82f4e0d5eaa40069f8fc642738f124cd4`
(`0.18.0`).

## Findings

- The source is `Qwen3_5ForConditionalGeneration`, BF16, with 17 base model
  shards and one indexed MTP shard (`model-mtp-restored.safetensors`).
- Its text configuration has 96 layers, `mtp_num_hidden_layers=1`, a 262144
  token native maximum, and a full-attention interval of four.
- The source tensor namespace contains `model.language_model.embed_tokens`,
  `lm_head`, `model.language_model.layers.*.linear_attn`, `model.visual.*`, and
  `mtp.*`; the preservation rules therefore use those observed namespaces.
- `model_free_ptq` in the pinned compressor processes Safetensors shard-wise,
  distributes supplied devices round-robin, and updates the index and
  compressed-tensors metadata without loading the complete 75 GiB model.
- The pinned vLLM recognizes this architecture, MXFP8 compressed-tensors W8A8,
  the `qwen3` reasoning parser, `qwen3_coder` tool parser, and native Qwen3.5
  MTP with `{"method":"mtp","num_speculative_tokens":1}`.

## Outcome

Produce a Golden MXFP8 W8A8 compressed-tensors checkpoint, integrity manifests
for source and output, and a localhost-only TP=2 vLLM deployment. The first
runtime acceptance is 64K with MTP disabled; MTP-1 and performance comparison
are separately gated.

## Goals / Non-goals

- Goals: immutable input provenance, permanent MXFP8 W8A8 output, E4M3 weights
  with group-32 E8M0 scales, dynamic MXFP8 activations at runtime, BF16
  preservation rules, TP=2, BF16/auto KV cache, and evidence-based promotion.
- Non-goals: online quantization, a full-model `from_pretrained` conversion,
  CPU model-weight offload, source-model mutation, LAN exposure, automatic
  promotion to MTP, automatic tuning, or AutoRound in the first Golden build.

## Target Files / Modules

- `config/quantize.env` and `config/runtime.env`
- `scripts/check-model.py`, `scripts/validate-quantize-config.py`,
  `scripts/build-fp8-checkpoint.py`, `scripts/build-fp8-checkpoint.sh`, and
  `scripts/verify-fp8-checkpoint.py`
- `scripts/bootstrap-quantizer.sh`, `scripts/bootstrap-vllm.sh`,
  `scripts/validate-runtime-config.py`, `scripts/vllm-server-first-boot.sh`,
  and `scripts/smoke-api.sh`
- `scripts/verify-source-upstream-buffered-incident.py`,
  `scripts/run-buffered-io-probe.sh`, and
  `scripts/verify-source-upstream-direct.py`
- `vllm/`, `llm-compressor/`, and `compressed-tensors/`

## Constraints

- Keep checkpoints and manifests under `/data/linux-fast/models`; Git stores
  only launchers, profiles, source references, and scope evidence.
- Use project-local `.quantize-venv` and `.venv` managed with `uv`.
- `model_free_ptq` must use `scheme="MXFP8"`, `device=["cuda:0", "cuda:1"]`,
  and `max_workers=2` for the first Golden build.
- Preserve BF16 `lm_head`, embeddings, `conv1d`, `in_proj_a`, `in_proj_b`, MTP,
  vision, and norms. Do not preemptively preserve arbitrary first, last, or
  full-attention layers.
- Bind vLLM to `127.0.0.1`; do not pass `--quantization mxfp8`, CPU offload, or
  `--trust-remote-code`.

## Boundaries

The 64K MTP-off launch is a load, capacity, and API acceptance gate only. It
does not prove 96K/128K capacity, multimodal operation, throughput, MTP benefit,
or BF16-to-MXFP8 quality parity. MTP-1 is allowed only after that baseline is
recorded. AutoRound and an HQ mixed-precision V2 require measured quality loss
and a new approved scope decision.

## Decision Summary

The production candidate is BF16 source -> offline RTN `MXFP8` -> permanent
compressed-tensors checkpoint -> vLLM TP=2. MXFP8 persists E4M3 weights with
one uint8 E8M0 scale per 32 values; W8A8 activation quantization is dynamic in
vLLM and is not stored as activation payload in the checkpoint. The initial
launch uses `--dtype bfloat16`, `--kv-cache-dtype auto`,
`--language-model-only`, 64K context, and MTP disabled.

## Verification Surface

```bash
scripts/check-model.py
scripts/validate-quantize-config.py
scripts/verify-fp8-checkpoint.py
scripts/validate-runtime-config.py
git submodule status --recursive
scripts/verify-source-upstream-direct.py --revision 7905312899185973580867f69d20d4cfc374ccaa
```

The buffered remote verifier is retained only for bounded fresh-boot trigger
probes. It must never be used for production source/output manifests.

After explicit runtime launch, record `/health`, `/v1/models`, a deterministic
chat completion, and per-GPU memory balance. Run the identical benchmark with
MTP off and MTP-1 before considering MTP for production.

## Escalation Triggers

- A source manifest changes after freeze, a shard is missing, or the source
  architecture and its indexed tensor namespace disagree with this contract.
- The output lacks compressed-tensors MXFP8 W8A8 metadata, BF16 MTP, or any
  required ignored-module rule.
- vLLM fails to load without an unsupported runtime override, or 64K cannot
  allocate a stable KV cache at the recorded profile.
- MTP-1 produces an API/correctness regression or loses its intended latency
  advantage versus the recorded MTP-off baseline.
- Quality evidence supports an HQ V2 or AutoRound candidate; do not overwrite
  the Golden checkpoint to explore either option.

## Rollback

Stop the local server and remove project-local environments/logs only. Retain
the BF16 source, its manifest, and a verified Golden MXFP8 checkpoint. Roll
back configuration through Git; never overwrite a promoted checkpoint.

## Open Questions

- Confirm the exact 64K KV headroom on this host from a real TP=2 run.
- Confirm MTP-1 acceptance and latency impact under the intended low-concurrency
  workload.
- Establish BF16 versus MXFP8 task-quality evidence before considering HQ V2.

## Execution Log / Evidence Updates

- 2026-08-13: model structure, source path, two-GPU capacity, local ext4
  destination, and fixed upstream source dependencies inspected. No environment
  creation, manifest generation, checkpoint conversion, runtime launch, or
  benchmark has run.
- 2026-08-13: on a clean boot with taint `4096` only, the bounded 1 MiB
  buffered-I/O incident probe completed without a new kernel event and the
  direct-I/O source verifier passed 30/30 at the pinned revision. The two-GPU
  `model_free_ptq` Golden build then exited zero, atomically promoted the output,
  and passed the MXFP8 checkpoint verifier. The 30-entry direct-I/O Golden
  manifest is `/data/linux-fast/models/Qwen3.6-40B-Eleanor-MXFP8-W8A8.sha256`
  with SHA256 `61a2e80f1ee6ac33fc2d39901b630ef8d5350cdded586a061bc03d46f3ae76c9`.
