# Session 10 — Post-Merge Verification Report

Verdict: **SESSION 10 MERGED — BRANCH PROTECTION APPLIED AND VERIFIED**
(protection section below; applied without `required_signatures` —
authorized deviation, key-registration finding recorded).

Date: 2026-07-13 (UTC)

## Merge

| Field | Value |
|---|---|
| PR | #2 — Harden GitHub Actions pins and main-branch protections |
| Source branch | `auto/session-10-actions-hardening` |
| Source tip | `ae2e88c410e022b3c46aeea9b2731d5e6c05641b` (`ae2e88c` — 6 session commits + 2 bot-review corrective commits) |
| Target | `main` (pre-merge `0d13047`) |
| Strategy | merge commit / `--no-ff` (local CLI merge, then push; no squash, no rebase) |
| Merge commit | `2e0e04346b3ae797c211fbe311afa0ecda626ff5` (`2e0e043`) |
| Merge commit date | 2026-07-13T08:34:48Z |
| Merged by | agent (B0LK13 account), under operator follow-up authorization |
| Merge commit GPG | signed — "Good signature from Wesley Bolk", EDDSA …240A4B |
| PR auto-closed | MERGED at 2026-07-13T08:47:16Z, `mergeCommit = 2e0e043` |
| Push | fast-forward `0d13047..2e0e043`, no force; gitleaks pre-push clean |

Merge tree is byte-identical to the verified source tip `ae2e88c`
(`git diff ae2e88c 2e0e043` empty): the tree that passed every gate is
exactly the tree on `main`.

### Pre-merge corrections (bot-review triage)

PR #2 carried two COMMENTED bot reviews; all six inline findings were
validated and fixed before merge (tip moved `1767b83 → ae2e88c`, full
local gate rerun, remote rerun green):

1. checker message prefix did not match the filename — fixed (`393f176`);
2. quoted YAML keys (`- 'uses':`) evaded the checker regex — fixed with
   §30 reject+accept regression coverage (Codex P2; `393f176`);
3. OPERATOR_COMMAND_INDEX tag→SHA command missed the annotated-tag
   dereference — documented (`ae2e88c`);
4.–6. `required_signatures=true` is not a `PUT .../protection` field;
   signed-commit enforcement uses the separate
   `POST .../protection/required_signatures` endpoint
   ([REST docs](https://docs.github.com/en/rest/branches/branch-protection))
   — runbook corrected (`ae2e88c`).

## Local verification (merge commit `2e0e043`, pre-push)

Evidence: `evidence/session-10/post-merge-*`.

| Check | Result |
|---|---|
| Suite (`bash tests/run_tests.sh`, inside ci-local) | 327 passed / 0 failed / 0 skipped |
| `scripts/ci-local.sh` | exit 0 (ALL GATES PASSED) — incl. pin gate 3 |
| Unsigned bundle verification | `verified-integrity-only`, exit 0 |
| Signed fixture (throwaway ed25519) | `verified-signed`, exit 0 |
| Reproducibility (two builds, SDE=1700000000) | byte-for-byte identical |
| Key-material scan (actual key blocks) | 0 files (naive substring variant matches only the harness §28b guard pattern — noted in scans.txt) |
| Commit signatures over `0d13047..2e0e043` | 9/9 good (8 session + merge) |
| Working tree | clean |

## Remote verification (merge commit `2e0e043`)

| Field | Value |
|---|---|
| Workflow run | 29236663421 (`tests`, trigger: push on `main`) |
| Job: suite | success, 44 s (08:47:21Z → 08:48:05Z); log: `passed: 327 failed: 0 skipped: 0` |
| Job: release-candidate-check | success, 7 s |
| Pin enforcement | `action-pin checker: repository workflows comply` (blocking step green) |
| Action SHA executed | `actions/checkout@9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0` (post-step line confirms the pin) |
| Annotations | 0 — Node 20 deprecation remains eliminated |
| Dependabot | activated by the merged config; two `Dependabot Updates` metadata runs succeeded on `2e0e043` (29236665562, 29236666099) |

## Branch protection

- authorization: operator, 2026-07-13 — **apply without
  `required_signatures`**;
- deviation rationale: the local signing key `0F8A4FD173240A4B` is not
  registered on the GitHub account (three other keys are); GitHub marks
  session commits `verified: false, reason: unknown_key`. With
  `required_signatures` on, every locally-signed push — including this
  session's evidence commits — would be rejected. Signed-commit policy
  remains enforced locally (all commits signed; harness + evidence verify);
  GitHub-side enforcement follows once the operator registers the key
  (`gh api -X POST user/gpg_keys` with the exported public key), then
  `POST .../protection/required_signatures` per the corrected runbook;
- applied settings and read-only verification: `evidence/session-10/protection-verification.txt`
  (captured after application, as the final outward action of the session —
  applying protection before the evidence pushes would lock out direct
  pushes to `main`, including the required-evidence commits).

## Publication boundary

Tags: no · Releases: no · Packages: no · Images: no · Production signing
keys: no · Deployments: no · Force-push: no · History rewritten: no ·
Secrets accessed: no.

## Security invariants (merge operation)

1. PR #2 merged without squash — PASS
2. no rebase merge — PASS
3. no history rewrite — PASS
4. no force-push — PASS
5. all Session 10 commits remain reachable (`ae2e88c` ancestor of `main`) — PASS
6. all external actions remain immutable-SHA pinned — PASS
7. pin enforcement passes locally — PASS
8. pin enforcement passes remotely — PASS
9. Node 20 annotation remains absent — PASS (0 annotations)
10. workflow token persistence remains disabled — PASS
11. required CI passed before merge — PASS (4/4 on `ae2e88c`)
12. post-merge CI passes — PASS (run 29236663421)
13. no production signing key used — PASS
14. no tag, release, package, image, or deployment — PASS
15. branch protection applied only with authorization — PASS (explicit operator decision; deviation authorized)
