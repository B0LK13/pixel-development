#!/usr/bin/env bash
set -euo pipefail
ROOT=$(dirname "$0")/fixtures/stream-json
OUTDIR=$ROOT/out
mkdir -p "$OUTDIR"

cases=(
  example-ack-complete.txt
  example-completion-only.txt
  example-malformed-line.txt
  example-echoed-user-prompt.txt
  example-system-envelope.txt
  example-assistant-prose.txt
  example-completion-before-ack.txt
  example-dup-ack.txt
  example-dup-completion.txt
  example-valid-json-no-event.txt
  example-nested-event-payload.txt
  example-unsupported-envelope.txt
  example-noncomplete-status.txt
  example-missing-status.txt
  example-original-crash.txt
)

# load expected matrix
MATRIX="$ROOT/fixture-matrix.json"

for c in "${cases[@]}"; do
  echo "--- $c ---"
  rm -f "$OUTDIR/dispatch-result.json"
  pwsh -File adapters/Invoke-CursorAgent.ps1 -InputFile "$ROOT/$c" -OutputDir "$OUTDIR" || true
  if [ ! -f "$OUTDIR/dispatch-result.json" ]; then
    echo "dispatch-result.json missing for $c"; exit 4
  fi
  # validate JSON
  jq -e . "$OUTDIR/dispatch-result.json" >/dev/null || { echo "invalid JSON for $c"; cat "$OUTDIR/dispatch-result.json"; exit 5; }
  actual_status=$(jq -r '.status' "$OUTDIR/dispatch-result.json")
  expected_status=$(jq -r ".\"$c\".expected_status" "$MATRIX")
  if [ "$actual_status" != "$expected_status" ]; then
    echo "FAIL: $c actual_status=$actual_status expected=$expected_status"; jq . "$OUTDIR/dispatch-result.json"; exit 6
  fi
  echo "PASS: $c -> $actual_status"
  echo
done
