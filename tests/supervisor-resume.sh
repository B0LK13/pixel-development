#!/usr/bin/env bash
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"
python3 scripts/supervisor.py init
OUT=$(python3 scripts/supervisor.py start --command "bash -lc 'echo start; sleep 8; echo done'" )
ID=$(python3 -c "import sys,json; print(json.loads(sys.stdin.read())['id'])" <<< "$OUT")
echo "started run id=$ID"
sleep 1
PIDS=$(pgrep -f "scripts/supervisor.py" || true)
echo "supervisor pids: $PIDS"
# kill one supervisor monitor if present
for p in $PIDS; do
  if [ "$p" != "$$" ]; then
    echo "killing monitor pid $p"
    kill -9 "$p" || true
    break
  fi
done
sleep 1
# attempt resume (should attach or start new)
python3 scripts/supervisor.py resume "$ID" > /tmp/resume_out.json || true
cat /tmp/resume_out.json
python3 - <<PY
import json
j=json.load(open('/tmp/resume_out.json'))
print('resume result:', j)
PY
sleep 10
python3 scripts/supervisor.py check "$ID" > /tmp/check_after.json || true
cat /tmp/check_after.json

echo "resume fixture completed"
