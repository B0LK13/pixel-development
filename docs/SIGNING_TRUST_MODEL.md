# Signing Trust Model

Trust domains for signing in this repository, and the separations between
them. Session 11 (2026-07-13). Companion to
`docs/PRODUCTION_SIGNING_ARCHITECTURE.md` (capstone) and
`docs/BOOTSTRAP_TRUST_MODEL.md` (install-chain trust — this document covers
the *signing* side; the two share the fail-closed and out-of-scope rules of
the install-chain model §4, §6).

**Status**: design only. No keys exist beyond the developer commit key and
throwaway fixtures; no production signing has occurred.

---

## 1. Roots of trust

| root | held by | what it anchors |
|---|---|---|
| release-signing public key (future, Phase 1) | operators, via independent-channel distribution (`SIGNING_KEY_LIFECYCLE.md` §4) | release authenticity: anchor + bundle signatures |
| SHA-256 pins in docs/README | repository documentation set | install integrity (tier 1, ADR) |
| git object model | any clone | commit/content addressing; self-authenticating refs |
| GitHub platform (TLS, accounts, Actions) | platform | tier-1 transport and CI execution — part of the TCB, stated plainly in `BOOTSTRAP_TRUST_MODEL.md` §2 |
| branch protection + required checks | repository configuration (Sessions 9/10) | promotion correctness: what may merge to `main` |

The release-signing key is the only root that provides *authenticity*.
Everything else provides integrity or process correctness.

## 2. Trust domains

### D1 — Developer (commit) signing

- **Identity**: `0F8A4FD173240A4B` (personal, ed25519), on the daily-use host.
- **Signs**: commits. Purpose: authorship and audit trail — the session chain
  is evidence (`BRANCH_PROMOTION_POLICY.md` §3).
- **Compromise impact**: forged commits. Contained by branch protection
  (required checks, approval, conversation resolution, enforce_admins) — a
  forged commit still cannot merge unreviewed, and *never* implies release
  trust.
- **Never**: signs releases, anchors, or manifests.

### D2 — CI signing

- **Identity**: none in production. CI generates throwaway fixture keys per
  run (harness §19 convention) and discards them.
- **Signs**: fixture artifacts only, to prove the verification machinery.
- **Compromise impact** (runner takeover): none for release trust — CI output
  never ships; the release artifact is operator-rebuilt from the pinned
  commit and operator-signed (D3). CI compromise can at worst produce false
  greens, which promotion policy counters with local/remote parity
  (`BRANCH_PROMOTION_POLICY.md` §4: local and remote results must agree).
- **Future option**: OIDC-bound ephemeral signing — evaluated and rejected as
  the current model; design and revisit conditions in
  `PRODUCTION_SIGNING_ARCHITECTURE.md` §5.2.

### D3 — Production release signing

- **Identity**: release-signing role identity (to be provisioned, Phase 1):
  certify-only ed25519 primary + ed25519 signing subkey, passphrase-mandatory,
  role identity per `SIGNING_KEY_LIFECYCLE.md` §1.
- **Signs**: `pixel-bootstrap.sh` (anchor, tier 2) and
  `SIGNING-MANIFEST.json` (release bundle) — one identity, one ceremony
  (`PRODUCTION_SIGNING_ARCHITECTURE.md` §4.1).
- **Custody**: primary offline; subkey on hardware token or encrypted offline
  medium, used from a trusted host (capstone §4.2).
- **Compromise impact**: full release authenticity — attacker releases verify.
  Hence: offline custody, revocation certificate pre-generated, independent
  distribution channel, incident runbook (`SIGNING_RUNBOOKS.md` §5), and
  pin-history `unsupported` marking (`BOOTSTRAP_RELEASE_PROCESS.md` §2).

## 3. Separation rules (structural)

1. Three domains, three disjoint key sets. No key material is ever shared or
   reused across domains — in particular, the D1 commit key never signs
   releases (Session 9/10 mandate; design spec §5.1).
2. D3 material never touches D1 or D2 hosts: not in the repository, not in CI
   secrets, not on the daily-use machine.
3. D2 cannot produce D3 artifacts: no signing secrets exist in CI; enforcement
   tests assert no non-fixture signing step (`PRODUCTION_SIGNING_ARCHITECTURE.md`
   §5.3).
4. D1 compromise cannot forge releases: release authenticity derives from D3
   only; a forged commit still faces the operator rebuild-and-compare step
   (the protocol rebuilds from the pinned *commit*, and a malicious commit
   cannot merge through protection unreviewed).
5. D3 compromise does not rewrite history: git history remains append-only;
   recovery is revocation + re-signing, never force-push
   (`BRANCH_PROMOTION_POLICY.md` §5).

## 4. Cross-domain trust flow

```
D1: developer signs commit ──► protected PR (checks + approval + resolution)
                                    │  merge (--no-ff, signed)
                                    ▼
                          release commit on main (reproducible build source)
                                    │
D2: CI verifies (fixture-only) ─────┤  CI attests correctness, never authenticity
                                    ▼
D3: operator rebuilds from pinned commit, compares, signs (offline)
                                    │
                                    ▼
        operators verify: gpgv + independent keyring ──► verified-signed
                          (checksums always re-hashed)
```

Each arrow is a boundary where the receiving domain re-verifies rather than
trusts: merge re-runs the gates; the operator rebuilds instead of trusting CI
artifacts; the end operator verifies the signature *and* re-hashes.

## 5. Trust assumptions and residuals

| domain | assumption | residual if broken |
|---|---|---|
| D1 | developer host not compromised at commit time | forged commits; contained by protection + review (§2 D1) |
| D2 | runner executes the reviewed workflow | false greens; contained by parity policy and operator rebuild |
| D3 | signing host trustworthy during ceremony; passphrase not captured | full authenticity loss; contained by revocation + re-verify sweep (runbook §5) |
| distribution | operator obtains the public key via the independent channel | keyring TOFU risk; documented diligence step, tooling surfaces fingerprint (design spec §4) |
| platform | GitHub TLS/accounts/Actions behave | tier-1 integrity loss; tier-2 (D3) unaffected — its root is off-platform |

Out of scope (unchanged from `BOOTSTRAP_TRUST_MODEL.md` §4): a hostile local
environment on any host; install-time third-party installer pipes.
