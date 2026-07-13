# Signing Runbooks

Operational procedures for the production signing architecture. Session 11
(2026-07-13), design only: nothing here has been executed against production;
no keys exist beyond throwaway fixtures. Every procedure is **operator-owned**
— autonomous sessions must not generate, import, store, or use production key
material (`SIGNING_KEY_LIFECYCLE.md` §9).

Canonical policy lives in `docs/SIGNING_KEY_LIFECYCLE.md` and
`docs/RELEASE_SIGNING.md`; this document sequences the steps. Until the
protocol tooling (design spec §6.2) is built, the manual equivalents cited
below are the operative commands.

---

## 1. Key ceremony (one-time, per identity)

1. Prepare the environment: offline machine (air-gapped or freshly booted live
   OS); `gpg` present; no network. Confirm no fixture or personal key will be
   reused — the release identity is a **role identity**
   (`SIGNING_KEY_LIFECYCLE.md` §1), never the commit-signing key.
2. Generate: certify-only ed25519 primary + ed25519 signing subkey, with a
   strong passphrase (never passphrase-less). Record the full fingerprint on
   durable media.
3. Create the backups: encrypted export of the private key to two separate
   encrypted offline media; generate the revocation certificate
   (`gpg --gen-revoke`) and store it **separately** from the key.
4. Verify the backups (restore test): on a scratch offline user, import the
   backup, confirm the fingerprint, and sign+verify a test file. A backup that
   has never been restored is not a backup.
5. Record the fingerprint in the operator's authorized-signer registry
   (outside the repo, or a clearly-marked operator doc — the repo never
   asserts a production fingerprint as trusted, `SIGNING_KEY_LIFECYCLE.md` §3).
6. Publish the public key through the independent channel (project website +
   keyserver; fingerprint cross-posted in release notes); export the
   verification keyring `pixel-release-signing.gpg` for distribution as a
   versioned release artifact.
7. Move the signing subkey to its working custody: hardware token (preferred)
   or encrypted offline medium. The primary never leaves offline storage.

Future option (gap G4): split signing across multiple operators
(threshold/multi-signature). Not required; revisit if signer count grows.

## 2. Signing ceremony (per release)

Prerequisites: release checklist `BOOTSTRAP_RELEASE_PROCESS.md` §3 steps 1–6
complete (suite green, checksum lockstep, VERSION bumped, pin history row,
README pin block).

1. **Prepare** — on the trusted signing host with a local clone at the release
   commit:
   `SOURCE_DATE_EPOCH="$(git log -1 --format=%ct)" bash scripts/build-release-candidate.sh --version=X.Y.Z`
   (manual equivalent of `prepare-signing-session.sh`; the builder refuses a
   dirty tree and validates the version).
2. **Rebuild-and-compare** — if the bundle was produced elsewhere (e.g. CI
   artifact for reference), rebuild locally and compare byte-for-byte. Sign
   only the locally reproduced manifest.
3. **Sign** — the only manual cryptographic act:
   `gpg --local-user "<release-signing-key>" --detach-sign --armor --output SIGNING-MANIFEST.json.asc SIGNING-MANIFEST.json`
   inside `dist/pixel-development-X.Y.Z/`. For the anchor (tier 2, at tag
   time): `gpg --detach-sign --armor -o pixel-bootstrap.sh.sig pixel-bootstrap.sh`.
4. **Verify** — `bash scripts/verify-release-bundle.sh --bundle=dist/pixel-development-X.Y.Z --signature=dist/pixel-development-X.Y.Z/SIGNING-MANIFEST.json.asc --keyring=pixel-release-signing.gpg --require-signature`
   must print `verified-signed`. Confirm the signer fingerprint matches the
   registry entry.
5. **Record evidence** — (when built) `record-signing-evidence.sh`; manual
   equivalent: save the verifier transcript and note version, commit, manifest
   SHA-256, signature SHA-256, fingerprint, date in the operator-held record.
   Commit only the public subset (`evidence/releases/<version>/`).
6. **Handoff** — publishing (tag, GitHub release, assets, keyring) is
   operator-owned per `BOOTSTRAP_RELEASE_PROCESS.md` §3 steps 7–10.

Failure handling: any verdict other than `verified-signed` stops the ceremony
— diagnose per `RELEASE_SIGNING.md` §5; never "sign anyway".

## 3. Verification runbook (end operator)

Integrity only:
`bash scripts/verify-release-bundle.sh --bundle=./dist/pixel-development-X.Y.Z`
→ `verified-integrity-only` (authenticity NOT established).

Signed: obtain `pixel-release-signing.gpg` via the independent channel,
cross-check its fingerprint against the value published out-of-band, then:
`bash scripts/verify-release-bundle.sh --bundle=DIR --signature=DIR/SIGNING-MANIFEST.json.asc --keyring=pixel-release-signing.gpg --require-signature`
→ `verified-signed`. Anchor check (direct-fetch flow):
`bash scripts/verify-bootstrap-signature.sh --keyring=pixel-release-signing.gpg --signature=pixel-bootstrap.sh.sig pixel-bootstrap.sh`.

Verdict meanings and policy: `RELEASE_SIGNING.md` §5. Every failure is
fail-closed; there is no "warn and continue".

## 4. Rotation runbook

Per `SIGNING_KEY_LIFECYCLE.md` §5: generate the replacement identity (§1
above); publish the new public key plus a **transition note signed by the old
key**; both keys accepted for one release window; the old key signs nothing
new afterwards; update the keyring artifact, registry, and docs in the same
release. Old keys stay in the keyring history so old releases remain
verifiable (§8).

## 5. Incident runbook — suspected key compromise

1. **Detect** — unexpected signature, unauthorized fingerprint, custody
   breach, or credible report. Log what was observed and when.
2. **Freeze** — halt release activity; mark affected pin-history rows
   `unsupported` (`BOOTSTRAP_RELEASE_PROCESS.md` §2).
3. **Revoke** — publish the pre-generated revocation certificate immediately
   via the independent channel (website + keyserver).
4. **Assess** — list every release signed between last-known-good and
   revocation; treat all as untrusted.
5. **Re-verify sweep** — for each affected release, re-verify artifacts
   against known-good out-of-band digests; record results (evidence plane).
6. **Replace and re-sign** — new identity per §1; transition note signed by
   the old key if it is still trusted for that purpose, else an out-of-band
   announcement; re-sign the current release; publish the new keyring.
7. **Communicate** — release notes, project site, README-adjacent docs;
   instruct operators to re-fetch the keyring.
8. **Post-incident** — update registry, evidence, this runbook, and the
   rotation cadence as warranted; consider the multi-signer option (§1).

## 6. Incident runbook — key unavailable (not compromised)

Key lost, destroyed, or signer unreachable, with no compromise indication:
ship an **integrity-only** release if one cannot wait — clearly labelled,
verified without `--require-signature`, announced as unsigned
(`SIGNING_KEY_LIFECYCLE.md` §7) — and follow with a signed release as soon as
the signing path is restored (backup restore per §7, or a new identity per §1
with out-of-band announcement if no backup exists).

## 7. Disaster recovery

| loss | response |
|---|---|
| signing subkey (backup exists) | restore from encrypted backup on the offline machine; restore-test before use; no identity change needed |
| signing subkey (no backup) | treat as permanent loss: new identity per §1, out-of-band announcement (no old-key transition note possible), re-sign current release, mark the gap in release notes |
| primary key (backup exists) | restore offline; the subkey keeps working; consider rotating the subkey as hygiene |
| primary + all backups | as "subkey, no backup" plus regenerate everything; the old public key remains in the keyring history for old releases |
| verification keyring (public) | regenerate from the published public key — no secret material involved |
| evidence records | reconstruct public subsets from published releases (digests re-computable); full records are operator-held — restore from the operator's own backup |
| repository | restore from any clone (git object model self-authenticates refs); the D3 root of trust is off-platform and unaffected |
| GitHub account | rotate credentials, review audit log, re-publish keyring/fingerprint via the independent channel; releases already signed remain verifiable |

DR principles: the release-signing root of trust must survive total platform
loss (offline custody); recovery never requires force-push or history rewrite
(`BRANCH_PROMOTION_POLICY.md` §5); old releases stay verifiable throughout.

## 8. Annual review checklist (monitoring)

- Key expiry dates and renewal plan; revocation certificate still accessible.
- Registry accuracy: fingerprints, role identities, authorized signers.
- Restore test of every backup (as §1 step 4).
- Doc lockstep: this runbook vs `SIGNING_KEY_LIFECYCLE.md` /
  `RELEASE_SIGNING.md`; harness §16/§18/§28 green.
- Reproducibility spot-check: rebuild the latest release from its pinned
  commit and compare bytes.
