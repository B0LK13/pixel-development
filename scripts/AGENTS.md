# Scoped agent rules for `scripts/`

- Preserve strict CLI contract style:
  - `--flag=value` for value flags
  - unknown flag → exit 2
  - `--help`/`-h` → exit 0
- Validate input before side effects.
- Keep diagnostics explicit; no silent fallback for invalid input.
- For bootstrap/script integrity changes, run:
  - `bash scripts/update-bootstrap-checksums.sh --write`
  - `bash scripts/update-bootstrap-checksums.sh --check`
  in the same change.
- Any new script must be referenced from docs/contracts or checks, and included in test/lint coverage.
- Preserve quoting and portability assumptions (bash + standard GNU tooling in supported environments).
- Runtime failures use exit 1; usage/contract failures use exit 2.
