#!/usr/bin/env bash
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"
python3 scripts/supervisor.py init
ITER=20
for i in $(seq 1 $ITER); do
  echo "iteration $i"
  OUT=$(python3 scripts/supervisor.py start --command "bash -lc 'sleep 3'" --timeout 1 --grace 1)
  ID=$(python3 -c "import sys,json; print(json.loads(sys.stdin.read())['id'])" <<< "$OUT")
  # hammer check_run while monitor races
  for j in $(seq 1 50); do
    python3 scripts/supervisor.py check "$ID" >/dev/null || true
    sleep 0.05
  done
  # wait shortly and inspect final state
  sleep 1
  python3 - <<PY
import sqlite3,sys
id = int(${ID})
conn=sqlite3.connect('reports/run-supervision/supervisor.db')
cur=conn.cursor()
cur.execute('SELECT status,timeout_detected_at,escalated_to_sigkill FROM runs WHERE id=?',(id,))
row=cur.fetchone()
print('iter', ${i}, 'db_row', row)
if not row:
    sys.exit(2)
if row[0] != 'timed_out':
    print('expected timed_out, got',row[0]); sys.exit(2)
# check transitions table
cur.execute('SELECT previous_status,new_status,source FROM transitions WHERE run_uuid=(SELECT run_uuid FROM runs WHERE id=?) ORDER BY id DESC LIMIT 1',(id,))
tr=cur.fetchone()
print('transition:',tr)
if not tr:
    print('no transition recorded'); sys.exit(2)
PY
  echo "iteration $i ok"
done

echo "race-timeout test completed ($ITER iterations)"
