# Session 10 — Final Report

GitHub Actions pinning and main-branch protection readiness.
Branch: `auto/session-10-actions-hardening`, tip `d27f1c9`. PR: #2.
Date: 2026-07-13 (UTC).

## Starting State

- branch: `auto/session-10-actions-hardening`, created from `main` @ `0d13047`;
  Sessions 1–9 merge `b106b35` and verified tip `78e8261` confirmed ancestors
- main status: `0d13047`, synchronized with origin, unchanged by this session
- working tree: clean at start
- baseline (Phase 2): suite 310/0/0 (508 s), `scripts/ci-local.sh` rc=0
  (521 s), `git diff --check` clean — `evidence/session-10/baseline-record.txt`
- inventory: one workflow (`test.yml`), one external action
  (`actions/checkout@v4` × 2), nothing else — `reports/session-10-action-inventory.md`

## Pinning Policy

- selected policy: every external action/reusable-workflow reference pinned
  to a full 40-character commit SHA with an inline `# vX.Y.Z` release
  comment — `docs/GITHUB_ACTIONS_PINNING_POLICY.md`
- exceptions: none granted (local `./` actions and digest-pinned `docker://`
  images are allowed by construction, not by exception)
- update procedure: policy §7 manual (tag→SHA mapping, diff review, full
  gate, PR); policy §8 Dependabot (weekly grouped PRs, no auto-merge)
- enforcement: `scripts/check-github-action-pins.py` — ci-local gate 3
  (before the expensive suite), blocking `Verify GitHub Action pins` step
  in the `suite` job, harness §30 fixture matrix

## Action Updates

| action | previous ref | new SHA | release tag | publisher | runtime | permissions |
|---|---|---|---|---|---|---|
| actions/checkout (suite) | `@v4` | `9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0` | `# v7.0.0` | GitHub (actions org, verified creator) | node20 → node24 | `contents: read`; `persist-credentials: false` added |
| actions/checkout (release-candidate-check) | `@v4` | same | `# v7.0.0` | same | same | same |

SHA provenance: GitHub API `repos/actions/checkout/git/refs/tags/v7.0.0`
(lightweight tag → commit `9c091bb…`, subject "update error wording
(#2467)", 2026-06-17; the moving `v7` tag agrees). Release notes reviewed:
v7.0.0 (blocks fork-PR checkout under pull_request_target/workflow_run;
ESM build) and v6.0.0 (credentials persisted to a separate file; node24).
`fetch-depth: 0` semantics unchanged.

## Node Runtime Deprecation

- original annotation: "Node.js 20 is deprecated … actions/checkout@v4
  … forced to run on Node.js 24" — present on every Session 9 run;
- root cause: the v4 action line runs on the node20 runtime;
- selected version: v7.0.0 (`runs.using: node24`);
- remote result: **0 annotations** on run 29234388613 — eliminated.

## Static Enforcement

- script: `scripts/check-github-action-pins.py` (stdlib-only Python 3, no
  network, deterministic output; exit 0 compliant / 1 violations / 2 usage);
- tests: harness §30 — 15 assertions (repo compliance; accept forms:
  SHA+comment, local, nested path, reusable workflow, docker digest;
  reject forms: `@v4`, short SHA, `@main`, `@master`, `@latest`, SHA
  without comment, missing `@ref`, reusable `@v1`, docker `:latest`;
  commented-out lines ignored; policy-doc contract; credential-persistence
  parity; §30g dependabot config) + §22 CI-parity coverage of the new gate;
- local result: suite 326/0/0; checker exits 0 on the repo;
- remote result: `0 violation(s)` on both remote runs;
- edge cases verified: quoted values, job-level reusable `uses:`, empty
  `uses:`, unknown argument (exit 2), missing workflow dir (exit 2).

## Branch Protection

- required checks: `suite`, `release-candidate-check` (real job names from
  run 29230870085 on the Sessions 1–9 merge commit);
- merge strategy: merge commits preserved; linear history NOT required
  (would forbid the mandatory `--no-ff` audit-trail merges);
- direct push policy: PR required, 1 approval, up-to-date branch,
  conversation resolution, signed commits;
- force-push: disabled; deletion: disabled;
- applied or documented only: **DOCUMENTED — NOT APPLIED** (operator
  decision, 2026-07-13: application not authorized this session);
- runbook + read-only verification steps: `docs/MAIN_BRANCH_PROTECTION.md`.

## Verification

- test total: **326 passed / 0 failed / 0 skipped** (310 baseline + 1 §22
  parity assertion + 15 §30 assertions), local and remote identical;
- `scripts/ci-local.sh`: exit 0 — includes the new pin gate as gate 3;
- integrity verification: `verified-integrity-only`, exit 0;
- signed fixture: `verified-signed`, exit 0 (throwaway ed25519 key);
- reproducibility: byte-for-byte identical (diff empty, modes same, sha same);
- key scan: 0 private-key blocks (naive substring variant matches only the
  harness's own §28b anti-leak guard pattern — documented in
  `evidence/session-10/scans.txt`);
- signatures: all 5 session commits GPG-signed, verified good;
- remote CI: runs 29234388613 (push) + 29234401276 (pull_request) — both
  jobs green on both runs; PR #2 checks 4/4 pass.

## Commits

| commit | change |
|---|---|
| cf1fc9d | docs(ci): define immutable GitHub Actions pinning policy |
| a2402fd | ci: pin workflow actions to immutable commits with static enforcement |
| c64d5e9 | chore(deps): configure controlled GitHub Actions updates |
| f831002 | docs(governance): define main branch protection requirements |
| d27f1c9 | docs: record session 10 action hardening evidence and reports |

Pins + enforcement landed in one commit deliberately: separating them
would leave a red intermediate tip (the checker fails on `@v4`; the old
§22 assertion fails on the pinned form). The pairing is the smallest
green-preserving unit.

## Security Review

`reports/session-10-actions-security-review.md`: no open CRITICAL/HIGH.
F-1 (HIGH — mutable `@v4` retargeting) fixed by SHA pins + blocking
enforcement; F-2 (MEDIUM — workflow token persisted in git config) fixed
by `persist-credentials: false`; F-3 (LOW — Dependabot relies on operator
review) accepted, no auto-merge; F-4 (INFORMATIONAL — line-oriented
parser surface) documented.

## Security Invariants

1. every external action pinned to an approved immutable SHA — PASS
2. no `@main`/`@master`/floating reference remains — PASS
3. action publishers documented — PASS (inventory §2/§3)
4. full-history checkout remains enabled — PASS (`fetch-depth: 0` × 2, §22-pinned)
5. pin enforcement runs locally — PASS (ci-local gate 3, suite §30)
6. pin enforcement runs remotely — PASS (blocking step, 0 violations)
7. workflow permissions follow least privilege — PASS (`contents: read`)
8. pull-request workflows expose no production secrets — PASS (no secrets context)
9. no publishing action reachable from verification triggers — PASS (none exist; §22 asserts)
10. Dependabot cannot bypass review — PASS (no auto-merge; policy §8)
11. no force-push — PASS
12. no history rewritten — PASS
13. no production signing key used — PASS (throwaway fixture only)
14. no tag, release, package, image, or deployment — PASS
15. all required CI jobs remain blocking and green — PASS (4/4 on PR #2)

## External Changes

- branch protection applied: no (DOCUMENTED — NOT APPLIED, operator decision)
- integration branch deleted: no (operator decision: retain)
- tags created: no · releases published: no · packages/images published: no
- production keys used: no · deployments performed: no

## Safety Confirmation

- "main" changed: no — session branch only
- anything pushed: yes — `auto/session-10-actions-hardening` (operator-authorized)
- PR opened: yes — #2, unmerged, awaiting operator review
- history rewritten: no · force used: no · secrets accessed: no
- host GPG locks modified: no
- Copilot PR reviewer run 29234404847 is a platform review agent, not a
  repository workflow; any comments it posts are advisory triage items,
  not required checks

## Operator-Owned Follow-Ups

- PR #2 review + merge decision (merge commit per policy; do not squash);
- branch protection application when desired (`docs/MAIN_BRANCH_PROTECTION.md` §3 runbook);
- TD-3 is resolved by this session; the former bot-review hardening notes
  from PR #1 (checksum-tool trap exit, ERE escaping, README wording,
  signed-manifest design question, whitespace-gate coverage) remain queued
  as low-priority hardening, none blocking;
- production signing operationalization — still a separate workstream;
- stale `/root/.gnupg` locks — host-side, untouched.

ACTIONS HARDENED — BRANCH PROTECTION AUTHORIZATION MISSING
