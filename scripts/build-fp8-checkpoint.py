#!/usr/bin/env python3
"""Build and atomically promote a permanent MXFP8 W8A8 checkpoint."""

from __future__ import annotations

import json
import os
import shutil
import stat
import subprocess
import sys
import time
from pathlib import Path

from llmcompressor import model_free_ptq


EXPECTED_ARCHITECTURE = "Qwen3_5ForConditionalGeneration"
ALLOWED_TAINTS = {0, 4096}
FORBIDDEN_KERNEL_MARKERS = (
    "bad page state",
    "bad_page",
    "compound_head",
    "corrupted mapping in tail page",
    "general protection fault",
    "nvrm: xid",
    "xid (pci:",
)


def fail(message: str) -> None:
    print(f"MXFP8 build failed: {message}", file=sys.stderr)
    raise SystemExit(1)


def required_path(name: str) -> Path:
    value = os.environ.get(name)
    if not value:
        fail(f"missing environment variable {name}")
    return Path(value)


def required_value(name: str) -> str:
    value = os.environ.get(name)
    if not value:
        fail(f"missing environment variable {name}")
    return value


def git_commit(repo: Path) -> str:
    return subprocess.check_output(["git", "-C", str(repo), "rev-parse", "HEAD"], text=True).strip()


def require_clean_boot() -> None:
    taint = int(Path("/proc/sys/kernel/tainted").read_text(encoding="utf-8").strip())
    if taint not in ALLOWED_TAINTS:
        fail(f"checkpoint build requires taint 0 or 4096, got {taint}")
    journal = subprocess.run(
        ["journalctl", "-k", "-b", "--no-pager"], check=True, text=True, capture_output=True
    ).stdout.lower()
    found = [marker for marker in FORBIDDEN_KERNEL_MARKERS if marker in journal]
    if found:
        fail(f"checkpoint build requires a clean kernel log; found {', '.join(found)}")


def require_read_only_source(source: Path) -> None:
    for path in [source, *source.rglob("*")]:
        mode = stat.S_IMODE(path.stat().st_mode)
        required = 0o555 if path.is_dir() else 0o444
        if mode & 0o222 or mode & required != required:
            fail(f"source permissions must be read-only for {path}: got {mode:o}")


def require_same_filesystem(source: Path, output: Path, stage_prefix: Path) -> None:
    try:
        source_device = source.stat().st_dev
        output_parent_device = output.parent.stat().st_dev
        stage_parent_device = stage_prefix.parent.stat().st_dev
    except OSError as error:
        fail(f"cannot inspect model filesystem: {error}")
    if len({source_device, output_parent_device, stage_parent_device}) != 1:
        fail("source, permanent output, and staging must share one filesystem")


def main() -> None:
    source = required_path("SOURCE_MODEL_DIR")
    output = required_path("FP8_MODEL_DIR")
    stage_prefix = required_path("FP8_STAGE_PREFIX")
    scheme = required_value("FP8_SCHEME")
    if scheme != "MXFP8":
        fail(f"expected MXFP8 scheme, got {scheme}")
    if output.exists():
        fail(f"refusing to overwrite permanent output: {output}")
    if not source.is_dir() or not (source / "model.safetensors.index.json").is_file():
        fail(f"invalid source model directory: {source}")
    require_clean_boot()
    require_read_only_source(source)
    require_same_filesystem(source, output, stage_prefix)
    stale_stages = sorted(stage_prefix.parent.glob(f"{stage_prefix.name}-*"))
    if stale_stages:
        fail(f"refusing build with existing staging directory: {stale_stages[0]}")

    config = json.loads((source / "config.json").read_text(encoding="utf-8"))
    if EXPECTED_ARCHITECTURE not in config.get("architectures", []):
        fail(f"expected {EXPECTED_ARCHITECTURE}, got {config.get('architectures')}")
    if not (source / "model-mtp-restored.safetensors").is_file():
        fail("missing source MTP shard")

    try:
        ignore = json.loads(required_value("IGNORE_MODULES_JSON"))
    except ValueError as error:
        fail(f"invalid IGNORE_MODULES_JSON: {error}")
    if not isinstance(ignore, list) or not all(isinstance(item, str) for item in ignore):
        fail("IGNORE_MODULES_JSON must be a JSON string array")

    devices = [f"cuda:{index}" for index in required_value("CUDA_DEVICES").split(",")]
    workers = int(required_value("MAX_WORKERS"))
    stage = Path(f"{stage_prefix}-{int(time.time())}")
    stage.mkdir(mode=0o2775)
    try:
        model_free_ptq(
            model_stub=source,
            save_directory=stage,
            scheme=scheme,
            ignore=ignore,
            device=devices,
            max_workers=workers,
        )
        manifest = {
            "architecture": EXPECTED_ARCHITECTURE,
            "build_method": "model_free_ptq",
            "compressed_tensors_submodule_commit": git_commit(Path(os.environ["COMPRESSED_TENSORS_DIR"])),
            "ignore": ignore,
            "llm_compressor_submodule_commit": git_commit(Path(os.environ["LLM_COMPRESSOR_DIR"])),
            "recipe": {"scheme": scheme, "targets": "Linear"},
            "source_model_dir": str(source),
            "vllm_submodule_commit": git_commit(Path(os.environ["VLLM_DIR"])),
        }
        (stage / "mxfp8-build-manifest.json").write_text(
            json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )
        os.rename(stage, output)
    except BaseException:
        shutil.rmtree(stage, ignore_errors=True)
        raise
    print(f"MXFP8 checkpoint promoted: {output}")


if __name__ == "__main__":
    main()
