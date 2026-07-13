# Session 9 — Post-Merge Verification Report

Verdict: **SESSIONS 1–9 MERGED — MAIN VERIFIED LOCALLY AND REMOTELY**

Date: 2026-07-13 (UTC)

---

## Merge

| Field | Value |
|---|---|
| PR | #1 — Integrate autonomous readiness sessions 1–8 |
| Source branch | `auto/integrate-session-8` |
| Source tip | `78e8261a99e47ad55a80b19f4dadd084aadd1bbd` (`78e8261`) |
| Target | `main` (pre-merge `bf8109c`) |
| Strategy | merge commit / `--no-ff` (local CLI merge, then push; no GitHub squash/rebase path used) |
| Merge commit | `b106b3539958b5fa8226d445e782ded44705e0d4` (`b106b35`) |
| Merge commit date | 2026-07-13T06:39:33Z |
| Merged by | agent (B0LK13 account), under operator follow-up authorization |
| Merge commit GPG | signed; "Good signature from Wesley Bolk &lt;wesley@bolk.dev&gt;", EDDSA key …240A4B |
| PR auto-closed | MERGED at 2026-07-13T07:04:33Z, `mergeCommit = b106b35` (GitHub recognized the pushed merge) |
| Push | `git push origin main`, fast-forward `bf8109c..b106b35`, no force; gitleaks pre-push scan clean |

The merge tree is byte-identical to the verified source tip `78e8261` (`git diff 78e8261 b106b35` empty), so the tree that passed every Session 9 gate is exactly the tree now on `main`.

## Local verification (merge commit `b106b35`, pre-push)

Evidence: `evidence/session-9/post-merge-test-results.txt`, `post-merge-ci-parity.txt`, `post-merge-gate-summary.txt`, `post-merge-release-validation.txt`, `post-merge-reproducibility.txt`.

| Check | Result |
|---|---|
| Verification suite (`bash tests/run_tests.sh`) | 310 passed / 0 failed / 0 skipped, rc=0 (692 s) |
| Local parity (`./ci-local.sh`) | exit 0 (529 s) |
| Unsigned bundle verification | `verified-integrity-only`, exit 0 |
| Signed fixture verification (throwaway ed25519 key) | `verified-signed`, exit 0 |
| Reproducibility (two builds, `SOURCE_DATE_EPOCH=1700000000`) | byte-for-byte identical (10 entries; diff empty, modes same, per-file sha256 same) |
| Key-material scan | 0 files |
| Commit signatures over `bf8109c..main` | 131/131 good (includes the merge commit) |
| Shallow-checkout refusal (§22 regression pin) | gate runs on a full clone; shallow environments are rejected by §22 |
| Working tree at gate completion | clean except the untracked evidence files recorded here |

Durations are this-host measurements on a throttled devbox; no performance claim is made.

## Remote verification (merge commit `b106b35`)

| Field | Value |
|---|---|
| Workflow run | 29230870085 (`tests`, trigger: `push` on `main`) |
| Commit | `b106b3539958b5fa8226d445e782ded44705e0d4` |
| Job: suite | success, 41 s (07:04:39Z → 07:05:20Z); suite log: `passed: 310 failed: 0 skipped: 0` |
| Job: release-candidate-check | success, 7 s; build → unsigned verify → reproducibility → throwaway-key signed verify |
| Annotations | one: Node.js 20 deprecation for `actions/checkout@v4` (forced onto Node 24). Known, non-blocking; tracked as TD-3 follow-up |
| Blockers | none |

The PR-head runs (Session 9, tip `78e8261`) were 4/4 green; this run additionally proves the merge commit itself on `main`.

## Audit preservation

- All session commits remain individually reachable: `git merge-base --is-ancestor 78e8261 main` → yes; full chain `e4304d5 → … → 78e8261 → b106b35` intact.
- No squash: the 129 signed commits of the integration chain plus the Session 9 fixes are all in `main` ancestry.
- No rebase: commit identities unchanged; the merge commit is the only new object on the integration line.
- No history rewritten; no force-push (`bf8109c..b106b35` fast-forward push accepted normally).
- Integration branch `auto/integrate-session-8` retained locally and remotely; deletion requires operator authorization (Phase 11).
- Rollback readiness: per `docs/BRANCH_PROMOTION_POLICY.md`, rollback would be `git revert -m 1 b106b35` — never reset/force-push.

## Bot-review dispositions (PR #1, both reviews COMMENTED, non-blocking)

1. `update-bootstrap-checksums.sh:46` — INT/TERM traps do not exit after cleanup. Deferred hardening item for the TD-3 governance workstream; not exercised by CI (script is operator-run).
2. `update-bootstrap-checksums.sh:129` — unescaped ERE artifact names in `rewrite_embedded`. Deferred hardening; current artifact names contain no ERE metacharacters.
3. `README.md:45` — verifier-availability wording. Documentation clarity item; deferred.
4. Codex P1 — `build-release-candidate.sh:97` "bind operator docs into signed manifest". Design proposal; the current 9-file allowlist is deliberate per `BOOTSTRAP_RELEASE_PROCESS.md`. Requires operator design decision, not a defect.
5. Codex P2 — `test.yml:36` whitespace gate is a no-op on clean CI checkouts. Intentional defense-in-depth for local runs; no action.

None amend the technical-debt register this session; all five are queued as TD-3 candidates.

## Publication boundary

| Action | Occurred |
|---|---|
| Tags created | no |
| Releases published | no |
| Packages published | no |
| Images published | no |
| Production signing keys used | no (throwaway ed25519 fixture key only, discarded) |
| Deployments performed | no |
| Force-push | no |
| History rewritten | no |
| Secrets accessed | no |
| Host-side `/root/.gnupg` stale locks touched | no |

## Security invariants (merge operation)

1. PR #1 merged without squash — PASS
2. No history rewritten — PASS
3. No force-push — PASS
4. All required CI green before merge — PASS (PR-head runs 4/4 green at `78e8261`)
5. Post-merge CI green — PASS (run 29230870085 on `b106b35`)
6. All session commits remain reachable — PASS
7. All commits remain signed — PASS (131/131 over `bf8109c..main`)
8. Key-material scan remains zero — PASS
9. No production key used — PASS
10. No tag created — PASS
11. No release published — PASS
12. No package or image published — PASS
13. No deployment performed — PASS
14. Branch protection not bypassed — PASS (no protection rules existed; merge followed the documented promotion policy)
15. Rollback uses `revert -m 1`, not reset — PASS (documented in `docs/BRANCH_PROMOTION_POLICY.md`)

## Operator-owned follow-ups

- **TD-3 — GitHub Actions pinning policy**: workflows pin `actions/checkout@v4` by major-version tag; the Node 20 deprecation annotation is now visible on every run. Decide pinning model (SHA / major tag / allowlist / update tooling) in a separate reviewed change.
- **Branch protection**: apply `docs/BRANCH_PROMOTION_POLICY.md` §6 recommendations (require PRs, blocking checks, up-to-date branch, no force-push, no deletion of `main`).
- **Production signing operationalization**: separate owner-approved workstream; untouched here.
- **Stale GPG locks**: `/root/.gnupg/.#lk*` files remain host-side; optional cleanup via `gpgconf --kill all` + manual inspection.
- **Integration branch deletion**: `auto/integrate-session-8` retained; delete (local + remote) only when the operator authorizes.

---

SESSIONS 1–9 MERGED — MAIN VERIFIED LOCALLY AND REMOTELY
