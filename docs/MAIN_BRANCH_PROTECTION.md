# Main Branch Protection

Recommended branch-protection configuration for `main`, formalizing the
recommendations in `docs/BRANCH_PROMOTION_POLICY.md` §6. Applying these
settings is an outward-facing repository change and remains
**operator-owned** — session 10 documents but does not apply them without
explicit authorization.

## 1. Required status checks

Extracted from the real green runs on the merged Sessions 1–9 tip
(workflow `tests`, run 29230870085 on `b106b35`; check names are the
**job names** in `.github/workflows/test.yml`):

| required check | what it proves |
|---|---|
| `suite` | whitespace gate, checksum lockstep, action-pin enforcement, shellcheck, full hermetic suite |
| `release-candidate-check` | fixture release build, unsigned + throwaway-signed verification, reproducibility |

Neither check publishes, tags, signs with a real identity, or mutates the
repository. Both must be **required** and **blocking**; neither may be
marked optional or `continue-on-error`.

"Require branches to be up to date before merging" must be enabled so a
stale PR cannot merge on old CI results.

## 2. Recommended settings

| setting | value | rationale |
|---|---|---|
| Require a pull request before merging | on | `main` is canonical; every change arrives as a PR and passes the automated gate (§7) |
| Required approvals | 0 (single-maintainer mode, §7) | no second-account reviewer exists; automated controls are the merge gate — restore ≥1 when a second maintainer joins |
| Require review from Code Owners | off | no CODEOWNERS; single-operator repo |
| Require status checks to pass | on | `suite`, `release-candidate-check` (§1) |
| Require branches to be up to date | on | no merging on stale CI |
| Require conversation resolution | on | review trail cannot be left dangling |
| Require signed commits | on | matches repository policy — all commits are GPG-signed |
| Require linear history | **off** | mandatory `--no-ff` merge commits are the audit trail; linear history would forbid them |
| Require deployments to succeed | off | no deployments exist |
| Lock branch | off | merges must remain possible |
| Do not allow bypassing the above settings | on (operator decision) | applies rules to administrators too |
| Allow force pushes | **off** | history is never rewritten |
| Allow deletions | **off** | `main` is never deleted |

Merge methods: keep **merge commits enabled**. Squash and rebase merging
may stay available for ordinary single-commit PRs, but session-integration
PRs must use merge commits (policy §3); do not enforce squash-only.

## 3. Application (operator runbook)

Capture current settings first:

```sh
gh api repos/B0LK13/pixel-development/branches/main/protection
```

Apply (classic branch protection via the REST API). Signed-commit
enforcement is a **separate endpoint** — the `PUT .../protection` body has
no `required_signatures` field
([REST docs](https://docs.github.com/en/rest/branches/branch-protection)):

```sh
gh api -X PUT repos/B0LK13/pixel-development/branches/main/protection \
  -F required_status_checks[strict]=true \
  -F 'required_status_checks[checks][][context]=suite' \
  -F 'required_status_checks[checks][][context]=release-candidate-check' \
  -F enforce_admins=true \
  -F required_pull_request_reviews[required_approving_review_count]=1 \
  -F required_pull_request_reviews[require_last_push_approval]=false \
  -F required_conversation_resolution=true \
  -F required_linear_history=false \
  -F allow_force_pushes=false \
  -F allow_deletions=false \
  -F restrictions=null

# signed-commit requirement — separate endpoint, after protection exists:
gh api -X POST repos/B0LK13/pixel-development/branches/main/protection/required_signatures
```

Adjust `enforce_admins` and the signed-commit endpoint only by explicit
operator decision. Note: required signatures reject any commit GitHub
cannot verify against a known key — ensure the operator's signing key is
registered with GitHub first (`gh api users/<user>/gpg_keys`), or web-flow
merges will fail.

## 4. Verification after applying

Read-only checks only — never test protection by destructive pushes:

```sh
gh api repos/B0LK13/pixel-development/branches/main/protection \
  --jq '{checks: [.required_status_checks.checks[].context],
         strict: .required_status_checks.strict,
         admins: .enforce_admins.enabled,
         signatures: .required_signatures.enabled,
         linear: .required_linear_history.enabled,
         force: .allow_force_pushes.enabled,
         deletion: .allow_deletions.enabled}'
```

Expected: checks `suite` + `release-candidate-check`, strict true, force
false, deletion false, linear false.

Then confirm on the next ordinary PR that:

- the two required checks appear and gate the merge button;
- "Create a merge commit" remains available;
- the merge queue / update-branch requirement triggers on stale PRs.

## 5. Failure and rollback

If a protection setting breaks the documented promotion flow (e.g.
`required_signatures` blocking a legitimate merge path), the operator
relaxes exactly that setting via the same API and records the change in
the session evidence. Protection changes are configuration, not code —
they are rolled back by re-applying the previous configuration, never by
rewriting history.

## 6. Status

- 2026-07-13: protection **applied** (session 10; evidence
  `evidence/session-10/protection-verification.txt`).
- 2026-07-13: required signed commits **enabled** (separate endpoint;
  `evidence/session-10/protection-verification.txt`).
- 2026-07-13: **Single-Maintainer Operating Mode adopted** (§7):
  required approvals 1 → 0, all other settings verified unchanged by
  deep diff (`evidence/session-10/protection-change-single-maintainer.txt`).

## 7. Single-Maintainer Operating Mode

Adopted by explicit operator decision on 2026-07-13.

**Why:** this repository is operated by a single maintainer. Requiring
approval from a second GitHub account creates a permanent deadlock
rather than a meaningful control: Session 10's PR #3 was closed
unmerged for want of an independent approver, and PR #4 sat blocked
solely on `REVIEW_REQUIRED` with every check green. The setting now
matches `docs/BRANCH_PROMOTION_POLICY.md` §6's long-standing intent
("no required approvals count imposed by tooling — the operator is the
reviewer").

**Setting:** `required_approving_review_count: 0`. Nothing else
changed — verified by a field-level diff of the protection state
before/after (`evidence/session-10/protection-change-single-maintainer.txt`).

**Compensating controls (all remain mandatory):**

- required checks `suite` + `release-candidate-check`, strict mode
  (branches must be up to date before merging);
- required signed commits, recognized by GitHub;
- required conversation resolution;
- administrator enforcement (`enforce_admins`) — the operator cannot
  bypass the gate either;
- force-push and branch deletion disabled;
- merge-commit history preserved (no squash/rebase of session chains);
- immutable GitHub Action pins, enforced locally and in CI;
- reproducibility and release-verification gates inside the required
  checks;
- key-material scans inside the suite.

**Scope limit:** this mode covers source/documentation PR merging only.
It does not authorize production release signing, tags, releases,
packages, images, deployments, key rotation, secret changes,
force-pushes, or merging with failing checks — those remain
operator-gated ceremonies with their own approval requirements.

**Restoring independent review:** set the approval count back to ≥1
when a trusted second maintainer joins, the repository moves to an
organization with a reviewer team, production release signing begins,
publication/deployment workflows are introduced, or regulation or
client terms require separation of duties. Until then, the automated
controls above are the primary merge gate.
