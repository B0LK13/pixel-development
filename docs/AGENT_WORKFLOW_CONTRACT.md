# Agent Workflow Contract

## Task initialization

1. Load context: `bash scripts/agent-context.sh --format markdown`.
2. Capture baseline (branch, commit, dirty/clean state, intended route).
3. Resolve route in `.agent/task-router.yaml`.
4. Select targeted checks from route metadata.

## Branch/worktree model

- Use one isolated branch per coherent task.
- Use isolated worktrees for parallel workstreams.
- Avoid overlapping ownership unless explicitly sequenced.
- Keep tree clean before final gate.

## Change classification

- classify as: cli / test / workflow / docs / release / security / adapter / evidence.
- update corresponding contracts/docs/checks in the same change.

## Validation sequence

1. targeted checks (route-scoped),
2. iterate until stable,
3. full harness: `bash tests/run_tests.sh`,
4. CI parity: `bash scripts/ci-local.sh`.

Targeted checks never replace the mandatory full gate.

## Commit and evidence rules

- Preserve signed-commit requirement for operator commit workflows.
- Keep evidence/report paths valid and reproducible.
- For contract/policy changes, include report updates under `reports/` as needed.

## PR/merge/post-merge policy

- PR creation/merge are operator-owned.
- Post-merge verification follows repository runbooks and CI policy.
- Rollback follows release/security recovery docs; never bypass policy checks.

