---
description: Gate any quality-recovery candidate behind measured evidence.
---

# Tasks: Qwen3.6-40B-Eleanor MXFP8 W8A8 Deployment

## Input

- Frozen BF16 and Golden MXFP8 manifests
- Phase 3 and Phase 4 runtime evidence
- Task-quality evaluation evidence

## Canonical Architecture / Key Constraints

- The Golden MXFP8 output remains immutable.
- Do not preserve arbitrary depth-based layers without measured sensitivity.
- Any AutoRound route requires calibration data, a distinct output path, and a
  new quantization candidate; it is not an in-place rerun of RTN.

## Format

- `[ID] [P?] [Component] Description`
- `[P]` means parallelizable.

## Phase 5: Quality-Gated HQ V2 or AutoRound

Goal: avoid unnecessary complexity while keeping a controlled recovery path for
materially demonstrated MXFP8 quality loss.

Definition of Done: either quality evidence closes this phase as unnecessary, or
a new scope defines an independently named candidate and acceptance criteria.

Tasks:
- [ ] T015 [QA] Establish BF16 versus Golden MXFP8 quality evidence
  - DoD: an agreed representative evaluation reports task-level comparison and identifies a material regression or records no action needed.
- [ ] T016 [Config] Define only evidence-backed HQ exclusions
  - DoD: any sensitivity-derived BF16 layers are named in a new candidate profile and output directory; Golden MXFP8 files remain unchanged.
- [ ] T017 [Backend] Evaluate AutoRound only after RTN evidence warrants it
  - DoD: calibration provenance, repeatable configuration, separate candidate output, and comparison against Golden RTN are written in a new scope before execution.

Checkpoint: no Phase 5 conversion occurs under this scope without a new approved candidate decision.

## Dependencies & Execution Order

- Phase 5 depends on quality evidence after Phase 3; Phase 4 informs the runtime choice but does not change quantization quality.
