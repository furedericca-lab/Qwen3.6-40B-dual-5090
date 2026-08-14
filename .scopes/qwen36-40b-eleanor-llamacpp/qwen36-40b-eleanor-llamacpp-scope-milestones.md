---
description: Scope boundaries and milestones for qwen36-40b-eleanor-llamacpp.
---

# qwen36-40b-eleanor-llamacpp Scope and Milestones

## In Scope

- Deploy Qwen3.6-40B-Eleanor Q8_0 GGUF via llama.cpp on dual RTX 5090.
- Build the pinned llama.cpp fork with CUDA support for RTX 5090 (sm_120a).
- Configure and verify 128K context startup with MTP enabled.
- Create the canonical `llama-server-first-boot.sh` launcher script.
- Run API health, behavior probes (raw, Chinese, JSON, Python), and prefill.
- Compare MTP-on vs MTP-off performance and quality.

## Out of Scope

- Reopening the archived vLLM/MXFP8 deployment scope.
- GGUF conversion, requantization, or alternative quantization types.
- Updating the llama.cpp fork beyond the pinned commit `efb81ab`.
- Binding beyond localhost without explicit approval.
- CPU weight offload as the primary strategy (last resort only).

## Decision Log

| Boundary / Decision | Evidence Source | Evidence Strength | Conflict | Confidence | Confidence Reason | Result |
|---|---|---|---|---:|---|---|
| Switch from vLLM to llama.cpp | Archived vLLM scope Phase 3 blocker | High | None | 0.95 | vLLM could not fit 64K KV cache at 0.90 utilization | Accepted |
| Use pre-built Q8_0 GGUF | User confirmed download and verification | High | None | 0.95 | User provided the file and stated it is verified | Accepted |
| 128K context target | User requirement | High | None | 0.90 | Fits within dual-5090 VRAM based on weight+KV estimate | Accepted |
| MTP enabled | User requirement | High | None | 0.95 | GGUF contains nextn tensors and metadata | Accepted |
| llama.cpp fork efb81ab | Matches reference project pin | High | None | 0.90 | Same fork commit as deepseek-v4-flash project | Accepted |

## Milestones

| Milestone | Status | Evidence |
|---|---|---|
| llama.cpp compiled with CUDA | Complete | sm_120a build exit 0, `--list-devices` sees both RTX 5090 |
| Scope scaffolded | Complete | `.scopes/qwen36-40b-eleanor-llamacpp/` created |
| GGUF artifact verified | Complete | Metadata confirms qwen35 arch, 97 blocks, Q8_0, MTP present, head_dim=256, 25 dense attn layers |
| 128K startup | Pending | `llama-server` loads at `-c 131072` without OOM |
| API and behavior probes | Pending | `/health`, `/v1/models`, raw/chat/Chinese/JSON/Python pass |
| MTP comparison | Pending | MTP-on vs MTP-off evidence recorded |

## Dependencies

- Pre-built Q8_0 GGUF at `/data/linux-fast/models/Qwen3.6-40B-Eleanor-GGUF/`
- `llama.cpp` submodule at commit `efb81ab` (native qwen35 support)
- CUDA Toolkit 13.3, Clang 21, CMake 4.4, Ninja
- Dual RTX 5090 with idle VRAM
- Clean kernel boot (taint 0 or 4096, no BAD_PAGE/Oops/Xid)

## Exit Criteria

- `llama-server` starts at 128K context on dual 5090 without OOM.
- API health and all behavior probes pass.
- MTP-on vs MTP-off comparison is recorded.
- Launcher script, README, AGENTS.md, and scope docs all agree.
- No kernel or GPU stability events in accepted runs.

## Escalation Triggers

- Escalate only when code/runtime evidence, authoritative wiki, and scope docs
  materially conflict and the conflict cannot be resolved from local evidence.
- Escalate for data deletion, permission semantics, production access model, or
  public API compatibility decisions outside the stated boundaries.
- Escalate when user-specified boundaries cannot be satisfied together
  (e.g. if 128K context cannot fit after all OOM ladder steps).
