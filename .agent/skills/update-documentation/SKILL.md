# Skill: update-documentation

## Trigger

Use when editing docs/README/contracts/reports.

## Mandatory context

- `docs/AGENTS.md`
- `docs/AGENT_HANDOFF_PROTOCOL.md`

## Commands

1. `python3 scripts/check-doc-command-parity.py`
2. `python3 scripts/check-evidence-links.py`
3. `python3 scripts/check-stale-claims.py`
4. `bash tests/run_tests.sh --tag docs`
5. `bash tests/run_tests.sh`

## Forbidden shortcuts

- stale command examples
- broken evidence links
- full gate omission

