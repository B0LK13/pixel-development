# Session 13 Final Report — Release Dry-Run Preparation (Roadmap 0.2)

Date: 2026-07-13 (UTC)
Mandate: `reports/project-roadmap.md` Horizon 0 item 0.2 — prepare the
first signed-release dry run on a throwaway identity (build → sign →
`verified-signed` → publish checklist walkthrough + disaster-recovery
pass). **Agent prepares, operator executes.** Docs + evidence only.

## 1. Baseline

- starting branch: `auto/session-13-release-dry-run-prep` — created from
  `main` (`git switch -c auto/session-13-release-dry-run-prep main`); no
  other branch was modified during the session
- base commit: `0508a044e059db1d2d20f240f6694b44e1a02b7b` (`main`)
- initial commit count: 3 (authoring)
- final commit count: 5 — 3 authoring + this finalization commit + one
  evidence-only follow-up appending the gate-2 record to
  `evidence/session-13/final-gate-summary.txt` (corrective commits would
  replace the follow-up if the confirmation gate fails)
- commits (all GPG-signed with `0F8A4FD173240A4B`):
  - `6494af7d0e4191db60302bc19b827254ba898735` — docs(release): add
    throwaway-identity release dry-run runbook (roadmap 0.2)
  - `7877ee3596414118225839500aa758de98026a54` — docs(evidence): record
    session 13 dry-run rehearsal (verified-signed + 5 fail-closed
    scenarios)
  - `9af937243e549049c4f5b94188e5736ea2f74042` — docs(report): session 13
    final report — release dry-run preparation complete
  - this finalization commit — docs(release): finalize Horizon 0.2
    dry-run guidance (SHA recorded in the gate-2 block of
    `evidence/session-13/final-gate-summary.txt`)
  - evidence follow-up — docs(evidence): record session 13 confirmation
    gate (branch tip after gate 2)
- changed files: 5 — `docs/RELEASE_DRY_RUN.md`,
  `reports/session-13-final-report.md`,
  `evidence/session-13/baseline-record.txt`,
  `evidence/session-13/dry-run-rehearsal.txt`,
  `evidence/session-13/final-gate-summary.txt`; docs/evidence-only
  scope: no code, no tests, no workflow changes
- starting gate status: `main` @ `0508a04` green
  (`evidence/session-10/post-merge-gate-summary.txt`: 327 passed /
  0 failed / 0 skipped, ci-local exit 0); authoring-tip quick checks:
  `git diff --check` clean, 0 pin violations, `bash -n` n/a (no scripts
  touched)

## 2. What was prepared

- `docs/RELEASE_DRY_RUN.md` — the complete operator runbook:
  - §0: one scratch root under `mktemp`; **all steps run in the same
    shell session** — `WORK`/`GNUPGHOME` are shell-scoped and losing
    them is a STOP condition (restart from §0, never reconstruct)
  - §1: throwaway identity provisioning — isolated `GNUPGHOME`, ed25519,
    no passphrase, identity marked `THROWAWAY ... (NOT PRODUCTION)`,
    1-day expiry; a second throwaway key for the wrong-keyring scenario.
    The throwaway key is **mandatory**: substituting, importing, or
    referencing any production/long-lived key is prohibited, and
    discovering a production key or credential in the environment is a
    STOP condition
  - §2–4: build (`SOURCE_DATE_EPOCH`-pinned, output under `$WORK`),
    **required** signer confirmation and reproducibility comparison
    (rebuild from the same inputs; compare files, modes, digests; any
    difference = STOP), offline `gpg --detach-sign --armor` of
    `SIGNING-MANIFEST.json`, then both verifier modes —
    `verified-integrity-only` and the target `verified-signed`
  - §5: publish checklist walkthrough mirroring
    `docs/BOOTSTRAP_RELEASE_PROCESS.md` §3 — every irreversible step
    (tag, push, GitHub release, second-network digest check, fresh
    install) listed with placeholder commands and explicitly NOT
    executed
  - §6: disaster-recovery pass — DR-1 wrong artifact (genuine signature
    over the wrong file; right signature under the wrong keyring), DR-2
    tampered bundle (altered artifact / manifest / metadata), DR-3 lost
    key (destructive, runs last) — each with expected verifier output
    and the production recovery action cross-referenced to
    `docs/SIGNING_KEY_LIFECYCLE.md` §2/§5–§8
  - §7: destruction of the throwaway identity (`gpgconf --kill all`,
    `rm -rf "$WORK"`), only after verification and DR checks finish
  - closing operator-ceremony checklist and a "what this does NOT do"
    boundary (no production keys, no tags/releases/packages, no real
    publish, mechanics-only trust, no authorization to sign for
    production)

Every command is copy-pasteable and hermetic: no network, no keyservers,
no package installs, no paid agents. All state lives under one `mktemp`
root; the repository tree is untouched by the run.

- `evidence/session-13/baseline-record.txt` — date, branch, base
  commit, commands, toolchain, boundaries.
- `evidence/session-13/dry-run-rehearsal.txt` — bounded output of the
  full rehearsal (header records command + commit per
  `evidence/README.md`).
- `evidence/session-13/final-gate-summary.txt` — gate records (gate 1
  pre-finalization; gate 2 confirmation, appended after the
  finalization commit).

## 3. Rehearsal results (evidence: `evidence/session-13/dry-run-rehearsal.txt`)

The runbook was executed end to end at commit `6494af7` from the
repository root. **All expectations met:**

| step | expected | got |
|---|---|---|
| build (pinned epoch) | exit 0, 9-file bundle | exit 0 |
| rebuild-compare | byte-identical | 0 diff lines |
| unsigned verify | `verified-integrity-only` | yes, exit 0 |
| signed verify | **`verified-signed`** | **yes, exit 0** |
| DR-1a wrong artifact | `failed-signature`, exit 1 | pass |
| DR-1b wrong keyring | `failed-signature`, exit 1 | pass |
| DR-2a altered artifact | `failed-checksum`, exit 1 | pass |
| DR-2b altered manifest | `failed-signature`, exit 1 | pass |
| DR-2c altered metadata | `failed-metadata`, exit 1 | pass |
| DR-3 lost key: re-sign | impossible, exit 2 | `No secret key` |
| DR-3 lost key: old bundle | still `verified-signed` | pass |
| destruction | scratch root gone, tree clean | pass |

## 4. Defects found during rehearsal

Both defects were found by the first rehearsal pass (pre-amend authoring
commit `607d734`, superseded by `6494af7` before any push) and fixed in
the runbook before the recorded clean pass.

### Defect 1 — destructive scenario ordered first

- Defect: the disaster-recovery pass originally ran the lost-key
  scenario (DR-3, which deletes the throwaway secret key) first, in
  roadmap list order.
- Impact: with the key already destroyed, the wrong-artifact scenario
  could not create its replacement signature (the `gpg` failure was
  silenced by redirection), so the copied *original* valid signature
  verified and the scenario returned a **false `verified-signed`** — a
  mandatory negative test silently passing.
- Correction: DR-3 (destructive) runs **last**; `docs/RELEASE_DRY_RUN.md`
  §6 states the ordering rule explicitly, with the reason.
- Verification: the clean second pass executes the corrected order end
  to end; DR-1a returns `failed-signature` as required
  (`evidence/session-13/dry-run-rehearsal.txt`).
- Commit: `6494af7d0e4191db60302bc19b827254ba898735` (runbook fix);
  evidence re-recorded in `7877ee3596414118225839500aa758de98026a54`.

### Defect 2 — over-broad secret-key-listing expectation

- Defect: the DR-3 expectation claimed `gpg --list-secret-keys` produces
  no output after the key deletion.
- Impact: the documented expectation contradicts real gpg output — the
  second throwaway key (wrong-key identity) legitimately remains, so an
  operator would see an unexpected listing and either STOP on a false
  divergence or learn to disregard mismatches.
- Correction: expectation narrowed to `gpg --list-secret-keys "$KEYID"`
  → empty output for the destroyed identity specifically.
- Verification: the clean second pass records the narrowed command and
  its empty result (`evidence/session-13/dry-run-rehearsal.txt` §6-DR3).
- Commit: `6494af7d0e4191db60302bc19b827254ba898735`.

## 5. Final gates

Gate 1 — pre-finalization, commit
`9af937243e549049c4f5b94188e5736ea2f74042`
(2026-07-13T18:03:29Z → 18:23:06Z, ~19m37s):

- test suite: 327 passed / 0 failed / 0 skipped (exit 0)
- `scripts/ci-local.sh`: exit 0 — ALL GATES PASSED
- action-pin checker: 0 violations (1 workflow file, 2 uses refs)
- `git diff --check`: clean
- key-material scan: 0 markers across `docs/RELEASE_DRY_RUN.md`, this
  report, and `evidence/session-13/`
- commit signatures: all 3 authoring commits `G` (`0F8A4FD173240A4B`)
- working tree: clean

Gate 2 — confirmation on the final committed tree (run after the
finalization commit): full suite + `ci-local.sh` + pin checker +
diff-check + clean-tree. Results are appended to
`evidence/session-13/final-gate-summary.txt` as the gate-2 block and
committed by the evidence follow-up commit; raw logs in
`/tmp/s10pm/s13-final-*`. The unsigned-integrity, signed-fixture, and
reproducibility invariants are exercised by the suite itself (harness
§19/§25–§27).

## 6. Safety boundary

- Production keys used: no
- Private keys exported: no (public-key-only exports of the throwaway
  identity, destroyed in the same run)
- Secrets accessed: no
- Tags created: no
- Releases published: no
- Packages published: no
- Images published: no
- Deployments performed: no
- Force-push used: no
- History rewritten: no — final branch history is linear; one
  pre-evidence authoring commit (`607d734`) was amended into `6494af7`
  before any push (the branch has never been pushed)
- Main modified: no
- Other session branches modified: no (Sessions 10/11/12 untouched;
  Session 11/12 material cited as local-only context only — e.g.
  `docs/SIGNING_ROADMAP.md` phase 2 = the operator ceremony this dry
  run prepares for)

## 7. Operator decision

Session 13 remains local-only. Pushing the branch, opening a pull
request, merging, tagging, releasing, or publishing requires explicit
operator authorization.

When authorized:

```bash
git push -u origin auto/session-13-release-dry-run-prep
```

Suggested PR title: "Document Horizon 0.2 release dry-run procedure" —
merge-commit workflow (no squash, no rebase).

Dry-run execution handoff:

1. Review `docs/RELEASE_DRY_RUN.md` end to end; confirm the §0
   same-shell-session rule and the "what this does NOT do" boundary.
2. Execute the runbook's operator-ceremony checklist on any offline
   host with `git`, `gpg`/`gpgv`, `sha256sum`, GNU `date`/`touch`.
   Expected runtime: a few minutes.
3. Confirm the target verdicts: one `verified-signed` on the happy
   path, five fail-closed negatives, `No secret key` after key
   destruction. Every expected verdict is mandatory; any unexpected
   verdict is a STOP condition, never a workaround opportunity.
4. Record any divergence and hand it back **before** starting roadmap
   0.1 (production key provisioning).
5. Destroy the throwaway identity (§7) even if the run diverges midway.

## 8. Gaps found

- **None requiring code.** The existing scripts and suite cover every
  mechanic the dry run exercises: build gates, both verifier modes, and
  all five negative scenarios mirror harness §19/§25/§26 fixtures
  (wrong-file signature §26-s9, wrong keyring §26-s4, altered
  artifact/manifest/metadata §26-s6/s5/s7). The deliverable is docs +
  evidence only, per the mandate's preference.
- Doc-level items handled in the runbook (not gaps): scenario execution
  order and the `list-secret-keys` expectation (§4 above); the §0
  same-shell-session rule, mandatory rebuild-compare, and
  production-key-substitution prohibition added by the finalization
  commit.
