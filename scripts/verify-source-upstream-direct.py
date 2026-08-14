#!/usr/bin/env python3
"""Verify Eleanor against Hugging Face with aligned O_DIRECT model reads."""

from __future__ import annotations

import argparse
import hashlib
import mmap
import os
import sys
from pathlib import Path
from typing import Any

from huggingface_hub import HfApi

DEFAULT_REPO = "DavidAU/Qwen3.6-40B-Fable-Fusion-6-Core-Deckard-Eleanor-Heretic-Uncensored"
DEFAULT_ROOT = Path("/data/linux-fast/models/Qwen3.6-40B-Eleanor")
ALIGN = 4096
BLOCK = 8 * 1024 * 1024


def direct_digest(path: Path, algorithm: str) -> str:
    """Hash a regular file without populating page cache for aligned payloads."""
    digest = hashlib.new(algorithm)
    fd = os.open(path, os.O_RDONLY | os.O_DIRECT)
    try:
        size = os.fstat(fd).st_size
        offset = 0
        while offset < size:
            wanted = min(BLOCK, size - offset)
            allocated = ((wanted + ALIGN - 1) // ALIGN) * ALIGN
            buffer = mmap.mmap(-1, allocated)
            try:
                view = memoryview(buffer)
                received = os.preadv(fd, [view], offset)
                if received < wanted:
                    raise OSError(f"short O_DIRECT read at {offset}: {received}/{wanted}")
                digest.update(view[:wanted])
                view.release()
            finally:
                buffer.close()
            offset += wanted
    finally:
        os.close(fd)
    return digest.hexdigest()


def lfs_value(lfs: object, key: str) -> Any:
    if lfs is None:
        return None
    return lfs.get(key) if isinstance(lfs, dict) else getattr(lfs, key, None)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", default=DEFAULT_REPO)
    parser.add_argument("--root", type=Path, default=DEFAULT_ROOT)
    parser.add_argument("--revision", default="main")
    args = parser.parse_args()
    root = args.root.resolve()
    if not root.is_dir():
        print(f"ERROR: local directory does not exist: {root}", file=sys.stderr)
        return 2

    api = HfApi(endpoint="https://huggingface.co")
    revision = api.model_info(args.repo, revision=args.revision).sha
    remote = {
        entry.path: entry
        for entry in api.list_repo_tree(args.repo, recursive=True, revision=revision, repo_type="model")
        if getattr(entry, "size", None) is not None and getattr(entry, "path", None)
    }
    local = {
        path.relative_to(root).as_posix(): path
        for path in root.rglob("*")
        if path.is_file() and not path.relative_to(root).as_posix().startswith(".cache/huggingface/")
    }
    missing, extra = sorted(set(remote) - set(local)), sorted(set(local) - set(remote))
    failed = bool(missing or extra)
    print(f"Repository : {args.repo}\nLocal path : {root}\nRemote commit: {revision}")
    for name in missing:
        print(f"MISSING {name}")
    for name in extra:
        print(f"EXTRA {name}")

    verified = 0
    for name in sorted(remote):
        entry, path = remote[name], local.get(name)
        if path is None:
            continue
        if path.stat().st_size != entry.size:
            failed = True
            print(f"SIZE FAIL {name}: local={path.stat().st_size} remote={entry.size}")
            continue
        expected_sha256 = lfs_value(getattr(entry, "lfs", None), "sha256")
        if expected_sha256:
            actual = direct_digest(path, "sha256")
            method, expected = "SHA256", expected_sha256
        else:
            header = f"blob {path.stat().st_size}\0".encode("ascii")
            actual = hashlib.sha1(header).hexdigest()
            digest = hashlib.sha1(header)
            fd = os.open(path, os.O_RDONLY | os.O_DIRECT)
            try:
                size = os.fstat(fd).st_size
                for offset in range(0, size, BLOCK):
                    wanted = min(BLOCK, size - offset)
                    allocated = ((wanted + ALIGN - 1) // ALIGN) * ALIGN
                    buffer = mmap.mmap(-1, allocated)
                    try:
                        view = memoryview(buffer)
                        received = os.preadv(fd, [view], offset)
                        if received < wanted:
                            raise OSError(f"short O_DIRECT read at {offset}: {received}/{wanted}")
                        digest.update(view[:wanted])
                        view.release()
                    finally:
                        buffer.close()
            finally:
                os.close(fd)
            actual, method, expected = digest.hexdigest(), "GIT", getattr(entry, "blob_id", None)
        if not expected or actual.lower() != expected.lower():
            failed = True
            print(f"{method} FAIL {name}: local={actual} remote={expected}")
        else:
            verified += 1
            print(f"OK {method} {name}")
    print(f"Verified: {verified}/{len(remote)}\nRESULT: {'FAIL' if failed else 'PASS'}")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
