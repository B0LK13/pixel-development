#!/usr/bin/env python3
import sqlite3, os, json, time, datetime, argparse
REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
EVIDENCE_DIR = os.path.join(REPO_ROOT, 'reports', 'run-supervision')
DB_PATH = os.path.join(EVIDENCE_DIR, 'supervisor.db')

def now_iso():
    return datetime.datetime.utcnow().replace(microsecond=0).isoformat() + 'Z'

parser = argparse.ArgumentParser()
parser.add_argument('--age', type=int, default=600, help='heartbeat age seconds to consider stale')
parser.add_argument('--apply', action='store_true', help='apply changes (default: dry-run)')
args = parser.parse_args()

conn = sqlite3.connect(DB_PATH)
conn.execute('PRAGMA journal_mode=WAL;')
cur = conn.cursor()
cur.execute("SELECT id,run_uuid,pid,log_path,started_at FROM runs WHERE status='running'")
runs = cur.fetchall()
now = time.time()
candidates = []
for r in runs:
    id, run_uuid, pid, log_path, started_at = r
    run_dir = os.path.join(EVIDENCE_DIR, run_uuid)
    hb_path = os.path.join(run_dir, 'heartbeat.json')
    hb_age = None
    if os.path.exists(hb_path):
        hb_age = now - os.path.getmtime(hb_path)
    else:
        hb_age = None
    pid_alive = False
    if pid:
        try:
            os.kill(pid, 0)
            pid_alive = True
        except Exception:
            pid_alive = False
    stale = False
    if hb_age is None:
        stale = True
    else:
        stale = hb_age > args.age
    if stale or not pid_alive:
        candidates.append({'id': id, 'run_uuid': run_uuid, 'pid': pid, 'pid_alive': pid_alive, 'hb_age': hb_age, 'run_dir': run_dir})

print(json.dumps({'now': now_iso(), 'age_threshold': args.age, 'candidates_count': len(candidates)}, indent=2))
for c in candidates:
    print(json.dumps(c))

if candidates and args.apply:
    for c in candidates:
        run_dir = c['run_dir']
        run_uuid = c['run_uuid']
        try:
            with conn:
                conn.execute("UPDATE runs SET status=?, updated_at=?, abandon_reason=? WHERE run_uuid=?", ('recovery-required', now_iso(), 'reconciler-stale', run_uuid))
                conn.execute('INSERT INTO transitions (run_uuid, previous_status, new_status, source, reason, evidence, transitioned_at) VALUES (?,?,?,?,?,?,?)', (run_uuid, 'running', 'recovery-required', 'reconciler', 'heartbeat-stale', json.dumps({'hb_age': c['hb_age'], 'pid_alive': c['pid_alive']}), now_iso()))
            # write reconciler artifact
            try:
                os.makedirs(run_dir, exist_ok=True)
                with open(os.path.join(run_dir, 'reconciler.json'), 'w') as rf:
                    json.dump({'run_uuid': run_uuid, 'action': 'marked recovery-required', 'hb_age': c['hb_age'], 'pid_alive': c['pid_alive'], 'timestamp': now_iso()}, rf)
            except Exception:
                pass
            print('marked', run_uuid)
        except Exception as e:
            print('error marking', run_uuid, str(e))

conn.close()
