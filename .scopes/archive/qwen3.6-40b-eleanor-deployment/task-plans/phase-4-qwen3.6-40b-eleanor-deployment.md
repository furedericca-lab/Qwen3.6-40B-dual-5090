---
description: Compare native Qwen3.6 MTP-1 against the accepted MTP-off baseline.
---

# Tasks: Qwen3.6-40B-Eleanor MXFP8 W8A8 Deployment

## Input

- Phase 3 runtime evidence
- `config/runtime.env`
- `scripts/vllm-server-first-boot.sh`
- `scripts/smoke-api.sh`

## Canonical Architecture / Key Constraints

- Use the same Golden checkpoint and Phase 3 runtime values.
- Add only `--speculative-config '{"method":"mtp","num_speculative_tokens":1}'`.
- Preserve BF16 MTP tensors; MTP is a latency experiment, not a prerequisite for
  initial production service.

## Format

- `[ID] [P?] [Component] Description`
- `[P]` means parallelizable.

## Phase 4: MTP-1 Comparison

Goal: establish whether native MTP-1 improves the intended low-concurrency
latency profile without changing the Golden checkpoint.

Definition of Done: MTP-1 passes the same API smoke, and like-for-like
`vllm bench serve` measurements compare TTFT, TPOT, output tokens/s, total
throughput, and GPU memory with MTP-off.

Tasks:
- [ ] T012 [Config] Launch native MTP-1 from the MTP-off profile
  - DoD: the only semantic runtime delta is `--speculative-config '{"method":"mtp","num_speculative_tokens":1}'`; the exact command is recorded.
- [ ] T013 [QA] Run equivalent functional smoke
  - DoD: health, models, deterministic chat, and tool/reasoning responses pass using the MTP-1 process.
- [ ] T014 [QA] Compare benchmark evidence
  - DoD: `vllm bench serve --backend openai-chat --endpoint /v1/chat/completions --model qwen3.6-40b-eleanor --dataset-name random --random-input-len 2048 --random-output-len 512 --num-prompts 100` is run for both profiles with recorded results and an explicit promotion decision.

Checkpoint: Phase 5 remains deferred unless quality or operational evidence requires it.

## Dependencies & Execution Order

- Phase 4 depends on Phase 3.
- T013 and T014 follow T012; benchmark comparison requires the Phase 3 baseline.
