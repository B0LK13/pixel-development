# Skill: update-doc-contracts

## Purpose

Keep contract docs aligned with live script behavior and checks.

## Steps

1. Update docs for behavioral changes.
2. Run parity checks:
   - `python3 scripts/check-doc-command-parity.py`
   - `python3 scripts/check-cli-contracts.py`
   - `python3 scripts/check-evidence-links.py`
3. Run full gate.

## Prohibited shortcuts

- leaving stale command examples
- stale evidence/report links

