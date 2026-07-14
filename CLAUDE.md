# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

`pixel-development` (the "pixel-lab kit") turns an Android phone into an autonomous AI
dev workstation: Termux (bionic) + a proot Ubuntu devbox (glibc) running Claude
Code/Codex/Gemini/Aider. The repo itself is a **script-first, trust-sensitive
platform**: four shell entry-point scripts, a hermetic self-test harness, release
build/sign/verify tooling, and an elaborate agent-operating-contract layer that governs
how autonomous coding agents (including you) are allowed to work in it.

Read `AGENTS.md` at the repo root first — it is the authoritative, tool-agnostic operating
contract (scoped copies exist at `.github/AGENTS.md`, `scripts/AGENTS.md`, `tests/AGENTS.md`,
`docs/AGENTS.md`; load the one matching the paths you're touching).

## Commands

```bash
# Context snapshot (branch, dirty state, gates, risk classification) — run first
bash scripts/agent-context.sh --format markdown     # or --format json

# Full verification gate — MANDATORY before claiming any task complete
bash tests/run_tests.sh

# Targeted iteration (never a substitute for the full gate above)
bash tests/run_tests.sh --list                      # stable section/test IDs
bash tests/run_tests.sh --test=<id>
bash tests/run_tests.sh --section=<n>
bash tests/run_tests.sh --tag=<tag>
bash tests/run_tests.sh --changed [--base <ref>]     # infer scope from changed files
bash tests/run_tests.sh --format json                # structured (schemas/test-result.schema.json)

PIXEL_TESTS_NO_CLONE=1 bash tests/run_tests.sh        # skip nested clean-clone smoke (dev speed only)
PIXEL_TEST_TIMINGS=1 bash tests/run_tests.sh          # per-test timings on stderr

# CI parity — MANDATORY alongside the full gate for anything gate/policy/release related
bash scripts/ci-local.sh                              # fail-fast, same gates as .github/workflows/test.yml
bash scripts/ci-local.sh --json

# Policy/contract checks (also run in CI)
python3 scripts/check-github-action-pins.py
python3 scripts/check-agent-instructions.py
python3 scripts/check-doc-command-parity.py
python3 scripts/check-evidence-links.py
python3 scripts/check-cli-contracts.py
python3 scripts/check-test-registration.py
python3 scripts/check-context-freshness.py
python3 scripts/check-stale-claims.py
python3 scripts/check-agent-secrets.py
python3 scripts/check-skill-index.py
```

After editing any of the three checksum-pinned scripts (`pixel-bootstrap.sh`,
`pixel-dev-setup.sh`, `pixel-apps-setup.sh`), **in the same commit**:

```bash
bash scripts/update-bootstrap-checksums.sh --write
bash scripts/update-bootstrap-checksums.sh --check   # must exit 0
```

Release bundle build/verify (see `docs/OPERATOR_COMMAND_INDEX.md` for the full table):

```bash
SOURCE_DATE_EPOCH="$(git log -1 --format=%ct)" bash scripts/build-release-candidate.sh --version=X.Y.Z
bash scripts/verify-release-bundle.sh --bundle=DIR                                    # integrity-only
bash scripts/verify-release-bundle.sh --bundle=DIR --signature=... --keyring=... --require-signature
```

## Architecture

**Product scripts (repo root, must stay at root — raw GitHub URLs resolve against it):**

- `pixel-bootstrap.sh` — verified-install entry point; downloads the two setup scripts and
  checks them against pinned SHA-256 digests (fail closed) before running them.
- `pixel-dev-setup.sh` — Termux CLI toolbelt + proot Ubuntu devbox provisioning.
- `pixel-apps-setup.sh` — daemons, fonts, autostart, app checklist.
- `pixel-autodev.sh` — autonomous backlog runner: reads `BACKLOG.md`, cuts one
  `auto/<slug>` branch per task, runs the target repo's own test command (via
  `.pixel-lab.json`), commits `feat(auto): ...` only on green (else leaves a
  `wip(auto)` branch), and never pushes.

All four share one flag-parsing convention (`docs/CLI_CONTRACT.md` is the normative
source): **`--flag=value` only** (no space form), unknown flag → exit 2, `--help`/`-h` →
exit 0, value validation happens *before* any side effect, exit 1 = runtime failure, exit
2 = usage error. Any script change must keep this contract and the CLI_CONTRACT.md table
in sync (`scripts/check-cli-contracts.py` enforces it).

**Verification harness:**

- `tests/run_tests.sh` — the one sanctioned gate. Hermetic (no network, no paid agent
  calls — stubs injected via `CLAUDE_BIN`/`CODEX_BIN`), runs from any directory, leaves
  the tree clean, ends with a clean-clone smoke test. Checks: required files, `bash -n`
  syntax, shellcheck, the `--help`/unknown-flag contract, `.pixel-lab.json` validity,
  autodev dry-run behavior, the full `--timeout` contract.
- `tests/run_tests_full.sh` + `tests/section-map.tsv` — the full check registry backing
  targeted `--section`/`--test`/`--tag` selection; section/test IDs must stay stable.
- `scripts/ci-local.sh` — reproduces `.github/workflows/test.yml` locally (whitespace,
  checksum lockstep, policy checks, syntax, shellcheck, full suite), fail-fast.
- `harness/` — scaffolded extraction target for the harness (`core/`, `checks/`,
  `adapters/`, `fixtures/`, `schemas/`, `evidence/`, `policy/`); not yet the canonical
  execution path — `tests/run_tests.sh` and `scripts/ci-local.sh` still are.

**Agent operating-system layer** (governs how you, specifically, should work here):

- `AGENTS.md` (root) + scoped `*/AGENTS.md` — the contract itself.
- `.agent/task-router.yaml` — routes a change (by keyword match: cli, tests, github-workflows,
  release-tooling, documentation, ...) to required reading, targeted checks, full gates, and
  operator-only boundaries for that route.
- `.agent/repository-manifest.yaml`, `.agent/skills/*/SKILL.md`, `.agent/templates/*.md` —
  machine model and per-task-shape playbooks/report templates.
- `docs/AGENT_ARCHITECTURE.md`, `AGENT_WORKFLOW_CONTRACT.md`, `AGENT_SECURITY_BOUNDARIES.md`,
  `AGENT_TEST_STRATEGY.md`, `AGENT_HANDOFF_PROTOCOL.md` — architecture, workflow sequencing,
  security boundaries, test strategy, and the mandatory session handoff report format.
- `schemas/` — JSON schemas for structured output (`agent-context`, `ci-result`,
  `test-result`, `agent-handoff`, `agent-task`, `evidence-index`).

Standing rules from this layer that apply to every task, not just ones that mention it:

- Work one coherent change per branch; keep the tree clean before the final gate.
- Validation sequence: targeted checks first, iterate, then **full harness**
  (`tests/run_tests.sh`) **and** **CI parity** (`scripts/ci-local.sh`) — targeted checks never
  replace either.
- Operator-only (never do these yourself): `git push`, force operations, `rm -rf`, `sudo`,
  merging/tagging/releasing/publishing/deploying, production signing, secret/credential or
  branch-protection changes.
- Never weaken SHA pinning, signing, or integrity checks to make a test pass; never claim
  full-gate completion from a targeted run only.
- End sessions with the handoff block from `docs/AGENT_HANDOFF_PROTOCOL.md`.
- MCP/adapter tooling (`docs/MCP_INTEGRATION.md`) may inform work but is never a substitute
  for the repository-native gates above.

**Evidence and reports:** `evidence/` (append-only, generated verification evidence,
per-session subfolders) and `reports/` (append-only session/completion reports) form the
audit trail; `scripts/check-evidence-links.py` and `check-stale-claims.py` keep doc
references to them honest. Contract/policy changes should include a report update in the
same change.

## Key docs to consult by task type

- CLI/flag changes → `docs/CLI_CONTRACT.md`, `scripts/AGENTS.md`
- Harness/test changes → `docs/AGENT_TEST_STRATEGY.md`, `tests/AGENTS.md`, `tests/section-map.tsv`
- `.github/workflows/` changes → `docs/GITHUB_ACTIONS_PINNING_POLICY.md`, `.github/AGENTS.md`
  (every external action SHA-pinned + version comment; `scripts/check-github-action-pins.py`)
- Release/signing/bundle changes → `docs/RELEASE_SIGNING.md`, `docs/PRODUCTION_SIGNING_ARCHITECTURE.md`,
  `docs/SIGNING_KEY_LIFECYCLE.md`, `docs/SIGNING_TRUST_MODEL.md`, `docs/BOOTSTRAP_RELEASE_PROCESS.md`
- Bootstrap trust/verification changes → `docs/BOOTSTRAP_TRUST_MODEL.md`
- Branch/merge policy → `docs/BRANCH_PROMOTION_POLICY.md`, `docs/MAIN_BRANCH_PROTECTION.md`
- Full operator command reference (tables only) → `docs/OPERATOR_COMMAND_INDEX.md`
- Security/portability audit and finding register → `docs/AUTONOMOUS_AUDIT.md`
