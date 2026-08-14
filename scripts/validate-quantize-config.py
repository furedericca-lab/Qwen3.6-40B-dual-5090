#!/usr/bin/env python3
"""Validate paths and capacity required for a non-destructive FP8 build."""

from __future__ import annotations

import re
import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CONFIG_PATH = ROOT / "config/quantize.env"
REQUIRED = {
    "SOURCE_MODEL_DIR", "FP8_MODEL_DIR", "FP8_STAGE_PREFIX", "FP8_SCHEME",
    "MAX_WORKERS", "CUDA_DEVICES", "IGNORE_MODULES_JSON",
}


def fail(message: str) -> None:
    print(f"quantization config failed: {message}", file=sys.stderr)
    raise SystemExit(1)


def load_env() -> dict[str, str]:
    values: dict[str, str] = {}
    for line in CONFIG_PATH.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        key, sep, value = line.partition("=")
        if not sep or not re.fullmatch(r"[A-Z][A-Z0-9_]*", key):
            fail(f"invalid assignment: {line}")
        values[key] = value
    return values


def main() -> None:
    values = load_env()
    missing = REQUIRED - values.keys()
    if missing:
        fail(f"missing keys: {', '.join(sorted(missing))}")
    source = Path(values["SOURCE_MODEL_DIR"])
    output = Path(values["FP8_MODEL_DIR"])
    stage_prefix = Path(values["FP8_STAGE_PREFIX"])
    if values["FP8_SCHEME"] != "MXFP8":
        fail("only the reviewed MXFP8 W8A8 recipe is accepted")
    if not source.is_dir():
        fail(f"source model directory is missing: {source}")
    if output.exists():
        fail(f"permanent output already exists: {output}")
    if output.parent != source.parent or stage_prefix.parent != source.parent:
        fail("source, staging, and output must share /data/linux-fast/models")
    if values["CUDA_DEVICES"] != "0,1" or int(values["MAX_WORKERS"]) != 2:
        fail("Golden MXFP8 build requires CUDA_DEVICES=0,1 and MAX_WORKERS=2")
    try:
        ignored = __import__("json").loads(values["IGNORE_MODULES_JSON"].strip("'"))
    except ValueError as error:
        fail(f"IGNORE_MODULES_JSON is invalid: {error}")
    required_ignores = {"lm_head", "embed_tokens", "conv1d", "in_proj_a", "in_proj_b", "mtp", "visual", "norm"}
    if not isinstance(ignored, list) or not all(term in " ".join(ignored) for term in required_ignores):
        fail("IGNORE_MODULES_JSON must preserve lm_head, embeddings, hybrid linear-attention, MTP, vision, and norms")
    try:
        gpu_caps = subprocess.check_output(
            ["nvidia-smi", "--query-gpu=compute_cap", "--format=csv,noheader"], text=True
        ).splitlines()
    except (OSError, subprocess.CalledProcessError) as error:
        fail(f"cannot query NVIDIA compute capability: {error}")
    if len(gpu_caps) != 2 or any(float(capability) < 10.0 for capability in gpu_caps):
        fail(f"MXFP8 requires two Blackwell-capable GPUs, got {gpu_caps}")
    source_bytes = sum(path.stat().st_size for path in source.glob("*.safetensors"))
    free_bytes = shutil.disk_usage(output.parent).free
    if free_bytes < source_bytes:
        fail("insufficient free space for staged FP8 checkpoint")
    print(f"quantization config passed: scheme=MXFP8 source_tensor_gib={source_bytes / 1024**3:.2f} free_gib={free_bytes / 1024**3:.2f} compute_cap={','.join(gpu_caps)}")


if __name__ == "__main__":
    main()
