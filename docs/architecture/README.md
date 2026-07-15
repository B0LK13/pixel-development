# Agent OS Harness Architecture Baseline

Phase 0 documents the current system as it exists now: the repo-native shell
entrypoints, the harness, the policy contracts, the evidence/report plane, and
the operator boundaries. This directory is intentionally descriptive, not
prescriptive; it records the live baseline before any modular refactor.

## Scope

- Current repository state and authoritative commands
- Current control/data flows
- Trust boundaries and governance
- Validation registry and runtime compatibility
- Evidence and promotion model
- Risk, debt, and Phase 1 entry criteria

## Reading order

1. `system-context.md`
2. `current-state.md`
3. `component-map.md`
4. `control-flow.md`
5. `data-flow.md`
6. `trust-boundaries.md`
7. `action-catalog.md`
8. `validation-catalog.md`
9. `runtime-compatibility.md`
10. `evidence-model.md`
11. `governance-model.md`
12. `risk-register.md`
13. `technical-debt-register.md`
14. `roadmap-mapping.md`
15. `phase-1-entry-criteria.md`

## Current baseline

- Baseline commit: `e487acf78788fc204f6f6950f4d13144a6de67e9`
- Phase 0 branch: `auto/phase-0-program-baseline`
- Promotion status: the follow-up branch `auto/follow-up-bwrap-selector-drift`
  is not present on `main`

## Canonical sources

- `AGENTS.md`
- `docs/AGENT_*.md`
- `.agent/task-router.yaml`
- `.agent/repository-manifest.yaml`
- `.agent/skills/index.yaml`
- `tests/section-map.tsv`
- `tests/run_tests.sh`
- `tests/run_tests_support.sh`
- `tests/run_tests_full.sh`
- `scripts/ci-local.sh`
- `docs/CLI_CONTRACT.md`
- `docs/BRANCH_PROMOTION_POLICY.md`
- `docs/BOOTSTRAP_TRUST_MODEL.md`
- `docs/RELEASE_SIGNING.md`
- `docs/PRODUCTION_SIGNING_ARCHITECTURE.md`
- `docs/SIGNING_TRUST_MODEL.md`
- `docs/SIGNING_KEY_LIFECYCLE.md`
- `docs/BOOTSTRAP_RELEASE_PROCESS.md`
- `docs/OPERATOR_COMMAND_INDEX.md`
