#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$repo_root/config/runtime.env"
base_url="http://${HOST}:${PORT}"

curl --fail --silent --show-error "$base_url/health" >/dev/null
curl --fail --silent --show-error "$base_url/v1/models" | jq --arg model "$SERVED_MODEL_NAME" '
  if any(.data[]?; .id == $model) then . else error("served model is absent") end
'
curl --fail --silent --show-error "$base_url/v1/chat/completions" \
  -H 'Content-Type: application/json' \
  --data "{\"model\":\"$SERVED_MODEL_NAME\",\"messages\":[{\"role\":\"user\",\"content\":\"Reply with exactly: ready\"}],\"max_tokens\":4,\"temperature\":0}" \
  | jq -e '.choices[0].message.content'
