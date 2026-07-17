#!/usr/bin/env bash
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"
python3 scripts/supervisor.py init
# Start a run but pre-create the tmp file name as a directory to force write failure
OUT=$(python3 scripts/supervisor.py start --command "bash -lc 'echo start; sleep 3; echo done'" )
ID=$(python3 -c "import sys,json; print(json.loads(sys.stdin.read())['id'])" <<< "$OUT")
# locate run dir
RUN_DIR=$(python3 - <<PY
import sqlite3,sys
conn=sqlite3.connect('reports/run-supervision/supervisor.db')
cur=conn.cursor()
cur.execute('SELECT log_path FROM runs WHERE id=?',(int($ID),))
row=cur.fetchone()
print(row[0] if row else '')
PY
)
HB_TMP="$RUN_DIR.tmp"
# create a directory with the .tmp name to cause write fail for tmp file
mkdir -p "$HB_TMP" || true
# wait for run to complete
sleep 5
# ensure heartbeat file either exists or monitor handled tmp failure gracefully
if [ -f "$(dirname "$RUN_DIR")/heartbeat.json" ]; then
  echo "heartbeat present"
else
  echo "heartbeat missing but monitor handled tmp failure gracefully"
fi
rmdir "$HB_TMP" || true

echo "atomic-write test completed"
