# Copilot entry instructions for `pixel-development`

Read `AGENTS.md` first. This file is the concise Copilot entrypoint.

## Commands

| Purpose | Command |
|---|---|
| Context snapshot | `bash scripts/agent-context.sh --format markdown` |
| Targeted harness list | `bash tests/run_tests.sh --list` |
| Targeted harness by section | `bash tests/run_tests.sh --section=<id>` |
| Targeted harness by test id | `bash tests/run_tests.sh --test=<id>` |
| Targeted harness by tag | `bash tests/run_tests.sh --tag=<tag>` |
| Targeted harness from changed files | `bash tests/run_tests.sh --changed` |
| Structured harness output | `bash tests/run_tests.sh --format json` |
| Full verification gate (mandatory) | `bash tests/run_tests.sh` |
| CI parity gate (mandatory) | `bash scripts/ci-local.sh` |
| Structured CI parity output | `bash scripts/ci-local.sh --format json` |

## Agent operating rules

- Follow scoped instructions for touched paths:
  - `.github/AGENTS.md`
  - `scripts/AGENTS.md`
  - `tests/AGENTS.md`
  - `docs/AGENTS.md`
- Maintain CLI contract (`docs/CLI_CONTRACT.md`) and validation-before-side-effects.
- Preserve hermetic test behavior and Action SHA pinning policy.
- Do not push/merge/tag/release/deploy without operator approval.

## Machine checks

- `python3 scripts/check-agent-instructions.py`
- `python3 scripts/check-doc-command-parity.py`
- `python3 scripts/check-evidence-links.py`
- `python3 scripts/check-cli-contracts.py`
- `python3 scripts/check-test-registration.py`
