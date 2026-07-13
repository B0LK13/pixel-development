# Signing Roadmap

Migration roadmap from the current state (integrity-verified, fixture-proven
signing mechanics, no production key) to fully signed releases — plus the
disaster-recovery plan and deferred options. Session 11 (2026-07-13), design
only. Every phase lists its owner, gate, and rollback; the architecture is
specified in `docs/PRODUCTION_SIGNING_ARCHITECTURE.md`.

---

## 1. Current state (as of Session 11)

- Tier-1 install integrity (commit pin + SHA-256) is the documented default.
- Signature mechanics are implemented and fixture-tested
  (`verify-bootstrap-signature.sh`, `verify-release-bundle.sh` signed mode).
- Policy set complete; Session 11 added architecture, trust/threat models,
  runbooks, and key-lifecycle recovery/destruction coverage.
- No production release-signing key exists; no signed release has shipped.

## 2. Phases

| phase | owner | content | gate | rollback |
|---|---|---|---|---|
| 0 | autonomous (Sessions 1–11) | governance foundation, signature mechanics, fixture verification, this architecture set | suite 327/0/0, ci-local exit 0, remote CI green | normal PR revert |
| 1 | operator | key ceremony (`SIGNING_RUNBOOKS.md` §1): generate the release identity offline, backups + restore test, revocation certificate, registry entry, publish public key + keyring via the independent channel | operator confirms publication and restore test | stop; the repo asserts no fingerprint, so nothing to undo in-repo |
| 2 | operator | first signed release (`SIGNING_RUNBOOKS.md` §2): rebuild-and-compare, sign anchor + manifest, verify `verified-signed`, record evidence, publish with signature + keyring | independent-machine verification returns `verified-signed`; README gains the tier-2 block as co-primary (ADR migration plan step 5) | integrity-only release remains valid (`SIGNING_KEY_LIFECYCLE.md` §7) |
| 3 | operator, optional | require-signature becomes the documented default expectation for official releases; emergency integrity-only path stays documented | operator approval after successful signed releases | revert docs |

Recommended sequencing note: Phase 2's first exercise can be a *re-sign of
the current release* (no new version) to rehearse the ceremony end-to-end
before a feature release depends on it.

## 3. Build-session recommendation (between Phases 0 and 2)

The design spec (`docs/superpowers/specs/2026-07-13-production-signing-architecture-design.md`
§6, §7, §12) specifies `prepare-signing-session.sh`,
`record-signing-evidence.sh`, the evidence schema, the CI fixture dry-run,
and the enforcement tests as implementation-ready contracts. Building them is
a normal development session (not operator-gated, no secrets) and de-risks
Phase 2: the ceremony then runs on tested tooling instead of manual
equivalents. Until then, the manual procedures in `SIGNING_RUNBOOKS.md` are
operative.

## 4. Deferred options (operator decision, not scheduled)

| option | summary | revisit condition |
|---|---|---|
| OIDC/keyless CI signing (Sigstore) | ephemeral OIDC-bound signing with transparency log; design in capstone §5.2 | operator reverses the no-automatic-signing rule (`SIGNING_KEY_LIFECYCLE.md` §9); trust model re-derived; gpgv UX preserved |
| signed provenance / SLSA L2–L3 | builder attestation over the reproducible build | after Phase 2; pairs with the OIDC option or a signed provenance statement from the operator ceremony |
| SPDX SBOM publication | standards-formatted view of the release manifest (capstone §6.2) | when downstream consumers request it; low value today |
| multi-signer / threshold signing | split the D3 capability across operators (gap G4) | signer count or release cadence grows |
| minisign/signify re-evaluation | lighter signature tooling (ADR evaluated alternatives) | if it becomes available in all supported harness environments |

## 5. Disaster-recovery plan

Scenarios and responses: `SIGNING_RUNBOOKS.md` §7. Principles:

1. **The D3 root of trust survives total platform loss** — offline custody of
   the primary, encrypted backups, and a separately stored revocation
   certificate.
2. **Recovery never rewrites history** — append-only, no force-push
   (`BRANCH_PROMOTION_POLICY.md` §5); recovery is restore/rotate/re-sign.
3. **Old releases stay verifiable** — revoked and retired keys remain in the
   keyring history (`SIGNING_KEY_LIFECYCLE.md` §8).
4. **Every backup is restore-tested** at creation and annually
   (`SIGNING_RUNBOOKS.md` §1 step 4, §8).
5. **Evidence is reconstructable** — public subsets re-derivable from
   published releases; full records restored from operator backups.

## 6. Migration principles

- **Additive only**: each phase adds capability; no flag day, no breaking
  change to the install or verify flows (compatibility guarantees,
  `BOOTSTRAP_RELEASE_PROCESS.md` §1).
- **Integrity-only remains valid**: unsigned releases keep working per the
  documented emergency path; a signature upgrades authenticity, it is never a
  precondition for integrity checks.
- **One identity, two targets**: anchor and bundle signatures are the same
  ceremony and keyring (capstone §4.1).
- **Everything operator-owned stays operator-owned**: keys, publishing,
  registry, distribution channels.
