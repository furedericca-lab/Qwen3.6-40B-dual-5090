# Qwen3.6-40B-Eleanor MXFP8 W8A8 Implementation Research Notes

## Problem Statement and Current Baseline

The repository must serve the BF16 Qwen3.6 Eleanor checkpoint from
`/data/linux-fast/models/Qwen3.6-40B-Eleanor` on two RTX 5090 GPUs without
repeating an online conversion at every server start. The source is about
75 GiB, while the two GPUs provide about 64 GiB total VRAM. The output must be
a separate permanent checkpoint under
`/data/linux-fast/models/Qwen3.6-40B-Eleanor-MXFP8-W8A8`.

Observed source facts:

- `config.json`: `Qwen3_5ForConditionalGeneration`, top-level
  `model_type=qwen3_5`, BF16, and `text_config.mtp_num_hidden_layers=1`.
- `model.safetensors.index.json`: 17 `model-*-of-00017.safetensors` files plus
  `model-mtp-restored.safetensors`; `mtp.fc.weight` is indexed in that MTP file.
- Indexed names include `model.language_model.embed_tokens`, `lm_head`,
  `model.language_model.layers.*.linear_attn`, and `model.visual.*`.

The planned project files are currently a scaffold. No project virtual
environment, source manifest, output checkpoint, server, benchmark, or quality
evaluation exists.

## Gap Analysis With Evidence

| Gap | Evidence | Required handling |
| --- | --- | --- |
| Complete-model loading exceeds practical host/GPU capacity | Source is about 75 GiB; project preflight observed about 42 GiB host RAM and two 32 GiB GPUs | Use local `llmcompressor.model_free_ptq`, not an `AutoModel.from_pretrained` conversion. |
| A permanent MXFP8 output needs exact metadata | `llm-compressor/src/llmcompressor/entrypoints/model_free/__init__.py` updates `config.json` and the Safetensors index | Verify config-group weights and input activations, output index, and ignored rules before promotion. |
| MXFP8 W8A8 needs native data/scale semantics | `compressed-tensors/src/compressed_tensors/quantization/quant_scheme.py` defines `MXFP8` as 8-bit float, symmetric, group 32, uint8 scales, with dynamic group-32 input activations | Use the preset string exactly: `scheme="MXFP8"`. |
| vLLM needs a checkpoint-backed route rather than an online flag | `vllm/.../compressed_tensors_w8a8_mxfp8.py` loads E4M3 values plus uint8 E8M0 group scales; `compressed_tensors.py` identifies group-32 symmetric float-8 uint8-scale W8A8 | Leave `--quantization` unset and use checkpoint metadata auto-detection. |
| Hybrid linear-attention and VLM paths are riskier than ordinary Linear modules | Source index has `linear_attn`, `model.visual`, and special `conv1d`/`in_proj_*` tensors | Preserve requested special namespaces in BF16 for V1. |
| Transformers does not load MTP tensors into the main Qwen3.5 model | `compressed-tensors/src/compressed_tensors/utils/mtp.py` documents MTP extraction, index update, and quantization ignore behavior | Do not quantize MTP; preserve it via the official MTP save helper, and verify the resulting index/ignore pattern. |
| Native MTP must not obscure basic load failure | `vllm/docs/features/speculative_decoding/mtp.md` supports `method=mtp` and recommends one token as a start | First boot MTP-off; compare MTP-1 only after baseline acceptance. |

## Architecture and Implementation Options

| Option | Benefits | Cost / rejection reason |
| --- | --- | --- |
| Online vLLM FP8/MXFP8 conversion | Short initial command | Repeats conversion at start, is not a permanent Safetensors artifact, and violates the user requirement. Rejected. |
| `oneshot` over a full transformers model | Familiar recipe API | Requires loading the complete model graph and payload; unsuitable for observed capacity. Rejected. |
| Offline model-free RTN MXFP8 | Shard-wise, no calibration dataset, two-GPU worker distribution, permanent compressed-tensors result | Must verify excluded modules, index semantics, and quality. Selected for V1. |
| Offline MXFP8 AutoRound | Potential quality recovery beyond RTN | Requires calibration/provenance and a separate candidate. Deferred until RTN quality evidence. |
| MXFP8A16 | Preserves activation precision | Does not meet requested Blackwell W8A8 path. Rejected for production V1. |
| NVFP4/MXFP4 | Greater compression | Greater quality risk; contrary to the high-quality first production candidate. Rejected for V1. |

## Decision Roundtable

| Decision | Requirement Clarity | Evidence Strength | Evidence Source | Conflict | User-Intent Confidence | Implementation Confidence | Risk/Reversibility | Outcome | Confidence Reason |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Offline permanent MXFP8 W8A8 | 5 | 5 | User direction; pinned compressor preset; vLLM loader | None | 5 | 5 | 4 | Accepted for Golden V1 | Exact `MXFP8` preset and vLLM W8A8 loader agree. |
| Shard-wise model-free PTQ | 5 | 5 | Pinned `model_free_ptq` implementation and host capacity | None | 5 | 5 | 5 | Accepted | Avoids complete-model loading and supports two devices. |
| Preserve special modules in BF16 | 5 | 4 | User preservation list and observed tensor names | None | 5 | 5 | 4 | Accepted for V1 | Direct namespace rules avoid speculative depth-based choices. |
| 64K MTP-off baseline | 5 | 5 | User direction; vLLM native MTP documentation | None | 5 | 5 | 5 | Accepted as Phase 3 | Separates core checkpoint acceptance from speculative decoding. |
| MTP-1 after baseline | 5 | 5 | Pinned vLLM native MTP config and Qwen3.5 MTP test | None | 5 | 4 | 5 | Deferred to Phase 4 | Exact target performance requires measurement on this host. |
| AutoRound/HQ V2 deferred | 5 | 5 | User direction and distinct calibration requirements | None | 5 | 5 | 5 | Deferred to a new candidate scope | Prevents replacing the Golden RTN artifact without evidence. |

## Selected Design and Rationale

Use `model_free_ptq` with `scheme="MXFP8"`, two CUDA devices, and two workers.
The first candidate preserves `lm_head`, `embed_tokens`, `conv1d`, `in_proj_a`,
`in_proj_b`, `mtp`, `visual`/`vision`, and norms in BF16. Quantized regular
weights use E4M3 with group-32 E8M0 scales. Dynamic group-32 MXFP8 activation
quantization is specified in `quantization_config` and performed by vLLM at
inference time.

vLLM receives the artifact with `--dtype bfloat16`, `--kv-cache-dtype auto`,
TP=2, text-only mode, and a 64K limit. Do not add a quantization CLI override,
because the compressed-tensors metadata selects the implementation. MTP remains
off until the exact same profile passes API and capacity checks; then compare
only the addition of native MTP-1.

## Test and Validation Strategy

1. Verify source metadata and shard accounting without reading full tensor
   payloads: `scripts/check-model.py`.
2. Generate and record a full-file SHA256 manifest for the source before a
   build; verify that source manifest after the build.
3. Validate a nonexisting target, same-filesystem staging path, free space,
   scheme, local dependency pins, and two GPUs before conversion.
4. Verify generated `quantization_config`, all output index paths, MTP payload,
   ignored rules, and weight/scale dtype semantics before output promotion.
5. Generate an output SHA256 manifest only after the output verifier passes.
6. Launch MTP-off 64K and record health, models, deterministic chat, parser/tool
   behavior, server command, and balanced GPU telemetry.
7. Run MTP-1 with identical conditions, then compare functional behavior and
   recorded benchmark metrics. No claim of improvement without both results.

## Risks, Assumptions, and Unresolved Questions

- Assumption: RTX 5090 reports compute capability at least 10.0; Phase 1 must
  verify it on the host before compression.
- Risk: a special Qwen hybrid tensor may require an additional BF16 exclusion.
  The first run must fail closed on an unsupported group-32 shape or vLLM load
  mismatch; do not widen exclusions silently.
- Risk: source/output full SHA256 manifests are I/O-heavy. They are deliberate
  provenance gates, not a routine startup check.
- Unresolved: actual 64K KV headroom and MTP-1 latency benefit require runtime
  evidence; scope claims neither before Phase 3/4.
- Unresolved: task-level quality loss must be measured before an HQ V2 or
  AutoRound proposal is justified.
