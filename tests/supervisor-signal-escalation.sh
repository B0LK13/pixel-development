#!/usr/bin/env bash
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"
python3 scripts/supervisor.py init
OUTFILE=$(mktemp /tmp/supervisor-start.XXXXXX.json)
SUPERVISOR_WAIT_FINALIZE_SECONDS=30 python3 scripts/supervisor.py start --command "bash -lc 'trap "echo received; sleep 100" TERM; echo started; sleep 100'" --timeout 2 --grace 1 >"$OUTFILE" 2>"$OUTFILE.err" || true
ID=$(python3 -c "import sys,json; print(json.load(open(sys.argv[1]))['id'])" "$OUTFILE")
rm -f "$OUTFILE" "$OUTFILE.err"
# wait until timed_out
for i in $(seq 1 30); do
  sleep 1
  STATUS=$(python3 scripts/supervisor.py check "$ID")
  echo "$STATUS"
  echo "$STATUS" | grep -q 'timed_out' && break || true
done
python3 - <<PY
import sqlite3,sys
conn=sqlite3.connect('reports/run-supervision/supervisor.db')
cur=conn.cursor()
cur.execute('SELECT status, timeout_detected_at, escalated_to_sigkill FROM runs WHERE id=?',(int($ID),))
row=cur.fetchone()
print('row:',row)
if row[0] != 'timed_out':
    print('expected timed_out', file=sys.stderr); sys.exit(2)
print('signal escalation test ok')
PY

echo "signal escalation test completed"
