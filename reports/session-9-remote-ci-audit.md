# Session 9 — Remote CI Audit

Evidence: `evidence/session-9/remote-config.txt`, `workflow-inventory.txt`,
`static-validation.txt`, `starting-graph.txt`.

## 1. Remote topology

- origin: `https://github.com/B0LK13/pixel-development` (public; gh identity
  B0LK13, admin; token scopes gist/read:org/repo/workflow).
- Remote refs: exactly one — `main` @ `bf8109c` ("feat: pixel-development
  v1.0.0"). No `auto/*` branches, no tags, no `.github/` directory.
- Local `main` (`711c23b`) is 36 commits ahead of remote main; the integration
  branch (`6497257`) is a further 89 ahead — 125 commits total, strictly linear
  ancestry (remote main is an ancestor of local main). No divergence; no force
  operation is needed or permitted.
- Branch protection: none on `main` (404 from the API). Recommendations are in
  `docs/BRANCH_PROMOTION_POLICY.md` §6 — changing protection is operator-owned.

## 2. Workflow inventory (`.github/workflows/test.yml` — the only workflow)

- Triggers: push to `main` + `auto/*`; `pull_request` unfiltered.
- Permissions: `contents: read` top-level, inherited by both jobs.
- Concurrency: one run per ref, stale runs cancelled.
- Secrets: none referenced. Artifacts: none uploaded.
- Job `suite` (10 min): checkout@v4, apt shellcheck, `git diff --check`,
  checksum lockstep, full suite. Local mirror: `bash scripts/ci-local.sh`.
- Job `release-candidate-check` (5 min): fixture RC build (version 0.0.0
  reserved, SDE=0), unsigned verify + verdict grep, second build + `diff -r`,
  throwaway ed25519 key + signed verify + verdict grep. Local mirror: the
  session evidence-capture procedure (fixture clones, same commands).
- Publication-capable workflows: **none exist**. Nothing tags, releases,
  uploads, signs with a real identity, or mutates the repository.

## 3. Static validation (Phase 4)

- YAML parses; both jobs well-formed; `checkout@v4` used without inputs.
- All six script invocation sites use equals-form flags (session-8 fix
  `66aedb9`, pinned by harness §22 — a regression fails the local gate).
- All quoting sound; Linux-only runner assumptions match `ubuntu-latest`.
- Every remote check has a local reproduction path (parity matrix in
  `evidence/session-9/static-validation.txt`).

## 4. Runner-environment risks (classified, not pre-emptively changed)

- **R1 shellcheck drift (low)**: local 0.11.0 vs ubuntu-24.04 apt 0.9.x — older
  on the runner, i.e. a subset of local warnings. Same `-S warning` threshold.
- **R2 suite timeout (medium, watch)**: job timeout 10 min vs 578–863 s for the
  full suite on the throttled devbox. Unthrottled runner should be far under,
  but this is the workflow's *first ever* remote execution — observe the actual
  run before any threshold discussion (mandate: evidence before performance
  changes).
- **R3 release job timeout (low)**: 5 min vs ~2–3 min local throttled.
- **R4 first-run novelty (unknown)**: no `.github/` exists on remote main; the
  workflow has never run on GitHub infrastructure.

## 5. PR-safety review (Phase 6)

The workflow already satisfies every hardening requirement: least-privilege
token, no secrets, no publication steps, bounded timeouts, stale-run
cancellation, fixture-only signing identity, equals-only CLI contracts.
`pull_request` runs PR code with a read-only token and no secrets — the standard
safe pattern. **No corrections applied** (mandate: narrowest safe change; none
was needed).

## 6. TD-3 exposure note (operator-owned, unchanged)

`actions/checkout@v4` is pinned by major-version tag, not commit SHA. Exposure:
a compromised or re-pointed `v4` tag would execute in the job context — impact
bounded by `contents: read` and zero secrets, but a malicious action could still
alter checked-out content *within* a run and produce misleading green checks.
Options (SHA pin / tag pin / allowlist / dependabot policy) and the decision
remain with the operator; this session changes nothing.

## 7. Verdict

Remote topology and workflow are **ready for a push/PR trial**: strictly
ahead-only ancestry, no remote conflicts, no publication-capable automation,
full local parity for every remote check. Push requires explicit operator
authorization (Session 9 Phase 7).
