---
description: Task list for qwen36-40b-eleanor-llamacpp phase 4: MTP comparison.
---

# Tasks: qwen36-40b-eleanor-llamacpp Phase 4

## Phase 4: MTP-on vs MTP-off comparison

Goal: Quantify the benefit of MTP (Multi-Token Prediction) speculative decoding
and confirm it does not degrade output quality.

Definition of Done: Side-by-side comparison of MTP-on and MTP-off for
throughput (tok/s) and output quality, recorded as evidence.

Tasks:

- [ ] T030 [Infra] Establish MTP-off baseline
  - DoD: Restart server with `MTP_MODE=off scripts/llama-server-first-boot.sh`.
    The launcher omits all speculative decoding args; llama.cpp defaults to
    spec-type none. Do NOT use `$@ --spec-type none` — llama.cpp appends
    spec types (it does not replace them), so passing both `--spec-type
    draft-mtp` and `--spec-type none` would still enable MTP via bitmask.
    Run raw, Chinese, and Python probes. Record tok/s. The same MTP GGUF
    is used; only `MTP_MODE` differs between runs.
  - Evidence: Probe outputs and timing saved to evidence/mtp-off/.

- [ ] T031 [Infra] Establish MTP-on baseline
  - DoD: Server with MTP enabled (`MTP_MODE=on scripts/llama-server-first-boot.sh`,
    which passes `--spec-type draft-mtp`, `--spec-draft-n-max 2`,
    `--spec-draft-n-min 0`, `--spec-draft-p-min 0.75`). Run the same raw,
    Chinese, and Python probes. Record tok/s.
  - Evidence: Probe outputs and timing saved to evidence/mtp-on/.

- [ ] T032 [QA] Compare quality
  - DoD: MTP-on outputs are semantically equivalent to MTP-off for the same
    prompts and greedy/low-temperature settings. No repeated-symbol collapse,
    no empty output.
  - Evidence: Side-by-side comparison table recorded.

- [ ] T033 [QA] Compare throughput
  - DoD: Record decode tok/s for both configurations. Document any MTP
    acceleration benefit.
  - Evidence: Timing comparison table recorded.

- [ ] T034 [Docs] Finalize deployment documentation
  - DoD: README.md, AGENTS.md, scope docs, and launcher all agree on the
    final deployment configuration (128K, MTP status, dual-5090 flags).
  - Evidence: `ok-skill repo-task-driven check --scope qwen36-40b-eleanor-llamacpp` passes.

Checkpoint: Deployment is complete with MTP benefit quantified and documented.
