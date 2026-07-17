# Skill: release-verification

## Purpose

Run release integrity/signature/repro checks safely.

## Steps

1. Build fixture candidate (`scripts/build-release-candidate.sh`).
2. Verify bundle (`scripts/verify-release-bundle.sh`) unsigned/signed as applicable.
3. Run harness release sections:
   - `bash tests/run_tests.sh --section=24,25,26,27`
4. Run full gate and ci-local.

## Prohibited shortcuts

- skipping reproducibility checks
- bypassing signature/keyring requirements

