# Rollback and Recovery Plan

Program-level rollback for the release-trust implementation, and recovery
procedures for the scenarios the program can hit. Session 12 (2026-07-13),
design only. This plan covers *implementation* rollback; key compromise, key
loss, and infrastructure disaster are covered by
`docs/SIGNING_RUNBOOKS.md` §5–§7 and `docs/SIGNING_ROADMAP.md` §5 — referenced,
not repeated. Promotion-level rollback rules:
`docs/BRANCH_PROMOTION_POLICY.md` §5.

---

## 1. Principles

1. **Append-only history**: rollback is `git revert` (merge commits:
   `git revert -m 1`) on a corrective branch through the normal PR path —
   never reset, never force-push (`docs/BRANCH_PROMOTION_POLICY.md` §5).
2. **Evidence is never deleted**: reverted work keeps its evidence; a
   rollback adds new evidence, it does not remove old.
3. **Integrity-only is always a valid state**: every phase can fall back to
   unsigned releases without breaking anything
   (`docs/SIGNING_KEY_LIFECYCLE.md` §7).
4. **Phases are independently revertible**: B1–B3 have no production
   consumers; B4's activation steps are operator-paced and reversible up to
   publication — and deliberately not reversed after it (§3.4).
5. **Fix-forward vs revert**: a narrow, testable defect is fixed forward
   (new signed commit); a structural defect, or one that cannot be verified
   quickly, is reverted first and reworked (`docs/BRANCH_PROMOTION_POLICY.md`
   §4 — promotion waits rather than weakening gates).

## 2. Rollback decision table

| situation | action |
|---|---|
| failing gate on a PR | fix forward on the branch; promotion waits |
| defect found post-merge, narrow and testable | fix-forward PR |
| defect found post-merge, structural or unverifiable | revert PR, then rework |
| CI dry-run flake (no product defect) | rerun; if recurrent, quarantine the step's inputs (fixture keygen, temp paths) — never mark `continue-on-error` |
| evidence re-verification false positive | investigate as a drift incident first (§4); revert the subset commit only if proven wrong |
| signed release already published | **no rollback** — §3.4 |

## 3. Per-phase rollback procedures

### 3.1 B1 (tooling)

Revert the tooling PR(s). No consumers exist before B2/B4; the suite returns
to 327 assertions. Verify: `bash tests/run_tests.sh` (327/0/0),
`bash scripts/ci-local.sh` exit 0. Contracts in the design spec remain valid
— rework resumes from them.

### 3.2 B2 (CI integration)

Revert the integration PR(s): the ad-hoc fixture sign/verify step returns as
the `release-candidate-check` coverage; `scripts/ci-local.sh` returns to
gates 1–6; enforcement scans removed. Verify remote: `suite` +
`release-candidate-check` green on the revert PR. If the dry-run defect also
affects the *verifier* (shared code path), treat as a product regression:
revert B1 as well and re-run the full matrix.

### 3.3 B3 (evidence plane)

Revert the helper + CI step. Committed `evidence/releases/` subsets are
**retained** (principle 2) even while the checker is absent; note the gap in
the revert PR. The registry template is a doc — revert freely.

### 3.4 B4 (activation) — staged

- **Before publication** (ceremony in progress): stop; revert the
  checklist-integration PR if it caused the halt; the unreleased state is
  unchanged. No evidence subset is committed without `verified-signed`
  (sequencing invariant, `docs/RELEASE_IMPLEMENTATION_BLUEPRINT.md` §4), so
  there is nothing to unpublish.
- **After a signed release is published**: there is **no rollback of the
  release itself**. A correctly signed release remains valid and trusted.
  "Rollback" means: the *next* release may ship integrity-only (documented
  emergency path), the README co-primary block may be reverted if it
  misleads, and a defective *artifact* is handled by publishing a corrected
  release and marking the bad pin-history row `unsupported`
  (`docs/BOOTSTRAP_RELEASE_PROCESS.md` §2) — not by deleting the published
  one.
- **Key compromise is not rollback**: it is incident response —
  `docs/SIGNING_RUNBOOKS.md` §5.

### 3.5 B5 (enhancements)

Each option reverts independently: stop publishing the SBOM/provenance
artifact (already-published files stay as historical artifacts, marked
informational); the OIDC revisit is a design document — abandon by decision
record, no code exists.

## 4. Recovery matrix

| scenario | immediate | git-level | communication | verification after |
|---|---|---|---|---|
| tooling regression post-merge | halt dependent work | fix-forward or revert PR | PR notes | full gate |
| dry-run defect masks real failure (RT-05) | treat as P1 planning-risk event | revert RT-05 step, restore ad-hoc cycle | session report | remote dry-run green |
| evidence re-verification fails on a committed subset | investigate as drift: rebuild referenced commit, compare | revert subset only if proven wrong; otherwise fix the release-evidence tooling | evidence-plane note in the release file | subset re-verification green |
| rehearsal failure (RT-12) | stop activation; diagnose per `docs/RELEASE_SIGNING.md` §5 verdicts | none if pre-publish | operator log | rerun ceremony after fix |
| post-publish verification mismatch (step 9 of the release checklist) | treat as potential compromise: freeze | mark row `unsupported`; investigate before any new release | release notes + project site | corrected release + independent re-verification |
| key compromise | `docs/SIGNING_RUNBOOKS.md` §5 (freeze → revoke → sweep → replace) | pin-history `unsupported` rows | independent channel | new keyring + re-signed release verify |
| key loss (no compromise) | `docs/SIGNING_RUNBOOKS.md` §6/§7 | none required | release notes if emergency-unsigned ships | restored/new identity signs next release |
| repository/account loss | `docs/SIGNING_RUNBOOKS.md` §7 table | restore from clone; no force-push | independent channel | full gate on restored repo |

## 5. Verification after any rollback

Always: `bash tests/run_tests.sh` (contract total for the reverted state),
`bash scripts/ci-local.sh` (exit 0),
`python3 scripts/check-github-action-pins.py` (0 violations), remote CI green
on the corrective PR, and a note in the session/release evidence naming the
reverted commits and the reason. Rollback is complete only when the baseline
is green again and the evidence trail names what happened.
