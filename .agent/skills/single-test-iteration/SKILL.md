# Skill: single-test-iteration

## Purpose

Run deterministic targeted harness checks during development.

## Commands

1. `bash tests/run_tests.sh --list`
2. `bash tests/run_tests.sh --test=<test-id>`
3. `bash tests/run_tests.sh --section=<section-id>`
4. `bash tests/run_tests.sh --changed`

## Completion

After targeted iterations, run:

- `bash tests/run_tests.sh`
- `bash scripts/ci-local.sh`

