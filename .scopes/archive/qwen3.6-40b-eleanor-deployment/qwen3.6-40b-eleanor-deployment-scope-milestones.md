# Qwen3.6-40B-Eleanor MXFP8 W8A8 Scope Milestones

## In Scope

- Freeze an external BF16 source manifest and a post-verification MXFP8 output
  manifest under `/data/linux-fast/models`.
- Pin vLLM, LLM Compressor, and compressed-tensors source as Git submodules.
- Create a permanent, offline RTN MXFP8 W8A8 compressed-tensors checkpoint.
- Preserve the selected high-sensitivity/nonstandard modules in BF16.
- Validate a local TP=2 64K text-only vLLM launch, then separately compare
  native MTP-1.

## Out of Scope

- Mutating, moving, or repacking the Golden BF16 source.
- Online conversion, CPU weight offload, LAN/public serving, or remote model
  downloads during runtime.
- Vision serving acceptance, 96K/128K capacity claims, concurrency acceptance,
  automatic throughput tuning, or automatic MTP promotion.
- AutoRound, calibration-dataset selection, and an HQ V2 checkpoint absent
  measured regression evidence and a new candidate scope.

## Decision Log

| Decision | Status | Basis | Handling |
| --- | --- | --- | --- |
| Use offline `MXFP8` W8A8 rather than FP8 dynamic | Accepted | Explicit user direction; pinned compressor/vLLM support | Golden V1 only. |
| Use model-free PTQ | Accepted | 75 GiB source and limited host RAM; source implementation is shard-wise | No full `AutoModel` build path. |
| Preserve special layers in BF16 | Accepted | User-defined safety profile and observed source namespace | Regexes must match `lm_head`, embeddings, special linear attention, MTP, and vision. |
| MTP disabled for first boot | Accepted | Isolate checkpoint load/capacity evidence | MTP-1 is an optional Phase 4 comparison. |
| `--kv-cache-dtype auto` | Accepted | User-directed BF16/auto policy and current vLLM Qwen hybrid configuration | Do not force FP8 KV. |
| 64K initial context | Accepted | Capacity-first runtime acceptance | Increase only in a later evidence-backed scope. |
| AutoRound / HQ V2 | Deferred | Needs task-quality and calibration provenance | Separate output and scope only. |

## Milestones and Acceptance Gates

| Milestone | Scope phase | Acceptance gate | Exit criterion |
| --- | --- | --- | --- |
| M1: Frozen inputs | Phase 1 | BF16 manifest, valid source config/index, fixed clean submodules, Blackwell capability | Source integrity and reproducible source dependencies recorded. |
| M2: Golden checkpoint | Phase 2 | Local quantizer succeeds and verifier proves compressed-tensors MXFP8 W8A8 plus BF16 exclusions/MTP | Output manifest created; output treated immutable. |
| M3: MTP-off service | Phase 3 | TP=2 64K MTP-off passes API and GPU capacity checks | Golden artifact is deployable locally. |
| M4: MTP decision | Phase 4 | Same smoke and like-for-like benchmark compare MTP-off and MTP-1 | MTP is promoted or rejected with recorded evidence. |
| M5: Quality recovery decision | Phase 5 | BF16 vs Golden quality comparison | No action, or a separate V2 scope is opened. |

## Dependencies Across Milestones

- M1 blocks M2 because output provenance is meaningless without a frozen input.
- M2 blocks M3 because runtime must never target a partial/staging checkpoint.
- M3 blocks M4 because MTP-1 cannot establish a root cause for a baseline load
  or capacity failure.
- M5 depends on a runnable M3 artifact and evaluation evidence; M4 can inform
  runtime selection but does not replace quality evidence.

## Escalation Triggers

- Stop conversion if the source manifest differs, the source index has a missing
  shard, or a source namespace conflicts with configured preservation regexes.
- Stop promotion if output metadata does not satisfy MXFP8 W8A8 requirements,
  MTP is missing, or ignored BF16 modules appear quantized.
- Stop runtime changes if loading requires online quantization, CPU offload,
  trust-remote-code, a public bind, or an unexplained workaround.
- Do not execute M5 in this scope when quality loss is merely suspected rather
  than measured.
