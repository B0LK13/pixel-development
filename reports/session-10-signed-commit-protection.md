# Session 10 — Signed-Commit Protection Report

Date: 2026-07-13 (UTC)
Status: COMPLETE — signatures enforced on `main`, evidence consolidated into PR #4

## Key registration

| Field | Value |
|---|---|
| Key ID | `0F8A4FD173240A4B` |
| Fingerprint | `E604658C6B8DFC4B9C735A1F0F8A4FD173240A4B` |
| Type | ed25519, created 2026-06-25, expires 2028-06-24, capability [SCA] |
| UID | Wesley Bolk &lt;wesley@bolk.dev&gt; (ultimate, local keyring) |
| GitHub registration | yes — registered by the operator via GitHub Settings → SSH and GPG keys on 2026-07-13 (~14:30Z) |
| GitHub verification | yes — commit `2e0e04346b3ae797c211fbe311afa0ecda626ff5`: REST read `verified: true, reason: valid` at 2026-07-13T14:34:02Z. The same REST endpoint can later return `verification: null` for the automation token (endpoint variability), so the token-independent source is authoritative: GraphQL `signature { isValid: true, state: VALID, keyId: 0F8A4FD173240A4B, signer: B0LK13 }`, re-confirmed 2026-07-13 |
| Registration confirmation path | GraphQL commit-signature state (authoritative, token-independent — see above). `GET /user/gpg_keys` returns 404 for the automation token (`repo` scope only; the read endpoint also requires `admin:gpg_key`); the REST commit-verification block passed at registration time but varies by token |
| Private key exported | no — public-key-only export; grep for `PRIVATE KEY` / `SECRET KEY` clean before every use |
| Temporary export | `/tmp/github-signing-public-key.asc` deleted 2026-07-13 (~14:36Z) after registration + verification + enforcement all confirmed; absence verified (`test ! -e`) |

## Protection update

| Field | Value |
|---|---|
| Required signatures before | disabled |
| Required signatures after | **enabled** — `POST /repos/B0LK13/pixel-development/branches/main/protection/required_signatures`, 2026-07-13 (~14:35Z) |
| API endpoint | `POST /repos/B0LK13/pixel-development/branches/main/protection/required_signatures` (corrected runbook endpoint, bot-review finding from PR #2) |
| Verification result | `GET` returns `enabled: true`; revalidated on every 13-minute watcher tick since enablement, no drift |
| Unrelated protection drift | none — full re-read after enablement matched every prior setting |

Full protection state on `main` after enablement (verified 2026-07-13):

- required status checks: `suite`, `release-candidate-check` — strict: true
- required approvals: 1
- conversation resolution: required
- administrator enforcement: enabled
- force-push: disabled
- branch deletion: disabled
- linear history: disabled (merge commits preserved)
- required signatures: **enabled**

## Enforcement recognition

- signed commit recognized by GitHub: yes — merge commit `2e0e043` (`verified: true, reason: valid`); no ceremonial commit was needed
- signed PR merge eligibility: not exercised end-to-end — PR #3 was closed unmerged by operator decision (2026-07-13T15:42:57Z) before an independent approval was submitted. Its content is consolidated into this evidence PR (#4) instead; see below.
- unsigned test disposition: not performed as a live negative test — GitHub's documented behavior (unverified commits cannot be pushed to a required-signatures branch; web/API merges remain GitHub-signed) is recorded instead, per the mandate's read-only preference
- required checks retained: yes (`suite`, `release-candidate-check`, strict)
- approval rule retained: yes (1 approval, conversation resolution, enforce_admins)

## PR #3 disposition

| Field | Value |
|---|---|
| PR | #3 — "Record main branch-protection application (docs-only, first protected-flow PR)" |
| Head | `b8fd2c721292db50d5c9994282e65a3173da3ecf` (branch `auto/session-10-protection-evidence`, retained on origin) |
| Checks | 4/4 green at closure (`suite`, `release-candidate-check` ×2 triggers) |
| Approval | none — only review was `copilot-pull-request-reviewer` (COMMENTED; does not count) |
| Disposition | **closed unmerged by the operator** (B0LK13), 2026-07-13T15:42:57Z |
| Content preservation | its single commit (adds `evidence/session-10/protection-verification.txt`, 56 lines) cherry-picked into this branch as `4c48e87` (signed) — no evidence lost |
| Local tests at base | 327 passed / 0 failed / 0 skipped on `0508a04` (see `evidence/session-10/post-merge-gate-summary.txt`) |
| ci-local at base | exit 0, ALL GATES PASSED (see `evidence/session-10/post-merge-ci-local.log`) |
| Remote runs at base | 29236663421 (`2e0e043`) green; 29236874256 (`0508a04`) green |

## Security boundaries

- private key uploaded: **no**
- private key committed: **no**
- public key committed to the repository: no (registration metadata only; no armored key in evidence)
- production release signing configured: **no** — separate workstream (see Session 11 architecture, `auto/session-11-signing-architecture`)
- tags created: **no**
- releases published: **no**
- packages/images published: **no**
- deployments: **no**
- force-push: **no**
- history rewritten: **no**
- protection bypassed: **no** — no `--admin`, no approval-count changes, no check removal, enforce_admins never disabled
