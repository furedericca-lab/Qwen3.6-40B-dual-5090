# AGENTS.md

## Source Of Truth

1. Active deployment contract under `.scopes/` for the current scope.
2. Durable incident and operational knowledge under `.wiki/`.
3. `README.md` for operator entry points.
4. `config/` for build and serving profiles.
5. Pinned upstream submodules: `llama.cpp/`, and any others declared by the
   active scope.

The scope is authoritative for phase gates and recorded evidence. Do not mark a
phase complete, start a later phase, or rewrite a Golden checkpoint based on a
planned command rather than its successful output.

The previous MXFP8 + vLLM deployment scope has been archived to
`.scopes/archive/qwen3.6-40b-eleanor-deployment/`. It is a historical record
only and must not be treated as active instructions.

## Mission

Deploy `Qwen3.6-40B-Eleanor` locally on two RTX 5090 GPUs using llama.cpp as
the serving runtime with GGUF quantization.

The BF16 source is immutable at:

```text
/data/linux-fast/models/Qwen3.6-40B-Eleanor
```

It is the byte-verified local checkout of
`DavidAU/Qwen3.6-40B-Fable-Fusion-6-Core-Deckard-Eleanor-Heretic-Uncensored`
at commit `7905312899185973580867f69d20d4cfc374ccaa` (30/30 remote-tree files
verified). Its files are mode `0444` and directories mode `0555`; preserve
those permissions and do not make the source writable.

Never copy the model payload into the repository, a system-disk cache, or a
Git object. The source is approximately 75 GiB and must never be converted in
place. GGUF output must be built to same-filesystem staging and atomically
renamed only after conversion succeeds; it must never be overwritten.

## Existing GGUF Asset

A Q8_0 GGUF file already exists at:

```text
/data/linux-fast/models/Qwen3.6-40B-Eleanor-GGUF/Qwen3.6-40B-...-MTP-Q8_0.gguf
```

It was generated 2026-08-14, is root-owned and read-only, and includes MTP
tensors. Whether this becomes the Golden product or a temporary artifact is a
decision for the active scope.

## Build And Runtime Environment

- Build llama.cpp from the pinned submodule using `cmake` and the system
  compiler (Clang 21 / CUDA 13.1). Do not install a pre-built binary.
- The project-local `.venv` is for any Python-based conversion tools. Never use
  `/home/build/torch/.venv`, a user-global Python, or system Python for this
  project.
- If Python CUDA dependencies are needed (e.g., for `convert_hf_to_gguf.py`),
  consume the CPython 3.13 local CUDA wheels from `/home/build/torch/dist`.
  Do not resolve replacement Torch or Triton packages from PyPI.
- Before a CUDA-dependent run, verify the environment with its own interpreter
  or the compiled binary: `torch.__version__`, `torch.version.cuda`,
  `torch.cuda.is_available()`, and two visible devices. Do not infer success
  from `which python` outside the launcher.
- Keep dependency caches project-local where practical. Virtual environments,
  caches, logs, bytecode, wheels, model payloads, staging directories, and
  generated manifests are not Git content.

## GGUF Conversion Contract

- Convert the BF16 source to GGUF using `convert_hf_to_gguf.py` from the
  pinned `llama.cpp` submodule or equivalent tooling.
- Quantization type is determined by the active scope (Q8_0, Q4_K_M, etc.).
  Record the choice and rationale in the scope.
- Preserve MTP tensors in the GGUF output. The verifier must confirm MTP
  tensors are present.
- Do not modify the BF16 source after its external manifest has been frozen.
- Do not create the Golden output manifest until the checkpoint verifier passes.

## Runtime Contract

- Serve using `llama-server` (or `llama.cpp` server mode) built from the pinned
  submodule.
- Multi-GPU: distribute across two RTX 5090 cards using llama.cpp's tensor
  splitting (`-ngl` / `-sm`).
- Context length, batch size, and MTP/flash-attention flags are determined by
  the active scope. Record baseline parameters before tuning.
- Bind to `127.0.0.1` only. Do not expose the API on a LAN interface unless the
  user explicitly approves it.
- Do not use CPU weight offload or a larger context as an unreviewed workaround
  for a failed baseline.

## Large Model Safety

- `/data/linux-fast` must be the active ext4 model mount before a large build.
- `scripts/verify-source-upstream-buffered-incident.py` is the incident
  workload and controlled trigger probe. Its unbounded default mode is never
  permitted; run only its bounded `--probe` mode through
  `scripts/run-buffered-io-probe.sh` after a clean reboot.
- A normal NVIDIA DKMS boot reports taint `4096` (`O`, external module). The
  `BAD_PAGE` bit is `32` (`B`), yielding `4128` after this incident. Probe and
  build baselines may use taint `0` or `4096`, but never `4128`.
- Do not run an unbounded buffered checksum, tensor scan, or memory map across
  full model shards. Use the direct verifier for production identity checks.
- Before a large build or full output manifest, record a clean relevant kernel
  and NVIDIA state. Stop on kernel Oops, `BAD_PAGE`, unexplained SIGSEGV, or
  NVIDIA Xid evidence; do not convert such a run into acceptance evidence.
- Never delete, rename, or overwrite a model directory, staging directory, or
  manifest without explicit user authorization and a verified exact path.

## Repository Hygiene

- Treat upstream submodules as pinned. Do not edit their source for local
  deployment behavior; place wrappers and configuration under `scripts/` and
  `config/`.
- Before dependency or submodule changes, record `git submodule status
  --recursive`. Keep the recorded commits aligned with the active scope.
- Keep `.scopes/` current as real evidence arrives. Use `repo-task-driven` for
  scope maintenance and do not treat archived scopes as active instructions.
- Inspect `git status --short` before edits and completion. Preserve unrelated
  user changes. Do not commit, push, rebase, or change remotes unless requested.
- Never commit model payloads, virtual environments, logs, generated artifacts,
  caches, or secrets.

## Validation Matrix

| Change class | Required evidence |
| --- | --- |
| scope/config/scripts | shell syntax, Python compilation, `git diff --check` |
| llama.cpp build | cmake exit zero, `llama-server --version`, CUDA GPU visibility |
| GGUF conversion | convert exit zero, output file size, MTP tensor verification |
| serving baseline | server startup, health endpoint, deterministic smoke test, GPU-memory evidence |
| MTP or context tuning | equivalent smoke plus a recorded comparison against baseline |

## Forbidden Shortcuts

- Do not claim GGUF conversion, context capacity, or MTP benefit without the
  corresponding successful evidence.
- Do not substitute PyPI Torch/Triton for `/home/build/torch/dist`.
- Do not treat a local import check or compilation step as a successful
  checkpoint load or API deployment.
- Do not overwrite the Golden path to retry a conversion. A future candidate
  requires a new destination and a new scope decision.
