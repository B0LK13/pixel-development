# Skill: security-review

## Trigger

Use for trust-boundary, policy, signing, or workflow security changes.

## Mandatory context

- `docs/AGENT_SECURITY_BOUNDARIES.md`
- `docs/GITHUB_ACTIONS_PINNING_POLICY.md`

## Commands

1. `python3 scripts/check-github-action-pins.py`
2. `python3 scripts/check-agent-secrets.py`
3. `python3 scripts/check-context-freshness.py`
4. `bash tests/run_tests.sh --tag security`
5. `bash tests/run_tests.sh`
6. `bash scripts/ci-local.sh`

## Rollback

Revert to last green contract/policy commit and re-run full gates.

