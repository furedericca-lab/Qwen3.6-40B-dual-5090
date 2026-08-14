#!/usr/bin/env python3
"""Validate local checkpoint metadata without reading model tensor payloads."""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path


EXPECTED_ARCHITECTURE = "Qwen3_5ForConditionalGeneration"
EXPECTED_SHARDS = 17
MTP_SHARD = "model-mtp-restored.safetensors"


def fail(message: str) -> None:
    print(f"model preflight failed: {message}", file=sys.stderr)
    raise SystemExit(1)


def main() -> None:
    model_dir = Path(os.environ.get("MODEL_DIR", "/data/linux-fast/models/Qwen3.6-40B-Eleanor"))
    config_path = model_dir / "config.json"
    index_path = model_dir / "model.safetensors.index.json"
    mtp_path = model_dir / MTP_SHARD

    if not model_dir.is_dir():
        fail(f"model directory is missing: {model_dir}")
    if not config_path.is_file() or not index_path.is_file():
        fail("config.json or model.safetensors.index.json is missing")

    config = json.loads(config_path.read_text(encoding="utf-8"))
    architectures = config.get("architectures", [])
    if EXPECTED_ARCHITECTURE not in architectures:
        fail(f"expected architecture {EXPECTED_ARCHITECTURE}, got {architectures}")
    if config.get("model_type") != "qwen3_5":
        fail(f"expected model_type qwen3_5, got {config.get('model_type')!r}")

    index = json.loads(index_path.read_text(encoding="utf-8"))
    weight_map = index.get("weight_map")
    if not isinstance(weight_map, dict) or not weight_map:
        fail("safetensors index has no weight_map")
    indexed_shards = sorted(set(weight_map.values()))
    if MTP_SHARD not in indexed_shards:
        fail(f"safetensors index does not reference MTP shard {MTP_SHARD}")
    primary_shards = [shard for shard in indexed_shards if shard != MTP_SHARD]
    if len(primary_shards) != EXPECTED_SHARDS:
        fail(f"expected {EXPECTED_SHARDS} primary shards, got {len(primary_shards)}")
    missing = [shard for shard in indexed_shards if not (model_dir / shard).is_file()]
    if missing:
        fail(f"missing primary shards: {', '.join(missing)}")
    if not mtp_path.is_file():
        fail(f"missing MTP shard: {mtp_path.name}")

    total_bytes = sum((model_dir / shard).stat().st_size for shard in indexed_shards)
    print(json.dumps({
        "architecture": EXPECTED_ARCHITECTURE,
        "model_dir": str(model_dir),
        "primary_shards": len(primary_shards),
        "mtp_shard": MTP_SHARD,
        "total_tensor_bytes": total_bytes,
        "total_tensor_gib": round(total_bytes / 1024**3, 2),
    }, sort_keys=True))


if __name__ == "__main__":
    main()
