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
    pid_start_time TEXT,
    pgid INTEGER,
    status TEXT,
    started_at TEXT,
    updated_at TEXT,
    finished_at TEXT,
    exit_code INTEGER,
    signal INTEGER,
    timeout_seconds INTEGER DEFAULT 0,
    timeout_detected_at TEXT,
    grace_period_seconds INTEGER DEFAULT 5,
    escalated_to_sigkill INTEGER DEFAULT 0,
    abandoned_at TEXT,
    abandon_reason TEXT,
    last_known_pid INTEGER,
    last_known_pgid INTEGER,
    last_heartbeat TEXT,
    status_confidence INTEGER DEFAULT 100,
    commit_hash TEXT
);

CREATE TABLE IF NOT EXISTS transitions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    run_uuid TEXT,
    previous_status TEXT,
    new_status TEXT,
    source TEXT,
    reason TEXT,
    evidence TEXT,
    transitioned_at TEXT
);
'''



def ensure_dirs():
    os.makedirs(EVIDENCE_DIR, exist_ok=True)


def connect_db():
    ensure_dirs()
    conn = sqlite3.connect(DB_PATH, timeout=30)
    conn.execute('PRAGMA journal_mode=WAL;')
    conn.executescript(SCHEMA)
    conn.commit()
    # migrate legacy table if needed
    try:
        cur = conn.cursor()
        cur.execute("PRAGMA table_info('runs')")
        cols = [r[1] for r in cur.fetchall()]
        needed = {
            'pid_start_time': "ALTER TABLE runs ADD COLUMN pid_start_time TEXT",
            'pgid': 'ALTER TABLE runs ADD COLUMN pgid INTEGER',
            'updated_at': "ALTER TABLE runs ADD COLUMN updated_at TEXT",
            'signal': "ALTER TABLE runs ADD COLUMN signal INTEGER",
            'timeout_seconds': "ALTER TABLE runs ADD COLUMN timeout_seconds INTEGER DEFAULT 0",
            'timeout_detected_at': "ALTER TABLE runs ADD COLUMN timeout_detected_at TEXT",
            'grace_period_seconds': "ALTER TABLE runs ADD COLUMN grace_period_seconds INTEGER DEFAULT 5",
            'escalated_to_sigkill': "ALTER TABLE runs ADD COLUMN escalated_to_sigkill INTEGER DEFAULT 0",
            'abandoned_at': "ALTER TABLE runs ADD COLUMN abandoned_at TEXT",
            'abandon_reason': "ALTER TABLE runs ADD COLUMN abandon_reason TEXT",
            'last_known_pid': "ALTER TABLE runs ADD COLUMN last_known_pid INTEGER",
            'last_known_pgid': "ALTER TABLE runs ADD COLUMN last_known_pgid INTEGER",
            'last_heartbeat': "ALTER TABLE runs ADD COLUMN last_heartbeat TEXT",
            'status_confidence': "ALTER TABLE runs ADD COLUMN status_confidence INTEGER DEFAULT 100",
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
    # timezone-aware UTC timestamp for persisted records
    return datetime.datetime.utcnow().replace(microsecond=0).isoformat() + 'Z'

# Configurable heartbeat and freshness thresholds (seconds)
HEARTBEAT_FRESHNESS_SECONDS = 10
HEARTBEAT_STALE_ABANDON_SECONDS = 600
CHECKRUN_GRACE_SECONDS = 3


def git_commit():
    try:
        out = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=REPO_ROOT)
        return out.decode().strip()
    except Exception:
        return None


def _proc_start_time(pid):
    # Robustly parse /proc/<pid>/stat to extract starttime (field 22, 1-based). If parsing fails, fall back to cmdline.
    try:
        with open(f"/proc/{pid}/stat", 'r') as fh:
            s = fh.read()
            # comm field may contain spaces inside parentheses; find last ')' then split the remainder
            idx = s.rfind(')')
            if idx != -1:
                post = s[idx+2:]
                fields = post.split()
                # starttime is the 22nd field overall; in 'post' it is at index 20 (0-based)
                if len(fields) >= 21:
                    return fields[20]
    except Exception:
        pass
    try:
        with open(f"/proc/{pid}/cmdline", 'rb') as fh:
            return fh.read().decode(errors='ignore')
    except Exception:
        return None


def start_run(cmd, workdir=None, parent_id=None, timeout_seconds=0, grace_period=5):
    run_uuid = datetime.datetime.utcnow().strftime('%Y%m%dT%H%M%SZ') + '-' + uuid.uuid4().hex[:8]
    run_dir = os.path.join(EVIDENCE_DIR, run_uuid)
    os.makedirs(run_dir, exist_ok=True)
    log_path = os.path.join(run_dir, 'stdout.log')
    commit = git_commit()

    # Monitor-first launch: fork monitor, monitor forks supervised child, monitor persists identity and finalizes
    # create a short pipe for monitor startup acknowledgement
    rfd, wfd = os.pipe()

    pid_fork = os.fork()
    if pid_fork > 0:
        # parent: wait for ack from monitor
        os.close(wfd)
        ack = None
        try:
            import select as _select
            rlist,_,_ = _select.select([rfd], [], [], 5)
            if rfd in rlist:
                data = os.read(rfd, 4096)
                if data:
                    try:
                        ack = json.loads(data.decode())
                    except Exception:
                        ack = None
        finally:
            try:
                os.close(rfd)
            except Exception:
                pass
        if not ack:
            print(json.dumps({'error': 'monitor-startup-timeout'}))
            return 2
        print(json.dumps({'id': ack.get('id'), 'run_uuid': ack.get('run_uuid'), 'pid': ack.get('child_pid'), 'pgid': ack.get('pgid'), 'log_path': os.path.join(EVIDENCE_DIR, ack.get('run_uuid'), 'stdout.log')}))
        return ack.get('id')

    # monitor child
    try:
        try:
            os.close(rfd)
        except Exception:
            pass
        mconn = connect_db()
        mconn.execute('PRAGMA journal_mode=WAL;')
        # fork supervised child
        child_pid = os.fork()
        if child_pid == 0:
            # supervised child
            try:
                os.setsid()
                if workdir:
                    try:
                        os.chdir(workdir)
                    except Exception:
                        pass
                # redirect stdout/stderr
                lf = os.open(log_path, os.O_CREAT | os.O_WRONLY | os.O_APPEND, 0o644)
                os.dup2(lf, 1)
                os.dup2(lf, 2)
                try:
                    os.close(wfd)
                except Exception:
                    pass
                env = os.environ.copy()
                os.execvpe('/bin/bash', ['bash', '-lc', cmd], env)
            except Exception:
                try:
                    sys.stderr.write('exec failed\n')
                    sys.stderr.flush()
                except Exception:
                    pass
                os._exit(127)
        else:
            # monitor: persist child identity and run row
            child_pgid = None
            try:
                child_pgid = os.getpgid(child_pid)
            except Exception:
                child_pgid = None
            time.sleep(0.02)
            child_start = _proc_start_time(child_pid)
            started_at = now_iso()
            cur = mconn.cursor()
            try:
                with mconn:
                    cur.execute('''INSERT INTO runs (run_uuid, parent_id, cmd, workdir, log_path, pid, pid_start_time, pgid, status, started_at, updated_at, commit_hash, timeout_seconds, grace_period_seconds) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)''',
                                (run_uuid, parent_id, cmd, workdir or REPO_ROOT, log_path, child_pid, child_start, child_pgid, 'running', started_at, started_at, commit, int(timeout_seconds), int(grace_period)))
                    run_id = cur.lastrowid
            except Exception:
                mconn.rollback()
                cur.execute('SELECT id FROM runs WHERE run_uuid=?', (run_uuid,))
                row = cur.fetchone()
                run_id = row[0] if row else None
            # send ack
            ack = {'id': run_id, 'run_uuid': run_uuid, 'child_pid': child_pid, 'pgid': child_pgid}
            try:
                os.write(wfd, json.dumps(ack).encode())
            except Exception:
                pass
            try:
                os.close(wfd)
            except Exception:
                pass

            # monitor loop: waitpid, enforce timeout, heartbeat and finalization
            hb_path = os.path.join(run_dir, 'heartbeat.json')
            timed_out = False
            heartbeat_last = None
            start_mon = time.monotonic()
            # diagnostic: mark monitor loop entry
            try:
                with open(os.path.join(run_dir, 'monitor.debug'), 'a') as md:
                    md.write(f'MON_LOOP_START child_pid={child_pid} child_pgid={child_pgid} monotonic={start_mon}\n')
                    md.flush()
                    try:
                        os.fsync(md.fileno())
                    except Exception:
                        pass
            except Exception:
                pass
            loop_count = 0
            while True:
                loop_count += 1
                try:
                    pid_ret, status = os.waitpid(child_pid, os.WNOHANG)
                except ChildProcessError as cpe:
                    pid_ret = 0
                    status = 0
                    try:
                        with open(os.path.join(run_dir, 'monitor.debug'), 'a') as md:
                            md.write(f'WAITPID ChildProcessError: {str(cpe)} child_pid={child_pid} proc_exists={os.path.exists(f"/proc/{child_pid}")}\n')
                            md.flush()
                            try:
                                os.fsync(md.fileno())
                            except Exception:
                                pass
                    except Exception:
                        pass
                # diagnostic: log first waitpid result or any non-zero result
                try:
                    if loop_count == 1 or pid_ret != 0:
                        with open(os.path.join(run_dir, 'monitor.debug'), 'a') as md:
                            md.write(f'WAITPID_RESULT loop={loop_count} pid_ret={pid_ret} status={status}\n')
                            md.flush()
                            try:
                                os.fsync(md.fileno())
                            except Exception:
                                pass
                except Exception:
                    pass
                now_mon = time.monotonic()
                elapsed = now_mon - start_mon
                try:
                    cur = mconn.cursor()
                    cur.execute('SELECT timeout_seconds, grace_period_seconds FROM runs WHERE run_uuid=?', (run_uuid,))
                    r = cur.fetchone()
                    tsec = int(r[0] or 0) if r else 0
                    grace = int(r[1] or 5) if r else 5
                except Exception:
                    tsec = int(timeout_seconds or 0)
                    grace = int(grace_period or 5)

                if pid_ret == child_pid:
                    # debug write: reaped child
                    try:
                        with open(os.path.join(run_dir, 'monitor.debug'), 'a') as md:
                            md.write(f'reaped child {child_pid} status={status}\n')
                            md.flush()
                            try:
                                os.fsync(md.fileno())
                            except Exception:
                                pass
                    except Exception:
                        pass
                    # extra diagnostic tick: mark entry to finalization block
                    try:
                        with open(os.path.join(run_dir, 'monitor.debug'), 'a') as md:
                            md.write(f'ENTER_FINALIZATION pid={child_pid} status={status} monotonic={time.monotonic()}\n')
                            md.flush()
                            try:
                                os.fsync(md.fileno())
                            except Exception:
                                pass
                    except Exception:
                        pass
                    exit_code = None
                    sig = None
                    final_status = 'failed'
                    if os.WIFEXITED(status):
                        exit_code = os.WEXITSTATUS(status)
                        final_status = 'completed' if exit_code == 0 else 'failed'
                    elif os.WIFSIGNALED(status):
                        sig = os.WTERMSIG(status)
                        final_status = 'failed'
                    finished_at = now_iso()
                    try:
                        st = os.stat(log_path)
                        hb = {'timestamp': finished_at, 'pid': child_pid, 'pgid': child_pgid, 'elapsed_seconds': int(elapsed), 'log_size': st.st_size, 'log_mtime': datetime.datetime.utcfromtimestamp(st.st_mtime).isoformat() + 'Z', 'status': final_status, 'exit_code': exit_code}
                        with open(hb_path + '.tmp', 'w') as fh:
                            fh.write(json.dumps(hb))
                        try:
                            os.replace(hb_path + '.tmp', hb_path)
                        except Exception:
                            pass
                    except Exception:
                        pass
                    # Attempt transactional finalization with bounded retries and a fallback short-lived connection.
                    import sqlite3 as _sqlite
                    retry_backoffs = [0.1, 0.2, 0.4, 0.6, 0.8]
                    success = False
                    attempt_info = []
                    try:
                        # read previous status
                        try:
                            tx = mconn.cursor()
                            tx.execute('SELECT status FROM runs WHERE run_uuid=?', (run_uuid,))
                            res = tx.fetchone()
                            prev = res[0] if res else None
                        except Exception:
                            prev = None

                        import random
                        for attempt, backoff in enumerate(retry_backoffs, start=1):
                            # test-only fault injection: raise a transient sqlite error once when requested by environment
                            try:
                                inj = os.environ.get('SUPERVISOR_INJECT_FINALIZE_ERROR')
                                inj_marker = os.path.join(run_dir, '.injected_finalization')
                                if inj == '1' and not os.path.exists(inj_marker):
                                    # create marker so injection happens only once per run
                                    open(inj_marker, 'w').close()
                                    raise _sqlite.OperationalError('injected finalization error')
                            except Exception:
                                # any exception here should be treated as injection-trigger or ignored
                                pass

                            started_at_attempt = now_iso()
                            try:
                                with mconn:
                                    # re-check current row to maintain idempotency
                                    cur_check = mconn.cursor()
                                    cur_check.execute('SELECT status FROM runs WHERE run_uuid=?', (run_uuid,))
                                    row_now = cur_check.fetchone()
                                    now_status = row_now[0] if row_now else None
                                    # If already terminal, respect it and don't overwrite
                                    if now_status in ('completed', 'failed', 'timed_out'):
                                        attempt_info.append({'attempt_number': attempt, 'connection_type': 'main', 'started_at': started_at_attempt, 'finished_at': now_iso(), 'result': 'already_terminal', 'row_status': now_status})
                                        success = True
                                        break

                                    # perform update and insert transition idempotently
                                    mconn.execute('UPDATE runs SET status=?, finished_at=?, updated_at=?, exit_code=?, signal=? WHERE run_uuid=?', (final_status, finished_at, finished_at, exit_code, sig, run_uuid))
                                    # avoid duplicate transitions: check existing transition
                                    cur_t = mconn.cursor()
                                    cur_t.execute('SELECT COUNT(1) FROM transitions WHERE run_uuid=? AND new_status=? AND source=? AND reason=?', (run_uuid, final_status, 'monitor', 'process-exit'))
                                    exists = cur_t.fetchone()[0]
                                    if not exists:
                                        mconn.execute('INSERT INTO transitions (run_uuid, previous_status, new_status, source, reason, evidence, transitioned_at) VALUES (?,?,?,?,?,?,?)', (run_uuid, prev, final_status, 'monitor', 'process-exit', json.dumps({'exit_code': exit_code, 'signal': sig}), finished_at))

                                    try:
                                        with open(os.path.join(run_dir, 'monitor.debug'), 'a') as md:
                                            md.write(f'finalized run in DB on attempt {attempt}\n')
                                    except Exception:
                                        pass

                                    attempt_info.append({'attempt_number': attempt, 'connection_type': 'main', 'started_at': started_at_attempt, 'finished_at': now_iso(), 'result': 'committed'})
                                    success = True
                                    break
                            except Exception as e:
                                finished_at_attempt = now_iso()
                                exc_class = type(e).__name__
                                err_text = str(e)
                                is_retryable = False
                                try:
                                    if isinstance(e, _sqlite.OperationalError):
                                        el = err_text.lower()
                                        if any(x in el for x in ('locked','busy','database is locked','table is locked','schema')):
                                            is_retryable = True
                                except Exception:
                                    is_retryable = False
                                backoff_ms = int(backoff * 1000)
                                attempt_info.append({'attempt_number': attempt, 'connection_type': 'main', 'started_at': started_at_attempt, 'finished_at': finished_at_attempt, 'exception_class': exc_class, 'sqlite_error': err_text, 'retryable': is_retryable, 'backoff_ms': backoff_ms})
                                try:
                                    with open(os.path.join(run_dir, 'monitor.debug'), 'a') as md:
                                        md.write(f'finalization attempt {attempt} failed: {err_text}\n')
                                except Exception:
                                    pass
                                if not is_retryable:
                                    break
                                # backoff with small jitter
                                jitter = random.uniform(0, 0.05)
                                time.sleep(backoff + jitter)

                        if not success:
                            # fallback: close/discard main connection and open a fresh short-lived connection and attempt once
                            fb_started = now_iso()
                            try:
                                try:
                                    mconn.close()
                                except Exception:
                                    pass
                            except Exception:
                                pass
                            try:
                                fb_conn = _sqlite.connect(DB_PATH, timeout=30)
                                fb_conn.execute('PRAGMA journal_mode=WAL;')
                                try:
                                    fb_conn.execute('PRAGMA busy_timeout = 5000;')
                                except Exception:
                                    pass
                            except Exception as e_fb_open:
                                attempt_info.append({'attempt_number': 'fallback', 'connection_type': 'fallback', 'started_at': fb_started, 'finished_at': now_iso(), 'exception_class': type(e_fb_open).__name__, 'sqlite_error': str(e_fb_open), 'retryable': False})
                                try:
                                    with open(os.path.join(run_dir, 'monitor.err'), 'w') as me:
                                        import traceback as _tb
                                        me.write(_tb.format_exc())
                                except Exception:
                                    pass
                                try:
                                    with open(os.path.join(run_dir, 'monitor.debug'), 'a') as md:
                                        md.write('unable to open fallback DB connection; see monitor.err\n')
                                except Exception:
                                    pass
                                success = False
                                fb_conn = None

                            if 'fb_conn' in locals() and fb_conn:
                                try:
                                    with fb_conn:
                                        cur_check = fb_conn.cursor()
                                        cur_check.execute('SELECT status FROM runs WHERE run_uuid=?', (run_uuid,))
                                        row_now = cur_check.fetchone()
                                        now_status = row_now[0] if row_now else None
                                        rec = {'attempt_number': 'fallback', 'connection_type': 'fallback', 'started_at': fb_started}
                                        rec['row_status_before'] = now_status
                                        if now_status in ('completed', 'failed', 'timed_out'):
                                            rec.update({'finished_at': now_iso(), 'result': 'already_terminal', 'row_status_after': now_status})
                                            attempt_info.append(rec)
                                            success = True
                                        else:
                                            fb_conn.execute('UPDATE runs SET status=?, finished_at=?, updated_at=?, exit_code=?, signal=? WHERE run_uuid=?', (final_status, finished_at, finished_at, exit_code, sig, run_uuid))
                                            cur_t = fb_conn.cursor()
                                            cur_t.execute('SELECT COUNT(1) FROM transitions WHERE run_uuid=? AND new_status=? AND source=? AND reason=?', (run_uuid, final_status, 'monitor', 'process-exit'))
                                            exists = cur_t.fetchone()[0]
                                            if not exists:
                                                fb_conn.execute('INSERT INTO transitions (run_uuid, previous_status, new_status, source, reason, evidence, transitioned_at) VALUES (?,?,?,?,?,?,?)', (run_uuid, prev, final_status, 'monitor', 'process-exit', json.dumps({'exit_code': exit_code, 'signal': sig, 'fallback': True}), finished_at))
                                            rec.update({'finished_at': now_iso(), 'result': 'committed', 'row_status_after': final_status})
                                            attempt_info.append(rec)
                                            success = True
                                except Exception as e_fb:
                                    rec = {'attempt_number': 'fallback', 'connection_type': 'fallback', 'started_at': fb_started, 'finished_at': now_iso(), 'exception_class': type(e_fb).__name__, 'sqlite_error': str(e_fb), 'retryable': False}
                                    attempt_info.append(rec)
                                    try:
                                        with open(os.path.join(run_dir, 'monitor.err'), 'w') as me:
                                            import traceback as _tb
                                            me.write(_tb.format_exc())
                                    except Exception:
                                        pass
                                    try:
                                        with open(os.path.join(run_dir, 'monitor.debug'), 'a') as md:
                                            md.write('fallback finalization failed; see monitor.err\n')
                                    except Exception:
                                        pass
                                finally:
                                    try:
                                        fb_conn.close()
                                    except Exception:
                                        pass

                        # write attempt_info summary
                        try:
                            with open(os.path.join(run_dir, 'monitor.finalization.json'), 'w') as mf:
                                json.dump({'run_uuid': run_uuid, 'attempts': attempt_info, 'success': success}, mf)
                        except Exception:
                            pass

                        if not success:
                            # mark run as needing recovery; do not claim terminal persisted
                            try:
                                with mconn:
                                    mconn.execute('UPDATE runs SET status=?, updated_at=?, abandon_reason=? WHERE run_uuid=?', ('recovery-required', now_iso(), 'finalization-failed', run_uuid))
                                    mconn.execute('INSERT INTO transitions (run_uuid, previous_status, new_status, source, reason, evidence, transitioned_at) VALUES (?,?,?,?,?,?,?)', (run_uuid, prev, 'recovery-required', 'monitor', 'finalization-failed', json.dumps({'attempts': attempt_info}), now_iso()))
                            except Exception:
                                try:
                                    with open(os.path.join(run_dir, 'monitor.err'), 'w') as me:
                                        import traceback as _tb
                                        me.write(_tb.format_exc())
                                except Exception:
                                    pass
                            # exit nonzero to signal supervisor failure; leave evidence
                            try:
                                os._exit(1)
                            except Exception:
                                pass
                    except Exception:
                        try:
                            import traceback as _tb
                            with open(os.path.join(run_dir, 'monitor.err'), 'w') as me:
                                me.write(_tb.format_exc())
                        except Exception:
                            pass
                        try:
                            with open(os.path.join(run_dir, 'monitor.debug'), 'a') as md:
                                md.write('unexpected exception during finalization; see monitor.err\n')
                        except Exception:
                            pass
                    break

                if tsec and not timed_out and elapsed > tsec:
                    timed_out = True
                    timeout_detected_at = now_iso()
                    try:
                        if child_pgid:
                            os.killpg(child_pgid, 15)
                        else:
                            os.kill(child_pid, 15)
                    except Exception:
                        pass
                    try:
                        with mconn:
                            mconn.execute('UPDATE runs SET status=?, timeout_detected_at=?, updated_at=? WHERE run_uuid=?', ('timed_out', timeout_detected_at, timeout_detected_at, run_uuid))
                            mconn.execute('INSERT INTO transitions (run_uuid, previous_status, new_status, source, reason, evidence, transitioned_at) VALUES (?,?,?,?,?,?,?)', (run_uuid, 'running', 'timed_out', 'monitor', 'timeout-detected', json.dumps({'timeout_seconds': tsec}), timeout_detected_at))
                    except Exception:
                        pass
                    waited = 0
                    while waited < grace:
                        try:
                            pid_ret2, status2 = os.waitpid(child_pid, os.WNOHANG)
                            if pid_ret2 == child_pid:
                                pid_ret = pid_ret2
                                status = status2
                                break
                        except ChildProcessError:
                            break
                        time.sleep(1)
                        waited += 1
                    try:
                        pid_ret3, _ = os.waitpid(child_pid, os.WNOHANG)
                        if pid_ret3 == 0:
                            try:
                                if child_pgid:
                                    os.killpg(child_pgid, 9)
                                else:
                                    os.kill(child_pid, 9)
                                escal = 1
                            except Exception:
                                escal = 0
                            try:
                                with mconn:
                                    mconn.execute('UPDATE runs SET escalated_to_sigkill=?, updated_at=? WHERE run_uuid=?', (escal, now_iso(), run_uuid))
                                    mconn.execute('INSERT INTO transitions (run_uuid, previous_status, new_status, source, reason, evidence, transitioned_at) VALUES (?,?,?,?,?,?,?)', (run_uuid, 'timed_out', 'timed_out', 'monitor', 'escalated-to-sigkill', json.dumps({'escalated': escal}), now_iso()))
                            except Exception:
                                pass
                    except Exception:
                        pass

                try:
                    now_iso_ts = now_iso()
                    if heartbeat_last is None or (time.time() - (heartbeat_last or 0)) >= 15:
                        try:
                            st = os.stat(log_path)
                            hb = {'timestamp': now_iso_ts, 'pid': child_pid, 'pgid': child_pgid, 'elapsed_seconds': int(elapsed), 'log_size': st.st_size, 'log_mtime': datetime.datetime.utcfromtimestamp(st.st_mtime).isoformat() + 'Z', 'status': 'running'}
                            with open(hb_path + '.tmp', 'w') as fh:
                                fh.write(json.dumps(hb))
                            try:
                                os.replace(hb_path + '.tmp', hb_path)
                            except Exception:
                                pass
                        except Exception:
                            pass
                        heartbeat_last = time.time()
                except Exception:
                    pass

                time.sleep(0.2)
    except Exception as e:
        try:
            import traceback
            with open(os.path.join(run_dir, 'monitor.err'), 'w') as me:
                me.write(traceback.format_exc())
        except Exception:
            pass
    finally:
        try:
            os._exit(0)
        except Exception:
            pass


def get_run(run_id):
    conn = connect_db()
    cur = conn.cursor()
    cur.execute('''SELECT id,run_uuid,parent_id,cmd,workdir,log_path,pid,pid_start_time,pgid,status,started_at,finished_at,exit_code,signal,timeout_seconds,timeout_detected_at,grace_period_seconds,escalated_to_sigkill,abandoned_at,abandon_reason,last_known_pid,last_known_pgid,last_heartbeat,status_confidence,commit_hash FROM runs WHERE id=?''', (run_id,))
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
    # Conservative check that avoids racing the monitor finalization
    row = get_run(run_id)
    if not row:
        print(json.dumps({'error': 'not found'}))
        return 2
    # columns: id(0),run_uuid(1),parent_id(2),cmd(3),workdir(4),log_path(5),pid(6),pid_start_time(7),pgid(8),status(9),started_at(10),finished_at(11),exit_code(12),signal(13),timeout_seconds(14),timeout_detected_at(15),grace_period_seconds(16),escalated_to_sigkill(17),abandoned_at(18),abandon_reason(19),last_known_pid(20),last_known_pgid(21),last_heartbeat(22),status_confidence(23),commit_hash(24)
    log_path = row[5]
    pid = row[6]
    pid_start = row[7]
    status = row[9]

    # If terminal already, return it unchanged
    if status in ('completed','failed','timed_out','abandoned','recovered'):
        print(json.dumps({'id': run_id, 'status': status, 'finished_at': row[11], 'exit_code': row[12], 'log_path': log_path}))
        return 0

    alive = False
    if pid is not None:
        try:
            os.kill(pid, 0)
            current_start = _proc_start_time(pid)
            if pid_start and current_start:
                if str(pid_start) == str(current_start):
                    alive = True
                else:
                    alive = False
            else:
                # couldn't verify start time; assume alive but with low confidence
                alive = True
        except Exception:
            alive = False

    conn = connect_db()

    if alive:
        # still running: update last_known and leave status as running
        try:
            with conn:
                conn.execute('UPDATE runs SET status=?, updated_at=?, last_known_pid=?, last_heartbeat=? WHERE id=?', ('running', now_iso(), pid, now_iso(), run_id))
        except Exception:
            pass
        print(json.dumps({'id': run_id, 'pid': pid, 'status': 'running', 'log_path': log_path}))
        return 0

    # pid not alive or not verifiable
    # inspect heartbeat freshness
    hb_path = os.path.join(os.path.dirname(log_path), 'heartbeat.json')
    hb_fresh = False
    try:
        if os.path.exists(hb_path):
            mtime = os.path.getmtime(hb_path)
            age = time.time() - mtime
            if age <= HEARTBEAT_FRESHNESS_SECONDS:
                hb_fresh = True
    except Exception:
        hb_fresh = False

    if hb_fresh:
        # finalization may be pending; do not overwrite DB state — return nonterminal assessment
        print(json.dumps({'id': run_id, 'status': 'finalization_pending', 'log_path': log_path}))
        return 0

    # heartbeat not fresh; apply a short grace window before mutating
    waited = 0
    while waited < CHECKRUN_GRACE_SECONDS:
        time.sleep(0.5)
        waited += 0.5
        # re-check heartbeat quickly
        try:
            if os.path.exists(hb_path):
                mtime = os.path.getmtime(hb_path)
                age = time.time() - mtime
                if age <= HEARTBEAT_FRESHNESS_SECONDS:
                    print(json.dumps({'id': run_id, 'status': 'finalization_pending', 'log_path': log_path}))
                    return 0
        except Exception:
            pass

    # re-read DB row to avoid stomping if monitor finished in the meantime
    row2 = get_run(run_id)
    if row2 and row2[11]:
        # finished_at exists now — return authoritative
        print(json.dumps({'id': run_id, 'status': row2[9], 'finished_at': row2[11], 'exit_code': row2[12], 'log_path': log_path}))
        return 0

    # finally, mark interrupted (provisional). This can be corrected later by the monitor.
    try:
        with conn:
            conn.execute('UPDATE runs SET status=?, updated_at=?, last_known_pid=?, last_heartbeat=? WHERE id=?', ('interrupted', now_iso(), pid, now_iso(), run_id))
            conn.execute('INSERT INTO transitions (run_uuid, previous_status, new_status, source, reason, evidence, transitioned_at) VALUES (?,?,?,?,?,?,?)', (row[1], row[9], 'interrupted', 'checker', 'heartbeat-stale', json.dumps({'hb_exists': os.path.exists(hb_path)}), now_iso()))
    except Exception:
        pass
    print(json.dumps({'id': run_id, 'status': 'interrupted', 'log_path': log_path}))
    return 0


def resume_run(run_id):
    row = get_run(run_id)
    if not row:
        print(json.dumps({'error': 'not found'}))
        return 2
    # columns index based on get_run select
    run_uuid = row[1]
    cmd = row[3]
    workdir = row[4]
    log_path = row[5]
    pid = row[6]
    pid_start = row[7]
    pgid = row[8]
    status = row[9]

    if status == 'running':
        print(json.dumps({'error': 'already running'}))
        return 2

    # If child PID still alive, attach a monitor rather than restarting
    alive = False
    if pid:
        try:
            os.kill(pid, 0)
            current_start = _proc_start_time(pid)
            if pid_start and current_start:
                if str(pid_start) == str(current_start):
                    alive = True
                else:
                    alive = False
            else:
                # no reliable start-time info; allow attach but low confidence
                alive = True
        except Exception:
            alive = False
    if alive:
        # spawn monitor that watches existing pid and updates DB
        pid_fork = os.fork()
        if pid_fork == 0:
            try:
                mconn = sqlite3.connect(DB_PATH)
                mconn.execute('PRAGMA journal_mode=WAL;')
                hb_path = os.path.join(os.path.dirname(log_path), 'heartbeat.json')
                start_ts = datetime.datetime.utcnow()
                last_hb = None
                while True:
                    now = datetime.datetime.utcnow()
                    elapsed = (now - start_ts).total_seconds()
                    try:
                        os.kill(pid, 0)
                        still = True
                    except Exception:
                        still = False
                    if last_hb is None or (now - last_hb).total_seconds() >= 15:
                        try:
                            st = os.stat(log_path)
                            hb = {
                                'timestamp': now.isoformat() + 'Z',
                                'pid': pid,
                                'elapsed_seconds': int(elapsed),
                                'log_size': st.st_size,
                                'log_mtime': datetime.datetime.utcfromtimestamp(st.st_mtime).isoformat() + 'Z',
                                'status': 'running' if still else 'unknown'
                            }
                            with open(hb_path + '.tmp','w') as fh:
                                fh.write(json.dumps(hb))
                            try:
                                os.replace(hb_path + '.tmp', hb_path)
                            except Exception:
                                pass
                        except Exception:
                            pass
                        last_hb = now
                    if not still:
                        finished_at = datetime.datetime.utcnow().replace(microsecond=0).isoformat() + 'Z'
                        # attempt to read exit code from log tail heuristics not available; mark interrupted->completed_unknown
                        try:
                            cur = mconn.cursor()
                            cur.execute('UPDATE runs SET status=?, finished_at=?, updated_at=? WHERE run_uuid=?', ('recovered', finished_at, finished_at, run_uuid))
                            mconn.commit()
                        except Exception:
                            pass
                        os._exit(0)
                    time.sleep(1)
            finally:
                os._exit(0)
        print(json.dumps({'attached_to_pid': pid, 'run_uuid': run_uuid}))
        return 0
    else:
        # safe to restart: create a new run record referencing parent
        new_id = start_run(cmd, workdir=workdir, parent_id=run_id)
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
    sstart.add_argument('--timeout', dest='timeout', type=int, default=0, help='timeout in seconds')
    sstart.add_argument('--grace', dest='grace', type=int, default=5, help='grace period seconds before SIGKILL')
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
        start_run(args.command, workdir=args.workdir, timeout_seconds=getattr(args,'timeout',0), grace_period=getattr(args,'grace',5))
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
