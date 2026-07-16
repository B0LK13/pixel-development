# Agent OS Phase 1 — Process Supervision

Summary

- Implemented bounded transactional retry and fallback for monitor finalization in scripts/supervisor.py.
- Added idempotent finalization using run_uuid as authoritative key.
- Added structured attempt evidence: monitor.finalization.json per run and monitor.debug/monitor.err artifacts.
- Deterministic fault-injection supported via SUPERVISOR_INJECT_FINALIZE_ERROR for testing.
- Added smoke tests at tests/supervisor-finalization.sh and helper harness scripts.

Observed failing point

- During timeout iterations, monitor processes were often terminated by SIGTERM from an external process. Evidence in per-run monitor.err and monitor.debug shows si_pid of the sender in strace snapshots and monitor.finalization.json shows 'recovery-required' when forced by external SIGTERM.

SQLite error/trace

- Fault injection used to simulate "database is locked" and exercised the retry loop: first attempt recorded OperationalError 'database is locked' (retryable), second attempt committed successfully.

Retry classification and schedule

- Bounded attempts: 5 attempts with backoffs [100,200,400,600,800] ms and jitter (0-50ms).
- Only 'locked', 'busy', 'database is locked', 'table is locked', 'schema' OperationalError text are treated as transient and retryable.

Fallback connection behavior

- After main connection retries exhaust, a short-lived fresh SQLite connection is opened with PRAGMA journal_mode=WAL and PRAGMA busy_timeout set; it re-reads the run row and applies idempotent terminal update if appropriate, and writes fallback diagnostics.

Single-case results

- Completion case: COMMITTED success, monitor.finalization.json present.
- Failure case: FAILED with exit_code=7, monitor.finalization.json present.
- Injected transient lock case: main attempt failed (database is locked), second main attempt committed (retry path exercised). Fallback path also tested via non-retryable injection and recorded as committed.

10× and race results

- Deterministic 10× timeout confirmation was attempted. Several timeout runs were terminated by an external SIGTERM, resulting in 'recovery-required' finalization artifacts. Recommended next step: investigate SIGTERM sender to ensure clean TIMED_OUT confirmations.

Validation

- Changed-scope harness: passed (bash tests/run_tests.sh --changed).
- CI-local parity: passed (bash scripts/ci-local.sh) on source.
- Fresh clean-clone: changed-scope harness passed from a clean clone.

Commits

- fix: make monitor finalization resilient to sqlite contention (signed)
- docs: document terminal persistence recovery guarantees (signed)
- test(supervisor): add finalization retry/fallback smoke tests (signed)

Exact final commit

- HEAD at commit: $(git rev-parse --verify HEAD)

Clean-clone parity

- Cloned repository at /tmp/clean-clone and ran changed-scope harness — PASS.

Residual risks

- External SIGTERM source kills monitors in timeout iterations leading to 'recovery-required' outcomes; further investigation needed to ensure 10/10 TIMED_OUT confirmations.

Next recommended action

- Trace and identify the SIGTERM sender (strace/process-tree correlation) in the environment and eliminate unintended external kills so the monitor can exercise the normal TIMED_OUT path.

Artifacts

- Per-run evidence: reports/run-supervision/<run_uuid>/monitor.finalization.json, monitor.debug, monitor.err
- Supervisor DB: reports/run-supervision/supervisor.db (+ WAL/SHM)
- Test scripts: tests/supervisor-finalization.sh

Prepared by: automated agent (Copilot-assisted).