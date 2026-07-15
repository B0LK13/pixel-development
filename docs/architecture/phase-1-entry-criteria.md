# Phase 1 Entry Criteria

Phase 1 may begin only when all of the following are true:

- The current action / route registry is documented
- The current validation-gate catalog is documented
- System context and trust boundaries are documented
- Current risks and technical debt are identified and ranked
- The runtime compatibility matrix exists
- The evidence model is documented
- The current baseline validation passes
- Architecture documents are internally consistent
- No unexplained mutation path remains in the baseline
- The Phase 1 backlog is prioritized

## Go / no-go criteria

### Go

- `bash tests/run_tests.sh` exits 0 on the source tree
- `bash scripts/ci-local.sh` exits 0 on the source tree
- Clean-clone validation passes from a fresh clone
- `main` remains unchanged by the workstream
- No operator-only action has been taken without authorization

### No-go

- Any required gate fails
- The validation or evidence model is still incomplete
- A mutation path cannot be explained from input to artifact
- The compatibility matrix has unresolved gaps that affect the baseline
- The architecture docs contradict the live scripts or harness

## Phase 1 first workstream

1. Normalize executable resolution and environment setup
2. Harden command, timeout, and exit-code contracts
3. Formalize result and evidence schema versions
