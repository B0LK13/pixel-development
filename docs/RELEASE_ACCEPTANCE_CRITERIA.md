# Release Acceptance Criteria

Acceptance criteria for every phase of the release-trust program. Session 12
(2026-07-13), design only. Item numbering matches the references in
`docs/IMPLEMENTATION_BACKLOG.md` (e.g. "AC-B1 items 1–4"). Contracts are
quoted from the design spec
(`docs/superpowers/specs/2026-07-13-production-signing-architecture-design.md`);
phases: `docs/RELEASE_PIPELINE_PHASES.md`.

**Global criteria (every phase)**: signed commits; protected PR path
(`docs/BRANCH_PROMOTION_POLICY.md`); full gate green —
`bash tests/run_tests.sh`, `bash scripts/ci-local.sh` (exit 0),
`python3 scripts/check-github-action-pins.py` (0 violations); no production
key material, secrets, or publishing in B1–B3; documentation references
scripts by their `scripts/` path (harness §29b).

---

## AC-B1 — Signing-session tooling (RT-01…RT-04)

| # | criterion | verification |
|---|---|---|
| 1 | `prepare-signing-session.sh` refuses a dirty tree, exit 1, nothing built | new harness section |
| 2 | refuses `--commit` ≠ `HEAD`, exit 1 naming the mismatch | harness |
| 3 | refuses `--version` ≠ `VERSION` file, exit 1 | harness |
| 4 | happy path: builds the bundle with the release commit's `SOURCE_DATE_EPOCH`, prints the manifest SHA-256 and the exact sign command; output byte-identical to a direct build (§27 determinism preserved) | harness |
| 5 | `record-signing-evidence.sh` happy path (fixture): verdict `verified-signed`, schema-valid `SIGNING-EVIDENCE.json` written atomically | harness |
| 6 | unsigned bundle with `--require-signature` → `failed-policy`, exit 1, **no** evidence written | harness |
| 7 | wrong keyring → `failed-signature`, exit 1, no evidence | harness |
| 8 | signer fingerprint ≠ `--expect-fingerprint` → `failed-policy`, exit 1, no evidence | harness |
| 9 | tampered artifact → `failed-checksum`; tampered metadata → `failed-metadata` | harness |
| 10 | fixture isolation: real `GNUPGHOME` untouched; no fixture material persists; public subset contains no hostname/username/key material (grep assertions) | harness |
| 11 | new authoritative test total recorded (327 + new assertions) in the session evidence | evidence file |
| 12 | `docs/OPERATOR_COMMAND_INDEX.md` rows added; `docs/RELEASE_SIGNING.md` §3 pointer added with the manual procedure retained; §28a contract strings intact | harness §28a + review |

## AC-B2 — CI integration (RT-05…RT-07)

| # | criterion | verification |
|---|---|---|
| 1 | protocol dry-run step executes in `release-candidate-check` and passes on the remote PR run: prepare → fixture sign → record → `verified-signed` | remote run log |
| 2 | the run's `SIGNING-EVIDENCE.json` validates against schema v1 (required fields, digest formats, stable key order) | step output + harness |
| 3 | no permissions/secrets/environments added; `contents: read` and `persist-credentials: false` intact; action pins unchanged (§30) | workflow diff + pin checker |
| 4 | enforcement scan detects seeded violations in fixture workflows (a signing-secret reference; a non-fixture `gpg --detach-sign`) and passes on the real workflow | harness fixtures |
| 5 | `scripts/ci-local.sh` runs the new gates in the same order as the workflow; CI-parity harness section updated and green | ci-local output + harness |

## AC-B3 — Evidence plane (RT-08…RT-09)

| # | criterion | verification |
|---|---|---|
| 1 | `scripts/verify-release-evidence.sh --all` exits 0 (vacuous pass) when `evidence/releases/` is empty | step run + harness |
| 2 | with a fixture subset present (test fixture), re-verification rebuilds the referenced commit and passes | harness |
| 3 | a tampered subset (altered digest, wrong commit, invalid schema) fails the step, exit 1, naming the subset | harness |
| 4 | registry template carries the banner "the repo never asserts a production fingerprint as trusted" and contains no fingerprint | review + grep |

## AC-B4 — Release activation (RT-10…RT-13; operator-executed)

| # | criterion | verification |
|---|---|---|
| 1 | `docs/BOOTSTRAP_RELEASE_PROCESS.md` §3 integrates RT-01/RT-02 with the manual equivalents retained as fallback | PR review |
| 2 | key ceremony executed per `docs/SIGNING_RUNBOOKS.md` §1: offline generation, two encrypted backups, restore test passed, revocation certificate stored separately | operator attestation (recorded in the operator-held log) |
| 3 | public key + `pixel-release-signing.gpg` published via the independent channel; fingerprint cross-posted | operator attestation |
| 4 | rehearsal: the current release re-signed end-to-end; `scripts/verify-release-bundle.sh --require-signature` → `verified-signed` | verifier transcript |
| 5 | public evidence subset committed to `evidence/releases/<version>/`; CI re-verification green and no longer vacuous | remote run |
| 6 | independent-machine verification (different host/network) → `verified-signed` | operator transcript |
| 7 | README tier-2 co-primary block merged (ADR migration step 5); harness §18 pin tests and §29b green | suite |

## AC-B5 — Trust enhancements (RT-14…RT-16; optional)

| # | criterion | verification |
|---|---|---|
| 1 | SPDX 2.3 SBOM validates against the SPDX schema and its file digests match `SIGNING-MANIFEST.json` exactly | schema validator + harness |
| 2 | signed-provenance design approved; the statement is covered by the release signature; verifier guidance updated (`docs/RELEASE_SIGNING.md`) | design review + suite |
| 3 | OIDC revisit occurs only after the operator reverses the no-automatic-signing rule (`docs/SIGNING_KEY_LIFECYCLE.md` §9) and a re-derived trust model is approved | operator decision record |

## Acceptance-criteria completeness

Every backlog task RT-01…RT-16 maps to at least one numbered criterion above
(mapping: `docs/IMPLEMENTATION_BACKLOG.md` task table); every criterion has a
stated verification method. The mapping is checked in
`reports/session-12-implementation-review.md`.
