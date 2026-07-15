# Current State

## Baseline

- Validated baseline commit: `e487acf78788fc204f6f6950f4d13144a6de67e9`
- Local phase-0 branch: `auto/phase-0-program-baseline`
- Follow-up branch `auto/follow-up-bwrap-selector-drift` is separate and has
  not been promoted into `main`
- Local `main` is ahead of `origin/main` by 10 commits in this workspace

## Repository shape

| path | role |
|---|---|
| `pixel-bootstrap.sh` | verified install entry point |
| `pixel-dev-setup.sh` | Termux toolchain + proot Ubuntu devbox setup |
| `pixel-apps-setup.sh` | apps, daemons, fonts, autostart |
| `pixel-autodev.sh` | backlog-driven autonomous runner |
| `scripts/` | release, checksum, signature, parity, context helpers |
| `tests/` | hermetic harness and registry |
| `docs/` | contracts, trust models, operator runbooks |
| `reports/` | session reports and summaries |
| `evidence/` | generated evidence artifacts |
| `.agent/` | routing, skills, templates, manifest |

## Primary entrypoints

- `bash tests/run_tests.sh`
- `bash scripts/ci-local.sh`
- `bash scripts/agent-context.sh --format markdown`
- `bash tests/run_tests.sh --list`
- `bash tests/run_tests.sh --changed`

## Current validation architecture

- One monolithic but hermetic harness in `tests/run_tests.sh`
- Stable section registry in `tests/section-map.tsv`
- Targeted iteration via `--section`, `--test`, `--tag`, and `--changed`
- CI parity in `scripts/ci-local.sh`
- Release verification and checksum tooling exercised by sections 16-28

## Current selection behavior

- Changed-path classification lives in `tests/run_tests_support.sh`
- Unknown paths fall back conservatively to the full gate
- `.gitignore` changes stay targeted and do not recurse
- Docs and reports changes trigger docs/evidence checks

## Current recursion protection

- Full-harness self-invocation is blocked through `PIXEL_HARNESS_ACTIVE`
- Nested clean-clone runs are explicitly guarded
- `scripts/ci-local.sh` kills child processes on interrupt
- `pixel-autodev.sh` distinguishes dry-run from real dispatch

## Current clean-clone behavior

- Clean-clone validation is section 8 and is also exercised in the full gate
- The harness clones the repo locally and reruns targeted checks from the clone
- The clean-clone selector docs are kept aligned with the live registry

## Runtime compatibility

- Linux is the canonical host for the harness and release checks
- Termux is the canonical phone runtime for bootstrap/dev setup
- proot Ubuntu is the canonical devbox runtime for the autonomous loop
- Bubblewrap is not a current canonical execution path in the repo harness

## Current evidence model

- Logs are written under `reports/logs/`
- Session reports live under `reports/`
- Generated evidence lives under `evidence/`
- Release artifacts are verified from file-based bundles, not live network fetches

## Promotion flow

```
task branch -> integration branch -> full harness -> ci-local -> operator review
-> PR / remote checks -> merge to main -> post-merge verification
```

Promotion remains operator-controlled; the repository does not auto-push, auto-
merge, or auto-release.
