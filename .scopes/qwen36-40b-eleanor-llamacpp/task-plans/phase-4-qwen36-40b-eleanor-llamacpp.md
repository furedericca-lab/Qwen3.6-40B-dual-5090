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

- [x] T030 [Infra] Establish MTP-off baseline
  - DoD: Restart server with `MTP_MODE=off scripts/llama-server-first-boot.sh`.
    The launcher omits all speculative decoding args; llama.cpp defaults to
    spec-type none. Do NOT use `$@ --spec-type none` — llama.cpp appends
    spec types (it does not replace them), so passing both `--spec-type
    draft-mtp` and `--spec-type none` would still enable MTP via bitmask.
    Run raw, Chinese, and Python probes. Record tok/s. The same MTP GGUF
    is used; only `MTP_MODE` differs between runs.
  - Evidence: Probe outputs saved to evidence/mtp-comparison/mtp-off-*.json.
    Mean decode speed: 34.71 tok/s.

- [x] T031 [Infra] Establish MTP-on baseline
  - DoD: Server with MTP enabled (`MTP_MODE=on scripts/llama-server-first-boot.sh`,
    which passes `--spec-type draft-mtp`, `--spec-draft-n-max 2`,
    `--spec-draft-n-min 0`, `--spec-draft-p-min 0.75`). Run the same raw,
    Chinese, and Python probes. Record tok/s.
  - Evidence: Probe outputs saved to evidence/mtp-comparison/n2-p075-*.json.
    Mean decode speed: 63.10 tok/s (1.82x speedup, 94.1% acceptance).

- [x] T032 [QA] Compare quality
  - DoD: MTP-on outputs are semantically equivalent to MTP-off for the same
    prompts and greedy/low-temperature settings. No repeated-symbol collapse,
    no empty output.
  - Evidence: All configurations produce correct, coherent output. Math: 2+3=5.
    Chinese: fluent quantum computing explanation. JSON: valid objects.
    Python: correct merge_sorted_lists. Summary: accurate bullet points.
    No quality degradation observed with MTP at any n-max setting.

- [x] T033 [QA] Compare throughput across MTP configurations
  - DoD: Run four MTP configurations and record decode tok/s for each:
    A. n-max=2, p-min=0 (current baseline without p-min gating)
    B. n-max=2, p-min=0.75 (current baseline with p-min gating)
    C. n-max=3, p-min=0 (higher draft count, no gating)
    D. n-max=3, p-min=0.75 (higher draft count, with gating)
    Record draft acceptance rate and mean draft length for each configuration.
    Compare against MTP-off baseline.
  - Evidence: Full results in evidence/mtp-comparison/RESULTS.md.
    Summary table:

    | Config       | Mean tok/s | Speedup | Accept Rate |
    |-------------|----------:|--------:|------------:|
    | MTP-off     |     34.71 |   1.00x |         N/A |
    | n=2, p=0    |     73.52 |   2.12x |       82.9% |
    | n=2, p=0.75 |     63.10 |   1.82x |       94.1% |
    | n=3, p=0    |     78.60 |   2.26x |       69.9% |
    | n=3, p=0.75 |     69.90 |   2.01x |       93.5% |

- [x] T034 [Docs] Finalize deployment documentation
  - DoD: README.md, AGENTS.md, scope docs, and launcher all agree on the
    final deployment configuration (128K, MTP status, dual-5090 flags).
    The optimal n-max and p-min values from T033 are recorded as the
    production configuration.
  - Evidence: Launcher defaults updated to n=2, p_min=0. All scope docs,
    AGENTS.md, README.md, and wiki pages updated to reflect Phase 4 results.
    Production default: n=2, p_min=0 (2.12x speedup, 82.9% acceptance).

Checkpoint: Deployment is complete with MTP benefit quantified and documented.
