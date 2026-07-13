# Signing Threat Model

Threat model for the production signing architecture: the signing event
(build → sign → publish → verify) and the supply chain around it. Session 11
(2026-07-13), design only. Extends — does not repeat —
`docs/BOOTSTRAP_TRUST_MODEL.md` §3 (install-chain attacker capabilities) and
the approved design spec §4.

Method: attacker-centric. For each threat, consequence, mitigation, and
residual are stated; §3 classifies every identified gap by severity. Trust
domains (D1 developer / D2 CI / D3 production release) are defined in
`docs/SIGNING_TRUST_MODEL.md`.

---

## 1. Signing-event threats

| # | threat | consequence | mitigation | residual |
|---|---|---|---|---|
| T1 | compromised build host emits a malicious manifest | operator signs attacker content | protocol rebuilds the bundle from the pinned commit **on the signing machine** and byte-compares before signing (design spec §6) | signing-host compromise — out of scope (local environment) |
| T2 | manifest swapped between build and sign | signature covers wrong bytes | same rebuild-and-compare; evidence records the compared digest | none identified |
| T3 | signing key copied from storage | attacker releases verify | passphrase mandatory; hardware-token option; revocation runbook | detection lag — re-verify sweep (runbook §5) |
| T4 | unauthorized/impersonated key used | "valid" signature from wrong identity | authorized-signer registry; `--expect-fingerprint` check in the recording tool; pinned verifier keyring | registry is governance — protected path only |
| T5 | keyring TOFU at verify time | user trusts a shipped keyring | independent-channel distribution; tooling surfaces fingerprint + date | operator diligence step, documented |
| T6 | replay of an old valid signature | old signature over a new manifest | manifest binds version + commit + digests; verifier re-hashes | old-signature-over-old-bundle = legitimate rollback |
| T7 | operator error (wrong bundle/version/commit) | valid signature over unintended release | pre-sign precondition checks (clean tree, HEAD, VERSION); evidence schema; fixture rehearsal | none identified |
| T8 | coerced or unavailable signer | forced signature, or release blocked | coercion: out of scope (physical); unavailability: emergency integrity-only path, labelled (`SIGNING_KEY_LIFECYCLE.md` §7) | documented behavior |
| T9 | evidence-plane tampering | altered audit record misleads reviewers | evidence is attestational, not a root: digests must match release artifacts; CI re-verifies committed subsets (capstone §7.2) | none identified |

## 2. Supply-chain threats

| # | threat | consequence | mitigation | residual |
|---|---|---|---|---|
| S1 | compromised GitHub account | branch rewrites, release edits | tier-1 commit pins survive (immutable objects); branch protection (enforce_admins, no force-push); D3 key is off-platform — account compromise alone cannot forge a signed release | account + key combined: T3/runbook §5 |
| S2 | malicious action / retargeted tag in CI | attacker code in the runner | immutable SHA pins + enforcement (`GITHUB_ACTIONS_PINNING_POLICY.md`); least privilege (`contents: read`); no secrets on verification paths | runner can still produce false greens — parity policy counters (`BRANCH_PROMOTION_POLICY.md` §4) |
| S3 | Dependabot/update PR smuggles a bad action | as S2 | grouped weekly PRs, operator review, full gate per PR, no auto-merge | review diligence |
| S4 | dependency confusion / malicious package | repo tooling has no package dependencies: bash, coreutils, git, gpg/gpgv, python3 stdlib — all from the platform | install-time third-party installer pipes are a separate, documented boundary (`BOOTSTRAP_TRUST_MODEL.md` §2) | platform package integrity |
| S5 | artifact poisoning between build and publish | swapped release assets | operator rebuild-and-compare at sign time; post-publish verification from a different machine/network (`BOOTSTRAP_RELEASE_PROCESS.md` §3 step 9) | none identified |
| S6 | keyserver/distribution poisoning | wrong public key imported | independent channel + cross-posted fingerprint + README never embeds unestablished fingerprints (`SIGNING_KEY_LIFECYCLE.md` §4) | TOFU diligence (T5) |
| S7 | forged provenance/SBOM (future artifacts) | consumers trust false build claims | until signed, provenance/SBOM are **informational only** — the operator signature + reproducible rebuild remain the authenticity path (capstone §6) | closes when provenance is signed (roadmap option) |
| S8 | clone/fork spoofing of the repository | user clones attacker repo | README pins full commit + digest; the docs channel states the canonical repository; D3 signature fails against attacker content | tier-1 channel trust (documented) |
| S9 | history rewrite hides a malicious commit | audit trail severed | append-only policy, no force-push anywhere, signed commits, merge-commit preservation (`BRANCH_PROMOTION_POLICY.md` §3, §5) | platform enforcement is configuration — Session 10 applied it |

## 3. Gap register

Severity uses CRITICAL / HIGH / MEDIUM / LOW. "Architecturally closed" means
the design fully addresses the gap and only the operator-owned activation
(roadmap phase) remains; no further design work is required.

| ID | gap | severity | status |
|---|---|---|---|
| G1 | joint anchor+manifest substitution passes tier-1 checks (the residual authenticity gap, `BOOTSTRAP_TRUST_MODEL.md` §3) | HIGH | **architecturally closed** — D3 signature against an independently distributed key; activation = roadmap Phases 1–2 (operator-owned) |
| G2 | no SBOM published | LOW | accepted today (bundle fully repo-contained); SPDX view of the manifest on the roadmap (capstone §6.2) |
| G3 | provenance unsigned (SLSA L2/L3 direction) | MEDIUM | design captured (capstone §5.2/§6.3); optional roadmap phase; reproducible rebuild is the interim attestation |
| G4 | single-signer model (no threshold/multi-sig) | MEDIUM | accepted: offline custody + backup + rotation + recovery runbook; multi-signer noted as a future option (runbook §1) |
| G5 | revocation distribution lag (users verify against stale keyrings) | MEDIUM | mitigated: independent channel, `unsupported` pin-history marking, re-verify sweep, keyring re-fetch in the communications step |
| G6 | key custody relies on operator discipline (no HSM mandate) | MEDIUM | mitigated: hardware-token recommendation, ceremony runbook, annual key/expiry review (capstone §7.2); mandate left to the operator |
| G7 | fixture-mode misuse could mask a real signing failure in CI | LOW | mitigated: fixture keys are generated per run in isolated `GNUPGHOME`; enforcement tests assert no non-fixture signing step exists |

**Summary: no CRITICAL gaps identified; no HIGH gap remains open — the sole
HIGH (G1) is architecturally closed with operator-owned activation on the
roadmap.** All MEDIUM/LOW gaps have documented mitigations or explicit
acceptance.

## 4. Out of scope

Unchanged from `docs/BOOTSTRAP_TRUST_MODEL.md` §4: hostile local environments
(compromised signing host, PATH shims, evil `gpg`/`sha256sum`); physical
coercion; install-time third-party installer pipes. Platform support remains
the evidenced set (Termux F-Droid aarch64, proot Ubuntu, `ubuntu-latest`).
