# AGENTS.md

## Source Of Truth

1. Archived deployment contract under
   `.scopes/archive/qwen36-40b-eleanor-llamacpp/`.
2. Archived vLLM/MXFP8 deployment scope under
   `.scopes/archive/qwen3.6-40b-eleanor-deployment/` (historical only).
3. Durable incident and operational knowledge under `.wiki/`.
4. `README.md` for operator entry points.
5. `scripts/llama-server-first-boot.sh` for the canonical runtime launcher.
6. `llama.cpp` submodule at merge commit `94e82e8ae` (fork `efb81ab` + upstream `885c5bb`).

The scope is authoritative for phase gates and recorded evidence. Do not mark a
phase complete, start a later phase, or rewrite a checkpoint based on a planned
command rather than its successful output.

## Mission

Deploy `Qwen3.6-40B-Eleanor` on two RTX 5090 GPUs using llama.cpp with a
pre-built Q8_0 GGUF, 128K context, and MTP enabled.

**Deployment complete** — all 4 phases finished and archived under
`.scopes/archive/qwen36-40b-eleanor-llamacpp/`. Production default: n=2,
p_min=0 (2.05x speedup, 71.20 tok/s, stddev 0.03). Maximum throughput:
n=3, p_min=0 (2.34x, 81.35 tok/s).

The Q8_0 GGUF artifact is the sole deployment model, immutable at:

```text
/data/linux-fast/models/Qwen3.6-40B-Eleanor-GGUF/Qwen3.6-40B-FF6core-Deck-Eleanor-H-Uncen-NEO-MAX-MTP-Q8_0.gguf
```

It is `43,180,558,336` bytes (approximately 40.2 GiB), owned by `root:build`,
mode `0444`. Its GGUF metadata reports `qwen35` architecture, 97 blocks (96
transformer + 1 MTP), `Q8_0` file type, `nextn_predict_layers: 1`, 1290
tensors, embedded imatrix (181 chunks), and a native context length of 262144.
Do not make the artifact writable, and never copy it into the repository or a
Git object.

The original BF16 source is immutable at:

```text
/data/linux-fast/models/Qwen3.6-40B-Eleanor
```

It is the byte-verified local checkout of
`DavidAU/Qwen3.6-40B-Fable-Fusion-6-Core-Deckard-Eleanor-Heretic-Uncensored`.
Its files are mode `0444` and directories mode `0555`. It is retained for
reference but is not used by the current deployment scope.

Never copy the model payload into the repository, a system-disk cache, or a
Git object.

## Build And Runtime Environment

Build llama.cpp from the pinned submodule using CMake + Ninja, Clang 21, and
CUDA 13.3. Target architecture is `sm_120a` (RTX 5090 / Blackwell):

```bash
cd llama.cpp
cmake -S . -B build -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DGGML_CUDA=ON \
  -DCMAKE_CUDA_ARCHITECTURES=120a \
  -DLLAMA_CURL=OFF
cmake --build build --target llama-server -j$(nproc)
```

The built binary is `llama.cpp/build/bin/llama-server`. It is not tracked by
Git; rebuild after any submodule update.

The llama.cpp submodule (`furedericca-lab/llama.cpp`, merge commit `94e82e8ae` =
fork `efb81ab` + upstream `885c5bb`) has native `qwen35`
architecture support including MTP/nextn and hybrid SSM+attention. The merge
incorporates 42 upstream commits (speculative/MTP improvements, server updates)
while preserving DIO and DeepSeek V4 quantization patches. Do not add
`--trust-remote-code` or alternative model loaders.

This project does not require a Python virtual environment for serving. If
Python tooling is ever needed, use a project-local `.venv` managed with `uv`;
never use `/home/build/torch/.venv` or system Python.

Keep dependency caches, virtual environments, caches, logs, build directories,
bytecode, model payloads, and generated manifests out of Git.

## Runtime Contract

Serve using `scripts/llama-server-first-boot.sh`, which calls the locally built
`llama-server`. The baseline runtime profile is:

```text
--load-mode dio
-dev CUDA0,CUDA1
-sm layer
--fit on --fit-target 2048,2048
-ctk f16 -ctv f16
-c 131072 -np 1
-b 512 -ub 128
-fa on
--spec-type draft-mtp --spec-draft-n-max 2 --spec-draft-n-min 0 --spec-draft-p-min 0
--temp 0.6 --top-p 0.95 --top-k 20 --min-p 0 --repeat-penalty 1.0
--host 127.0.0.1 --port 8000
```

Do not use `-ngl all`; it disables auto-fit and requests an impossible
per-device allocation for a 40 GiB model. Use `--fit on` instead. Do not use
`--no-kv-offload`; KV offload to GPU is the default in llama.cpp, and
`--no-kv-offload` would force KV to CPU/RAM.

The GGUF contains one MTP/nextn layer (`nextn_predict_layers: 1`).
Runtime MTP is explicitly enabled with `--spec-type draft-mtp`;
the llama.cpp default speculative decoding type is `none`.
`n-max=2` with `p_min=0` is the production default after Phase 4
benchmarking (2.05x speedup vs MTP-off, 71.20 tok/s, stddev 0.03). Phase 4
benchmark tested n=2/3 × p_min=0/0.75 with fixed seed, temperature 0, and 5
repeated runs per config: n=3,p=0 is fastest (2.34x, 81.35 tok/s) but with
lower acceptance (70.7%); n=2,p=0.75 has highest acceptance (94.0%) but
lower speed (1.73x); n=2,p=0 is the best balance for interactive use.
The n-max=3 Qwen3.6 output drift bug (llama.cpp #23302) was superseded by
#23335; fixed-seed testing in #23335 showed Q8_0 agreeing across no-MTP
and MTP n=1–5.

OOM ladder: reduce `-ub` first, then relax `--fit-target` (increase to allow
less on GPU), then switch KV to Q8_0 (`-ctk q8_0 -ctv q8_0`, preserves
128K context), and only then reduce `-c` to 65536. Reducing fit-target
(e.g. 2048 → 1536) is NOT an OOM recovery step — it asks the fitter to use
more VRAM (less margin).

Bind to `127.0.0.1` only. Do not expose the API on a LAN interface unless the
user explicitly approves it. Do not use CPU weight offload as the primary
strategy.

The launcher uses `MTP_MODE` (default `on`) to control speculative decoding.
`MTP_MODE=on` passes `--spec-type draft-mtp` and related flags; `MTP_MODE=off`
omits all speculative args, letting llama.cpp default to spec-type none.
Do NOT use `$@ --spec-type none` to disable MTP — llama.cpp appends spec
types into a bitmask rather than replacing them, so passing both
`--spec-type draft-mtp` (from the launcher) and `--spec-type none` (from
`$@`) would still enable MTP. The `$@` passthrough is available for other
controlled experimental overrides, but all appended arguments must be
recorded in the evidence for that run.

## Large Model Safety

`/data/linux-fast` must be the active ext4 model mount before serving.

Before serving, record a clean kernel and NVIDIA state. Verify
`cat /proc/sys/kernel/tainted` is `0` or `4096` (not `4128`), and
`journalctl -k -b` has no `BAD_PAGE`, `Oops`, or `Xid` events.

Stop on kernel Oops, `BAD_PAGE`, unexplained SIGSEGV, or NVIDIA Xid evidence;
do not convert such a run into acceptance evidence.

Do not run an unbounded buffered checksum, tensor scan, or memory map across
full model files. Use the direct verifier
(`scripts/verify-source-upstream-direct.py`) for production identity checks.

Never delete, rename, or overwrite a model directory, staging directory, or
manifest without explicit user authorization and a verified exact path.

## Repository Hygiene

Treat the `llama.cpp` submodule as pinned. Do not edit its source for local
deployment behavior; place wrappers and configuration under `scripts/`.

Keep `.scopes/` current as real evidence arrives. Use `repo-task-driven` for
scope maintenance and do not treat archived scopes as active instructions.

Inspect `git status --short` before edits and completion. Preserve unrelated
user changes. Do not commit, push, rebase, or change remotes unless requested.

Never commit model payloads, virtual environments, logs, generated artifacts,
caches, or secrets.

## Validation Matrix

| Change class | Required evidence |
| --- | --- |
| scope/scripts | shell syntax (`bash -n`), Python compilation, `git diff --check` |
| llama.cpp build | cmake exit zero, `llama-server --version`, `--list-devices` sees both RTX 5090 |
| serving baseline | server startup, `/health`, `/v1/models`, behavior probes, GPU-memory evidence |
| MTP or context tuning | equivalent smoke plus a recorded comparison against baseline |

## Forbidden Shortcuts

Do not claim 128K capacity or MTP benefit without the corresponding successful
evidence. Do not treat a successful compilation as a successful model load or
API deployment. Do not overwrite the GGUF artifact path to retry a deployment.
Do not reopen the archived vLLM/MXFP8 scope as active instructions.
