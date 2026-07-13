# Release Signing (Operator Workflow)

How the operator signs a release bundle offline and how anyone verifies it.
Companion to `docs/BOOTSTRAP_RELEASE_PROCESS.md` (release mechanics),
`docs/SIGNING_KEY_LIFECYCLE.md` (key custody),
`docs/BOOTSTRAP_TRUST_MODEL.md` (threat model),
`docs/PRODUCTION_SIGNING_ARCHITECTURE.md` (architecture capstone), and
`docs/SIGNING_RUNBOOKS.md` (operational procedures).

**Boundary:** signing is always operator-owned. Autonomous sessions build the
bundle and the signing manifest; they never hold a production key, never sign
an official release, and never publish. All signing mechanics are exercised in
CI and in the test suite with **throwaway fixture keys only**.

---

## 1. What gets signed

The release bundle contains `SIGNING-MANIFEST.json`, which binds:

- project name and release version;
- the full git commit the bundle was built from;
- every artifact filename with its SHA-256 digest and mode;
- the SHA-256 of `RELEASE-METADATA.json`;
- the expected detached-signature filename (`SIGNING-MANIFEST.json.asc`).

Signing the manifest therefore signs the version, the commit, and the complete
artifact hash list in one object. Two rules follow:

- A signature **never replaces checksum verification**:
  `scripts/verify-release-bundle.sh` always re-hashes the artifacts after the
  signature check, so a valid signature over altered artifacts still fails
  (`failed-checksum`).
- A signature is authenticity; checksums are integrity — neither substitutes
  for the other.

## 2. Build (operator or CI, network-free)

```bash
# pin all timestamps to the release commit for byte-reproducible output
SOURCE_DATE_EPOCH="$(git log -1 --format=%ct)" \
  bash scripts/build-release-candidate.sh --version=1.0.0
```

Output: `dist/pixel-development-1.0.0/` (9 files: the three pinned scripts,
`bootstrap-checksums.txt`, `SHA256SUMS`, `RELEASE-METADATA.json`,
`SIGNING-MANIFEST.json`, `INSTALL.md`, `VERIFY.md`). The build refuses a dirty
working tree, validates the version format, and checks checksum-manifest
lockstep before producing anything.

## 3. Sign (offline, operator-only)

On a trusted machine holding the signing subkey:

```bash
cd dist/pixel-development-1.0.0
gpg --local-user "<approved-signing-key>" \
    --detach-sign --armor \
    --output SIGNING-MANIFEST.json.asc \
    SIGNING-MANIFEST.json
```

- `<approved-signing-key>` is the operator's release signing identity — never
  hardcoded in the repository, never present in CI.
- Signing input is deterministic: the same bundle rebuilds byte-identically
  from the same commit with the same `SOURCE_DATE_EPOCH` (harness §27), so the
  signer can rebuild before signing and confirm the manifest matches.

## 4. Verify

Integrity only (no trust claim beyond the hashes):

```bash
bash scripts/verify-release-bundle.sh --bundle=./dist/pixel-development-1.0.0
# verdict: verified-integrity-only
```

Signed verification (authenticity, once the operator keyring exists):

```bash
bash scripts/verify-release-bundle.sh \
  --bundle=./dist/pixel-development-1.0.0 \
  --signature=./dist/pixel-development-1.0.0/SIGNING-MANIFEST.json.asc \
  --keyring=./pixel-release-signing.gpg \
  --require-signature
# verdict: verified-signed
```

Verification is read-only: it creates no files and mutates nothing. It runs
offline; `gpgv` needs only the public keyring.

## 5. Signature policy

| situation | behavior |
|---|---|
| signature present and valid, artifacts match | `verified-signed` — ship |
| signature absent | `verified-integrity-only`; with `--require-signature`: `failed-policy`, exit 1 — **do not ship as signed** |
| signature invalid / wrong keyring | `failed-signature`, exit 1 — do not ship |
| valid signature, altered artifact | `failed-checksum`, exit 1 — do not ship |
| valid signature, altered metadata | `failed-metadata`, exit 1 — do not ship |

A release may ship **integrity-only** only when explicitly labelled as such
(see the emergency-unsigned-release case in `docs/SIGNING_KEY_LIFECYCLE.md`).
A signature is authenticity; checksums are integrity; neither substitutes for
the other.

## 6. What this repository does NOT do

- No production private key is stored, generated, or imported here.
- No key ID or fingerprint is hardcoded (fixture keys live under test-only
  paths and are marked non-production).
- Signing never runs automatically — not in the builder, not in CI, not in
  the test suite (fixtures generate and discard their own throwaway keys).
- The verifier never executes downloaded content and never trusts a signature
  file it did not verify.
