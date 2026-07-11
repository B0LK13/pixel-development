# Evidence

This directory holds generated verification evidence for the autonomous
follow-up loop. It is deliberately plain text so it can be diffed, grepped,
and regenerated without tooling.

## Layout

- `session-N/` — evidence captured during session N. One directory per
  session, append-only. Once a session closes, its directory is not edited;
  corrections land as new dated files in the same directory.
- File names are stable within a session so reports can cite them:
  `baseline-record.txt`, `test-results.txt`, `ci-parity.txt`,
  `trust-model-evidence.txt`, `test-timings.txt`, `final-status.txt`.

## Generated vs source

Everything under `evidence/` is generated output, not source documentation.
If evidence and a `docs/` page disagree, the docs page is the normative
statement and the evidence must be regenerated.

## Regeneration

Each evidence file records, in its header, the command that produced it and
the commit it was produced on. The expensive gate outputs (full suite,
ShellCheck, syntax checks, `git diff --check`, checksum gate) are
reproducible at any time, from anywhere, with:

```bash
bash scripts/ci-local.sh
```

Per-file regeneration:

- `test-timings.txt`: `PIXEL_TEST_TIMINGS=1 bash tests/run_tests.sh`
- `ci-parity.txt`: run `bash scripts/ci-local.sh` from `/`
- `trust-model-evidence.txt`: run the commands printed in the file itself
- `baseline-record.txt` / `final-status.txt`: session-specific snapshots;
  re-run the git commands shown in the file

## Conventions

- Timestamps: UTC, ISO 8601 (`date -u +%Y-%m-%dT%H:%M:%SZ`).
- Every file records the commit it was generated on.
- Outputs are bounded: gate summaries and suite tails, not megabyte logs.
- No secrets, tokens, or environment dumps. Absolute repository paths are
  allowed where needed for reproducibility.
- Whitespace: generated files must pass `git diff --check` (no trailing
  whitespace, LF endings). Graph output is piped through
  `sed 's/[[:space:]]*$//'` before capture.

## Retention

Evidence is kept for every session and is never deleted or rewritten in
place — the audit trail is the point. Evidence carries no CI gate of its
own; the gates regenerate equivalent output on demand via
`scripts/ci-local.sh`.

## Why no generator script

A `scripts/generate-session-evidence.sh` was considered and rejected for
now: the evidence set is session-specific (each session answers different
questions), and the only truly recurring artifacts — the gate outputs — are
already regenerated deterministically by `scripts/ci-local.sh`. A framework
would add maintenance cost without improving reproducibility. Revisit if
future sessions converge on an identical evidence shape.
