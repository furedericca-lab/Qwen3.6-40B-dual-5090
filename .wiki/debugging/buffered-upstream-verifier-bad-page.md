---
title: Buffered upstream verifier BAD_PAGE trigger investigation
type: debugging
status: historical
scope: qwen3.6-40b-eleanor-deployment
related_scopes: []
related_files:
  - scripts/verify-source-upstream-direct.py
  - AGENTS.md
source_docs: []
tags:
  - bad-page
  - ext4
  - buffered-io
  - o-direct
  - trigger-probe
last_checked: 2026-08-14
updated: 2026-08-14T00:00:00Z
---

# Buffered upstream verifier BAD_PAGE trigger investigation

> **Historical note (2026-08-14):** This investigation was conducted during
> the archived vLLM/MXFP8 deployment scope. The probe scripts
> (`verify-source-upstream-buffered-incident.py`, `run-buffered-io-probe.sh`)
> were removed when the project switched to llama.cpp. The incident findings
> remain valid for large-model safety on this host. The production identity
> verifier `scripts/verify-source-upstream-direct.py` is retained.

## Incident

The original full remote verifier uses ordinary buffered `path.open("rb").read(32 MiB)` loops to hash Eleanor LFS safetensors. It verified 30/30 source files against `DavidAU/Qwen3.6-40B-Fable-Fusion-6-Core-Deckard-Eleanor-Heretic-Uncensored` at `7905312899185973580867f69d20d4cfc374ccaa`, then triggered `BUG: Bad page state` in the same workload. The kernel logged `page does not match folio`, `invalid mapping: dead...`, then `kswapd0` reported `corrupted mapping in tail page`.

The exact taint decoding is `4128 = 4096 + 32`: `4096` is `O` for the normally loaded external NVIDIA DKMS module; `32` is `B` for BAD_PAGE. A fresh normal boot should therefore be accepted with taint `0` or `4096`, provided its current-boot kernel log has no BAD_PAGE, compound-head, Oops, GPF, or NVIDIA Xid. The BAD_PAGE bit cannot be cleared on a live kernel; reboot is required.

## Probe Design

The buffered-incident probe scripts were removed during the vLLM-to-llama.cpp
transition. Their design is documented here for historical reference:

The baseline workload used `--probe` mode with exactly one repository-relative
file and a byte limit. It supported `--start-offset`, `--chunk-mib`, and
`--repeats`; it recorded device, inode, byte range, boot taint, and new kernel
signatures in JSON. The wrapper script rejected a dirty boot, created an
ignored per-run evidence directory, captured journal records from the run
start, and optionally used `--trace-syscalls` to preserve file descriptors,
offsets, read sizes, timing, and paths through strace.

The first fresh-boot probe is one 1 MiB read of `model-00001-of-00017.safetensors`; each subsequent fresh boot changes only one variable: read length, chunk size, offset, repetition count, or shard. The probe stops at the first new kernel event. Initial no-trace runs preserve the original timing; a successful reproduction is then repeated once with syscall tracing for correlation.

## Boundary

This is a trigger investigation, not a production verifier. `scripts/verify-source-upstream-direct.py` is the production identity route. The DeepSeek project has previously reproduced the same buffered page-cache folio failure family across kernels and with MGLRU both enabled and disabled. That narrows the known trigger to full buffered checkpoint I/O and generic reclaim; it does not prove whether the underlying cause is the kernel folio lifecycle, RAM/IMC, DMA/IOMMU, or storage topology.
