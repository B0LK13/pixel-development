# Harness Inventory (Agent OS)

## Canonical harness files

- `tests/run_tests_full.sh` (monolithic canonical checks)
- `tests/run_tests.sh` (targeted/full wrapper)
- `tests/section-map.tsv` (stable check registry)

## Section inventory

Source of truth: `tests/section-map.tsv` (section, check_id, title, dependencies, tags, duration, platforms).

## Shared setup and fixtures

- Preflight vars/functions (`PASS/FAIL/SKIP`, `t_ok/t_fail/t_skip`)
- Shared temp fixtures and fake tool seams (notably around autodev/release checks)
- Cleanup via trap-driven tmp removal

## Side effects

- Intended: tmp fixture creation/removal, local git fixture repositories
- Forbidden: network reliance in harness fixtures, release/push/mutation of remote state

## Execution order and coupling

- Canonical order remains section order in `tests/run_tests_full.sh`.
- Wrapper targeted mode resolves dependencies from `tests/section-map.tsv` and executes conservatively up to highest selected section to preserve setup coupling.
- Full mode is authoritative for completion.

## Implicit coupling hot spots

- Release checks depend on earlier setup/fixtures.
- CI parity and action-pin checks depend on workflow file invariants.
- Agent OS section (31) validates wrapper/context/ci structured outputs and machine checks.

## Duplicated logic candidates

- Shared shell/script discovery patterns across harness + ci-local.
- Repeated command reference checks that could be consolidated through registry-driven adapters.

## Timing and performance notes

- Full harness runtime is long due release/signing/fixture breadth.
- Targeted mode reduces iteration but remains conservative when high-number sections are selected.

