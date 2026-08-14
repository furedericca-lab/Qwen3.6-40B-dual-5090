#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$repo_root/config/runtime.env"

if [[ "$ENABLE_MTP" != "false" ]]; then
  printf 'runtime profile must keep ENABLE_MTP=false; this launcher adds MTP-1 explicitly\n' >&2
  exit 1
fi

exec "$repo_root/scripts/vllm-server-first-boot.sh" \
  --speculative-config '{"method":"mtp","num_speculative_tokens":1}' \
  "$@"
