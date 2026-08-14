#!/usr/bin/env bash
# Run standard probes against llama-server and record timing/acceptance.
# Usage: probe-all.sh [label]
# Label is used as a prefix for output files.
set -euo pipefail

label=${1:-default}
base=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
outdir="$base/evidence/mtp-comparison"
mkdir -p "$outdir"

url=http://127.0.0.1:8000

echo "=== Running probes for configuration: $label ==="

# Health check
curl -fsS "$url/health" | jq . > "$outdir/${label}-health.json" 2>/dev/null || true
echo "Health: $(cat "$outdir/${label}-health.json" 2>/dev/null || echo FAIL)"

# Model info
curl -fsS "$url/v1/models" | jq . > "$outdir/${label}-models.json" 2>/dev/null || true

# Helper: extract common metrics from a completion response, handling missing speculative fields
extract_metrics() {
  local infile="$1"
  local outfile="$2"
  # chat completions: draft_n/draft_n_accepted at top level of timings
  # completions: no draft fields in timings
  # speculative sub-object may also appear in some versions
  jq '{
    prompt_tokens: .usage.prompt_tokens,
    completion_tokens: .usage.completion_tokens,
    prompt_tok_s: .timings.prompt_per_second,
    completion_tok_s: .timings.predicted_per_second,
    prompt_ms: .timings.prompt_ms,
    predicted_ms: .timings.predicted_ms,
    draft_n: (.timings.draft_n // (.timings.speculative.draft_n // 0)),
    accepted_n: (.timings.draft_n_accepted // (.timings.speculative.accepted_n // 0)),
    accepted_pct: (if (.timings.draft_n // (.timings.speculative.draft_n // 0)) > 0 then ((.timings.draft_n_accepted // (.timings.speculative.accepted_n // 0)) / (.timings.draft_n // (.timings.speculative.draft_n // 1)) * 100) else 0 end),
    mean_draft_len: (.timings.speculative.draft_length // null),
    content: (if .choices[0].text then .choices[0].text else .choices[0].message.content end)
  }' "$infile" > "$outfile"
}

# Probe 1: Math
echo "--- Math probe ---"
curl -fsS "$url/v1/completions" \
  -H 'Content-Type: application/json' \
  -d '{"prompt":"2+3=","max_tokens":32,"temperature":0}' \
  > "$outdir/${label}-math-raw.json"
extract_metrics "$outdir/${label}-math-raw.json" "$outdir/${label}-math.json"
cat "$outdir/${label}-math.json"

# Probe 2: Chinese
echo "--- Chinese probe ---"
curl -fsS "$url/v1/chat/completions" \
  -H 'Content-Type: application/json' \
  -d '{"messages":[{"role":"user","content":"用三句话解释量子计算的基本原理"}],"max_tokens":256,"temperature":0.6}' \
  > "$outdir/${label}-chinese-raw.json"
extract_metrics "$outdir/${label}-chinese-raw.json" "$outdir/${label}-chinese.json"
cat "$outdir/${label}-chinese.json"

# Probe 3: JSON
echo "--- JSON probe ---"
curl -fsS "$url/v1/chat/completions" \
  -H 'Content-Type: application/json' \
  -d '{"messages":[{"role":"user","content":"Output a JSON object with three keys: name (string), age (number), hobbies (array of strings). No other text."}],"max_tokens":128,"temperature":0.3}' \
  > "$outdir/${label}-json-raw.json"
extract_metrics "$outdir/${label}-json-raw.json" "$outdir/${label}-json.json"
cat "$outdir/${label}-json.json"

# Probe 4: Python code
echo "--- Python probe ---"
curl -fsS "$url/v1/chat/completions" \
  -H 'Content-Type: application/json' \
  -d '{"messages":[{"role":"user","content":"Write a Python function merge_sorted_lists(a, b) that merges two sorted lists into one sorted list."}],"max_tokens":256,"temperature":0.3}' \
  > "$outdir/${label}-python-raw.json"
extract_metrics "$outdir/${label}-python-raw.json" "$outdir/${label}-python.json"
cat "$outdir/${label}-python.json"

# Probe 5: Summary
echo "--- Summary probe ---"
curl -fsS "$url/v1/chat/completions" \
  -H 'Content-Type: application/json' \
  -d '{"messages":[{"role":"user","content":"Summarize the following in three bullet points:\n\nThe Internet is a global system of interconnected computer networks that use the standardized Internet Protocol Suite (TCP/IP) to serve billions of users worldwide. It is a network of networks that consists of millions of private, public, academic, business, and government networks, of local to global scope, that are linked by a broad array of electronic and optical networking technologies."}],"max_tokens":128,"temperature":0.3}' \
  > "$outdir/${label}-summary-raw.json"
extract_metrics "$outdir/${label}-summary-raw.json" "$outdir/${label}-summary.json"
cat "$outdir/${label}-summary.json"

# GPU state
nvidia-smi --query-gpu=index,memory.used,memory.total --format=csv,noheader > "$outdir/${label}-gpu.csv" 2>/dev/null || true
cat "$outdir/${label}-gpu.csv"

echo "=== Probes complete for: $label ==="
