# Action Catalog

## Live registry status

The repository does **not** currently expose a command dispatcher with
first-class actions named `doctor`, `policy_check`, `bootstrap`,
`bootstrap_strict`, `validate`, `validate_explain`, `verify_changed`,
`verify_full`, `plan`, `approvals`, `report`, `inspect_run`, or `events`.

The nearest live registry is:

- `.agent/task-router.yaml` (routing categories)
- `.agent/skills/index.yaml` (skill IDs)
- `scripts/agent-context.sh` (repository snapshot command)

## Current route registry

| route | status | mutating? | implementation | tests | notes |
|---|---|---|---|---|---|
| `cli-changes` | live | no | `.agent/task-router.yaml` | `scripts/check-cli-contracts.py`, `tests/run_tests.sh --test cli.help-contract` | covers CLI contract work |
| `tests` | live | no | `.agent/task-router.yaml` | `tests/run_tests.sh --changed` | harness workstream |
| `github-workflows` | live | no | `.agent/task-router.yaml` | `scripts/check-github-action-pins.py`, section 30 | workflow pinning |
| `release-tooling` | live | yes/no depending on task | `.agent/task-router.yaml` | release sections 24-28 | release/signing work |
| `documentation` | live | no | `.agent/task-router.yaml` | docs parity checks | docs/report work |
| `security-review` | live | no | `.agent/task-router.yaml` | security checks | boundaries/hardening |
| `ci-failure` | live | no | `.agent/task-router.yaml` | harness + ci-local | failure recovery |
| `adapter-changes` | live | no | `.agent/task-router.yaml` | instruction drift checks | MCP / adapter work |
| `evidence-and-reports` | live | no | `.agent/task-router.yaml` | evidence link checks | report hygiene |

## Unsupported related actions

The future control-plane vocabulary is documented in the product roadmap and
should be treated as planning language only until a dispatcher exists.

## Discrepancy notes

- The prompt-style action names above are not present in the current repo.
- The live registry is route-based, not command-based.
- The current support count is therefore best read as "9 live routing
  categories, 0 implemented dispatcher actions".
