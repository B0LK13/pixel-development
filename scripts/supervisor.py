#!/usr/bin/env python3
"""
Lightweight process supervisor for run lifecycle tracking.
Usage: supervisor.py init | start --cmd '...' [--workdir .] | status <id> | list | check <id> | resume <id>
Persists metadata to reports/run-supervision/supervisor.db and writes logs to reports/run-supervision/<run_uuid>/stdout.log
"""
import argparse
import os
import sqlite3
import subprocess
import sys
import uuid
import datetime
import json

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
EVIDENCE_DIR = os.path.join(REPO_ROOT, 'reports', 'run-supervision')
DB_PATH = os.path.join(EVIDENCE_DIR, 'supervisor.db')

SCHEMA = '''
CREATE TABLE IF NOT EXISTS runs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    run_uuid TEXT UNIQUE,
    parent_id INTEGER,
    cmd TEXT,
    workdir TEXT,
    log_path TEXT,
    pid INTEGER,
    status TEXT,
    started_at TEXT,
    finished_at TEXT,
    exit_code INTEGER,
    commit_hash TEXT
);
'''



def ensure_dirs():
    os.makedirs(EVIDENCE_DIR, exist_ok=True)


def connect_db():
    ensure_dirs()
    conn = sqlite3.connect(DB_PATH)
    conn.execute('PRAGMA journal_mode=WAL;')
    conn.executescript(SCHEMA)
    conn.commit()
    return conn


def now_iso():
    return datetime.datetime.utcnow().replace(microsecond=0).isoformat() + 'Z'


def git_commit():
    try:
        out = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=REPO_ROOT)
        return out.decode().strip()
    except Exception:
        return None


def start_run(cmd, workdir=None, parent_id=None):
    conn = connect_db()
    run_uuid = datetime.datetime.utcnow().strftime('%Y%m%dT%H%M%SZ') + '-' + uuid.uuid4().hex[:8]
    run_dir = os.path.join(EVIDENCE_DIR, run_uuid)
    os.makedirs(run_dir, exist_ok=True)
    log_path = os.path.join(run_dir, 'stdout.log')
    started_at = now_iso()
    commit = git_commit()

    # Launch subprocess in new session
    with open(log_path, 'ab') as lf:
        # Use bash -lc to support shell constructs
        proc = subprocess.Popen(['bash', '-lc', cmd], cwd=(workdir or REPO_ROOT), stdout=lf, stderr=subprocess.STDOUT, preexec_fn=os.setsid)
        pid = proc.pid

    cur = conn.cursor()
    cur.execute('''INSERT INTO runs (run_uuid, parent_id, cmd, workdir, log_path, pid, status, started_at, commit_hash) VALUES (?,?,?,?,?,?,?,?,?)''',
                (run_uuid, parent_id, cmd, workdir or REPO_ROOT, log_path, pid, 'running', started_at, commit))
    conn.commit()
    run_id = cur.lastrowid
    print(json.dumps({'id': run_id, 'run_uuid': run_uuid, 'pid': pid, 'log_path': log_path}))
    return run_id


def get_run(run_id):
    conn = connect_db()
    cur = conn.cursor()
    cur.execute('SELECT id,run_uuid,parent_id,cmd,workdir,log_path,pid,status,started_at,finished_at,exit_code,commit_hash FROM runs WHERE id=?', (run_id,))
    row = cur.fetchone()
    return row


def list_runs():
    conn = connect_db()
    cur = conn.cursor()
    cur.execute('SELECT id,run_uuid,status,started_at,finished_at,cmd FROM runs ORDER BY id DESC LIMIT 200')
    rows = cur.fetchall()
    for r in rows:
        print(json.dumps({'id': r[0], 'run_uuid': r[1], 'status': r[2], 'started_at': r[3], 'finished_at': r[4], 'cmd': r[5]}))


def check_run(run_id):
    row = get_run(run_id)
    if not row:
        print(json.dumps({'error': 'not found'}))
        return 2
    pid = row[5]
    status = row[7]
    log_path = row[5]
    try:
        os.kill(pid, 0)
        alive = True
    except Exception:
        alive = False
    conn = connect_db()
    cur = conn.cursor()
    if alive:
        # still running
        cur.execute('UPDATE runs SET status=? WHERE id=?', ('running', run_id))
        conn.commit()
        print(json.dumps({'id': run_id, 'pid': pid, 'status': 'running', 'log_path': row[5]}))
        return 0
    else:
        # process not alive -- try to collect exit_code by checking if finished_at recorded
        if row[9]:
            print(json.dumps({'id': run_id, 'status': row[7], 'finished_at': row[9], 'exit_code': row[10], 'log_path': row[5]}))
            return 0
        else:
            # mark interrupted
            cur.execute('UPDATE runs SET status=?, finished_at=? WHERE id=?', ('interrupted', now_iso(), run_id))
            conn.commit()
            print(json.dumps({'id': run_id, 'status': 'interrupted', 'log_path': row[5]}))
            return 0


def resume_run(run_id):
    row = get_run(run_id)
    if not row:
        print(json.dumps({'error': 'not found'}))
        return 2
    status = row[7]
    if status == 'running':
        print(json.dumps({'error': 'already running'}))
        return 2
    cmd = row[3]
    workdir = row[4]
    parent = row[0]
    new_id = start_run(cmd, workdir=workdir, parent_id=parent)
    print(json.dumps({'resumed_from': run_id, 'new_run': new_id}))
    return 0


def init_db():
    connect_db()
    print(json.dumps({'db': DB_PATH}))


def main():
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest='verb')
    sub.add_parser('init')
    sstart = sub.add_parser('start')
    sstart.add_argument('--command', dest='command', required=True)
    sstart.add_argument('--workdir', required=False)
    sstatus = sub.add_parser('status')
    sstatus.add_argument('id', type=int)
    sub.add_parser('list')
    scheck = sub.add_parser('check')
    scheck.add_argument('id', type=int)
    sresume = sub.add_parser('resume')
    sresume.add_argument('id', type=int)

    args = p.parse_args()
    if args.verb == 'init':
        init_db()
        return
    if args.verb == 'start':
        start_run(args.command, workdir=args.workdir)
        return

    if args.verb == 'list':
        list_runs()
        return
    if args.verb == 'status':
        row = get_run(args.id)
        if not row:
            print(json.dumps({'error': 'not found'}))
            sys.exit(2)
        print(json.dumps({'id': row[0],'run_uuid': row[1],'cmd': row[3],'workdir': row[4],'log_path': row[5],'pid': row[6],'status': row[7],'started_at': row[8],'finished_at': row[9],'exit_code': row[10],'commit': row[11]}))
        return
    if args.verb == 'check':
        sys.exit(check_run(args.id))
    if args.verb == 'resume':
        sys.exit(resume_run(args.id))

    # fallback: support simple shell-style start
    if len(sys.argv) >= 2 and sys.argv[1] == 'start' and '--command' not in sys.argv and '--cmd' not in sys.argv:
        cmdline = ' '.join(sys.argv[2:])
        start_run(cmdline)
        return

    p.print_help()


if __name__ == '__main__':
    # Fix the earlier placeholder bug by mapping args correctly
    # Quick wrapper to parse and delegate properly
    if 'start' in sys.argv:
        # ensure we call start with parsed args
        pass
    main()
