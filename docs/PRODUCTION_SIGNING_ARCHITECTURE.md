# Production Signing Architecture

Capstone architecture for production release signing in this repository.
Session 11 (2026-07-13), branch `auto/session-11-signing-architecture`.
**Design only**: this document creates no keys, changes no production behavior,
and performs no signing or publishing. It extends — does not replace — the
existing governance document set.

**Chosen model**: offline operator signing, tooling-assisted (Approach A of the
approved design spec, `docs/superpowers/specs/2026-07-13-production-signing-architecture-design.md`
— hereafter "the design spec"). A human operator signs offline; CI and
autonomous sessions never hold production key material and never sign
production artifacts.

---

## 1. Document map

The signing governance set, with each document's role (read these together;
this capstone references rather than repeats them):

| document | role |
|---|---|
| `docs/PRODUCTION_SIGNING_ARCHITECTURE.md` (this file) | capstone: components, CI/CD signing design, artifact integrity, audit/monitoring/compliance |
| `docs/SIGNING_TRUST_MODEL.md` | trust domains and their separation (developer / CI / production release signing) |
| `docs/SIGNING_THREAT_MODEL.md` | signing-event and supply-chain threat model, gap register |
| `docs/SIGNING_KEY_LIFECYCLE.md` | key generation, custody, rotation, revocation, **recovery, destruction** (extended this session) |
| `docs/RELEASE_SIGNING.md` | what is signed, sign/verify mechanics, signature policy matrix |
| `docs/BOOTSTRAP_TRUST_MODEL.md` | install-chain trust model; names the residual authenticity gap this architecture closes |
| `docs/BOOTSTRAP_RELEASE_PROCESS.md` | versioning, release checklist, tier-2 signing at tag time, rollback |
| `docs/adr/ADR-BOOTSTRAP-ANCHOR-AUTHENTICITY.md` | two-tier anchor decision (immutable reference + SHA-256; detached gpgv signature) |
| `docs/SIGNING_RUNBOOKS.md` | operational runbooks: key ceremony, signing ceremony, verification, rotation, incident, disaster recovery |
| `docs/SIGNING_ROADMAP.md` | migration roadmap from the current unsigned state; disaster-recovery plan; SLSA/SBOM path |
| `docs/GITHUB_ACTIONS_PINNING_POLICY.md` | CI supply-chain pinning (Session 10), part of the signing supply chain |
| `docs/BRANCH_PROMOTION_POLICY.md` | promotion gates every signing change must pass |
| `docs/superpowers/specs/2026-07-13-production-signing-architecture-design.md` | approved design spec: protocol contracts, evidence schema, test plan (recommendations for a build session) |

## 2. Current state (what exists today)

- **Integrity, not yet authenticity**: the README primary path pins a full
  commit + SHA-256 (tier 1 of the ADR); `pixel-bootstrap.sh` verifies
  downstream scripts against embedded pins; release bundles verify to
  `verified-integrity-only` (`docs/RELEASE_SIGNING.md` §4).
- **Signature mechanics proven with fixtures**: `scripts/verify-bootstrap-signature.sh`
  (gpgv, offline) and the signed mode of `scripts/verify-release-bundle.sh`
  (`verified-signed`) are implemented and hermetically tested with throwaway
  keys (harness §19).
- **Policy complete**: signing mechanics (`RELEASE_SIGNING.md`), key custody
  (`SIGNING_KEY_LIFECYCLE.md`), release process (`BOOTSTRAP_RELEASE_PROCESS.md`),
  and the anchor ADR agree on the operator-owned boundary.
- **Missing**: a production release-signing key (operator-owned, Phase 1 of the
  roadmap), the signing-session tooling and evidence plane (specified in the
  design spec §6, build deferred), SBOM/provenance artifacts (§6 below).

## 3. Architecture overview

Four planes (design spec §3):

1. **Policy plane** — the document set in §1. Normative behavior is enforced
   by the test harness; prose explains *why*.
2. **Operator plane** — the signing-session protocol:
   *prepare → rebuild-and-compare → sign (human) → verify → record evidence*.
   Contracts for `scripts/prepare-signing-session.sh` and
   `scripts/record-signing-evidence.sh` are specified in the design spec §6.2
   as implementation-ready recommendations.
3. **Automation plane** — CI exercises the entire protocol with throwaway
   fixture keys only, plus enforcement tests that fail if any workflow ever
   references a signing secret or a non-fixture signing step (design spec §7).
4. **Evidence plane** — one `SIGNING-EVIDENCE.json` per signing event: full
   record operator-held, public subset committable under
   `evidence/releases/<version>/` (design spec §6.2 schema, §8 handling).
   Evidence is attestational; the signature + independently distributed
   keyring remain the trust roots.

Trust domains and their separation are specified in
`docs/SIGNING_TRUST_MODEL.md`; the threat model in
`docs/SIGNING_THREAT_MODEL.md`.

## 4. Component architecture

### 4.1 Signing targets

One release-signing identity signs **two** artifact classes at release time:

| target | signature file | verifier | defined in |
|---|---|---|---|
| `pixel-bootstrap.sh` (anchor, tier 2) | `pixel-bootstrap.sh.sig` | `scripts/verify-bootstrap-signature.sh` | ADR; `BOOTSTRAP_RELEASE_PROCESS.md` §4 |
| release bundle `SIGNING-MANIFEST.json` | `SIGNING-MANIFEST.json.asc` | `scripts/verify-release-bundle.sh` | `RELEASE_SIGNING.md` §1, §3 |

The bundle manifest binds version + commit + every artifact digest
(`RELEASE_SIGNING.md` §1), so the bundle signature transitively covers the
anchor script as shipped in the bundle. The detached anchor signature
additionally covers operators who fetch `pixel-bootstrap.sh` directly from a
commit URL (the README flow). Both use the same identity, the same keyring
artifact, and the same offline ceremony.

### 4.2 Signing environment model (reconciliation)

Existing docs describe generation on an *offline* machine
(`SIGNING_KEY_LIFECYCLE.md` §1) and signing on a *trusted machine holding the
signing subkey* (`RELEASE_SIGNING.md` §3). These are consistent and this
architecture fixes the model explicitly:

- the **certify-only primary key** is generated offline and never leaves
  offline storage;
- the **signing subkey** may reside on a hardware token (preferred) or an
  encrypted offline medium, used from a trusted host for the ceremony;
- the signing host needs no network: the protocol rebuilds the bundle from a
  local clone and verifies with `gpgv` against a local keyring;
- CI is never a signing environment (§5).

### 4.3 Signing-session protocol (recommended tooling)

Per the design spec §6: `prepare-signing-session.sh` enforces preconditions
(clean tree, `HEAD` == release commit, `VERSION` agreement, toolchain present)
and performs the reproducible rebuild; the operator signs; `record-signing-evidence.sh`
re-verifies with `--require-signature`, checks the signer fingerprint against
an explicit `--expect-fingerprint` parameter, and emits schema-valid evidence.
Both scripts have a `--fixture` mode that runs in an isolated temp `GNUPGHOME`,
which is what makes the full protocol exercisable in CI and the suite with
zero secrets. Until built, the manual equivalents in `RELEASE_SIGNING.md` §2–4
remain the operative procedure.

### 4.4 Verification plane (unchanged)

`scripts/verify-release-bundle.sh` and `scripts/verify-bootstrap-signature.sh`
keep their contracts: offline, read-only, fail-closed, no keyserver, verdict
vocabulary per `RELEASE_SIGNING.md` §5. Signature never replaces checksum
verification — the verifier always re-hashes.

## 5. CI/CD signing architecture

### 5.1 Current state (normative)

- CI holds **no** signing material and performs **no** production signing.
  The `release-candidate-check` job builds fixture bundles and verifies them
  with throwaway keys generated and discarded per run.
- Workflow least privilege is enforced: `contents: read`, immutable action
  pins, no secrets on verification paths (Sessions 9/10;
  `docs/GITHUB_ACTIONS_PINNING_POLICY.md`, `docs/MAIN_BRANCH_PROTECTION.md`).
- The recommended fixture dry-run of the signing protocol (design spec §7)
  extends this without changing the boundary.

### 5.2 OIDC / ephemeral credentials — evaluated design option

If the operator ever reverses the no-automatic-signing rule
(`SIGNING_KEY_LIFECYCLE.md` §9), the only acceptable CI signing shape is:

- GitHub OIDC workload identity → short-lived, repo-and-ref-scoped token
  (ephemeral credentials; nothing stored);
- a signing service that binds the key to the OIDC identity (Sigstore Fulcio
  model) or a cloud KMS key with an OIDC-only access policy;
- signatures published to a transparency log (Rekor model) for public
  auditability;
- a protected `environment` requiring manual approval on the release workflow,
  so a human gate precedes any signing job;
- verification tooling that checks the certificate identity and log entry,
  alongside (not instead of) checksum verification.

**Rejected as the current model** (design spec §13): it overturns the hard
rule, adds Fulcio/Rekor as network trust roots, requires a second verifier
toolchain, and makes GitHub-account compromise a signing capability. Revisit
conditions are recorded in the design spec §13 and the roadmap
(`docs/SIGNING_ROADMAP.md`). This section exists so the evaluation never has
to be repeated from scratch.

### 5.3 Least-privilege invariants for CI

Items 1–4 hold of the current workflow (`.github/workflows/test.yml`) by
construction — its header contract is "no agents, no secrets, no pushes, no
repository mutation" and the only signing step uses a per-run throwaway
fixture key. Dedicated harness assertions for items 1–2 are a build-session
recommendation (design spec §12), not yet part of the suite; the
action-pin gate is test-enforced today.

1. No workflow may reference a signing secret or a private-key variable.
2. No workflow step may invoke `gpg --detach-sign` outside fixture mode.
3. Verification jobs require no secrets at all.
4. No publish/tag/release step may be reachable from verification triggers.
5. `continue-on-error` may never be used to obtain green status
   (`BRANCH_PROMOTION_POLICY.md` §4).

## 6. Artifact integrity: checksums, signatures, SBOM, provenance, SLSA

### 6.1 Controls in place

| control | mechanism | evidence |
|---|---|---|
| artifact integrity | SHA-256 of every artifact in `SIGNING-MANIFEST.json`; verifier re-hashes | `verified-integrity-only` |
| authenticity (when keyed) | detached GPG signature over the manifest | `verified-signed` (fixture-proven) |
| reproducibility | `SOURCE_DATE_EPOCH`-pinned builds are byte-identical | harness §27; `evidence/session-6/reproducibility.txt` |
| provenance metadata | `RELEASE-METADATA.json` records project, version, commit, build date | bundle contents |
| supply-chain (CI) | immutable action pins + enforcement | `GITHUB_ACTIONS_PINNING_POLICY.md` |
| supply-chain (install) | commit-pinned URLs, embedded pins, no pipe-to-shell | `BOOTSTRAP_TRUST_MODEL.md` |

### 6.2 SBOM — assessment and recommendation

The release bundle is small and fully repo-contained (9 files; third-party
installers are fetched at *install* time, not shipped — see
`BOOTSTRAP_TRUST_MODEL.md` §2 for that trust boundary). A full dependency
SBOM is therefore low-value today. Recommendation (roadmap Phase 3+): publish
an **SPDX 2.3 JSON** SBOM naming the shipped files with their SHA-256 digests
and the repository commit — effectively a standards-formatted view of the
existing manifest — so downstream consumers can ingest it with standard
tooling. Design only; generation tooling is a build-session decision.

### 6.3 SLSA compatibility mapping

Self-assessment against SLSA 1.0 (no certification is claimed):

| level | requirement (summary) | status |
|---|---|---|
| L1 — provenance exists | build process documented; provenance available | **met in substance**: `RELEASE-METADATA.json` + documented build (`BOOTSTRAP_RELEASE_PROCESS.md` §3); reproducible by anyone |
| L2 — hosted build, signed provenance | build on a hosted service; authenticated provenance | **partial**: CI builds run on GitHub Actions, but the release artifact is operator-built and provenance is unsigned until Phase 2 |
| L3 — hardened, isolated builds | ephemeral, isolated, hermetic build; unforgeable provenance | **not met**: requires builder-side attestation (e.g. OIDC provenance, §5.2) |

The reproducible-build property is the strongest existing SLSA-relevant
control: any verifier can rebuild from the pinned commit and compare bytes,
which independently attests the artifact regardless of builder honesty. The
roadmap sequences SBOM publication and, optionally, OIDC-signed provenance
(SLSA L2/L3 direction) without changing the operator-signature gate.

## 7. Audit logging, monitoring, compliance

### 7.1 Audit records

Per signing event: `SIGNING-EVIDENCE.json` (schema v1, design spec §6.2) plus
the verifier transcript. Public subset committed under
`evidence/releases/<version>/`; full record operator-held with the key backup.
Retention: indefinite, including after revocation (historical verification,
`SIGNING_KEY_LIFECYCLE.md` §8).

### 7.2 Monitoring (design recommendations)

- **Release-time re-verification**: when a public evidence subset lands, CI
  re-verifies the referenced release commit's bundle against the committed
  keyring (drift detector; attestational only).
- **Doc-lockstep monitoring (already live)**: harness §16/§18/§28 fail on
  checksum/README-pin/doc-contract drift — the repository's existing
  governance-drift alarms.
- **Key-expiry monitoring**: the evidence schema records the verification
  date; the roadmap recommends an annual operator review of key expiry,
  registry accuracy, and revocation-certificate accessibility.
- **No runtime telemetry**: the kit has no phone-home; "monitoring" means
  repository-side gates and operator reviews, not agent reporting.

### 7.3 Compliance mapping (grounded, no certification claims)

| framework | practice | where satisfied |
|---|---|---|
| SLSA 1.0 | provenance, reproducible builds, hardened CI | §6.3 |
| NIST SSDF (selected) | protect software from tampering (PO.3.2), archive/release integrity (PS.2.1, PS.3.1) | signature + checksum policy, reproducibility, evidence retention |
| Sigstore landscape | keyless signing, transparency log | evaluated, deferred (§5.2, design spec §13) |
| OpenSSF Scorecard (direction) | branch protection, pinned actions, signed commits | Sessions 9/10 controls; `MAIN_BRANCH_PROTECTION.md` |

## 8. Key lifecycle summary

Canonical policy: `docs/SIGNING_KEY_LIFECYCLE.md` — generation (offline,
ed25519, passphrase-mandatory, role identity), custody and backup, authorized
signers, distribution, rotation, revocation, emergency unsigned releases,
historical verification. This session extends it with **recovery** and
**destruction** sections and adds operational procedures in
`docs/SIGNING_RUNBOOKS.md`. Two identities are structural: the release-signing
role identity is never the commit-signing identity (`0F8A4FD173240A4B`) —
see `docs/SIGNING_TRUST_MODEL.md` §3.

## 9. Incident response and disaster recovery

Summaries; operative procedures live in `docs/SIGNING_RUNBOOKS.md`:

- **Key compromise**: freeze → revoke (independent channel) → assess window →
  re-verify sweep → replace + re-sign → communicate → post-incident (design
  spec §9; runbook §5).
- **Key unavailability**: emergency integrity-only release, explicitly
  labelled (`SIGNING_KEY_LIFECYCLE.md` §7; runbook §6).
- **Infrastructure loss** (repository, keyring, evidence): disaster-recovery
  plan in `docs/SIGNING_ROADMAP.md` §4 — restore from clone + operator-held
  backups; the evidence plane is reconstructable from published releases.

## 10. Evaluated alternatives

- **Keyless CI signing (Sigstore/OIDC)**: rejected as the current model;
  design captured in §5.2; revisit conditions in the design spec §13.
- **Hybrid provenance (CI unsigned provenance + operator signature)**:
  deferred; absorbable as a roadmap phase without changing the gate.
- **minisign/signify**: better ergonomics than GPG but absent from the
  harness environments; gpgv is present everywhere supported (ADR, evaluated
  alternatives table). Not revisited this session.

## 11. Invariants and non-goals

Preserved invariants: no production private key in repo or CI; no
passphrase-less production keys; no automatic signing; signature never
replaces checksums; all verification fails closed; no tags/releases/publishing
by automation; history append-only; `main` changes only via the protected PR
path; all commits GPG-signed.

Non-goals for this architecture: runtime telemetry, a keyserver-based web of
trust, hardware-token mandate (recommended, not required), SLSA certification
claims, and any change to the install-time third-party trust boundary
(`BOOTSTRAP_TRUST_MODEL.md` §2, charter exception).

## 12. Reconciliation notes (this session)

1. **"Maintainer key" terminology** (ADR; `BOOTSTRAP_RELEASE_PROCESS.md` §4)
   means the **release-signing role identity** of
   `SIGNING_KEY_LIFECYCLE.md` §1 — a project role identity, not a personal
   address, and never the commit-signing key. The capstone and trust model use
   "release-signing identity" throughout.
2. **Signing environment** (§4.2): generation offline; signing subkey on
   hardware token or encrypted offline medium, used from a trusted host.
3. **Test-count drift** in `BRANCH_PROMOTION_POLICY.md` (§2 says 309, §7 says
   326; actual contract is 327) — corrected this session.
4. **Two signing targets, one identity** (§4.1): anchor signature and bundle
   signature are the same ceremony and keyring.
5. The design spec's tooling/test deliverables are **recommendations** for a
   build session; Session 11 ships documentation only (operator mandate).
