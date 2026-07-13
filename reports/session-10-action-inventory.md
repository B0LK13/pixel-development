# Session 10 — GitHub Actions Inventory

Date: 2026-07-13 (UTC). Repository state: `auto/session-10-actions-hardening`
based on `main` @ `0d13047`.

## 1. Workflow topology

One workflow file: `.github/workflows/test.yml` (name `tests`).

- triggers: `push` to `main` + `auto/*`; `pull_request` (all targets);
  no `pull_request_target`, no `workflow_dispatch`, no `schedule`;
- concurrency: one run per ref, cancel-in-progress;
- workflow-level permissions: `contents: read` (least privilege); no
  job-level permission widening; no `id-token`, no secrets context;
- jobs: `suite` (ubuntu-latest, 10 min) and `release-candidate-check`
  (ubuntu-latest, 5 min), both verification-only.

## 2. `uses:` reference inventory

Complete list — exactly two references, both the same action:

| workflow | job | action | ref before | publisher | purpose | risk before |
|---|---|---|---|---|---|---|
| test.yml | suite | actions/checkout | `@v4` (mutable major tag) | GitHub (`actions` org, marketplace-verified creator) | full-history checkout for §18/§28 anchor-pin tests + §8 clean-clone | tag retargeting; Node 20 runtime deprecation annotation |
| test.yml | release-candidate-check | actions/checkout | `@v4` (mutable major tag) | same | fixture release build + verify + reproducibility | same |

No third-party actions, no local actions, no reusable workflows, no
container actions, no composite actions.

## 3. Upstream verification (actions/checkout)

- official repository: `github.com/actions/checkout` (GitHub-maintained);
- current release line at audit time: v7.0.0 (published 2026-06-18);
  previous lines: v6.0.3 (2026-06-02), v5.0.1 (2025-11-17);
- v7.0.0 runtime: `node24` (`action.yml` `runs.using`) — resolves the
  Node 20 deprecation annotation that `@v4` (node20, forced onto Node 24)
  produces;
- v7.0.0 tag → commit: `9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0`
  (lightweight tag, commit subject "update error wording (#2467)",
  committed 2026-06-17; moving `v7` tag currently agrees);
- `fetch-depth: 0` still supported ("0 indicates all history for all
  branches and tags");
- notable upstream hardening in the v6/v7 line: credentials persisted to
  a separate file (v6), fork-PR checkout blocked under
  `pull_request_target`/`workflow_run` (v7) — neither trigger exists here;
- maintenance: active (three release lines shipped within 12 months);
- permissions required: `contents: read` suffices for our usage;
- credential access: checkout defaults to persisting the workflow token
  in git config — neutralized in this session via
  `persist-credentials: false` (no step performs authenticated git
  operations; the suite clones locally).

## 4. Permission matrix

| workflow | job | permissions | secrets used | network beyond checkout | pushes/tags/publishes |
|---|---|---|---|---|---|
| tests | suite | `contents: read` (workflow level) | none | apt-get shellcheck only | no |
| tests | release-candidate-check | `contents: read` (workflow level) | none (throwaway ed25519 key generated per run) | none | no |

## 5. Resolution applied this session

| action | previous ref | new ref | release tag | runtime | permissions impact |
|---|---|---|---|---|---|
| actions/checkout (suite) | `@v4` | `@9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0` | `# v7.0.0` | node20 → node24 | none (adds `persist-credentials: false`) |
| actions/checkout (release-candidate-check) | `@v4` | `@9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0` | `# v7.0.0` | node20 → node24 | none (adds `persist-credentials: false`) |

Release notes reviewed: v7.0.0, v6.0.0 (GitHub API, 2026-07-13).
`fetch-depth: 0` preserved on both checkouts (harness §22 pins this).
