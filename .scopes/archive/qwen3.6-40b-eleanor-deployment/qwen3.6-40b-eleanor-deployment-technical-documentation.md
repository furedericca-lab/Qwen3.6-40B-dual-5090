# Qwen3.6-40B-Eleanor MXFP8 W8A8 Technical Documentation

## Canonical Architecture

```text
/data/linux-fast/models/Qwen3.6-40B-Eleanor
  -> BF16 SHA256 manifest
  -> local llm-compressor/model_free_ptq (two GPU workers)
  -> same-filesystem staging checkpoint
  -> validation and MXFP8 SHA256 manifest
  -> /data/linux-fast/models/Qwen3.6-40B-Eleanor-MXFP8-W8A8
  -> vLLM TP=2 / 127.0.0.1:8000
  -> OpenAI-compatible API
```

The project has three checked-out dependency sources: `vllm/`,
`llm-compressor/`, and `compressed-tensors/`. `scripts/bootstrap-quantizer.sh`
installs the latter two local source trees into `.quantize-venv`; it must not
download their development source again. `scripts/bootstrap-vllm.sh` installs
the local vLLM source into `.venv`. Both environments are ignored.

## Quantization Contract

`model_free_ptq` receives the source path, staging output path,
`scheme="MXFP8"`, `device=["cuda:0", "cuda:1"]`, and `max_workers=2`. It works
per Safetensors shard, writes compressed data and non-weight metadata to the
staging tree, then updates `model.safetensors.index.json` and
`config.json.quantization_config`.

The V1 compressed-tensors profile must describe:

- weights: symmetric 8-bit float E4M3, group strategy, `group_size=32`, and
  `scale_dtype=uint8` for E8M0 microscaling;
- input activations: the same 8-bit float/group-32/uint8 configuration with
  `dynamic=true`;
- format: the compressor's float-quantized compressed-tensors serialization;
- ignore rules: `lm_head`, embeddings, `conv1d`, `in_proj_a`, `in_proj_b`, MTP,
  vision, and norms.

Activation tensors are not persisted as runtime data. vLLM reads this metadata
and dynamically quantizes activations while loading MXFP8 values/scales from the
checkpoint. The vLLM command must not set an online `--quantization` mode.

## Major Decisions and Trade-offs

- RTN MXFP8 is the Golden V1 because it is data-free and shard-wise; AutoRound
  remains a later separate candidate because it requires calibration provenance.
- MXFP8 W8A8 maximizes native Blackwell coverage for regular supported Linear
  modules, while preserving the explicitly named high-risk/nonstandard modules
  avoids a blanket full-precision fallback.
- MTP-off at 64K establishes an attributable serving baseline. MTP-1 is a
  runtime-only experiment after that baseline and cannot alter the checkpoint.
- `--kv-cache-dtype auto` avoids an FP8 KV request while retaining vLLM's
  model-compatible cache selection; it is validated by observed first-boot
  capacity rather than assumed from static configuration.

## BF16 Preservation and MTP

The selected BF16 rules are deliberate V1 safety boundaries:

- `lm_head` and embeddings remain full precision.
- Qwen hybrid `linear_attn` `conv1d`, `in_proj_a`, and `in_proj_b` remain full
  precision; ordinary supported linear matrices continue through MXFP8.
- `mtp.*` remains BF16. Use the official compressed-tensors MTP helper to write
  MTP tensors into the output and update the Safetensors index/config ignore
  list.
- `model.visual.*`/vision stays BF16 even though Phase 3 serves text-only.
- Norms are never targets in model-free PTQ and must remain excluded.

No depth-based exclusions are configured in V1. A later candidate may preserve
only layers proven sensitive by an evaluation, and must use a distinct output.

## Runtime Modes

### Baseline: 64K MTP Off

The required semantics are:

```text
CUDA_VISIBLE_DEVICES=0,1
vllm serve <Golden checkpoint>
  --tensor-parallel-size 2
  --dtype bfloat16
  --kv-cache-dtype auto
  --language-model-only
  --max-model-len 65536
  --gpu-memory-utilization 0.90
  --reasoning-parser qwen3
  --enable-auto-tool-choice
  --tool-call-parser qwen3_coder
  --host 127.0.0.1 --port 8000
```

This starts MTP-off. The `dtype` applies to unquantized tensors and related
compute; it does not convert stored MXFP8 weights back into a BF16 checkpoint.
`kv-cache-dtype auto` preserves the model-selected unquantized KV behavior and
does not request FP8 KV.

### Optional: MTP-1

Only after baseline acceptance, start with every baseline value unchanged and
add `--speculative-config '{"method":"mtp","num_speculative_tokens":1}'`.
The selected vLLM source maps Qwen3.5/Qwen3.6 MTP configuration to its native
MTP model path. MTP-1 is not enabled by default because it must be measured
against the accepted MTP-off behavior.

## Operational Behavior and Failure Handling

- Preflight refuses a missing source, output overwrite, wrong filesystem parent,
  bad source index, incorrect architecture, insufficient disk space, unavailable
  GPUs, or an unsupported profile.
- Build starts in a timestamped same-filesystem staging directory and promotes
  only after the output verifier succeeds. On failure, staging is removed; source
  and any previously promoted Golden output remain untouched.
- The server script verifies the checkpoint/profile before starting and binds
  only to loopback. It records logs under ignored `logs/`.
- If a Qwen hybrid/Mamba CUDA-graph cache-size error is observed, retry exactly
  once with `--max-cudagraph-capture-size 128` and record the error and result.
  Do not add the flag preemptively.

## Observability and Evidence

Record the source/output manifest file SHA256s, submodule commits, quantization
metadata, exact server command, `/health`, `/v1/models`, deterministic chat
response, and `nvidia-smi` memory/utilization for both GPUs. The Phase 4
comparison uses identical `vllm bench serve` parameters for MTP-off and MTP-1.

## Security Model and Hardening Notes

- All checkpoint data remains local on the ext4 `/data/linux-fast` filesystem.
- The model server binds to `127.0.0.1`; broader network exposure requires a
  separate explicit decision.
- Do not place model files, manifests, virtual environments, logs, tokens, or
  secrets in Git. Do not inspect or print credential values.
- Do not use `--trust-remote-code`, online quantization, or CPU offload as an
  unreviewed startup workaround.

## Test Strategy Mapping

| Concern | Validation |
| --- | --- |
| Source invariants | `scripts/check-model.py` and BF16 manifest verification |
| Build configuration | `scripts/validate-quantize-config.py` |
| Persistent output format | `scripts/verify-fp8-checkpoint.py` and MXFP8 manifest |
| Runtime configuration | `scripts/validate-runtime-config.py` |
| Script integrity | `bash -n scripts/*.sh` and `python3 -m py_compile scripts/*.py` |
| Static scope integrity | `repo-task-driven` placeholder, roundtable, sync, and residual-text checks |
| Functional runtime | health, models, deterministic chat, parser/tool smoke, GPU telemetry |
| MTP decision | equivalent MTP-off/MTP-1 smoke and benchmark evidence |
