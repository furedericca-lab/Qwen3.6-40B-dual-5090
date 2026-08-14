#!/usr/bin/env bash
# Long prefill probe: generate a ~32K token prompt and verify it prefills
# and decodes without error, crash, or quality collapse.
# Usage: probe-long-prefill.sh [label]
set -euo pipefail

label=${1:-long-prefill}
base=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
outdir="$base/evidence/phase3"
mkdir -p "$outdir"

url=http://127.0.0.1:8000

echo "=== Long prefill probe for: $label ==="

# Generate a large prompt by repeating a substantial paragraph.
# Each paragraph is ~100 tokens. 320 repetitions ≈ 32K tokens.
paragraph="The development of artificial intelligence has been one of the most transformative technological advances of the twenty-first century. Machine learning algorithms, particularly deep neural networks, have achieved remarkable performance across a wide range of tasks including image recognition, natural language processing, and strategic game playing. The field traces its roots to the Dartmouth Conference of 1956, where the term was first coined, but progress was slow for decades due to limited computational resources and data availability. The breakthrough came with the convergence of three factors: the availability of massive datasets through the internet, the development of powerful GPU hardware originally designed for graphics rendering, and algorithmic innovations such as the transformer architecture introduced in 2017. These transformer models, which rely on self-attention mechanisms rather than recurrent connections, have proven exceptionally scalable, with modern language models trained on trillions of tokens across thousands of GPUs. The implications extend far beyond technology into economics, healthcare, education, and governance, raising fundamental questions about automation, employment, privacy, and the nature of intelligence itself."

# Build the long prompt: 320 repetitions of the paragraph
prompt_file=$(mktemp /tmp/long-prefill-XXXXXX.json)
trap "rm -f $prompt_file" EXIT

# Build JSON body in a temp file using python3 (avoids arg list too long)
python3 -c "
import json, sys
paragraph = '''$paragraph'''
long_text = (paragraph + ' ') * 320
body = {
    'messages': [
        {'role': 'user', 'content': long_text + '\n\nBased on the above text, summarize in exactly three sentences the key factors that enabled the AI breakthrough.'}
    ],
    'max_tokens': 256,
    'temperature': 0.3
}
json.dump(body, sys.stdout)
" > "$prompt_file"

# Estimate token count
char_count=$(wc -c < "$prompt_file")
echo "JSON body size: ${char_count} bytes"

# Send the request
echo "--- Sending long prefill request ---"
time curl -fsS "$url/v1/chat/completions" \
  -H 'Content-Type: application/json' \
  -d @"$prompt_file" \
  > "$outdir/${label}-raw.json" 2>&1

# Extract metrics
jq '{
  prompt_tokens: .usage.prompt_tokens,
  completion_tokens: .usage.completion_tokens,
  prompt_tok_s: .timings.prompt_per_second,
  completion_tok_s: .timings.predicted_per_second,
  prompt_ms: .timings.prompt_ms,
  predicted_ms: .timings.predicted_ms,
  draft_n: (.timings.draft_n // (.timings.speculative.draft_n // 0)),
  accepted_n: (.timings.draft_n_accepted // (.timings.speculative.accepted_n // 0)),
  content: .choices[0].message.content
}' "$outdir/${label}-raw.json" > "$outdir/${label}-metrics.json"

echo "--- Metrics ---"
cat "$outdir/${label}-metrics.json"

echo "--- Output preview ---"
jq -r '.content' "$outdir/${label}-metrics.json" | head -10

# GPU state after long prefill
nvidia-smi --query-gpu=index,memory.used,memory.total --format=csv,noheader > "$outdir/${label}-gpu.csv" 2>/dev/null || true
cat "$outdir/${label}-gpu.csv"

# Kernel stability check
echo "--- Kernel stability ---"
sudo dmesg | grep -iE 'BAD_PAGE|Oops|Xid' | grep -v RTL | head -5 || echo "No kernel errors"

echo "=== Long prefill probe complete ==="
