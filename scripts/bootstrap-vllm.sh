#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
venv="$repo_root/.venv"

if [[ ! -f "$repo_root/vllm/pyproject.toml" ]]; then
  printf 'vLLM submodule is unavailable; run git submodule update --init --recursive\n' >&2
  exit 1
fi

uv venv --clear --python 3.13 "$venv"
python="$venv/bin/python"

# This pinned vLLM CUDA release requires the matching official Torch/Triton
# pair. Installing it as one resolver transaction prevents an ABI-mismatched
# Triton module from surviving in the runtime environment.
uv pip install --python "$python" --torch-backend cu130 \
  'torch==2.13.0' 'torchvision==0.28.0' 'torchaudio==2.11.0' 'triton==3.7.1'

mapfile -t common_requirements < <(
  sed -E 's/[[:space:]]+#.*$//; /^[[:space:]]*#/d; /^[[:space:]]*$/d' "$repo_root/vllm/requirements/common.txt" |
    awk '$1 !~ /^-r/ && $0 !~ /^compressed-tensors([[:space:]<=>!~]|$)/ && $0 !~ /^xgrammar([[:space:]<=>!~;]|$)/ { print }'
)
mapfile -t cuda_requirements < <(
  sed -E 's/[[:space:]]+#.*$//; /^[[:space:]]*#/d; /^[[:space:]]*$/d' "$repo_root/vllm/requirements/cuda.txt" |
    awk '$1 !~ /^-r/ && $1 !~ /^--/ && $1 !~ /^(torch|torchaudio|torchvision)[<=>]/ && $1 !~ /^flashinfer-cubin/ && $1 !~ /^humming-kernels/ { print }'
)
uv pip install --python "$python" "${common_requirements[@]}"
uv pip install --python "$python" --extra-index-url https://flashinfer.ai/whl/ "${cuda_requirements[@]}"
uv pip install --python "$python" --no-deps 'xgrammar>=0.2.1,<1.0.0'
uv pip install --python "$python" --no-deps 'humming-kernels[cu13]==0.1.12'
uv pip install --python "$python" --no-deps --editable "$repo_root/compressed-tensors"
uv pip install --python "$python" 'cmake>=3.26.1' ninja 'packaging>=24.2' 'setuptools>=77.0.3,<81.0.0' 'setuptools-scm>=8.0' 'setuptools-rust>=1.9.0' 'jinja2>=3.1.6' loguru

CUDA_HOME=${CUDA_HOME:-/usr/local/cuda-13.3} BUILD_TYPE=release \
  uv pip install --python "$python" --no-deps --no-build-isolation --editable "$repo_root/vllm"

"$python" - <<'PY'
import importlib.metadata as metadata
import json
import torch
import torchvision
import vllm._C_stable_libtorch
import vllm._moe_C_stable_libtorch

assert torch.cuda.is_available(), "CUDA is unavailable"
assert torch.cuda.device_count() == 2, f"expected two GPUs, got {torch.cuda.device_count()}"
owners = metadata.packages_distributions().get("triton", [])
assert owners == ["triton"], f"unexpected triton module owners: {owners}"
assert metadata.version("torch") == "2.13.0+cu130"
assert metadata.version("torchvision") == "0.28.0+cu130"
assert metadata.version("torchaudio") == "2.11.0+cu130"
assert metadata.version("triton") == "3.7.1"
assert metadata.version("compressed-tensors") == "0.18.1.dev0"
assert metadata.version("loguru")
print(json.dumps({
    "torch": torch.__version__,
    "cuda": torch.version.cuda,
    "devices": torch.cuda.device_count(),
    "triton": metadata.version("triton"),
    "compressed_tensors": metadata.version("compressed-tensors"),
    "torchvision": torchvision.__version__,
    "vllm": metadata.version("vllm"),
}, sort_keys=True))
PY

if "$python" -c 'import importlib.metadata as m; m.version("pytorch-triton")' 2>/dev/null; then
  printf 'refusing local pytorch-triton alongside the official vLLM Triton stack\n' >&2
  exit 1
fi
