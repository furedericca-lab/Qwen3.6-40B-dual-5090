#!/usr/bin/env python3
"""Verify a permanent compressed-tensors MXFP8 W8A8 checkpoint."""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path


EXPECTED_ARCHITECTURE = "Qwen3_5ForConditionalGeneration"
REQUIRED_IGNORE_TERMS = ("lm_head", "embed_tokens", "conv1d", "in_proj_a", "in_proj_b", "mtp", "visual", "norm")


def fail(message: str) -> None:
    print(f"MXFP8 checkpoint verification failed: {message}", file=sys.stderr)
    raise SystemExit(1)


def verify_quant_args(args: object, *, dynamic: bool, name: str) -> None:
    if not isinstance(args, dict):
        fail(f"{name} quantization arguments are missing")
    expected = {
        "num_bits": 8,
        "type": "float",
        "strategy": "group",
        "group_size": 32,
        "symmetric": True,
        "dynamic": dynamic,
        "scale_dtype": "torch.uint8",
    }
    for key, value in expected.items():
        if args.get(key) != value:
            fail(f"{name}.{key} must be {value!r}, got {args.get(key)!r}")


def main() -> None:
    model_dir = Path(os.environ.get("MODEL_DIR", "/data/linux-fast/models/Qwen3.6-40B-Eleanor-MXFP8-W8A8"))
    if not model_dir.is_dir():
        fail(f"checkpoint directory is missing: {model_dir}")
    required = ("config.json", "model.safetensors.index.json", "mxfp8-build-manifest.json")
    missing = [name for name in required if not (model_dir / name).is_file()]
    if missing:
        fail(f"missing required files: {', '.join(missing)}")
    config = json.loads((model_dir / "config.json").read_text(encoding="utf-8"))
    if EXPECTED_ARCHITECTURE not in config.get("architectures", []):
        fail(f"expected architecture {EXPECTED_ARCHITECTURE}")
    quantization = config.get("quantization_config")
    if not isinstance(quantization, dict):
        fail("config.json has no quantization_config")
    if quantization.get("quant_method") != "compressed-tensors":
        fail(f"expected quant_method compressed-tensors, got {quantization.get('quant_method')!r}")
    if quantization.get("format") != "mxfp8-quantized":
        fail(f"expected mxfp8-quantized format, got {quantization.get('format')!r}")
    groups = quantization.get("config_groups")
    if not isinstance(groups, dict) or "MXFP8" not in groups:
        fail("quantization_config lacks MXFP8 config group")
    group = groups["MXFP8"]
    if not isinstance(group, dict):
        fail("MXFP8 config group is invalid")
    if group.get("format") != "mxfp8-quantized":
        fail(f"expected MXFP8 group format mxfp8-quantized, got {group.get('format')!r}")
    verify_quant_args(group.get("weights"), dynamic=False, name="weights")
    verify_quant_args(group.get("input_activations"), dynamic=True, name="input_activations")
    ignored = quantization.get("ignore")
    if not isinstance(ignored, list) or not all(term in " ".join(ignored) for term in REQUIRED_IGNORE_TERMS):
        fail("quantization_config ignore rules do not preserve required BF16 modules")
    index = json.loads((model_dir / "model.safetensors.index.json").read_text(encoding="utf-8"))
    weight_map = index.get("weight_map")
    if not isinstance(weight_map, dict) or not weight_map:
        fail("safetensors index has no weight_map")
    files = sorted(set(weight_map.values()))
    if any(not (model_dir / name).is_file() for name in files):
        fail("index references missing safetensors files")
    mtp_keys = [name for name in weight_map if name.startswith("mtp.")]
    if not mtp_keys:
        fail("output index has no MTP tensors")
    manifest = json.loads((model_dir / "mxfp8-build-manifest.json").read_text(encoding="utf-8"))
    if manifest.get("recipe", {}).get("scheme") != "MXFP8" or manifest.get("build_method") != "model_free_ptq":
        fail("build manifest does not record model_free_ptq MXFP8")
    total_bytes = sum((model_dir / name).stat().st_size for name in files)
    print(json.dumps({"model_dir": str(model_dir), "mtp_tensors": len(mtp_keys), "quantization_format": quantization["format"], "weight_files": len(files), "weight_gib": round(total_bytes / 1024**3, 2)}, sort_keys=True))


if __name__ == "__main__":
    main()
