# Agent Test Strategy

## Testing model

- Primary gate is the monolithic hermetic harness: `bash tests/run_tests.sh`.
- CI parity chain is `bash scripts/ci-local.sh`.
- Targeted iteration is supported through:
  - `bash tests/run_tests.sh --list`
  - `bash tests/run_tests.sh --section=<id>`
  - `bash tests/run_tests.sh --test=<id>`
  - `bash tests/run_tests.sh --tag=<tag>`
  - `bash tests/run_tests.sh --changed`

## Required discipline

- Use targeted checks while iterating.
- Always finish with full harness and CI parity.
- Keep fixture behavior equivalent between targeted and full execution.
- Keep section/test identifiers stable for automation.

## Structured output

- `bash tests/run_tests.sh --format json`
- `bash scripts/ci-local.sh --format json`
- `bash scripts/agent-context.sh --format json`

Schemas live under `schemas/`.
