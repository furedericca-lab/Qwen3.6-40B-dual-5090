---
title: Maintenance Log
type: maintenance-log
status: current
updated: 2026-08-13T13:05:42Z
---

# Maintenance Log

Append-only history for wiki updates caused by scope work, implementation closeout, or knowledge refresh.

## 2026-08-13T13:15:31Z [qwen3.6-40b-eleanor-deployment]

- Summary: Recorded the buffered verifier as the BAD_PAGE trigger workload and added fresh-boot bounded probe instrumentation.
- Pages: debugging/buffered-upstream-verifier-bad-page.md
- Verification: python3 -m py_compile scripts/*.py; scripts/run-buffered-io-probe.sh --probe --only model-00001-of-00017.safetensors --max-bytes-per-file 1048576
- Residual risk: The host root cause is still unproven; no probe may run until reboot clears BAD_PAGE.

## 2026-08-14T07:20:33Z [qwen36-40b-eleanor-llamacpp]

- Summary: Scaffolded new llama.cpp deployment scope. Compiled llama.cpp fork efb81ab with CUDA sm_120a. Removed vLLM scripts, configs, and submodules. Created launcher and updated AGENTS.md, README.md.
- Pages: none
