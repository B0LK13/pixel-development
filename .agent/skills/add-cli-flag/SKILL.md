# Skill: add-cli-flag

## Purpose

Safely add a new CLI flag to repository scripts while preserving contract guarantees.

## Steps

1. Update target script flag parser and validation order.
2. Update `docs/CLI_CONTRACT.md`.
3. Add/adjust harness assertions in `tests/run_tests_full.sh`.
4. Run targeted checks:
   - `bash tests/run_tests.sh --section=3,6,9,10,11,12`
5. Run full checks:
   - `bash tests/run_tests.sh`
   - `bash scripts/ci-local.sh`

## Prohibited shortcuts

- adding flag behavior without docs
- bypassing usage/exit code contract
- skipping full gate

