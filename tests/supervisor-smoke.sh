#!/usr/bin/env bash
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"
# initialize DB
python3 scripts/supervisor.py init
# start a short run
OUT=$(python3 scripts/supervisor.py start --command "bash -lc 'echo smoke; sleep 0.5; echo done'" )
# parse id from JSON
ID=$(python3 -c "import sys,json; print(json.loads(sys.stdin.read())['id'])" <<< "$OUT")
echo "started run id=$ID"
# wait for completion (poll)
for _ in $(seq 1 20); do
  sleep 0.2
  STATUS=$(python3 scripts/supervisor.py check "$ID" )
  echo "$STATUS" | grep -q 'interrupted' && break || true
  # if running, continue; if interrupted or finished, break
  if echo "$STATUS" | grep -q 'running'; then
    continue
  else
    break
  fi
done
# print log tail
LOG=$(python3 - <<PY
import json,sys
info=json.loads('''$STATUS''')
print(info.get('log_path',''))
PY
)
[ -n "$LOG" ] && echo "=== log tail ===" && tail -n +1 "$LOG" || true

echo "smoke test completed"
