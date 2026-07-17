# Horizon 0.2 Integration Log

Coordinator record of every integration event on
`auto/integrate-horizon-02-readiness`. Gate = `git diff --check` +
`scripts/check-github-action-pins.py` + `bash tests/run_tests.sh` +
`bash scripts/ci-local.sh` + clean-tree check (raw logs host-only under
`/tmp/h02/`; summaries committed to `evidence/horizon-02/`).

| # | event | commit(s) | gate | window (UTC) | result |
|---|---|---|---|---|---|
| 0 | baseline evidence + report (Agent A role, coordinator commit) | `cc5c0d3` tested; evidence commit `858d42f` | full | 21:16:19 → 21:32:59 | green — 327/0/0, ci-local 0, pins 0, diff clean, tree clean |
| 1 | merge `auto/horizon-02-reproducibility` (Agent B — byte-identical rebuild proof) | merge `0dabaae` + log commit | full | follows | pending |

Merge policy per event: signed `--no-ff` merge, log commit, then the full
gate on the frozen tree. No merge with unresolved findings, incomplete
evidence, failed tests, unsigned commits, or unrelated changes.
