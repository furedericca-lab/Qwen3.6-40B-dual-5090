#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
torch_dist=${TORCH_DIST_DIR:-"$HOME/torch/dist"}
for source_dir in "$repo_root/compressed-tensors" "$repo_root/llm-compressor"; do
  if [[ ! -f "$source_dir/setup.py" ]]; then
    printf 'required submodule is unavailable: %s\n' "$source_dir" >&2
    exit 1
  fi
done

shopt -s nullglob
torch_wheels=("$torch_dist"/torch-*-cp313-cp313-linux_x86_64.whl)
triton_wheels=("$torch_dist"/pytorch_triton-*-cp313-cp313-linux_x86_64.whl)
if [[ ${#torch_wheels[@]} -ne 1 || ${#triton_wheels[@]} -ne 1 ]]; then
  printf 'expected one CPython 3.13 Torch and pytorch_triton wheel under %s\n' "$torch_dist" >&2
  exit 1
fi

uv venv --clear --python 3.13 "$repo_root/.quantize-venv"
python="$repo_root/.quantize-venv/bin/python"

# Local CUDA ABI is owned by ~/torch/dist; do not resolve substitute wheels.
uv pip install --python "$python" --no-deps "${torch_wheels[@]}" "${triton_wheels[@]}"
uv pip install --python "$python" \
  'loguru>=0.7.2,<=0.7.3' 'pyyaml>=6.0.1,<=6.0.3' \
  'numpy>=2.0.0,<=2.4.6' 'requests>=2.32.2,<2.35.0' \
  'tqdm>=4.66.3,<=4.70.0' 'transformers>=5.9.0,<=5.14.1' \
  'datasets>=4.8.4,<=5.0.1' 'auto-round>=0.14.1,<=0.14.2' \
  'accelerate>=1.6.0,<=1.14.0' 'nvidia-ml-py>=12.560.30,<=13.610.43' \
  'pillow>=10.4.0,<13.0.0' 'pydantic>=2.0' psutil
BUILD_TYPE=release uv pip install --python "$python" --no-deps \
  --editable "$repo_root/compressed-tensors" \
  --editable "$repo_root/llm-compressor"
