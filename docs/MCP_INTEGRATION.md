# MCP Integration (Optional Adapter)

MCP is optional in this repository. The source of truth remains repository-native contracts, scripts, and checks.

## Recommended adapters

- GitHub metadata: PRs/issues/reviews/actions log retrieval.
- Workflow observability: remote run status/log collection.
- Branch policy visibility: read-only branch/ruleset inspection.

## Required boundary

MCP data may inform execution, but completion must still satisfy:

- `bash tests/run_tests.sh`
- `bash scripts/ci-local.sh`
- contract/policy checks in `scripts/check-*.py`

