# Production Signing Architecture — Design Spec (Session 11)

- **Date**: 2026-07-13
- **Branch**: `auto/session-11-signing-architecture` (base: `main` @ `0508a04`)
- **Status**: approved design. The Session 11 operator mandate (2026-07-13)
  rescoped delivery to **documentation only** — the tooling contracts in §6/§7
  and the test plan in §12 are implementation-ready *recommendations* for a
  subsequent build session, not Session 11 deliverables.
- **Chosen approach**: **A — offline operator signing, tooling-assisted** (alternatives evaluated in §13)
- **Companion documents**: `docs/RELEASE_SIGNING.md`, `docs/SIGNING_KEY_LIFECYCLE.md`,
  `docs/BOOTSTRAP_TRUST_MODEL.md`, `docs/BOOTSTRAP_RELEASE_PROCESS.md`,
  `docs/adr/ADR-BOOTSTRAP-ANCHOR-AUTHENTICITY.md`

This spec is implementation-ready: every component has a contract, every failure
mode has a verdict, and everything that does not require production secrets is
buildable and testable in-session with fixture keys.

---

## 1. Purpose

Close the *residual authenticity gap* named in `docs/BOOTSTRAP_TRUST_MODEL.md`
§3: an attacker who alters the bootstrap **and** its checksum manifest together
currently verifies clean against SHA-256 pins alone. Only a signature verified
against an independently distributed public key closes that gap.

This spec turns the operator's offline GPG signature — already specified in
`docs/RELEASE_SIGNING.md` — into a complete, evidenced, incident-ready system
**without moving any trust boundary**: signing remains operator-owned, offline,
and human-executed. No automatic signing is introduced anywhere.

## 2. Scope

### In scope

- Threat model of the *signing event* (build → sign → publish → verify window).
- Key architecture with purpose separation: release-signing identity ≠
  commit-signing identity (`0F8A4FD173240A4B`).
- Signing-session protocol and tooling contracts:
  `scripts/prepare-signing-session.sh`, `scripts/record-signing-evidence.sh`,
  the `SIGNING-EVIDENCE.json` schema (v1), and fixture mode for both scripts.
- CI fixture-key dry-run design and enforcement tests.
- Audit-evidence handling (operator-held full record; committable public subset).
- Incident-response runbook (compromise and unavailability paths).
- Phased rollout plan with gates and rollback.
- Test strategy extending `tests/run_tests.sh` in its existing §-numbered style.
- A capstone policy document `docs/PRODUCTION_SIGNING_ARCHITECTURE.md` tying the
  four existing documents together (written during implementation).

### Out of scope

- Generating, importing, storing, or using production key material.
- Publishing keys, keyrings, tags, releases, packages, or images.
- The Sigstore/keyless CI-signing path (evaluated and rejected — §13).
- Changing release semantics: integrity-only releases remain valid per
  `docs/SIGNING_KEY_LIFECYCLE.md` §7.
- Reusing the commit-signing key for releases — explicitly forbidden by the
  Session 9/10 mandates; this spec makes the separation structural (§5).

### Standing invariants preserved

No production private key in the repository or CI; no passphrase-less production
keys; no automatic signing; signature verification never replaces checksum
verification (`docs/RELEASE_SIGNING.md` §1); all verification failures fail
closed; no tags, releases, force-pushes, or history rewrites; all commits
GPG-signed; `main` changes only through the protected PR path.

## 3. Architecture overview — four planes

1. **Policy plane** — the existing four documents plus the new capstone
   `docs/PRODUCTION_SIGNING_ARCHITECTURE.md`. Normative behavior remains
   enforced by the test suite; prose explains *why*.
2. **Operator plane** — the signing-session protocol:
   *prepare → rebuild-and-compare → sign (human) → verify → record evidence*.
   The manual "the signer can rebuild before signing and confirm the manifest
   matches" guidance in `docs/RELEASE_SIGNING.md` §3 becomes enforced machinery.
3. **Automation plane** — CI runs the entire protocol with throwaway fixture
   keys (generated and discarded per run), plus enforcement tests proving no
   workflow ever requires a signing secret.
4. **Evidence plane** — one audit record per signing event: a full record held
   by the operator, and a public subset committed to the repository at release
   time. Evidence is attestational, never a trust root (§8).

## 4. Threat model of the signing event

Extends `docs/BOOTSTRAP_TRUST_MODEL.md` (install chain) to the
build → sign → publish → verify window.

| Threat | Consequence | Mitigation | Residual |
|---|---|---|---|
| Compromised build host emits a malicious manifest | operator signs attacker content | Protocol rebuilds the bundle from the pinned commit **on the signing machine** and byte-compares before signing; only a locally reproduced manifest is signable | Compromise of the *signing* machine — out of scope per trust model §4; hardware-token custody limits blast radius |
| Manifest swapped between build and sign | signature covers wrong bytes | Same rebuild-and-compare; evidence record stores the compared digest | none identified |
| Signing key copied from storage | attacker signs releases that verify | passphrase mandatory; hardware-token option; revocation runbook (§9) | detection lag — covered by the re-verification sweep (§9 step 5) |
| Wrong/impersonated key used | "valid" signature from an unauthorized identity | authorized-signer registry (operator doc); evidence carries the full fingerprint and the tooling checks it against the registry parameter; verifier keyring pinned | the registry is governance — protected by branch protection (Sessions 9/10) |
| Keyring TOFU at verify time | user trusts a keyring shipped with the release | independent-channel distribution (`SIGNING_KEY_LIFECYCLE` §4); tooling surfaces fingerprint and verification date, never hides them | first-contact trust remains an operator-diligence step — documented, not silently "solved" |
| CI runner compromise | attacker signs from CI | CI holds no production material by construction; enforcement tests assert no signing secrets or non-fixture signing steps exist in any workflow | none — fixture keys only |
| Replay of an old valid signature | old signature over a *new* manifest | the manifest binds version + commit + artifact digests; the verifier re-hashes — mismatch fails | old-signature-over-old-bundle is legitimate rollback semantics (trust model §3) |
| Compromised GitHub account **and** stolen key | attacker-published release verifies | revocation + `unsupported` pin-history marking; publication-side controls from Sessions 9/10 | requires two independent failures |
| Operator error (wrong bundle/version) | valid signature over an unintended release | tooling validates version/commit against git pre-sign; evidence schema is mandatory; fixture dry-run rehearses the flow | none identified |
| Key unavailable (loss, coercion, unreachable signer) | release blocked | emergency integrity-only path (`SIGNING_KEY_LIFECYCLE` §7) — explicitly labelled, never silent | documented behavior, not a failure |

Out of scope remains unchanged: a hostile *local* environment (compromised
signing host, PATH shims, evil `gpg`) — `docs/BOOTSTRAP_TRUST_MODEL.md` §4.

## 5. Key architecture

### 5.1 Two identities, never shared

| | Commit-signing identity | Release-signing identity |
|---|---|---|
| Status | exists: `0F8A4FD173240A4B` (personal, daily-use host) | to be provisioned by the operator (Phase 1) |
| Signs | commits only | release manifests only (`SIGNING-MANIFEST.json`) |
| Custody | daily-use host | encrypted offline storage or hardware token |
| Algorithm | ed25519 | certify-only ed25519 primary + ed25519 signing subkey (`SIGNING_KEY_LIFECYCLE` §1) |
| Passphrase | yes | yes — mandatory, never passphrase-less |
| Rotation | independent | independent; transition note signed by old key (`SIGNING_KEY_LIFECYCLE` §5) |

Separation is load-bearing: different custody, different compromise blast
radius, independent rotation and revocation. Losing the commit key never
touches release trust, and vice versa. Tooling and tests must never default to
the commit-signing key for any release operation.

### 5.2 Authorized-signer registry

The repository never asserts a production fingerprint as trusted
(`SIGNING_KEY_LIFECYCLE` §3). The authorized-signer list lives in an operator
document outside the repo (or a clearly-marked operator doc). Tooling accepts
the expected fingerprint as an explicit parameter (`--expect-fingerprint`) and
compares it against the signature's actual signer — it never hardcodes one.

### 5.3 Public-key distribution

Per `SIGNING_KEY_LIFECYCLE` §4: the public key is published through a channel
independent of the raw content host (project website + keyserver, fingerprint
cross-posted in release notes). The verification keyring
(`pixel-release-signing.gpg`, `gpg --export` output) becomes a versioned
release artifact; `scripts/verify-release-bundle.sh --keyring` already consumes
it and needs no changes. Revoked keys remain in the keyring history so old
releases stay verifiable (§8 of the lifecycle doc).

## 6. Signing-session protocol

### 6.1 Flow

```
prepare-signing-session.sh --version=X.Y.Z [--commit=<sha>]
  → asserts preconditions (clean tree, HEAD == commit, VERSION agreement, tools)
  → builds bundle with SOURCE_DATE_EPOCH from the release commit
  → prints manifest digest + exact sign command
operator: gpg --local-user <release-key> --detach-sign --armor
  → the only manual cryptographic act; tooling never sees key or passphrase
record-signing-evidence.sh --bundle=<dir> --signature=<file> --keyring=<pub>
    --expect-fingerprint=<40-hex> [--full-record=<path>]
  → re-verifies via verify-release-bundle.sh --require-signature
  → checks signer fingerprint against --expect-fingerprint
  → writes SIGNING-EVIDENCE.json (public subset) + optional full record
```

### 6.2 Component contracts

**`scripts/prepare-signing-session.sh`**

- Flags: `--version=X.Y.Z` (required), `--commit=<full-40-hex>` (optional,
  defaults to `HEAD`), `--help`.
- Preconditions (any failure → exit 1 naming the cause): working tree clean;
  `HEAD` equals `--commit`; `VERSION` file equals `--version`; `git`, `gpg`,
  `sha256sum` present (missing tool = abort, never skip — the bootstrap rule).
- Behavior: builds the bundle via `scripts/build-release-candidate.sh` with
  `SOURCE_DATE_EPOCH="$(git log -1 --format=%ct <commit>)"` into a fresh
  output directory; prints the bundle path, the `SIGNING-MANIFEST.json`
  SHA-256, and the exact `gpg --detach-sign` command for the operator.
- Writes nothing outside the build output directory; never touches `GNUPGHOME`.

**`scripts/record-signing-evidence.sh`**

- Flags: `--bundle=<dir>` (required), `--signature=<file>` (required),
  `--keyring=<file>` (required unless `--fixture`),
  `--expect-fingerprint=<40-hex>` (required), `--evidence-out=<dir>`
  (default `evidence/releases/<version>/`, where `<version>` is read from the
  bundle's `RELEASE-METADATA.json`), `--full-record=<path>` (optional;
  operator-held output), `--fixture` (derives keyring and signer from the
  fixture `GNUPGHOME` in `$PIXEL_FIXTURE_GNUPGHOME`), `--help`.
- Behavior: runs `scripts/verify-release-bundle.sh --require-signature`; on
  `verified-signed`, extracts the signer fingerprint from `gpgv` status output
  and compares it to `--expect-fingerprint` (mismatch → exit 1,
  `failed-policy`); validates and writes the evidence atomically (temp file +
  rename). On any failure verdict, writes **no** evidence and exits 1 with the
  verifier's verdict.
- `--fixture` runs entirely inside an isolated, generated temp `GNUPGHOME`
  (extends the Session 7 test-hermeticity convention: the operator's real
  keyring is never touched). Non-fixture mode never reads fixture paths; no
  key parameter ever defaults.

**`SIGNING-EVIDENCE.json` schema v1 — public subset (committable)**

```json
{
  "schema": "signing-evidence/v1",
  "project": "pixel-development",
  "version": "X.Y.Z",
  "commit": "<full-40-hex>",
  "manifest":   { "file": "SIGNING-MANIFEST.json",     "sha256": "<64-hex>" },
  "signature":  { "file": "SIGNING-MANIFEST.json.asc", "sha256": "<64-hex>" },
  "signer":     { "fingerprint": "<40-hex>", "algorithm": "ed25519" },
  "verified":   { "verdict": "verified-signed",
                  "verifier": "scripts/verify-release-bundle.sh",
                  "date": "YYYY-MM-DD" }
}
```

**Full record** (operator-held, never committed): the public subset plus
`environment` (`hostname`, `user`, `gpg --version` first line), the verifier
transcript, and free-text `notes`. Emission is deterministic given inputs
(stable key order; the only date is the operator-confirmed verification date).

### 6.3 What the protocol does NOT change

`scripts/build-release-candidate.sh`, `scripts/verify-release-bundle.sh`, and
`scripts/verify-bootstrap-signature.sh` keep their contracts. The new scripts
compose them; they do not modify them. Reproducibility (harness §27) is
unaffected because the build path is untouched.

## 7. CI access design

- **May**: run the full protocol in `--fixture` mode as a step in the existing
  `release-candidate-check` job — prepare → generate throwaway key in an
  isolated temp `GNUPGHOME` → fixture sign → record → assert
  `verified-signed` and schema validity. Fixture keys are generated and
  discarded per run (existing suite §19 convention).
- **Must never**: hold production key material or a passphrase; run a
  non-fixture signing step; publish anything. This is enforced by suite tests
  that scan `.github/workflows/` for signing-secret references and non-fixture
  `gpg --detach-sign` invocations — a test, not a convention. Any future
  workflow violating this goes red.
- **Permissions**: no change — `contents: read` remains sufficient (Session 10
  least-privilege baseline). No new secrets, no new environments.

## 8. Audit logging and evidence handling

- One `SIGNING-EVIDENCE.json` plus verifier transcript per signing event.
- **Storage split**: the full record stays operator-held, alongside the key
  backup and revocation certificate. The public subset is committed at release
  time under `evidence/releases/<version>/signing-evidence.json` — public data
  only: version, commit, digests, the *published* public key's fingerprint,
  date, verdict.
- **Retention**: indefinite, per release, including after revocation —
  historical verification (`SIGNING_KEY_LIFECYCLE` §8) requires evidence and
  keyring history to survive key death.
- **Evidence is attestational, not a trust root.** The signature and the
  independently distributed keyring remain authoritative. Tampered evidence is
  detectable: its digests must match the release artifacts, and CI re-verifies
  committed public subsets against the corresponding release commits.

## 9. Incident-response runbook

Suspected compromise (extends `SIGNING_KEY_LIFECYCLE` §6 into an operational
sequence):

1. **Detect** — unexpected signature, unauthorized fingerprint, custody
   breach, or operator report.
2. **Freeze** — halt release activity; mark affected pin-history rows
   `unsupported` (`BOOTSTRAP_RELEASE_PROCESS` §2).
3. **Revoke** — publish the revocation certificate immediately through the
   independent channel.
4. **Assess** — enumerate every release signed between last-known-good and
   revocation; all treated as untrusted.
5. **Re-verify sweep** — check affected releases against known-good
   out-of-band digests; record results in the evidence plane.
6. **Replace and re-sign** — generate the replacement key per lifecycle §1;
   transition note signed by the old key if still trusted, else an out-of-band
   announcement; re-sign the current release; publish the new keyring.
7. **Communicate** — release notes, project site, docs; operators re-fetch the
   keyring.
8. **Post-incident** — update the registry, evidence, this runbook, and the
   rotation cadence as warranted.

Key *unavailability* (not compromise) routes to the existing emergency
integrity-only path (`SIGNING_KEY_LIFECYCLE` §7): clearly labelled, verified
without `--require-signature`, announced as unsigned, followed by a signed
release as soon as the signing path is restored.

## 10. Rollout plan

| Phase | Owner | Content | Gate | Rollback |
|---|---|---|---|---|
| 0 | autonomous (Session 11) | this spec, tooling with fixture mode, CI dry-run, enforcement tests, capstone doc | full suite + `ci-local.sh` + remote CI green; zero production material | normal PR revert |
| 1 | operator | provision the release key (lifecycle §1–2); record fingerprint in the operator registry; publish public key + keyring via the independent channel | operator confirms publication | stop; nothing in the repo asserts the key |
| 2 | operator | first signed release: prepare → sign → record; commit public evidence subset; publish release with signature + keyring | independent-machine verification returns `verified-signed` | integrity-only release remains valid (§7 lifecycle) |
| 3 | operator, optional | document `--require-signature` as the default expectation for official releases after successful signed releases | operator approval | revert docs; emergency path stays documented |

No phase requires a force-push, a history rewrite, a tag created by
automation, or a change to branch protection.

## 11. Error handling

All new failure modes fail closed and reuse the existing verdict vocabulary
(`verified-integrity-only`, `verified-signed`, `failed-signature`,
`failed-checksum`, `failed-metadata`, `failed-policy` — `RELEASE_SIGNING` §5)
plus script-local precondition errors:

| Condition | Behavior |
|---|---|
| dirty working tree / wrong `HEAD` / version mismatch (prepare) | exit 1, naming the cause; nothing built |
| missing `git` / `gpg` / `sha256sum` | abort naming the tool — never skip-verify |
| build failure | propagate `build-release-candidate.sh`'s exit; no partial-output claims |
| signature absent / invalid / wrong keyring (record) | exit 1 with the verifier's verdict; no evidence written |
| signer fingerprint ≠ `--expect-fingerprint` | exit 1, `failed-policy`; no evidence written |
| tampered artifact or metadata | `failed-checksum` / `failed-metadata`; no evidence written |
| evidence write | atomic (temp + rename); schema self-validates before emission |
| `--fixture` invoked without fixture environment | exit 1 naming `$PIXEL_FIXTURE_GNUPGHOME` |

## 12. Testing strategy

New `tests/run_tests.sh` sections in the existing §-numbered style, all
hermetic (fixture keys in generated temp `GNUPGHOME`s; the operator's real
keyring is never touched — the Session 7 hermeticity rule):

- Fixture happy path: prepare → fixture sign → record → `verified-signed` and
  a schema-valid `SIGNING-EVIDENCE.json`.
- Prepare refusals: dirty tree, wrong `--commit`, version/`VERSION` mismatch,
  missing-tool abort.
- Record refusals: unsigned bundle with `--require-signature` → `failed-policy`;
  wrong keyring → `failed-signature`; fingerprint mismatch → `failed-policy`;
  tampered artifact → `failed-checksum`.
- Evidence schema validation: required fields, digest formats, stable key
  order; the public subset contains no hostname, username, or key material
  (grep assertions).
- Fixture isolation: real `GNUPGHOME` untouched; no fixture material persists.
- Workflow assertions: no signing secrets and no non-fixture
  `gpg --detach-sign` in `.github/workflows/`.
- Regression: harness §16 lockstep, §18 README pin, §19 signature fixtures,
  §27 reproducibility, and the action-pin checker (§30) all stay green.

New tests add to the authoritative suite count (currently 327); the new total
is recorded in the session evidence. No existing gate is weakened.

## 13. Evaluated alternatives

**B — Keyless CI signing (Sigstore/OIDC): rejected for now.** GitHub Actions
would sign manifests via workload identity with a transparency-log trail.
Rejected because it overturns the repository's hard rule ("no automatic
signing — a human operator runs the sign command", `SIGNING_KEY_LIFECYCLE` §9),
adds Fulcio/Rekor as new network trust roots, requires a second verification
toolchain (cosign alongside gpgv), and makes GitHub-account compromise a
signing capability. Revisit conditions: the operator explicitly reverses the
no-automatic-signing rule, *and* the trust model is re-derived with the new
roots, *and* verification UX for offline gpgv users is preserved.

**C — Hybrid provenance (CI emits unsigned provenance metadata; operator
signature remains the gate): deferred.** Compatible with Approach A and
absorbable as a later phase once the evidence plane is proven in production.
Not required to close the authenticity gap.

## 14. Deliverables (implementation phase)

1. `docs/PRODUCTION_SIGNING_ARCHITECTURE.md` — capstone policy document.
2. `scripts/prepare-signing-session.sh` — contract per §6.2.
3. `scripts/record-signing-evidence.sh` — contract per §6.2.
4. Fixture-mode CI dry-run step in the `release-candidate-check` job.
5. New suite sections per §12; updated authoritative test count.
6. `docs/RELEASE_SIGNING.md`, `docs/SIGNING_KEY_LIFECYCLE.md`,
   `docs/OPERATOR_COMMAND_INDEX.md`, `docs/CONTRIBUTOR_QUICKSTART.md` —
   cross-references to the protocol and tooling (additive only).
7. Session 11 evidence and reports under `evidence/session-11/` and
   `reports/`, per the established session conventions.

Every commit is GPG-signed; all work lands on
`auto/session-11-signing-architecture` and reaches `main` only through the
protected PR path (1 approval + required checks).
