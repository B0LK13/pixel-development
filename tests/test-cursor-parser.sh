#!/usr/bin/env bash
set -euo pipefail
ROOT=$(dirname "$0")/fixtures/stream-json
OUTDIR=$ROOT/out
mkdir -p "$OUTDIR"

cases=(
  example-ack-complete.txt
  example-completion-only.txt
  example-malformed-line.txt
)

for c in "${cases[@]}"; do
  echo "--- $c ---"
  pwsh -File adapters/Invoke-CursorAgent.ps1 -InputFile "$ROOT/$c" -OutputDir "$OUTDIR" || true
  jq -C . "$OUTDIR/dispatch-result.json" || cat "$OUTDIR/dispatch-result.json"
  echo
done
