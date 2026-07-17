#!/usr/bin/env bash
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"
python3 scripts/supervisor.py init
OUTFILE=$(mktemp /tmp/supervisor-start.XXXXXX.json)
SUPERVISOR_WAIT_FINALIZE_SECONDS=30 python3 scripts/supervisor.py start --command "sleep 5" --timeout 2 --grace 2 >"$OUTFILE" 2>"$OUTFILE.err" || true
ID=$(python3 -c "import sys,json; print(json.load(open(sys.argv[1]))['id'])" "$OUTFILE")
rm -f "$OUTFILE" "$OUTFILE.err"
echo "started run id=$ID"
# wait until status becomes timed_out or escalated
for i in $(seq 1 30); do
  sleep 1
  STATUS_JSON=$(python3 scripts/supervisor.py check "$ID")
  echo "$STATUS_JSON"
  echo "$STATUS_JSON" | grep -q 'timed_out' && break || true
done
# verify DB entry contains escalated_to_sigkill or timed_out
python3 - <<PY
import sqlite3,sys
from pathlib import Path
db=Path('reports/run-supervision/supervisor.db')
if not db.exists():
    print('db missing', file=sys.stderr); sys.exit(2)
conn=sqlite3.connect(str(db))
cur=conn.cursor()
cur.execute('SELECT status, timeout_detected_at, escalated_to_sigkill FROM runs ORDER BY id DESC LIMIT 1')
row=cur.fetchone()
print('db_row:', row)
if row[0] != 'timed_out':
    print('expected timed_out status', file=sys.stderr)
    sys.exit(2)
print('timeout test ok')
PY

echo "timeout test completed"
