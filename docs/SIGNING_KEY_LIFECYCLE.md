# Signing Key Lifecycle (Production — Operator-Owned)

Governance for the future production release-signing identity. This document
prescribes **no** key material and creates none; the repository contains only
throwaway test fixtures. Every step below is operator-owned — autonomous
sessions must not generate, import, store, or use production keys.

Companion to `docs/RELEASE_SIGNING.md` (signing mechanics),
`docs/BOOTSTRAP_RELEASE_PROCESS.md` §4 (tier-2 signing at tag time),
`docs/PRODUCTION_SIGNING_ARCHITECTURE.md` (architecture capstone), and
`docs/SIGNING_RUNBOOKS.md` (operational procedures).

---

## 1. Key generation

- **Environment**: an offline, trusted machine (air-gapped or freshly booted
  live OS); never a CI runner, never a shared host.
- **Algorithm**: Ed25519 (`gpg --full-generate-key` → ECC sign/certify, or a
  certify-only primary with an Ed25519 signing subkey). 4096-bit RSA is an
  acceptable conservative alternative.
- **Passphrase**: mandatory. Production keys must never be passphrase-less.
  (The repo's *fixture* keys are passphrase-less by design and are marked
  non-production; they must never be reused for anything real.)
- **Identity**: project role identity (e.g. `pixel-development release
  signing <releases@…>`), not a personal address that may change.

## 2. Custody and backup

- Private key material lives on encrypted offline storage (hardware token or
  encrypted removable media), not in the repository, not in CI secrets, not
  in cloud notes.
- At creation time, also generate and store offline:
  - an encrypted backup of the private key;
  - a **revocation certificate** (`gpg --gen-revoke`), stored separately from
    the key itself.
- Record the public fingerprint on paper or equivalent durable media.

## 3. Authorized signers

- Maintain a short, explicit list of authorized signing fingerprints in
  operator documentation (outside the repo or in a clearly-marked operator
  doc; the repo never asserts a production fingerprint as trusted).
- Releases signed by any other identity are not official, whatever the
  signature's cryptographic validity.

## 4. Public-key distribution

- Publish the public key through a channel **independent** of the raw content
  host: project website plus a keyserver, with the fingerprint cross-posted
  in release notes and in `docs/BOOTSTRAP_RELEASE_PROCESS.md` §4 once
  established.
- Distribute the verification keyring (`gpg --export`) as a versioned release
  artifact so `scripts/verify-release-bundle.sh --keyring` has a canonical input.
- The README must never embed a "trusted" fingerprint that was not
  established out-of-band.

## 5. Rotation

- Rotate on a planned cadence or when custody changes.
- Publish the new public key plus a **transition note signed by the old key**.
- Both keys are accepted for one release window; the old key signs nothing
  new after the window closes.
- Update the docs and the verification keyring in the same release.

## 6. Revocation and suspected compromise

- Suspected compromise → publish the revocation certificate immediately
  through the independent channel, and mark affected releases `unsupported`
  in the pin history (`docs/BOOTSTRAP_RELEASE_PROCESS.md` §2).
- Re-sign the current release with the replacement key and publish a new
  verification keyring.
- Treat every artifact signed between the suspected compromise and revocation
  as untrusted until re-verified against a known-good digest published
  out-of-band.

## 7. Emergency unsigned releases

- If signing is impossible (key unavailable, signer unreachable), a release
  may ship **integrity-only**: clearly labelled, verified with
  `scripts/verify-release-bundle.sh` without `--require-signature`, and announced as
  unsigned.
- Ship a signed follow-up as soon as the signing path is restored.
- Integrity-only releases prove hashes, not authenticity — say so.

## 8. Historical verification

- Retain every released public key (including revoked ones) in the
  verification keyring history so old releases remain verifiable.
- Revoked keys verify *signatures made before revocation*; the revocation
  date is part of the trust decision, which the tooling surfaces rather than
  hides.

## 9. Hard rules

- No private keys in the repository, in CI secrets, or in test fixtures
  beyond throwaway, clearly-marked, non-production material.
- No passphrase-less production keys.
- No automatic signing — a human operator runs the sign command.
- Signature verification precedes trusting signed hashes; checksum
  verification always follows (see `docs/RELEASE_SIGNING.md` §5).

## 10. Recovery

Recovering use of the key when there is **no** compromise indication
(compromise follows §6 and `docs/SIGNING_RUNBOOKS.md` §5):

- **Subkey lost, backup exists**: restore the encrypted backup on the offline
  machine; verify the fingerprint against the durable record created at
  generation (§1); sign and verify a scratch file before returning the key to
  custody. A backup that fails a restore test is treated as no backup.
- **Primary lost, backup exists**: restore offline the same way; the signing
  subkey keeps working in the meantime; rotate the subkey afterwards as
  hygiene.
- **All backups lost (key still in custody)**: immediately create fresh
  encrypted backups and a fresh revocation certificate, and restore-test them.
- **Key lost entirely (no backups)**: permanent loss — provision a new
  identity per §1, announce out-of-band (no old-key transition note is
  possible), re-sign the current release, and note the gap in the release
  notes. The old public key stays in the keyring history (§8).
- **Forgotten passphrase**: treated as key loss. There is no recovery path by
  design — never weaken the passphrase policy to recover convenience.

Record every recovery event (what, when, which backup, restore-test result)
in the operator-held log. Recovery never relaxes §9: offline handling and
passphrase protection apply throughout.

## 11. Destruction

- **When**: an identity is retired after its rotation window closes (§5),
  media is decommissioned, or a compromised identity is cleaned up after
  revocation (§6).
- **How**: destroy all private key material — delete working copies
  (`gpg --delete-secret-keys`) and securely wipe or physically destroy the
  storage media. When retiring early (before natural expiry), revoke first,
  then destroy, so a rediscovered backup cannot be misused.
- **Retain forever**: the **public** key stays in the verification keyring
  history so old releases remain verifiable (§8); the destruction event
  (date, identity, method) is recorded in the operator-held log.
- **Fixture keys**: throwaway test keys are destroyed with their temp
  directories at the end of every test run — this is already the harness
  convention and needs no ceremony.
