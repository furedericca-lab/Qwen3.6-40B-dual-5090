#!/usr/bin/env python3
"""Buffered Eleanor upstream verifier and controlled BAD_PAGE trigger probe.

The default full verification is the exact workload that triggered BAD_PAGE on
2026-08-13. Use --probe with explicit bounds for fresh-boot, one-variable-at-a-
time diagnosis. Never run a probe after the boot already has BAD_PAGE or Xid.
"""

import argparse
import json
from pathlib import Path
import hashlib
import re
import subprocess
import sys
from time import monotonic

DEFAULT_REPO = "DavidAU/Qwen3.6-40B-Fable-Fusion-6-Core-Deckard-Eleanor-Heretic-Uncensored"
DEFAULT_ROOT = Path("/data/linux-fast/models/Qwen3.6-40B-Eleanor")
FORBIDDEN_KERNEL = re.compile(
    r"bad page state|BAD_PAGE|compound_head|corrupted mapping in tail page|"
    r"general protection fault|NVRM: Xid|Xid \(PCI:",
    re.IGNORECASE,
)

def sha256_file(
    path: Path, chunk_size: int, max_bytes: int | None = None, start_offset: int = 0
) -> tuple[str, int]:
    """Intentionally ordinary buffered reads for reproducing the incident."""
    digest = hashlib.sha256()
    read_total = 0
    with path.open("rb") as handle:
        handle.seek(start_offset)
        while True:
            wanted = chunk_size if max_bytes is None else min(chunk_size, max_bytes - read_total)
            if wanted <= 0:
                break
            chunk = handle.read(wanted)
            if not chunk:
                break
            digest.update(chunk)
            read_total += len(chunk)
    return digest.hexdigest(), read_total


def git_blob_sha1(
    path: Path, chunk_size: int, max_bytes: int | None = None, start_offset: int = 0
) -> tuple[str, int]:
    """Intentionally ordinary buffered reads for reproducing the incident."""
    size = path.stat().st_size
    digest = hashlib.sha1()
    digest.update(f"blob {size}\0".encode("ascii"))
    read_total = 0
    with path.open("rb") as handle:
        handle.seek(start_offset)
        while True:
            wanted = chunk_size if max_bytes is None else min(chunk_size, max_bytes - read_total)
            if wanted <= 0:
                break
            chunk = handle.read(wanted)
            if not chunk:
                break
            digest.update(chunk)
            read_total += len(chunk)
    return digest.hexdigest(), read_total


def lfs_value(lfs: object, key: str) -> object:
    if lfs is None:
        return None
    return lfs.get(key) if isinstance(lfs, dict) else getattr(lfs, key, None)


def forbidden_kernel_lines() -> list[str]:
    result = subprocess.run(
        ["journalctl", "-k", "-b", "--no-pager"], check=True, text=True, capture_output=True
    )
    return [line for line in result.stdout.splitlines() if FORBIDDEN_KERNEL.search(line)]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", default=DEFAULT_REPO)
    parser.add_argument("--root", type=Path, default=DEFAULT_ROOT)
    parser.add_argument("--revision", default="main")
    parser.add_argument("--chunk-mib", type=int, default=32)
    parser.add_argument("--probe", action="store_true", help="bounded buffered-read trigger experiment")
    parser.add_argument("--only", help="single repo-relative file for a probe")
    parser.add_argument("--max-bytes-per-file", type=int)
    parser.add_argument("--max-files", type=int)
    parser.add_argument("--start-offset", type=int, default=0)
    parser.add_argument("--repeats", type=int, default=1)
    parser.add_argument("--report", type=Path, help="write JSON evidence")
    args = parser.parse_args()
    if args.chunk_mib <= 0:
        parser.error("--chunk-mib must be positive")
    if args.probe and (not args.only or not args.max_bytes_per_file):
        parser.error("--probe requires --only and --max-bytes-per-file")
    if not args.probe and any((args.only, args.max_bytes_per_file, args.max_files, args.start_offset, args.repeats != 1)):
        parser.error("bounded read options require --probe")
    if args.start_offset < 0 or args.repeats <= 0:
        parser.error("--start-offset must be non-negative and --repeats must be positive")
    tainted = int(Path("/proc/sys/kernel/tainted").read_text().strip())
    kernel_before = forbidden_kernel_lines()
    if args.probe and (tainted not in (0, 4096) or kernel_before):
        parser.error(f"probe requires clean boot with taint 0 or 4096; taint={tainted}, events={len(kernel_before)}")

    root = args.root.resolve()
    if not root.is_dir():
        parser.error(f"local directory does not exist: {root}")
    from huggingface_hub import HfApi

    api = HfApi(endpoint="https://huggingface.co")
    revision = api.model_info(args.repo, revision=args.revision).sha
    entries = list(api.list_repo_tree(args.repo, recursive=True, revision=revision, repo_type="model"))
    remote = {entry.path: entry for entry in entries if getattr(entry, "size", None) is not None and getattr(entry, "path", None)}
    local = {path.relative_to(root).as_posix(): path for path in root.rglob("*") if path.is_file() and not path.relative_to(root).as_posix().startswith(".cache/huggingface/")}
    names = [args.only] if args.probe else sorted(remote)
    if args.probe and args.only not in remote:
        parser.error(f"--only is not a remote repository file: {args.only}")
    if args.max_files:
        names = names[:args.max_files]
    chunk_size = args.chunk_mib * 1024 * 1024
    outcome = {
        "mode": "probe" if args.probe else "full",
        "repo": args.repo,
        "revision": revision,
        "root": str(root),
        "chunk_mib": args.chunk_mib,
        "start_offset": args.start_offset,
        "max_bytes_per_file": args.max_bytes_per_file,
        "repeats": args.repeats,
        "taint_before": tainted,
        "kernel_events_before": kernel_before,
        "files": [],
        "started_monotonic": monotonic(),
    }
    failed = False
    for name in names:
        entry, path = remote[name], local.get(name)
        if path is None or path.stat().st_size != entry.size:
            failed = True
            outcome["files"].append({"path": name, "status": "missing-or-size-mismatch"})
            continue
        stat = path.stat()
        if args.probe and args.start_offset >= stat.st_size:
            parser.error(f"--start-offset is beyond EOF for {name}: {args.start_offset}/{stat.st_size}")
        for repeat in range(args.repeats):
            expected = lfs_value(getattr(entry, "lfs", None), "sha256")
            if expected:
                actual, read_bytes = sha256_file(path, chunk_size, args.max_bytes_per_file if args.probe else None, args.start_offset)
                status = "probe-complete" if args.probe else ("pass" if actual.lower() == expected.lower() else "hash-fail")
            else:
                actual, read_bytes = git_blob_sha1(path, chunk_size, args.max_bytes_per_file if args.probe else None, args.start_offset)
                expected = getattr(entry, "blob_id", None)
                status = "probe-complete" if args.probe else ("pass" if expected and actual.lower() == expected.lower() else "hash-fail")
            outcome["files"].append({
                "path": name,
                "device": stat.st_dev,
                "inode": stat.st_ino,
                "size": stat.st_size,
                "start_offset": args.start_offset,
                "read_bytes": read_bytes,
                "repeat": repeat + 1,
                "status": status,
                "actual": actual if not args.probe else None,
            })
            print(f"{status.upper()} {name} offset={args.start_offset} read_bytes={read_bytes} repeat={repeat + 1}", flush=True)
            kernel_now = forbidden_kernel_lines()
            if len(kernel_now) > len(kernel_before):
                failed = True
                outcome["kernel_events_after"] = kernel_now
                print("KERNEL EVENT DETECTED: stopping immediately", file=sys.stderr)
                break
            if status == "hash-fail":
                failed = True
        if failed:
            break
    outcome["elapsed_seconds"] = round(monotonic() - outcome.pop("started_monotonic"), 3)
    outcome["taint_after"] = int(Path("/proc/sys/kernel/tainted").read_text().strip())
    outcome.setdefault("kernel_events_after", forbidden_kernel_lines())
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(outcome, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({key: outcome[key] for key in ("mode", "revision", "chunk_mib", "taint_before", "taint_after", "elapsed_seconds")}, sort_keys=True))
    return 1 if failed or (not args.probe and any(item["status"] != "pass" for item in outcome["files"])) else 0


if __name__ == "__main__":
    raise SystemExit(main())
