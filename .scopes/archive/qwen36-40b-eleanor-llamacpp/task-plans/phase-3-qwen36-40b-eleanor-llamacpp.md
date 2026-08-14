---
description: Task list for qwen36-40b-eleanor-llamacpp phase 3: behavior probes.
---

# Tasks: qwen36-40b-eleanor-llamacpp Phase 3

## Phase 3: Behavior probes and semantic acceptance

Goal: Verify the deployed model produces coherent, correct output across
multiple modalities (raw text, chat, Chinese, JSON, Python code) and can handle
long prefill.

Definition of Done: All probes pass; long prefill completes without decode
collapse; no stability events.

Tasks:

- [ ] T020 [QA] Raw completion probe
  - DoD: `The capital of France is` produces a completion starting with
    `Paris`. Temperature 0 or low for determinism.
  - Evidence: curl completion output saved to evidence.

- [ ] T021 [QA] Chat probe
  - DoD: A chat-formatted request produces a coherent multi-sentence response.
  - Evidence: curl chat completion output saved.

- [ ] T022 [QA] Chinese language probe
  - DoD: A Chinese-language prompt produces coherent Chinese output (not
    gibberish, not repeated symbols).
  - Evidence: curl output saved.

- [ ] T023 [QA] JSON structured output probe
  - DoD: A request asking for JSON produces valid, parseable JSON.
  - Evidence: curl output saved; `jq .` validates parseability.

- [ ] T024 [QA] Python code generation probe
  - DoD: `Write Python: def add(a,b): return a+b` or equivalent produces
    valid Python code.
  - Evidence: curl output saved.

- [ ] T025 [QA] Long prefill probe
  - DoD: A large prompt (at least 8K tokens, ideally 32K+) prefills and
    decodes without error, crash, or quality collapse.
  - Evidence: Prefill token/s and decode output recorded.

- [ ] T026 [Security] Post-probe stability check
  - DoD: After all probes, verify no Xid/BAD_PAGE/Oops/GPF in current boot.
  - Evidence: `journalctl -k -b --no-pager | grep -iE 'Xid|BAD_PAGE|Oops'`.

Checkpoint: Model is behaviorally accepted and ready for MTP comparison.
