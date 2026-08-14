#!/usr/bin/env bash
# Rigorous MTP benchmark with proper warm-up exclusion, continuous power
# sampling, and latency percentiles.
#
# Usage: BENCH_TEMP=0.6 MTP_BENCH_LABEL=n3-p0-t06 benchmark-mtp.sh
#
# Requires llama-server running with the target MTP configuration.
# Set MTP_BENCH_LABEL to identify the configuration in output filenames.
# Set BENCH_TEMP to control sampling temperature (default: 0).
#
# Methodology:
#   - Fixed seed (42) and temperature for deterministic sampling
#   - 1 warm-up run (excluded from all statistics)
#   - 5 formal runs (all statistics computed from these only)
#   - Continuous GPU power sampling during generation (200ms interval)
#   - Reports: mean, median, stddev, P95, min, max of decode tok/s
#   - Energy: avg power, P95 power, max power, J/token
set -euo pipefail

base=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
outdir="$base/evidence/mtp-benchmark"
mkdir -p "$outdir"

url=http://127.0.0.1:8000

config_label="${MTP_BENCH_LABEL:-unknown}"
BENCH_TEMP="${BENCH_TEMP:-0}"
echo "=== MTP Benchmark: $config_label (temp=$BENCH_TEMP) ==="

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

# --- Functions ---

run_one() {
  local run_id="$1"
  local outfile="$outdir/${config_label}-run${run_id}.json"
  
  python3 -c "
import json, sys
payload = {
    'messages': [{'role': 'user', 'content': '''$PROMPT'''}],
    'max_tokens': $MAX_TOKENS,
    'temperature': $BENCH_TEMP,
    'seed': 42
}
json.dump(payload, sys.stdout)
" | curl -fsS "$url/v1/chat/completions" \
    -H 'Content-Type: application/json' \
    -d @- \
    > "$outfile"
  
  local ts=$(jq -r '.timings.predicted_per_second // 0' "$outfile")
  local pt=$(jq -r '.usage.prompt_tokens // 0' "$outfile")
  local ct=$(jq -r '.usage.completion_tokens // 0' "$outfile")
  local dn=$(jq -r '(.timings.draft_n // (.timings.speculative.draft_n // 0))' "$outfile")
  local da=$(jq -r '(.timings.draft_n_accepted // (.timings.speculative.accepted_n // 0))' "$outfile")
  local pps=$(jq -r '.timings.prompt_per_second // 0' "$outfile")
  local prompt_ms=$(jq -r '.timings.prompt_ms // 0' "$outfile")
  local predicted_n=$(jq -r '.timings.predicted_n // 0' "$outfile")
  local predicted_ms=$(jq -r '.timings.predicted_ms // 0' "$outfile")
  
  echo "  Run $run_id: prompt=${pt} completion=${ct} decode=${ts} tok/s prompt=${pps} tok/s draft_n=${dn} accepted=${da}" >&2
  
  # Return tok/s for collection (stdout only)
  echo "$ts"
}

# Continuous power sampling during a command, output to a file
# Usage: start_power_sampling <output_file>
# Stops when stop_power_sampling is called
_power_pid=""

start_power_sampling() {
  local pfile="$1"
  rm -f "$pfile"
  # Sample both GPUs every 200ms
  (
    while true; do
      nvidia-smi --query-gpu=index,power.draw --format=csv,noheader,nounits 2>/dev/null >> "$pfile" || true
      sleep 0.2
    done
  ) &
  _power_pid=$!
}

stop_power_sampling() {
  if [[ -n "$_power_pid" ]]; then
    kill "$_power_pid" 2>/dev/null || true
    wait "$_power_pid" 2>/dev/null || true
    _power_pid=""
  fi
}

# --- Clean previous data ---
rm -f "$outdir/${config_label}-run"*.json
rm -f "$outdir/${config_label}-formal-toks.txt"
rm -f "$outdir/${config_label}-power-samples.csv"

# --- Warm-up run (excluded from statistics) ---
echo "--- Warm-up (excluded from stats) ---"
run_one "warmup" > /dev/null

# --- Formal runs ---
echo "--- Formal runs ($RUNS) ---"
for i in $(seq 1 "$RUNS"); do
  power_file="$outdir/${config_label}-power-run${i}.csv"
  start_power_sampling "$power_file"
  toks=$(run_one "$i")
  stop_power_sampling
  echo "$toks" >> "$outdir/${config_label}-formal-toks.txt"
  
  # Compute per-run power stats
  python3 -c "
import statistics, sys
vals = []
with open('$power_file') as f:
  for line in f:
    parts = line.strip().split(',')
    if len(parts) == 2:
      try:
        gpu_idx = int(parts[0].strip())
        power = float(parts[1].strip())
        vals.append((gpu_idx, power))
      except ValueError:
        continue
if not vals:
  print(f'  Run $i power: no samples')
  sys.exit(0)
g0 = [p for idx,p in vals if idx == 0]
g1 = [p for idx,p in vals if idx == 1]
total = [a+b for a,b in zip(g0,g1)] if g0 and g1 else []
if total:
  print(f'  Run $i power: avg={statistics.mean(total):.1f}W  P95={sorted(total)[int(len(total)*0.95)]:.1f}W  max={max(total):.1f}W  (G0={statistics.mean(g0):.1f}W, G1={statistics.mean(g1):.1f}W)')
  # Append to aggregated power file
  with open('${power_file}.summary', 'w') as sf:
    sf.write(f'avg={statistics.mean(total):.1f}\n')
    sf.write(f'p95={sorted(total)[int(len(total)*0.95)]:.1f}\n')
    sf.write(f'max={max(total):.1f}\n')
    sf.write(f'g0_avg={statistics.mean(g0):.1f}\n')
    sf.write(f'g1_avg={statistics.mean(g1):.1f}\n')
"
done

# --- Compute statistics from formal runs only ---
echo "--- Statistics (formal runs only) ---"
python3 -c "
import statistics, sys, json

vals = [float(x.strip()) for x in open('$outdir/${config_label}-formal-toks.txt') if x.strip()]
if not vals:
    print('No data')
    sys.exit(1)

mean = statistics.mean(vals)
median = statistics.median(vals)
stdev = statistics.stdev(vals) if len(vals) > 1 else 0.0
sorted_vals = sorted(vals)
p95 = sorted_vals[int(len(sorted_vals) * 0.95)] if len(sorted_vals) > 1 else sorted_vals[0]
mn, mx = min(vals), max(vals)

print(f'  N={len(vals)}')
print(f'  Mean:   {mean:.2f} tok/s')
print(f'  Median: {median:.2f} tok/s')
print(f'  StdDev: {stdev:.4f} tok/s')
print(f'  P95:    {p95:.2f} tok/s')
print(f'  Min:    {mn:.2f} tok/s')
print(f'  Max:    {mx:.2f} tok/s')

# Aggregate power across all runs
power_avgs = []
power_p95s = []
power_maxs = []
for i in range(1, $RUNS + 1):
    sf = f'$outdir/${config_label}-power-run{i}.csv.summary'
    try:
        d = {}
        with open(sf) as f:
            for line in f:
                k,v = line.strip().split('=')
                d[k] = float(v)
        power_avgs.append(d['avg'])
        power_p95s.append(d['p95'])
        power_maxs.append(d['max'])
    except:
        pass

if power_avgs:
    pavg = statistics.mean(power_avgs)
    pp95 = statistics.mean(power_p95s)
    pmax = max(power_maxs)
    jpt = pavg / mean if mean > 0 else 0
    print(f'  Power avg: {pavg:.1f} W')
    print(f'  Power P95: {pp95:.1f} W')
    print(f'  Power max: {pmax:.1f} W')
    print(f'  J/token:   {jpt:.2f} J/tok')
else:
    pavg = pp95 = pmax = jpt = 0

# Write summary
with open('$outdir/${config_label}-summary.json', 'w') as f:
    json.dump({
        'n': len(vals),
        'mean': round(mean, 2),
        'median': round(median, 2),
        'stdev': round(stdev, 4),
        'p95': round(p95, 2),
        'min': round(mn, 2),
        'max': round(mx, 2),
        'power_avg_w': round(pavg, 1),
        'power_p95_w': round(pp95, 1),
        'power_max_w': round(pmax, 1),
        'j_per_token': round(jpt, 2),
    }, f, indent=2)
"

# GPU memory state (post-benchmark snapshot)
nvidia-smi --query-gpu=index,memory.used,memory.total --format=csv,noheader 2>/dev/null || true

echo "=== Benchmark complete: $config_label ==="
