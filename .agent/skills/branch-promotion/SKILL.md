# Skill: branch-promotion

## Trigger

Use when preparing integration-ready handoff for operator-managed promotion.

## Mandatory context

- `docs/BRANCH_PROMOTION_POLICY.md`
- `docs/AGENT_HANDOFF_PROTOCOL.md`

## Commands

1. `bash tests/run_tests.sh`
2. `bash scripts/ci-local.sh`
3. `bash scripts/agent-context.sh --format markdown`

## Forbidden shortcuts

- direct merge/tag/release from autonomous sessions
- skipping final full gates

