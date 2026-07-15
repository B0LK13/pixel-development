# Agent OS Harness — Product Roadmap

## Build Philosophy

- Ship the trust contract before the fancy orchestration.
- Keep every phase demoable and non-breaking.
- Prefer explicit evidence and clear diagnostics over convenience.
- Preserve clean-clone parity as a standing trust signal.
- Extract modules only after behavior is characterized by tests.
- Design for the end-state architecture from day one: thin entrypoints, layered core services, explicit policy, and a path to distributed execution.

## Phase 0 — Baseline and Governance

**Prompt for the coding agent:** “Map the current harness contract, trust boundaries, and authoritative files before changing behavior.”

- [ ] **TASK-001** — Inventory the current harness contract and ownership boundaries
  Files: `docs/AGENT_ARCHITECTURE.md`, `docs/AGENT_WORKFLOW_CONTRACT.md`, `docs/AGENT_SECURITY_BOUNDARIES.md`, `docs/AGENT_HANDOFF_PROTOCOL.md`
  Notes: Record the current entrypoints, validation gates, evidence locations, and promotion boundaries in a single baseline summary.
- [ ] **TASK-002** — Define the current-state architecture and terminology
  Files: `docs/architecture/system-context.md`, `docs/architecture/current-state.md`, `docs/architecture/terminology.md`
  Notes: Capture the current repository shape, authoritative commands, and the exact words used for run, plan, evidence, and promotion.
- [ ] **TASK-003** — Build the initial risk and dependency register
  Files: `docs/implementation-backlog.md`, `docs/risk-register.md`, `docs/dependency-inventory.md`
  Notes: List the trust-sensitive areas first: PATH normalization, runtime isolation, recursion guards, clean-clone parity, and evidence handling.
- [ ] **TASK-004** — Document the target layered architecture and interface boundaries
  Files: `docs/product-vision.md`, `docs/prd.md`, `docs/architecture/*.md`
  Notes: Capture the long-term layers explicitly so future refactors keep platform, core services, validation, evidence, and governance separated.

## Phase 1 — Core Stabilization and Contract Hardening

**Prompt for the coding agent:** “Make the public harness contract deterministic and fail-closed.”

- [ ] **TASK-005** — Normalize executable resolution and environment setup
  Files: `tests/run_tests_support.sh`, `scripts/ci-local.sh`, `tests/run_tests.sh`
  Notes: Keep PATH construction explicit and portable; unsupported environments should fail clearly instead of silently falling back.
- [ ] **TASK-006** — Harden command, timeout, and exit-code contracts
  Files: `docs/CLI_CONTRACT.md`, `scripts/*.sh`, `tests/run_tests_full.sh`
  Notes: Preserve equals-form semantics, validate before side effects, and keep failure modes deterministic.
- [ ] **TASK-007** — Formalize result and evidence schema versions
  Files: `schemas/*.json`, `tests/run_tests_full.sh`, `reports/`
  Notes: Version the machine-readable outputs so later phases can trust their shape.

## Phase 2 — Modular Architecture and Internal APIs

**Prompt for the coding agent:** “Extract reusable modules without changing observable behavior.”

- [ ] **TASK-008** — Isolate repository and workspace helpers
  Files: `harness/core/*.sh`, `tests/lib/*.sh`
  Notes: Separate Git identity, dirty-tree analysis, clone handling, and artifact inventory from entrypoint scripts.
- [ ] **TASK-009** — Centralize process supervision and cleanup
  Files: `harness/core/process.*`, `scripts/ci-local.sh`, `tests/run_tests_support.sh`
  Notes: One executor should own signals, timeouts, process groups, and cleanup semantics.
- [ ] **TASK-010** — Add contract-level tests around extracted modules
  Files: `tests/run_tests_full.sh`, `tests/fixtures/**`
  Notes: Characterize behavior before extraction and keep the old and new paths behaviorally equivalent.

## Phase 3 — Observability and Evidence

**Prompt for the coding agent:** “Make every run explain itself with durable evidence.”

- [ ] **TASK-011** — Emit structured run manifests and evidence bundles
  Files: `evidence/`, `reports/`, `schemas/evidence-index.schema.json`
  Notes: Every run should capture source identity, policy version, runtime profile, exit status, and evidence paths.
- [ ] **TASK-012** — Add diagnostic commands for tracing and comparison
  Files: `scripts/*.sh`, `harness/README.md`, `docs/OPERATOR_COMMAND_INDEX.md`
  Notes: Commands like doctor, trace, compare, and explain should reuse the same core services.
- [ ] **TASK-013** — Track performance and fallback metrics
  Files: `reports/`, `tests/run_tests_full.sh`
  Notes: Measure duration, fallback frequency, clean-clone parity, and retry behavior without weakening trust.

## Phase 4 — Change Intelligence and Runtime Security

**Prompt for the coding agent:** “Make validation selection smarter without making it less trustworthy.”

- [ ] **TASK-014** — Implement change classification and risk scoring
  Files: `harness/core/change.*`, `tests/run_tests_full.sh`
  Notes: Start with deterministic rules and dependency traversal; keep ML advisory only.
- [ ] **TASK-015** — Classify runtime support and unsupported environments
  Files: `tests/run_tests_support.sh`, `scripts/ci-local.sh`, `docs/CLI_CONTRACT.md`
  Notes: Runtime profiles must report capabilities, limitations, and fallback status explicitly.
- [ ] **TASK-016** — Enforce recursion and nested-run guards
  Files: `tests/run_tests.sh`, `tests/run_tests_full.sh`
  Notes: Top-level orchestration must not re-enter itself through internal fallbacks.

## Phase 5 — Agent Governance and Distributed Execution

**Prompt for the coding agent:** “Add bounded autonomy and worker coordination only after the core contract is stable.”

- [ ] **TASK-017** — Define agent scope, budgets, and approval metadata
  Files: `schemas/agent-task.schema.json`, `docs/MCP_INTEGRATION.md`, `harness/core/agents.*`
  Notes: Agents need explicit allowed actions, prohibited actions, and escalation rules.
- [ ] **TASK-018** — Prototype a worker registry and scheduling contract
  Files: `harness/core/scheduling.*`, `docs/AGENT_ARCHITECTURE.md`
  Notes: Match tasks to workers by trust level, platform, and toolchain identity.
- [ ] **TASK-019** — Add remote-result attestation and promotion inputs
  Files: `harness/core/provenance.*`, `docs/RELEASE_SIGNING.md`, `docs/SIGNING_TRUST_MODEL.md`
  Notes: Remote results must carry signed worker identity and environment attestation.

## Phase 6 — Production Maturity and Ecosystem Expansion

**Prompt for the coding agent:** “Prepare the harness for long-term use across more repositories and more operators.”

- [ ] **TASK-020** — Expand release and rollback documentation
  Files: `docs/ROLLBACK_AND_RECOVERY_PLAN.md`, `docs/RELEASE_PIPELINE_PHASES.md`, `docs/RELEASE_ACCEPTANCE_CRITERIA.md`
  Notes: Promotion rules, rollback readiness, and recovery paths should be explicit and tested.
- [ ] **TASK-021** — Align evidence, audit, and policy documentation
  Files: `docs/AUTONOMOUS_AUDIT.md`, `docs/BOOTSTRAP_TRUST_MODEL.md`, `docs/PRODUCTION_SIGNING_ARCHITECTURE.md`
  Notes: The docs should describe the same trust model the code enforces.
- [ ] **TASK-022** — Prepare ecosystem extension points
  Files: `docs/MCP_INTEGRATION.md`, `harness/README.md`, `docs/CONTRIBUTOR_QUICKSTART.md`
  Notes: Keep the core contract stable while exposing clear extension seams for adjacent repos and tools.

## Agent Session Guide

1. Start with the oldest unchecked task in the earliest incomplete phase.
2. Keep each session scoped to one phase or one coherent trust boundary.
3. Characterize behavior with tests before refactoring the implementation.
4. End each session by marking completed tasks in this roadmap and updating any touched evidence or contract docs.
5. If a change affects trust, promotion, or release behavior, run the full harness and CI parity before handing off.
