# Agent Security Boundaries

## Autonomous actions (allowed)

- Read/write repository files within task scope.
- Run repository-owned validation commands.
- Produce deterministic reports/evidence artifacts.

## Approval-required actions (operator gates)

- production signing operations
- tag creation
- release publication
- deployment/publishing
- secrets/credential changes
- branch-protection/ruleset changes
- force operations
- destructive host changes

## Forbidden shortcuts

- downgrading SHA pinning, signing, or integrity checks
- bypassing validation-before-side-effects behavior
- introducing non-hermetic dependencies into canonical harness paths
- claiming full-gate completion from targeted runs only

## Enforcement anchors

- `scripts/check-github-action-pins.py`
- `scripts/update-bootstrap-checksums.sh --check`
- `scripts/check-agent-instructions.py`
- `scripts/check-cli-contracts.py`
- `tests/run_tests.sh`
- `scripts/ci-local.sh`

## Failure policy

Fail closed with explicit diagnostics. Security-control regressions are blocking.

