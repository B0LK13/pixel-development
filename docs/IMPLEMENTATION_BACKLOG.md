# Implementation Backlog — Release Trust Program

Execution backlog for the production release-trust program. Session 12
(2026-07-13), design only: no task here has been started; this document
sequences them. Architecture: `docs/PRODUCTION_SIGNING_ARCHITECTURE.md`;
contracts: `docs/superpowers/specs/2026-07-13-production-signing-architecture-design.md`
("the design spec"); phasing: `docs/RELEASE_PIPELINE_PHASES.md`; acceptance
detail: `docs/RELEASE_ACCEPTANCE_CRITERIA.md`.

Priorities: **P1** required for the first signed release · **P2** should land
with it · **P3** valuable, not blocking · **P4** optional/future · **PG**
operator-gated (requires an operator decision or key ceremony).

Phases: **B1** signing-session tooling · **B2** CI integration · **B3**
evidence plane · **B4** release activation · **B5** trust enhancements.

---

## Task table

| ID | phase | task | depends on | priority | acceptance |
|---|---|---|---|---|---|
| RT-01 | B1 | `scripts/prepare-signing-session.sh` | — | P1 | AC-B1 |
| RT-02 | B1 | `scripts/record-signing-evidence.sh` + schema validation | RT-01 | P1 | AC-B1 |
| RT-03 | B1 | harness sections: protocol fixtures, refusals, schema, isolation | RT-01, RT-02 | P1 | AC-B1 |
| RT-04 | B1 | docs: command index + `docs/RELEASE_SIGNING.md` §3 pointer | RT-01–RT-03 | P2 | AC-B1 |
| RT-05 | B2 | fixture dry-run step in `release-candidate-check` | RT-01–RT-03 | P1 | AC-B2 |
| RT-06 | B2 | enforcement tests: no secrets / no non-fixture signing in workflows | RT-03 | P1 | AC-B2 |
| RT-07 | B2 | `scripts/ci-local.sh` + workflow parity for the new gates | RT-05, RT-06 | P1 | AC-B2 |
| RT-08 | B3 | `evidence/releases/<version>/` convention + CI re-verification of committed public subsets | RT-02 | P2 | AC-B3 |
| RT-09 | B3 | operator registry template (clearly-marked operator doc) | — | P3 | AC-B3 |
| RT-10 | B4 | release-checklist integration (`docs/BOOTSTRAP_RELEASE_PROCESS.md` §3) | RT-01–RT-03 | P2 | AC-B4 |
| RT-11 | B4 | key ceremony execution (Phase 1) | operator | PG | AC-B4 |
| RT-12 | B4 | first signed release rehearsal (re-sign current release) | RT-10, RT-11 | PG | AC-B4 |
| RT-13 | B4 | README tier-2 co-primary block (ADR migration step 5) | RT-12 | PG | AC-B4 |
| RT-14 | B5 | SPDX 2.3 SBOM view of the release manifest | — | P3 | AC-B5 |
| RT-15 | B5 | signed provenance statement evaluation (SLSA L2 direction) | RT-14 | P4 | AC-B5 |
| RT-16 | B5 | OIDC/keyless feasibility revisit | operator decision | P4 | AC-B5 |

## Dependency graph

```
RT-01 ──► RT-02 ──► RT-03 ──► RT-05 ──► RT-07
  │         │         │         ▲
  │         │         ├────────►│ RT-06 ──► RT-07
  │         │         └─► RT-04 │
  │         └─► RT-08           │
  └────────► RT-10 ──► RT-12 ──► RT-13      RT-11 (operator) ──► RT-12
RT-09 (independent)                          RT-14 ──► RT-15
                                             RT-16 (operator decision)
```

Critical path to the first signed release:
`RT-01 → RT-02 → RT-03 → RT-10 → RT-11 → RT-12 → RT-13`, with RT-05–RT-07
(CI integration) required before RT-12 so the dry-run protects the ceremony.

## Task details

### B1 — Signing-session tooling (build session; no secrets)

**RT-01 `scripts/prepare-signing-session.sh`** — contract: design spec §6.2.
Preconditions (clean tree, `HEAD` == `--commit`, `VERSION` agreement,
toolchain present), reproducible build with `SOURCE_DATE_EPOCH` from the
release commit, prints manifest digest + exact sign command. Writes nothing
outside the build output. *Acceptance*: AC-B1 items 1–4. *Rollback*: delete
the script; no consumers exist before RT-04/RT-05.

**RT-02 `scripts/record-signing-evidence.sh`** — contract: design spec §6.2;
schema v1 per §6.2 (public subset + operator-held full record). Re-verifies
with `--require-signature`, checks `--expect-fingerprint`, atomic evidence
writes, `--fixture` mode deriving keyring from `$PIXEL_FIXTURE_GNUPGHOME`.
*Acceptance*: AC-B1 items 5–9. *Rollback*: delete script + schema doc
section; no evidence exists before B4.

**RT-03 harness sections** — new `tests/run_tests.sh` §-numbered sections per
design spec §12: fixture happy path (`verified-signed` + valid evidence),
prepare refusals (dirty tree / wrong commit / version mismatch / missing
tool), record refusals (`failed-policy` / `failed-signature` / fingerprint
mismatch / `failed-checksum`), schema validation, public-subset cleanliness,
real-`GNUPGHOME` isolation. New tests add to the authoritative count (327);
record the new total. *Acceptance*: AC-B1 items 10–11. *Rollback*: remove the
sections; count returns to 327.

**RT-04 docs** — rows in `docs/OPERATOR_COMMAND_INDEX.md`; pointer in
`docs/RELEASE_SIGNING.md` §3 to the tooling (manual procedure stays valid as
fallback); harness §28a strings preserved. *Acceptance*: AC-B1 item 12.

### B2 — CI integration (build session)

**RT-05 fixture dry-run** — a step in the existing `release-candidate-check`
job: RT-01 prepare → generate throwaway key in isolated temp `GNUPGHOME` →
fixture sign → RT-02 record → assert `verified-signed` + schema validity
(design spec §7). No secrets; `contents: read` unchanged. *Acceptance*:
AC-B2 items 1–3.

**RT-06 enforcement tests** — suite assertions that `.github/workflows/`
contains no signing-secret reference and no non-fixture `gpg --detach-sign`
(design spec §7; capstone §5.3). *Acceptance*: AC-B2 item 4.

**RT-07 parity** — `scripts/ci-local.sh` gains the new gates in the same order
as the workflow; CI-parity harness section updated so gate lists stay in
lockstep. *Acceptance*: AC-B2 item 5.

### B3 — Evidence plane

**RT-08 evidence convention** — `evidence/releases/<version>/SIGNING-EVIDENCE.json`
public subsets; CI re-verifies committed subsets against the referenced
release commits (attestational drift detector; capstone §7.2, design spec §8).
*Acceptance*: AC-B3 items 1–3. *Note*: no subset exists before B4 — the CI
check must pass vacuously when the directory is empty.

**RT-09 registry template** — `docs/SIGNING_KEY_LIFECYCLE.md` §3 requires an
operator-held authorized-signer list; provide a clearly-marked template
(operator doc, no fingerprint asserted as trusted). *Acceptance*: AC-B3
item 4.

### B4 — Release activation (operator-gated)

**RT-10 checklist integration** — `docs/BOOTSTRAP_RELEASE_PROCESS.md` §3 steps
3–4 switch from manual commands to RT-01/RT-02 with the manual equivalents
kept as fallback (runbook §2). *Acceptance*: AC-B4 item 1.

**RT-11 key ceremony** — operator executes `docs/SIGNING_RUNBOOKS.md` §1
(offline generation, backups + restore test, revocation certificate,
registry, independent-channel publication). Design only here. *Acceptance*:
AC-B4 items 2–3 (operator-attested).

**RT-12 first signed release rehearsal** — re-sign the *current* release (no
new version) end-to-end; commit the public evidence subset; verify from an
independent machine (`verified-signed`). *Acceptance*: AC-B4 items 4–6.

**RT-13 README tier-2 co-primary** — ADR migration plan step 5: the README
gains the signature-verification block as co-primary; harness §18 pin tests
must stay green. *Acceptance*: AC-B4 item 7.

### B5 — Trust enhancements (optional)

**RT-14 SPDX SBOM** — standards-formatted view of the existing manifest
(capstone §6.2); informational only until signed (threat S7). *Acceptance*:
AC-B5 item 1.

**RT-15 signed provenance** — evaluation + design for operator-signed
provenance statements (SLSA L2 direction, capstone §6.3). *Acceptance*:
AC-B5 item 2.

**RT-16 OIDC/keyless revisit** — only if the operator reverses the
no-automatic-signing rule (`docs/SIGNING_KEY_LIFECYCLE.md` §9); design
already captured (capstone §5.2, design spec §13). *Acceptance*: AC-B5
item 3.

## Standing rules for every task

- Signed commits; task branches → PR → protected merge
  (`docs/BRANCH_PROMOTION_POLICY.md`).
- Full local gate after every material change: `bash tests/run_tests.sh`,
  `bash scripts/ci-local.sh`, `python3 scripts/check-github-action-pins.py`.
- No production key material, secrets, publishing, or release-behavior change
  in B1–B3; B4 activation steps are operator-executed by design.
- Rollback for every task is a normal PR revert unless noted;
  `docs/ROLLBACK_AND_RECOVERY_PLAN.md` covers program-level rollback.
