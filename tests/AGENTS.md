# Scoped agent rules for `tests/`

- Keep harness paths hermetic: no live network/service/paid-agent dependencies.
- Preserve fixture isolation and cleanup behavior.
- Targeted modes must not change default full-suite semantics.
- Maintain stable section/test IDs for machine use.
- Keep dependency selection conservative (uncertainty adds checks, not fewer checks).
- Add coverage for new governance checks and agent-system scripts.
- Full gate remains mandatory before completion.
