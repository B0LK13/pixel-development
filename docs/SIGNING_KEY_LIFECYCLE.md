# Signing Key Lifecycle (Production — Operator-Owned)

Governance for the future production release-signing identity. This document
prescribes **no** key material and creates none; the repository contains only
throwaway test fixtures. Every step below is operator-owned — autonomous
sessions must not generate, import, store, or use production keys.

Companion to `docs/RELEASE_SIGNING.md` (signing mechanics) and
`docs/BOOTSTRAP_RELEASE_PROCESS.md` §4 (tier-2 signing at tag time).

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
  artifact so `verify-release-bundle.sh --keyring` has a canonical input.
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
  `verify-release-bundle.sh` without `--require-signature`, and announced as
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
