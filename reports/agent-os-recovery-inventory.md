# Agent OS Recovery Inventory

Date: 2026-07-14 (UTC)
Branch: `auto/integrate-horizon-02-readiness`
Head Commit: `0dabaaef3bcb6e00c5709507fcde2c85f8b4ac14`

## Interrupted Milestone Identification

- **Interrupted Milestone**: Session 15 hardening, swarm foundation, evidence scaffolding safety, and final integration checks (`--changed` hardening, clean-clone validation, security review, report generation, and signed commit preparation).
- **Completed Precursor**: Session 14 foundation (initial instruction hierarchy, `.agent` manifest/router, basic targeted wrapper `tests/run_tests.sh` + full harness `tests/run_tests_full.sh`, `tests/section-map.tsv`, skills/templates, and `check-*.py` scripts) is present in untracked/modified state.

## Modified Files Inventory

| Path | Git State | Probable Purpose | Status | Related Task | Action |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `.github/workflows/test.yml` | Modified (`M`) | CI enforcement for Agent OS checks and clean-clone verification | Complete | CI Workflow Reconciliation | Keep |
| `README.md` | Modified (`M`) | Documentation of targeted harness (`--list`, `--test`, `--section`, `--changed`, `--json`) and Agent OS contracts | Complete | Documentation & Reports | Keep |
| `docs/CONTRIBUTOR_QUICKSTART.md` | Modified (`M`) | Contributor runbook updates with new targeted harness options and checker scripts | Complete | Documentation & Reports | Keep |
| `docs/OPERATOR_COMMAND_INDEX.md` | Modified (`M`) | Operator index updates covering `run_tests.sh --json` and `ci-local.sh --json` | Complete | Documentation & Reports | Keep |
| `reports/horizon-02-readiness/integration-log.md` | Modified (`M`) | Historical session log update | Complete | Session 14 Integration | Keep |
| `scripts/ci-local.sh` | Modified (`M`) | Local CI gate runner updated to execute Agent OS checkers and `--json` format | Complete | CI Workflow Reconciliation | Keep |
| `tests/run_tests.sh` | Modified (`M`) | Converted to targeted wrapper delegating to `tests/run_tests_full.sh` or targeted checks | Complete | Targeted Harness & Backward Compatibility | Keep / Harden `--changed` |

## Untracked Files Inventory

| Path | Git State | Probable Purpose | Status | Related Task | Action |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `.agent/repository-manifest.yaml` | Untracked (`??`) | Machine-readable repository architecture manifest | Complete | Task Router & Manifest | Keep |
| `.agent/task-router.yaml` | Untracked (`??`) | Deterministic task routing configuration | Complete | Task Router Safety | Keep |
| `.agent/skills/index.yaml` | Untracked (`??`) | Index of available reusable skills | Complete | Skills & Templates | Keep |
| `.agent/skills/*/SKILL.md` (14 skills) | Untracked (`??`) | Reusable skills (`add-adapter`, `add-cli-flag`, `branch-promotion`, `clean-clone-validation`, `evidence-reconciliation`, `fix-ci`, `full-gate-verification`, `release-doc-update`, `release-verification`, `security-review`, `single-test-iteration`, `update-doc-contracts`, `update-documentation`, `workflow-change`) | Complete | Skills & Templates | Keep / Audit |
| `.agent/templates/*.md` (8 templates) | Untracked (`??`) | Task templates (`bug-fix`, `ci-failure`, `documentation-change`, `evidence-update`, `feature`, `release-readiness`, `security-review`, `session-final-report`) | Complete | Skills & Templates | Keep / Audit |
| `AGENTS.md` | Untracked (`??`) | Root universal instruction contract | Complete | Instruction Hierarchy | Keep |
| `.github/AGENTS.md`, `scripts/AGENTS.md`, `tests/AGENTS.md`, `docs/AGENTS.md` | Untracked (`??`) | Scoped instruction contracts | Complete | Instruction Hierarchy | Keep |
| `.github/copilot-instructions.md` | Untracked (`??`) | Copilot specific instruction contract | Complete | Instruction Hierarchy | Keep |
| `docs/AGENT_*.md` & `MCP_INTEGRATION.md` | Untracked (`??`) | Agent architecture, handoff protocol, security boundaries, test strategy, workflow contract, MCP integration | Complete | Documentation & Reports | Keep |
| `evidence/SIGNING-EVIDENCE.json` | Untracked (`??`) | Scaffolding for signing evidence | Partial | Evidence Scaffolding Safety | Fix / Harden (`valid_for_release: false`) |
| `evidence/releases/.gitkeep` | Untracked (`??`) | Directory structure for release evidence | Complete | Evidence Scaffolding Safety | Keep |
| `harness/*.gitkeep` & `harness/README.md` | Untracked (`??`) | Structure and documentation for modular harness expansion | Complete | Harness Scaffolding | Keep |
| `reports/agent-os/harness-inventory.md` | Untracked (`??`) | Inventory of harness sections and options | Complete | Session 14 Reports | Keep |
| `reports/session-14-final-report.md` | Untracked (`??`) | Final report for Session 14 foundation | Complete | Session 14 Reports | Keep |
| `schemas/*.schema.json` (6 schemas) | Untracked (`??`) | JSON schemas (`agent-context`, `agent-handoff`, `agent-task`, `ci-result`, `evidence-index`, `test-result`) | Complete | JSON Contracts | Keep / Validate |
| `scripts/agent-context.sh` | Untracked (`??`) | Context generation utility (`--format markdown|json`) | Complete | Context Generation | Keep |
| `scripts/check-*.py` (9 scripts) | Untracked (`??`) | Automated machine validation scripts (`check-agent-instructions.py`, `check-doc-command-parity.py`, `check-evidence-links.py`, `check-cli-contracts.py`, `check-test-registration.py`, `check-context-freshness.py`, `check-stale-claims.py`, `check-agent-secrets.py`, `check-skill-index.py`) | Complete | Instruction Hierarchy & Drift Checkers | Keep / Verify |
| `tests/run_tests_full.sh` | Untracked (`??`) | Canonical full monolithic verification suite preserved from old `run_tests.sh` | Complete | Backward Compatibility | Keep |
| `tests/section-map.tsv` | Untracked (`??`) | Tab-separated registry mapping section and check IDs | Complete | Registry Routing | Keep |

## Missing Session 15 Items to Complete

1. **Swarm Foundation** (Phase 13): Create `.agent/swarm.yaml`, `reports/swarm-status.schema.json`, and `docs/AGENT_SWARM_OPERATIONS.md`.
2. **Evidence Scaffolding Safety** (Phase 14): Add explicit placeholder rejection fields (`valid_for_release: false`) to `evidence/SIGNING-EVIDENCE.json` and regression coverage in harness/tests.
3. **`--changed` Hardening** (Phase 7): Verify conservative behavior across all Git/untracked/detached states.
4. **Security & Threat Model** (Phase 17): Create/update `docs/AGENT_OS_THREAT_MODEL.md` and `reports/agent-os-security-review.md`.
5. **Clean-Clone Validation** (Phase 16): Perform pristine clone test and record `reports/agent-os-clean-clone-validation.md`.
6. **Audit & Final Reports** (Phase 22): Create `reports/session-15-final-report.md`, `reports/session-15-agent-os-audit.md`, `reports/session-15-security-review.md`, `reports/session-15-clean-clone-validation.md`, `reports/agent-os-interruption-recovery.md`, and `reports/agent-os-final-report.md`.
