# Agent Architecture

## Core components

1. **Agent entry layer**: `AGENTS.md` + scoped `*/AGENTS.md`.
2. **Context loader**: `scripts/agent-context.sh`.
3. **Task router**: `.agent/task-router.yaml`.
4. **Machine model**: `.agent/repository-manifest.yaml` + `schemas/`.
5. **Execution harness**: `tests/run_tests.sh` (targeted/full) + `tests/run_tests_full.sh`.
6. **CI parity runner**: `scripts/ci-local.sh`.
7. **Policy checks**: `scripts/check-*.py`.
8. **Evidence/report plane**: `evidence/` and `reports/`.
9. **Phase 0 architecture baseline**: `docs/architecture/` (current system-context,
   control/data flows, trust boundaries, catalogues, risks, debt, and Phase 1
   entry criteria).

## Control flow

Agent
-> context loader
-> task router
-> scoped instructions
-> isolated branch/worktree
-> targeted checks
-> full gate
-> evidence/report updates
-> operator-owned PR/merge/release actions

## Trust boundaries

- **Repository-owned truth**: contracts/docs/scripts/schemas in this repository.
- **Adapter tooling**: optional integrations (including MCP) may consume repository truth, never replace it.
- **Operator boundary**: signing, release publication, protected operations.

## Configuration ownership

- Contracts: `AGENTS.md`, `docs/AGENT_*`.
- Routing/manifest: `.agent/`.
- Execution behavior: `tests/`, `scripts/`.
- Enforcement: workflow + `scripts/ci-local.sh` + harness checks.

## Failure handling model

- Usage/contract violations fail explicitly.
- Security/policy drift fails blocking checks.
- Unknown route/mapping expands selected checks conservatively.
- Full gate remains mandatory for completion claims.

## Extension and extraction model

- Add checks by registering metadata + validation wiring.
- Add routes/skills/templates under `.agent/` without changing baseline entry commands.
- If extracted into a standalone harness later, keep repository adapters thin and preserve:
  - `bash tests/run_tests.sh`
  - `bash scripts/ci-local.sh`
