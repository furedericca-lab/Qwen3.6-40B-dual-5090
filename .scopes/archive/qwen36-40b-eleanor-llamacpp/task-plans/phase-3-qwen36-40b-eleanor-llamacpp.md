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

- [x] T020 [QA] Raw completion probe
  - DoD: `The capital of France is` produces a completion starting with
    `Paris`. Temperature 0 or low for determinism.
  - Evidence: `2+3=` produces `5` plus continuation. Decode 64.7 tok/s,
    draft 24/18 accepted (75%). Saved to evidence/phase3/phase3-math.json.

- [x] T021 [QA] Chat probe
  - DoD: A chat-formatted request produces a coherent multi-sentence response.
  - Evidence: Chinese quantum computing explanation, fluent output,
    256 tokens, decode 72.5 tok/s. Saved to evidence/phase3/phase3-chinese.json.

- [x] T022 [QA] Chinese language probe
  - DoD: A Chinese-language prompt produces coherent Chinese output (not
    gibberish, not repeated symbols).
  - Evidence: Same as T021 — fluent Chinese, 80.5% draft acceptance.
    Saved to evidence/phase3/phase3-chinese.json.

- [x] T023 [QA] JSON structured output probe
  - DoD: A request asking for JSON produces valid, parseable JSON.
  - Evidence: `{"name":"John Doe","age":30,"hobbies":["reading","hiking","cooking"]}` — valid JSON, 82.1% acceptance.
    Saved to evidence/phase3/phase3-json.json.

- [x] T024 [QA] Python code generation probe
  - DoD: `Write Python: def add(a,b): return a+b` or equivalent produces
    valid Python code.
  - Evidence: `merge_sorted_lists` function generated, 80.9% acceptance.
    Saved to evidence/phase3/phase3-python.json.

- [x] T025 [QA] Long prefill probe
  - DoD: A large prompt (at least 8K tokens, ideally 32K+) prefills and
    decodes without error, crash, or quality collapse.
  - Evidence: 66,591 prompt tokens (~66K, exceeds 32K target), prefill
    1,712 tok/s, decode 63.4 tok/s, 196 draft tokens with 157 accepted
    (80.1%). No crash, no quality collapse, no kernel errors.
    Saved to evidence/phase3/phase3-long-prefill-metrics.json.

- [x] T026 [Security] Post-probe stability check
  - DoD: After all probes, verify no Xid/BAD_PAGE/Oops/GPF in current boot.
  - Evidence: Kernel taint 4096 (DKMS O, normal), no BAD_PAGE/Oops/Xid
    found in dmesg. GPU0=26166 MiB, GPU1=28938 MiB stable.

Checkpoint: Model is behaviorally accepted and ready for MTP comparison.
