# Evidence Model

## Current artifacts

| artifact | location | purpose | authoritative? |
|---|---|---|---|
| Logs | `reports/logs/` | command transcripts and parity output | yes |
| Reports | `reports/*.md` | session handoff, audits, final reports | yes |
| Evidence bundles | `evidence/` | generated run evidence | yes |
| Status snapshots | `agent-context` / harness JSON | branch, dirty state, selected sections | yes |
| Commit hashes | git history, report headers | exact source identity | yes |
| Signature results | release/signature verifier output | integrity / authenticity classification | yes |
| Clean-clone paths | nested clone directories | source/clone parity proof | yes |
| Process diagnostics | ci-local / harness logs | failures, interruptions, child exits | yes |

## Naming and retention

- `reports/logs/ci-local_<timestamp>/`
- `reports/logs/run_tests_<timestamp>/`
- `reports/session-*.md`
- `reports/*final-report.md`
- `evidence/session-*`

The repository treats reports and evidence as append-only by convention, but
specific scripts may overwrite temporary working files while a run is active.

## Redaction

- Logs are not automatically redacted beyond the checks that scan for secret
  patterns.
- Evidence should avoid including credentials, token values, or private keys.
- Signature and checksum outputs are safe to store because they are derived
  values, not raw secrets.

## Provenance gaps

- There is no single immutable evidence-bundle schema for every run yet
- Some provenance is implicit in the git commit and report path rather than
  in a dedicated manifest
- Machine-readable run output exists, but not every report file is schema-
  validated

## Gap to the future model

The future state is an immutable evidence bundle with explicit source commit,
policy version, runtime profile, and normalized artifact inventory. The
current model is still file-and-convention based: useful, auditable, and
conservative, but not yet unified.
