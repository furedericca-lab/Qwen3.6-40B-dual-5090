#!/usr/bin/env python3
"""Write a SHA256 manifest using aligned O_DIRECT reads for a checkpoint tree."""

from __future__ import annotations

import argparse
import hashlib
import mmap
import os
from pathlib import Path


ALIGN = 4096
BLOCK = 8 * 1024 * 1024


def direct_sha256(path: Path) -> str:
    digest = hashlib.sha256()
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
                if received != wanted:
                    raise OSError(f"short O_DIRECT read at {offset}: {received}/{wanted}")
                digest.update(view[:wanted])
                view.release()
            finally:
                buffer.close()
    finally:
        os.close(fd)
    return digest.hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path)
    parser.add_argument("manifest", type=Path)
    args = parser.parse_args()
    root = args.root.resolve()
    manifest = args.manifest.resolve()
    if not root.is_dir():
        parser.error(f"checkpoint directory is missing: {root}")
    if manifest.exists():
        parser.error(f"refusing to overwrite manifest: {manifest}")
    files = sorted(path for path in root.rglob("*") if path.is_file())
    if not files:
        parser.error(f"checkpoint has no files: {root}")
    temporary = manifest.with_name(f".{manifest.name}.tmp-{os.getpid()}")
    try:
        with temporary.open("x", encoding="ascii") as handle:
            for path in files:
                relative = path.relative_to(root).as_posix()
                digest = direct_sha256(path)
                handle.write(f"{digest}  {relative}\n")
                print(f"OK SHA256 {relative}", flush=True)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, manifest)
    except BaseException:
        temporary.unlink(missing_ok=True)
        raise
    print(f"Manifest: {manifest}\nFiles: {len(files)}\nRESULT: PASS")


if __name__ == "__main__":
    main()
