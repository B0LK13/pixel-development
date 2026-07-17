#!/usr/bin/env bash
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"
python3 scripts/supervisor.py init
# start a short run
OUT=$(python3 scripts/supervisor.py start --command "bash -lc 'echo hello; sleep 1; echo done'" )
ID=$(python3 -c "import sys,json; print(json.loads(sys.stdin.read())['id'])" <<< "$OUT")
echo "started run id=$ID"
# Wait for completion
sleep 2
# corrupt heartbeat.json if present
RUN_DIR=$(python3 - <<PY
import sqlite3,sys
conn=sqlite3.connect('reports/run-supervision/supervisor.db')
cur=conn.cursor()
cur.execute('SELECT log_path FROM runs WHERE id=?',(int($ID),))
row=cur.fetchone()
print(row[0] if row else '')
PY
)
if [ -n "$RUN_DIR" ]; then
  HB=$(dirname "$RUN_DIR")/heartbeat.json
  if [ -f "$HB" ]; then
    echo "{" > "$HB"  # truncated JSON
    echo "corrupted heartbeat written"
  fi
fi
# call check_run and ensure no crash; expect interrupted/completed/abandoned output
python3 - <<PY
import subprocess,sys
out=subprocess.run(['python3','scripts/supervisor.py','check',str($ID)], capture_output=True, text=True)
print('check output:', out.stdout)
print('returncode:', out.returncode)
if out.returncode not in (0,2):
    print('unexpected return code', out.returncode)
    sys.exit(2)
print('corrupted-state test ok')
PY

echo "corrupted-state test completed"
