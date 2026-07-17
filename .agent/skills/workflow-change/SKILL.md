# Skill: workflow-change

## Purpose

Safely modify `.github/workflows/*` with supply-chain constraints.

## Commands

1. `python3 scripts/check-github-action-pins.py`
2. `bash tests/run_tests.sh --test=workflow.action-pins`
3. `bash tests/run_tests.sh`
4. `bash scripts/ci-local.sh`

## Constraints

- Full SHA pins with version comments.
- Least-privilege permissions.
- Verification-only behavior preserved.
