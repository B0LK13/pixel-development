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
import time

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
EVIDENCE_DIR = os.path.join(REPO_ROOT, 'reports', 'run-supervision')
DB_PATH = os.path.join(EVIDENCE_DIR, 'supervisor.db')

SCHEMA = '''
CREATE TABLE IF NOT EXISTS runs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    run_uuid TEXT UNIQUE,
    schema_version INTEGER DEFAULT 1,
    parent_id INTEGER,
    cmd TEXT,
    workdir TEXT,
    log_path TEXT,
    pid INTEGER,
    pgid INTEGER,
    status TEXT,
    started_at TEXT,
    updated_at TEXT,
    finished_at TEXT,
    exit_code INTEGER,
    signal INTEGER,
    timeout_seconds INTEGER DEFAULT 0,
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
    # migrate legacy table if needed
    try:
        cur = conn.cursor()
        cur.execute("PRAGMA table_info('runs')")
        cols = [r[1] for r in cur.fetchall()]
        needed = {
            'pgid': 'ALTER TABLE runs ADD COLUMN pgid INTEGER',
            'updated_at': "ALTER TABLE runs ADD COLUMN updated_at TEXT",
            'signal': "ALTER TABLE runs ADD COLUMN signal INTEGER",
            'timeout_seconds': "ALTER TABLE runs ADD COLUMN timeout_seconds INTEGER DEFAULT 0",
            'commit_hash': "ALTER TABLE runs ADD COLUMN commit_hash TEXT",
            'schema_version': "ALTER TABLE runs ADD COLUMN schema_version INTEGER DEFAULT 1",
        }
        for k,stmt in needed.items():
            if k not in cols:
                try:
                    cur.execute(stmt)
                    conn.commit()
                except Exception:
                    # best-effort migration
                    pass
    except Exception:
        pass
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
        try:
            pgid = os.getpgid(pid)
        except Exception:
            pgid = None

    cur = conn.cursor()
    cur.execute('''INSERT INTO runs (run_uuid, parent_id, cmd, workdir, log_path, pid, pgid, status, started_at, updated_at, commit_hash) VALUES (?,?,?,?,?,?,?,?,?,?,?)''',
                (run_uuid, parent_id, cmd, workdir or REPO_ROOT, log_path, pid, pgid, 'running', started_at, started_at, commit))
    conn.commit()
    run_id = cur.lastrowid

    # Spawn a detached monitor process to wait for the child and update DB and heartbeat
    pid_fork = os.fork()
    if pid_fork == 0:
        # child monitor
        try:
            # New DB connection in monitor
            mconn = sqlite3.connect(DB_PATH)
            mconn.execute('PRAGMA journal_mode=WAL;')
            run_dir_local = os.path.dirname(log_path)
            hb_path = os.path.join(run_dir_local, 'heartbeat.json')
            start_ts = datetime.datetime.utcnow()
            last_hb = None
            # Poll loop: check every second, write heartbeat every 15s
            while True:
                ret = proc.poll()
                now = datetime.datetime.utcnow()
                elapsed = (now - start_ts).total_seconds()
                # heartbeat write every 15s
                if last_hb is None or (now - last_hb).total_seconds() >= 15:
                    try:
                        st = os.stat(log_path)
                        hb = {
                            'timestamp': now.isoformat() + 'Z',
                            'pid': pid,
                            'pgid': pgid,
                            'elapsed_seconds': int(elapsed),
                            'log_size': st.st_size,
                            'log_mtime': datetime.datetime.utcfromtimestamp(st.st_mtime).isoformat() + 'Z',
                            'status': 'running' if ret is None else 'exited'
                        }
                        with open(hb_path + '.tmp', 'w') as fh:
                            fh.write(json.dumps(hb))
                        os.replace(hb_path + '.tmp', hb_path)
                    except Exception:
                        pass
                    last_hb = now
                if ret is not None:
                    # process ended
                    exit_code = ret
                    finished_at = datetime.datetime.utcnow().replace(microsecond=0).isoformat() + 'Z'
                    status = 'completed' if exit_code == 0 else 'failed'
                    try:
                        curm = mconn.cursor()
                        curm.execute('UPDATE runs SET status=?, finished_at=?, updated_at=?, exit_code=? WHERE run_uuid=?', (status, finished_at, finished_at, exit_code, run_uuid))
                        mconn.commit()
                    except Exception:
                        pass
                    # final heartbeat
                    try:
                        st = os.stat(log_path)
                        hb = {
                            'timestamp': finished_at,
                            'pid': pid,
                            'pgid': pgid,
                            'elapsed_seconds': int(elapsed),
                            'log_size': st.st_size,
                            'log_mtime': datetime.datetime.utcfromtimestamp(st.st_mtime).isoformat() + 'Z',
                            'status': status,
                            'exit_code': exit_code
                        }
                        with open(hb_path + '.tmp', 'w') as fh:
                            fh.write(json.dumps(hb))
                        os.replace(hb_path + '.tmp', hb_path)
                    except Exception:
                        pass
                    os._exit(0)
                # sleep small
                try:
                    time.sleep(1)
                except Exception:
                    pass
        finally:
            os._exit(0)

    # parent returns
    print(json.dumps({'id': run_id, 'run_uuid': run_uuid, 'pid': pid, 'pgid': pgid, 'log_path': log_path}))
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
    # columns: id(0),run_uuid(1),parent_id(2),cmd(3),workdir(4),log_path(5),pid(6),status(7),started_at(8),finished_at(9),exit_code(10),commit_hash(11)
    log_path = row[5]
    pid = row[6]
    status = row[7]
    try:
        if pid is not None:
            os.kill(pid, 0)
            alive = True
        else:
            alive = False
    except Exception:
        alive = False
    conn = connect_db()
    cur = conn.cursor()
    if alive:
        # still running
        cur.execute('UPDATE runs SET status=?, updated_at=? WHERE id=?', ('running', now_iso(), run_id))
        conn.commit()
        print(json.dumps({'id': run_id, 'pid': pid, 'status': 'running', 'log_path': log_path}))
        return 0
    else:
        # process not alive -- try to collect exit_code by checking if finished_at recorded
        if row[9]:
            print(json.dumps({'id': run_id, 'status': row[7], 'finished_at': row[9], 'exit_code': row[10], 'log_path': log_path}))
            return 0
        else:
            # mark interrupted
            cur.execute('UPDATE runs SET status=?, finished_at=?, updated_at=? WHERE id=?', ('interrupted', now_iso(), now_iso(), run_id))
            conn.commit()
            print(json.dumps({'id': run_id, 'status': 'interrupted', 'log_path': log_path}))
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
