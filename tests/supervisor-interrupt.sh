#!/usr/bin/env bash
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"
python3 scripts/supervisor.py init
OUT=$(python3 scripts/supervisor.py start --command "bash -lc 'echo start; sleep 5; echo done'" )
ID=$(python3 -c "import sys,json; print(json.loads(sys.stdin.read())['id'])" <<< "$OUT")
echo "started run id=$ID"
# give monitor time to start
sleep 1
# find supervisor.py processes (monitors)
ps -ef | grep supervisor.py | grep -v grep | awk '{print $2" "$8" "$9" "$10}' || true
PIDS=$(pgrep -f "scripts/supervisor.py" || true)
# pick a monitor pid to kill (not the invoker)
for p in $PIDS; do
  # ensure it's not the current shell or recent immediate parent
  if [ "$p" != "$$" ]; then
    echo "killing monitor pid $p"
    kill -9 "$p" || true
    break
  fi
done
# now check run status
sleep 1
python3 scripts/supervisor.py check "$ID" > /tmp/supervisor-check.json || true
cat /tmp/supervisor-check.json
# ensure it reports running or interrupted but child still exists
python3 - <<PY
import json,sys
j=json.load(open('/tmp/supervisor-check.json'))
print('status=', j.get('status'))
PY

echo "waiting for child to finish"
sleep 6
python3 scripts/supervisor.py check "$ID" > /tmp/supervisor-check2.json || true
cat /tmp/supervisor-check2.json

echo "interrupt fixture completed"
