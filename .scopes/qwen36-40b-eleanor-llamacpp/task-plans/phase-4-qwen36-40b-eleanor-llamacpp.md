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
  - DoD: Restart server with MTP disabled (equivalent to
    `--no-mtp` or `nextn_predict_layers: 0`). Run raw, Chinese, and Python
    probes. Record tok/s.
  - Evidence: Probe outputs and timing saved to evidence/mtp-off/.

- [ ] T031 [Infra] Establish MTP-on baseline
  - DoD: Server with MTP enabled (default, `nextn_predict_layers: 1`). Run the
    same raw, Chinese, and Python probes. Record tok/s.
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
