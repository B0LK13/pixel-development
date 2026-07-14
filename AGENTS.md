# Repository agent operating contract

Tool-agnostic operating contract for Copilot, Codex, Claude, Kimi, and future agents.

## Repository purpose

`pixel-development` is a script-first, trust-sensitive platform for bootstrap/install, autonomous backlog execution, and release/signing verification on Pixel/Termux + devbox environments.

## Authoritative commands

- Context: `bash scripts/agent-context.sh --format markdown`
- Targeted harness: `bash tests/run_tests.sh --list`
- Full gate: `bash tests/run_tests.sh`
- CI parity: `bash scripts/ci-local.sh`

## Architecture overview

Bootstrap (`pixel-bootstrap.sh`) -> setup layers (`pixel-dev-setup.sh`, `pixel-apps-setup.sh`) -> autonomous runner (`pixel-autodev.sh`) -> repository verification gates (`tests/run_tests.sh`, `scripts/ci-local.sh`) -> evidence/report artifacts.

## Branch/commit/worktree rules

- One coherent change scope per branch.
- Keep working tree clean before final validation.
- Use isolated worktrees/branches for parallel workstreams.
- Commits must be signed when committing is requested by the operator workflow.

## Required pre-completion state

- Clean tree for final gate run.
- Targeted checks for touched routes.
- Full harness green.
- CI-local green.
- Evidence/report updates included for contract/policy or release-surface changes.

## Operator-only actions

- Push/merge/tag/release/publish/deploy.
- Production signing and key lifecycle operations.
- Secret/credential and branch-protection changes.
- Force operations and destructive host actions.

## Prohibited shortcuts

- Skipping full gate after targeted checks.
- Relaxing SHA pinning/signing/integrity controls to make tests pass.
- Silent behavior changes without contract/doc updates.
- Treating adapter tooling as source-of-truth over repository contracts.

## Completion report format (mandatory)

Use `docs/AGENT_HANDOFF_PROTOCOL.md` and include:

1. starting state,
2. changes and rationale,
3. validation commands/results,
4. security invariants,
5. deferred/operator-owned actions,
6. readiness decision + exact operator commands.

## Canonical references

- Architecture: `docs/AGENT_ARCHITECTURE.md`
- Workflow contract: `docs/AGENT_WORKFLOW_CONTRACT.md`
- Security boundaries: `docs/AGENT_SECURITY_BOUNDARIES.md`
- Test strategy: `docs/AGENT_TEST_STRATEGY.md`
- Handoff protocol: `docs/AGENT_HANDOFF_PROTOCOL.md`
