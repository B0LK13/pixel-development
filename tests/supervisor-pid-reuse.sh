#!/usr/bin/env bash
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"
python3 scripts/supervisor.py init
# start a long sleep in background as unrelated process
bash -c "sleep 30 & echo $!" > /tmp/unrelated_pid.txt
UNPID=$(cat /tmp/unrelated_pid.txt)
echo "unrelated pid=$UNPID"
# craft a fake DB entry referencing this pid but with a mismatched pid_start_time
python3 - <<PY
import sqlite3,os
conn=sqlite3.connect('reports/run-supervision/supervisor.db')
cur=conn.cursor()
cur.execute("INSERT INTO runs (run_uuid,cmd,workdir,log_path,pid,pid_start_time,pgid,status,started_at,updated_at,commit_hash) VALUES (?,?,?,?,?,?,?,?,?,?,?)",
            ('fake-'+os.urandom(4).hex(),'sleep 30',os.getcwd(),'reports/run-supervision/fake/stdout.log',%d,'FAKE_START','0','running','now','now',None))
conn.commit()
print('inserted fake run')
PY
# find fake id
ID=$(python3 - <<PY
import sqlite3
conn=sqlite3.connect('reports/run-supervision/supervisor.db')
cur=conn.cursor()
cur.execute("SELECT id FROM runs WHERE pid_start_time=? ORDER BY id DESC LIMIT 1", ('FAKE_START',))
row=cur.fetchone()
print(row[0] if row else '')
PY
if [ -z "$ID" ]; then echo "could not create fake run"; exit 2; fi
# attempt resume: should not attach to unrelated pid but instead start a fresh run
OUT=$(python3 scripts/supervisor.py resume "$ID")
echo "resume out: $OUT"
if echo "$OUT" | grep -q 'new_run'; then
  echo 'pid reuse test ok'
  exit 0
else
  echo 'resume incorrectly attached to unrelated pid' >&2
  exit 2
fi
