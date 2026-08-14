#!/usr/bin/env python3
"""Check the checked-in first-boot configuration before a vLLM launch."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CONFIG_PATH = ROOT / "config/runtime.env"
REQUIRED = {
    "MODEL_DIR",
    "SERVED_MODEL_NAME",
    "HOST",
    "PORT",
    "TENSOR_PARALLEL_SIZE",
    "GPU_MEMORY_UTILIZATION",
    "MAX_MODEL_LEN",
    "MAX_NUM_SEQS",
    "MAX_NUM_BATCHED_TOKENS",
    "MAX_PARALLEL_LOADING_WORKERS",
    "DTYPE",
    "KV_CACHE_DTYPE",
    "LANGUAGE_MODEL_ONLY",
    "REASONING_PARSER",
    "ENABLE_AUTO_TOOL_CHOICE",
    "TOOL_CALL_PARSER",
    "ENABLE_MTP",
}


def load_env() -> dict[str, str]:
    values: dict[str, str] = {}
    for line in CONFIG_PATH.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        key, sep, value = line.partition("=")
        if not sep or not re.fullmatch(r"[A-Z][A-Z0-9_]*", key):
            raise ValueError(f"invalid assignment: {line}")
        values[key] = value
    return values


def fail(message: str) -> None:
    print(f"runtime config failed: {message}", file=sys.stderr)
    raise SystemExit(1)


def main() -> None:
    values = load_env()
    missing = REQUIRED - values.keys()
    if missing:
        fail(f"missing keys: {', '.join(sorted(missing))}")
    if values["HOST"] != "127.0.0.1":
        fail("default host must remain 127.0.0.1")
    if values["TENSOR_PARALLEL_SIZE"] != "2":
        fail("dual-GPU first boot requires TENSOR_PARALLEL_SIZE=2")
    if values["DTYPE"] != "bfloat16" or values["KV_CACHE_DTYPE"] != "auto":
        fail("initial MXFP8 runtime requires DTYPE=bfloat16 and KV_CACHE_DTYPE=auto")
    if values["LANGUAGE_MODEL_ONLY"] != "true":
        fail("initial acceptance must use LANGUAGE_MODEL_ONLY=true")
    if values["REASONING_PARSER"] != "qwen3" or values["TOOL_CALL_PARSER"] != "qwen3_coder":
        fail("initial runtime requires qwen3 reasoning and qwen3_coder tool parsers")
    if values["ENABLE_AUTO_TOOL_CHOICE"] != "true" or values["ENABLE_MTP"] != "false":
        fail("initial runtime requires auto tool choice and MTP disabled")
    if not 0 < float(values["GPU_MEMORY_UTILIZATION"]) <= 1:
        fail("GPU_MEMORY_UTILIZATION must be in (0, 1]")
    for key in ("MAX_MODEL_LEN", "MAX_NUM_SEQS", "MAX_NUM_BATCHED_TOKENS", "MAX_PARALLEL_LOADING_WORKERS"):
        if int(values[key]) <= 0:
            fail(f"{key} must be positive")
    if int(values["MAX_MODEL_LEN"]) != 65536:
        fail("initial MXFP8 acceptance requires a 64K context profile")
    if values["GPU_MEMORY_UTILIZATION"] != "0.97":
        fail("reviewed single-Agent profile requires GPU_MEMORY_UTILIZATION=0.97")
    if values["MAX_NUM_SEQS"] != "1" or values["MAX_NUM_BATCHED_TOKENS"] != "2048":
        fail("reviewed single-Agent profile requires one sequence and 2048-token chunked prefill")
    print(json.dumps({"config": str(CONFIG_PATH), "profile": values}, sort_keys=True))


if __name__ == "__main__":
    main()
