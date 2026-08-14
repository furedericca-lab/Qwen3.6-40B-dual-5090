#!/usr/bin/env bash
# Rigorous MTP benchmark: fixed seed, temperature=0, same prompt per config,
# warm-up 1 + 5 formal runs. Reports mean/median/stddev.
#
# Usage: benchmark-mtp.sh
#
# Requires llama-server running with the target MTP configuration.
# Run this script once per configuration, changing MTP_N_MAX/MTP_P_MIN
# between restarts.
set -euo pipefail

base=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
outdir="$base/evidence/mtp-benchmark"
mkdir -p "$outdir"

url=http://127.0.0.1:8000

# Detect current config from server props
config_label="${MTP_BENCH_LABEL:-unknown}"
echo "=== MTP Benchmark: $config_label ==="

# Verify server is up
health=$(curl -fsS "$url/health" 2>/dev/null || echo "FAIL")
if [[ "$health" == "FAIL" ]]; then
  echo "ERROR: llama-server not responding at $url" >&2
  exit 1
fi

# Standard benchmark prompt (same for all configs)
PROMPT="Explain the difference between supervised learning and unsupervised learning in machine learning. Provide concrete examples of each approach and discuss when you would choose one over the other."

WARMUP=1
RUNS=5
MAX_TOKENS=200

# Array to collect tok/s values
declare -a tok_s_arr=()

run_one() {
  local run_id="$1"
  local outfile="$outdir/${config_label}-run${run_id}.json"
  
  curl -fsS "$url/v1/chat/completions" \
    -H 'Content-Type: application/json' \
    -d "$(jq -n \
      --arg prompt "$PROMPT" \
      '{
        messages: [{role: "user", content: $prompt}],
        max_tokens: '"$MAX_TOKENS"',
        temperature: 0,
        seed: 42
      }')" \
    > "$outfile"
  
  local ts=$(jq -r '.timings.predicted_per_second // 0' "$outfile")
  local pt=$(jq -r '.usage.prompt_tokens // 0' "$outfile")
  local ct=$(jq -r '.usage.completion_tokens // 0' "$outfile")
  local dn=$(jq -r '(.timings.draft_n // (.timings.speculative.draft_n // 0))' "$outfile")
  local da=$(jq -r '(.timings.draft_n_accepted // (.timings.speculative.accepted_n // 0))' "$outfile")
  local pps=$(jq -r '.timings.prompt_per_second // 0' "$outfile")
  
  echo "  Run $run_id: prompt=${pt} completion=${ct} decode=${ts} tok/s prompt=${pps} tok/s draft_n=${dn} accepted=${da}"
  
  echo "$ts" >> "$outdir/${config_label}-all-toks.txt"
}

# Clean previous data for this config
rm -f "$outdir/${config_label}-all-toks.txt"
rm -f "$outdir/${config_label}-run"*.json

# Warm-up run
echo "--- Warm-up ---"
run_one "warmup"

# Formal runs
echo "--- Formal runs ($RUNS) ---"
for i in $(seq 1 "$RUNS"); do
  run_one "$i"
done

# Compute statistics
echo "--- Statistics ---"
python3 -c "
import statistics, sys
vals = [float(x.strip()) for x in open('$outdir/${config_label}-all-toks.txt') if x.strip()]
if not vals:
    print('No data')
    sys.exit(1)
mean = statistics.mean(vals)
median = statistics.median(vals)
stdev = statistics.stdev(vals) if len(vals) > 1 else 0.0
mn, mx = min(vals), max(vals)
print(f'  N={len(vals)}')
print(f'  Mean:   {mean:.2f} tok/s')
print(f'  Median: {median:.2f} tok/s')
print(f'  StdDev: {stdev:.2f} tok/s')
print(f'  Min:    {mn:.2f} tok/s')
print(f'  Max:    {mx:.2f} tok/s')
# Write summary
with open('$outdir/${config_label}-summary.json', 'w') as f:
    import json
    json.dump({'n': len(vals), 'mean': round(mean,2), 'median': round(median,2), 'stdev': round(stdev,2), 'min': round(mn,2), 'max': round(mx,2)}, f, indent=2)
"

# GPU state
nvidia-smi --query-gpu=index,memory.used,memory.total,power.draw --format=csv,noheader > "$outdir/${config_label}-gpu.csv" 2>/dev/null || true
echo "--- GPU ---"
cat "$outdir/${config_label}-gpu.csv"

echo "=== Benchmark complete: $config_label ==="
