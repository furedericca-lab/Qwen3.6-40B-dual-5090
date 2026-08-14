#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
python="$repo_root/.quantize-venv/bin/python"
probe="$repo_root/scripts/verify-source-upstream-buffered-incident.py"

if [[ ! -x "$python" ]]; then
  printf 'missing quantizer environment: %s\n' "$python" >&2
  exit 2
fi
if [[ $# -eq 0 ]]; then
  printf 'usage: %s [--trace-syscalls] --probe --only <repo-path> --max-bytes-per-file <bytes> [probe options]\n' "$0" >&2
  exit 2
fi

trace=false
if [[ ${1:-} == "--trace-syscalls" ]]; then
  trace=true
  shift
fi
if [[ " $* " != *" --probe "* ]]; then
  printf 'refusing non-probe invocation; full buffered verification is not permitted\n' >&2
  exit 2
fi

taint=$(< /proc/sys/kernel/tainted)
if [[ "$taint" != 0 && "$taint" != 4096 ]]; then
  printf 'probe requires a clean boot with taint 0 or 4096; current taint=%s\n' "$taint" >&2
  exit 2
fi
if journalctl -k -b --no-pager | rg -qi 'bad page state|BAD_PAGE|compound_head|corrupted mapping in tail page|general protection fault|NVRM: Xid|Xid \(PCI:'; then
  printf 'probe requires a clean boot with no prior kernel corruption or Xid\n' >&2
  exit 2
fi

timestamp=$(date -u +%Y%m%dT%H%M%SZ)
run_dir="$repo_root/logs/buffered-io-probe-$timestamp"
mkdir -p "$run_dir"
boot_id=$(< /proc/sys/kernel/random/boot_id)
started=$(date --iso-8601=seconds)
printf 'boot_id=%s\nstarted=%s\ntaint_before=%s\ncommand=%q ' "$boot_id" "$started" "$taint" "$python" > "$run_dir/run.env"
printf '%q ' "$probe" "$@" >> "$run_dir/run.env"
printf '\n' >> "$run_dir/run.env"

set +e
if "$trace"; then
  strace -ff -ttt -T -yy -s 160 -o "$run_dir/strace" \
    -e trace=openat,read,lseek,close,statx \
    "$python" "$probe" "$@" --report "$run_dir/report.json" \
    >"$run_dir/stdout.log" 2>"$run_dir/stderr.log"
  status=$?
else
  "$python" "$probe" "$@" --report "$run_dir/report.json" \
    >"$run_dir/stdout.log" 2>"$run_dir/stderr.log"
  status=$?
fi
set -e

journalctl -k -b --no-pager -o short-iso --since "$started" > "$run_dir/kernel-after.log" || true
printf 'exit_status=%s\ntaint_after=%s\nended=%s\n' "$status" "$(< /proc/sys/kernel/tainted)" "$(date --iso-8601=seconds)" >> "$run_dir/run.env"
printf 'evidence=%s\nexit_status=%s\n' "$run_dir" "$status"
exit "$status"
