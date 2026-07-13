# Release Implementation Blueprint

Master blueprint for converting the Session 11 production signing
architecture into a working release-trust program. Session 12 (2026-07-13),
design only: this document changes no behavior; it sequences the work that
would. Architecture is referenced by path, not repeated:
`docs/PRODUCTION_SIGNING_ARCHITECTURE.md` (capstone),
`docs/SIGNING_TRUST_MODEL.md`, `docs/SIGNING_THREAT_MODEL.md`,
`docs/SIGNING_RUNBOOKS.md`, `docs/SIGNING_ROADMAP.md`,
`docs/SIGNING_KEY_LIFECYCLE.md`, and the contracts in
`docs/superpowers/specs/2026-07-13-production-signing-architecture-design.md`.

Companion execution documents: `docs/IMPLEMENTATION_BACKLOG.md` (tasks,
dependencies, priorities), `docs/RELEASE_PIPELINE_PHASES.md` (phase detail),
`docs/CI_SIGNING_INTEGRATION_PLAN.md` (CI design), `docs/RELEASE_ACCEPTANCE_CRITERIA.md`
(acceptance), `docs/ROLLBACK_AND_RECOVERY_PLAN.md` (rollback).

---

## 1. Program goal and shape

Move releases from integrity-verified (`verified-integrity-only`) to fully
trusted (`verified-signed` against an independently distributed key) **without
a flag day**: every step is additive, integrity-only releases remain valid
throughout (`docs/SIGNING_KEY_LIFECYCLE.md` §7), and the operator's offline
signature is the only new trust root (`docs/SIGNING_TRUST_MODEL.md` §1).

Five phases (detailed in `docs/RELEASE_PIPELINE_PHASES.md`):

| phase | name | owner | activation |
|---|---|---|---|
| B1 | signing-session tooling | build session | autonomous, no secrets |
| B2 | CI integration | build session | autonomous, no secrets |
| B3 | evidence plane | build session | autonomous, no secrets |
| B4 | release activation | operator | key ceremony + first signed release |
| B5 | trust enhancements | operator decision | optional (SBOM, provenance, OIDC revisit) |

B1–B3 are ordinary development work (the "build session" recommended in
`docs/SIGNING_ROADMAP.md` §3); B4 is operator-executed; B5 is optional.

## 2. Repository changes required

| phase | new files | modified files |
|---|---|---|
| B1 | `scripts/prepare-signing-session.sh`, `scripts/record-signing-evidence.sh` | `tests/run_tests.sh` (new sections), `docs/OPERATOR_COMMAND_INDEX.md`, `docs/RELEASE_SIGNING.md` §3 (pointer only) |
| B2 | — | `.github/workflows/test.yml` (fixture dry-run step in `release-candidate-check`), `scripts/ci-local.sh` (new gates), `tests/run_tests.sh` (enforcement + parity) |
| B3 | `evidence/releases/` (convention; empty until B4), operator registry template doc | `.github/workflows/test.yml` (subset re-verification step), `docs/SIGNING_KEY_LIFECYCLE.md` §3 (template pointer) |
| B4 | `evidence/releases/<version>/signing-evidence.json` (first real subset) | `docs/BOOTSTRAP_RELEASE_PROCESS.md` §3 (checklist integration), README §1 (tier-2 co-primary block) |
| B5 | SBOM artifact (generated), provenance statement (design-dependent) | release process docs as needed |

Every modified file has harness coverage to respect: §16 lockstep, §18 README
pin, §28 doc contracts, §29b script-path references, §30 action pins — see
`docs/RELEASE_ACCEPTANCE_CRITERIA.md` for the per-phase gate list.

## 3. Release pipeline integration

Today (`docs/BOOTSTRAP_RELEASE_PROCESS.md` §3): build → verify
(unsigned + fixture-signed) → review → release commit → tag → publish →
post-publish verification. The blueprint inserts signing at exactly one
point — between *release commit* and *tag* — and adds evidence recording:

```
build ─► verify (unsigned + fixture) ─► review ─► release commit
                                                     │
              NEW: prepare (rebuild-and-compare) ◄───┘
                     │ operator-only from here
                     ▼
              sign (human, offline) ─► verify (verified-signed)
                     │
                     ▼
              record evidence (public subset committed) ─► tag ─► publish
                                                                 │
              NEW: post-publish signed verification (independent machine)
```

The pipeline before the release commit is unchanged; CI continues to run the
fixture dry-run (B2) so the ceremony path is exercised on every PR. No
existing gate is weakened or reordered (`docs/BRANCH_PROMOTION_POLICY.md` §4).

## 4. Signing workflow sequencing

Actors: **builder** (CI or operator), **signer** (operator, offline), and
**publisher** (operator). Sequence per release (procedure:
`docs/SIGNING_RUNBOOKS.md` §2; tooling contracts: design spec §6.2):

1. *Prepare* — `scripts/prepare-signing-session.sh --version=X.Y.Z` on the
   signing host: preconditions → reproducible rebuild → manifest digest.
   Handoff artifact: bundle + printed digest.
2. *Compare* — if a reference bundle exists (e.g. from CI), byte-compare;
   sign only the locally reproduced manifest (threat T1/T2).
3. *Sign* — human runs `gpg --detach-sign --armor` (the only manual
   cryptographic act; tooling never sees key or passphrase).
4. *Verify* — `scripts/record-signing-evidence.sh` re-verifies with
   `--require-signature` and checks `--expect-fingerprint` against the
   operator registry (threat T4).
5. *Record* — public evidence subset committed to
   `evidence/releases/<version>/`; full record stays operator-held.
6. *Publish* — tag, release assets, keyring artifact (operator-owned,
   `docs/BOOTSTRAP_RELEASE_PROCESS.md` §3 steps 7–10).

Sequencing invariants: no evidence without `verified-signed`; no publish
without evidence; every failure fail-closed with the existing verdict
vocabulary (`docs/RELEASE_SIGNING.md` §5).

## 5. SBOM and provenance integration points

- **SBOM (RT-14)**: the SPDX 2.3 document is a standards-formatted view of
  `SIGNING-MANIFEST.json` (same digests, same commit binding) — generation
  slots into B1 tooling as an optional output of the builder, published as a
  release asset in B4. Until signed, it is informational only
  (`docs/SIGNING_THREAT_MODEL.md` S7).
- **Provenance (RT-15)**: a signed provenance statement (builder identity,
  source commit, reproducibility claim) attaches at the same point as the
  manifest signature — the operator signs it in the same ceremony. SLSA
  context: `docs/PRODUCTION_SIGNING_ARCHITECTURE.md` §6.3.
- **OIDC provenance (RT-16)**: only under the revisit conditions of the
  design spec §13.

## 6. Artifact verification workflow

End-operator flow, before and after activation:

| | today | after B4 |
|---|---|---|
| integrity | `scripts/verify-release-bundle.sh --bundle=DIR` → `verified-integrity-only` | unchanged |
| authenticity | fixture-only proof | `--keyring=pixel-release-signing.gpg --require-signature` → `verified-signed` |
| anchor (direct fetch) | commit pin + SHA-256 | + `scripts/verify-bootstrap-signature.sh` (tier 2, ADR) |
| keyring source | n/a | independent channel (`docs/SIGNING_KEY_LIFECYCLE.md` §4) |

Verification stays offline, read-only, fail-closed; signature never replaces
checksum re-hashing.

## 7. Release validation gates

| gate | runs | added by |
|---|---|---|
| suite (327 assertions today) | PR + main + local | exists |
| checksum lockstep / README pin / doc contracts (§16/§18/§28/§29b) | suite | exists |
| action-pin enforcement (§30) | suite + ci-local + workflow | exists |
| reproducibility (§27) | suite + release-candidate-check | exists |
| protocol fixture dry-run | release-candidate-check | B2 (RT-05) |
| workflow no-secret / no non-fixture signing | suite | B2 (RT-06) |
| evidence-subset re-verification (vacuous until B4) | release-candidate-check | B3 (RT-08) |
| `verified-signed` on the real release | operator, independent machine | B4 (RT-12) |

## 8. Key-management integration points (design only)

No key operations are performed by this program; the integration *points*
are: the operator registry template (RT-09, `docs/SIGNING_KEY_LIFECYCLE.md`
§3), the keyring release artifact (§4 of the lifecycle doc), the
`--expect-fingerprint` check in RT-02, the evidence schema's signer fields
(design spec §6.2), and the annual review hook
(`docs/SIGNING_RUNBOOKS.md` §8). Custody, rotation, revocation, recovery, and
destruction procedures remain exactly as Session 11 specified.

## 9. Operator approval checkpoints

| # | checkpoint | decision |
|---|---|---|
| C1 | merge Session 11 (`auto/session-11-signing-architecture`) | architecture accepted |
| C2 | merge Session 12 (this branch) | blueprint accepted |
| C3 | start the B1–B3 build session | implementation authorized |
| C4 | key ceremony (RT-11) | production identity provisioned |
| C5 | first signed release (RT-12) | activation go/no-go |
| C6 | README tier-2 co-primary (RT-13) | authenticity becomes the documented default path |
| C7 | require-signature as default expectation (roadmap Phase 3) | policy flip |
| C8 | B5 options (SBOM publish, signed provenance, OIDC revisit) | per-option |

## 10. Migration strategy (unsigned → fully trusted)

Additive migration per `docs/SIGNING_ROADMAP.md` §6: tooling first (B1–B3),
ceremony second (B4), policy last (C7). At no point does an unsigned release
become invalid; old releases stay verifiable via keyring history
(`docs/SIGNING_KEY_LIFECYCLE.md` §8); every phase rolls back independently
(`docs/ROLLBACK_AND_RECOVERY_PLAN.md`).

## 11. Planning-risk register

| ID | risk to the plan | handling |
|---|---|---|
| P1 | build session drifts from the design-spec contracts | acceptance criteria quote the contracts verbatim (`docs/RELEASE_ACCEPTANCE_CRITERIA.md`); contract changes require a spec amendment commit |
| P2 | evidence-subset re-verification breaks when no release exists | RT-08 requires the check to pass vacuously on an empty directory |
| P3 | README co-primary edit trips §18 pin tests | RT-13 acceptance includes the §18 matrix; the block is additive, the pin values untouched |
| P4 | operator key ceremony delayed | B1–B3 deliver value independently (tested ceremony path); activation waits without blocking the repo |
| P5 | registry template mistaken for a trusted fingerprint source | template carries the "repo never asserts a production fingerprint" banner (`docs/SIGNING_KEY_LIFECYCLE.md` §3) |

No unresolved critical planning gaps: every phase has tasks, dependencies,
acceptance criteria, gates, and rollback. The review report
(`reports/session-12-implementation-review.md`) records the verification.
