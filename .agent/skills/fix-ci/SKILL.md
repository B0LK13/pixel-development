# Skill: fix-ci

## Purpose

Diagnose and fix CI parity failures with deterministic local reproduction.

## Steps

1. Reproduce locally with `bash scripts/ci-local.sh`.
2. Run targeted harness sections using `bash tests/run_tests.sh --changed`.
3. Apply minimal fix.
4. Re-run targeted checks, then full checks:
   - `bash tests/run_tests.sh`
   - `bash scripts/ci-local.sh`

## Prohibited shortcuts

- editing workflow pins without checker parity
- suppressing failing checks instead of fixing root cause

