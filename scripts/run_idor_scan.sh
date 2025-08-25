#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${1:-/workspace/gitlab}"
OUT_JSON="${2:-/workspace/idor_findings.json}"
OUT_CSV="${3:-/workspace/idor_findings.csv}"

PY="python3"
SCANNER="/workspace/idor_scanner/scanner.py"

if [ ! -f "$SCANNER" ]; then
  echo "Scanner not found at $SCANNER" >&2
  exit 2
fi

"$PY" "$SCANNER" \
  --root "$ROOT_DIR" \
  --export-json "$OUT_JSON" \
  --export-csv "$OUT_CSV" \
  --batch-size 10 \
  --threshold 8 \
  --max-files 2000

echo "Findings JSON: $OUT_JSON"
echo "Findings CSV:  $OUT_CSV"

