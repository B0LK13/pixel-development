# Harness module scaffold

This directory is the extraction target for the monolithic harness.

Current state:

- canonical execution remains:
  - `tests/run_tests.sh`
  - `tests/run_tests_full.sh`
- registration metadata lives in `tests/section-map.tsv`.

Scaffolded layers:

- `harness/core/` — selection/dependency/result orchestration contracts
- `harness/checks/` — check implementations/adapters
- `harness/adapters/` — repository-specific wrappers
- `harness/fixtures/` — reusable fixture helpers
- `harness/schemas/` — harness result/event schemas
- `harness/evidence/` — evidence-index generation hooks
- `harness/policy/` — route/constraint wiring

The extraction remains compatibility-first: wrapper/full commands must stay backward-compatible.

