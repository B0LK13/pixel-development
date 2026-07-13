# Release Dry Run (Throwaway Identity) — Operator Runbook

Roadmap item 0.2 (`reports/project-roadmap.md`, Horizon 0): rehearse the
full signed-release ceremony on a **throwaway** identity before any
production key exists — build → sign → `verified-signed` → publish
checklist walkthrough, plus a disaster-recovery pass (lost key, wrong
artifact, tampered bundle).

Companion to `docs/RELEASE_SIGNING.md` (signing mechanics + policy),
`docs/SIGNING_KEY_LIFECYCLE.md` (production key custody — the real
ceremony), and `docs/BOOTSTRAP_RELEASE_PROCESS.md` §3 (release checklist).

**Roles:** an autonomous session prepares this runbook and rehearses it
(evidence: `evidence/session-13/dry-run-rehearsal.txt`); the **operator**
executes it. Nothing here creates or touches a production key.

**Hermeticity:** every command below runs offline — no network, no
keyservers, no paid agents, no package installs. Tools required: `git`,
`gpg` + `gpgv` (gnupg), `sha256sum`, GNU `date`/`touch` (already required
by the builder). All scratch state lives under one `mktemp` directory and
is destroyed at the end.

**Rule for the whole run:** if any expected output does not match, STOP.
Do not improvise a workaround; record the divergence and hand it back.

---

## 0. Setup — one scratch root for everything

Run from the repository root on the commit chosen for the dry run
(a clean tree is a build gate — `git status --porcelain` must be empty).

Run §0 and **every subsequent step in the same shell session**. `WORK`
and `GNUPGHOME` are shell-scoped variables: they will not survive
opening a new terminal or starting an unrelated shell. Losing them is a
STOP condition — restart the dry run from §0 with a fresh scratch root;
do not reconstruct the values by hand.

```bash
cd /path/to/pixel-development
git status --porcelain   # expected: empty output

# all throwaway state lives here; nothing is written anywhere else
WORK="$(mktemp -d /tmp/pixel-dry-run.XXXXXX)"
GNUPGHOME="$WORK/gnupg"; export GNUPGHOME
mkdir -p "$GNUPGHOME"; chmod 700 "$GNUPGHOME"
```

Version used throughout: `1.0.0` (hypothetical — the bundle never leaves
`$WORK`; no tag or release is created).

## 1. Provision the throwaway signing identity

An isolated GnuPG home, an ed25519 signing key, no passphrase, an identity
string that says THROWAWAY, and a 1-day expiry — the exact opposite of the
production rules in `docs/SIGNING_KEY_LIFECYCLE.md` §1, on purpose.

The throwaway key is **mandatory** for this dry run. Do not substitute,
import, reference, or use any production, release, maintainer, or other
long-lived signing key at any point. The `<approved-signing-key>`
placeholder used in `docs/RELEASE_SIGNING.md` describes the future
production architecture only — it is not an instruction to insert a real
key into this rehearsal. Discovering a production key or production
credential in the environment is a STOP condition: halt the run and treat
it as a custody finding (`docs/SIGNING_KEY_LIFECYCLE.md` §5/§6).

```bash
cat > "$WORK/keyparams" <<'EOF'
Key-Type: eddsa
Key-Curve: ed25519
Key-Usage: sign
Name-Real: Pixel THROWAWAY Dry Run (NOT PRODUCTION)
Name-Email: throwaway-dry-run@example.invalid
Expire-Date: 1d
%no-protection
%commit
EOF
gpg --batch --gen-key "$WORK/keyparams"
```

Record the fingerprint (display only — it is never trusted by anything):

```bash
KEYID="throwaway-dry-run@example.invalid"
gpg --fingerprint "$KEYID"
FPR="$(gpg --batch --with-colons --list-secret-keys "$KEYID" \
  | awk -F: '/^fpr:/ {print $10; exit}')"
printf 'throwaway fingerprint: %s\n' "$FPR"
```

Export the public keyring the verifier will use (this file is the dry-run
stand-in for the future `pixel-release-signing.gpg` release artifact,
`docs/SIGNING_KEY_LIFECYCLE.md` §4):

```bash
gpg --export "$KEYID" > "$WORK/throwaway-signing.gpg"
```

Also provision a **second** throwaway key — the disaster-recovery pass
needs a wrong keyring:

```bash
cat > "$WORK/keyparams2" <<'EOF'
Key-Type: eddsa
Key-Curve: ed25519
Key-Usage: sign
Name-Real: Pixel THROWAWAY Wrong Key (NOT PRODUCTION)
Name-Email: throwaway-wrong@example.invalid
Expire-Date: 1d
%no-protection
%commit
EOF
gpg --batch --gen-key "$WORK/keyparams2"
gpg --export throwaway-wrong@example.invalid > "$WORK/throwaway-wrong.gpg"
```

## 2. Build the release candidate

Pin `SOURCE_DATE_EPOCH` to the dry-run commit for byte-reproducible
output (`docs/RELEASE_SIGNING.md` §2; reproducibility proven by harness
§27):

```bash
SOURCE_DATE_EPOCH="$(git log -1 --format=%ct)" \
  bash scripts/build-release-candidate.sh --version=1.0.0 \
  --output-dir="$WORK/dist"
# expected: "release candidate built: .../pixel-development-1.0.0" (exit 0)
```

The build refuses a dirty tree, validates the version, and checks
checksum-manifest lockstep before writing anything.

Required signer confirmation and reproducibility comparison (the future
production ceremony does this — the signer rebuilds and compares before
signing). This is the dry run's reproducibility proof and is **not
skippable**: rebuild from the same inputs and compare the resulting
files, modes, and digests. Any difference is a STOP condition —
investigate; do not sign.

```bash
SOURCE_DATE_EPOCH="$(git log -1 --format=%ct)" \
  bash scripts/build-release-candidate.sh --version=1.0.0 \
  --output-dir="$WORK/dist-recheck" >/dev/null
diff -r "$WORK/dist/pixel-development-1.0.0" \
        "$WORK/dist-recheck/pixel-development-1.0.0"
# expected: no output (byte-identical rebuild; any output = STOP)
```

## 3. Sign the manifest (throwaway key, offline)

Exactly the mechanics of `docs/RELEASE_SIGNING.md` §3, with the throwaway
identity standing in for `<approved-signing-key>`:

```bash
BUNDLE="$WORK/dist/pixel-development-1.0.0"
gpg --batch --yes --local-user "$KEYID" \
    --detach-sign --armor \
    --output "$BUNDLE/SIGNING-MANIFEST.json.asc" \
    "$BUNDLE/SIGNING-MANIFEST.json"
# expected: no output on success (exit 0)
```

## 4. Verify

Integrity only (no authenticity claim — baseline mode):

```bash
bash scripts/verify-release-bundle.sh --bundle="$BUNDLE"
# expected last line: verdict: verified-integrity-only
```

Signed verification (the dry run's target verdict):

```bash
bash scripts/verify-release-bundle.sh \
  --bundle="$BUNDLE" \
  --signature="$BUNDLE/SIGNING-MANIFEST.json.asc" \
  --keyring="$WORK/throwaway-signing.gpg" \
  --require-signature
# expected: ok lines for layout/metadata/signing manifest/signature/
#           checksums, then: verdict: verified-signed   (exit 0)
```

`verified-signed` on a throwaway key proves the **mechanics** end to end;
it says nothing about production trust — the production keyring and its
out-of-band publication are Horizon 0 items 0.1/0.2's operator ceremony.

## 5. Publish checklist walkthrough (NOT executed)

Walk `docs/BOOTSTRAP_RELEASE_PROCESS.md` §3 with placeholders. The dry run
**reads and confirms** each step; it executes none of the irreversible
ones. Mark each `[ ]` as reviewed:

- [x] §3.1–3.3 — artifacts landed, checksum lockstep green, full suite
  green (preconditions of the commit this runbook sits on).
- [x] §3.4 — bundle flow exercised: build + both verifier modes
  (steps 2–4 above).
- [ ] §3.5 — review the release diff:
  `git diff <prev-tag>..HEAD -- pixel-*.sh config/`
- [ ] §3.6 — release commit: bump `VERSION`, add the pin-history row,
  update the README §1 pin block (harness §18 enforces agreement).
- [ ] §3.7 — tag (**walkthrough only; the dry run creates no tags**):
  `git tag -a v<version> -m "release <version>"`
  (production: `git tag -s` once the signing identity exists).
- [ ] §3.8 — publish (**walkthrough only; nothing is pushed**):
  `git push origin <branch> v<version>`; create the GitHub release;
  attach `pixel-bootstrap.sh` and, once a signing identity exists,
  `pixel-bootstrap.sh.sig`.
- [ ] §3.9 — verify the published digest **from a different
  machine/network**: fetch the release asset, `sha256sum` it, compare
  with the pin-history row and the out-of-band value.
- [ ] §3.10 — fresh-install test on a clean environment (README §1 flow,
  verbatim).
- [ ] §3.11 — flip the previous pin-history row to `deprecated` (never
  delete it).

## 6. Disaster-recovery pass

Each scenario starts from a fresh copy of the signed bundle from step 3,
so scenarios are independent. Every expected failure is `exit 1` with the
named verdict — anything else is a divergence: STOP.

**Execution order matters:** the lost-key scenario (DR-3) destroys the
signing capability the other scenarios need, so it runs last. (Session 13
rehearsal found this the hard way: run first, it silently turns the
wrong-artifact scenario into a false `verified-signed` — see
`reports/session-13-final-report.md`.)

### DR-1 — wrong artifact

(a) A signature over the wrong file must never validate the manifest:

```bash
cp -a "$BUNDLE" "$WORK/dr1a"
gpg --batch --yes --local-user "$KEYID" \
    --detach-sign --armor \
    --output "$WORK/dr1a/SIGNING-MANIFEST.json.asc" \
    "$WORK/dr1a/INSTALL.md"
bash scripts/verify-release-bundle.sh \
  --bundle="$WORK/dr1a" \
  --signature="$WORK/dr1a/SIGNING-MANIFEST.json.asc" \
  --keyring="$WORK/throwaway-signing.gpg" \
  --require-signature
# expected: verdict: failed-signature (exit 1)
```

The signature is genuine — over the wrong file. The verifier checks the
signature against `SIGNING-MANIFEST.json` only, so a valid signature over
anything else is `failed-signature`; it never says why beyond the verdict,
by design.

(b) The right signature checked against the wrong keyring:

```bash
bash scripts/verify-release-bundle.sh \
  --bundle="$BUNDLE" \
  --signature="$BUNDLE/SIGNING-MANIFEST.json.asc" \
  --keyring="$WORK/throwaway-wrong.gpg" \
  --require-signature
# expected: verdict: failed-signature (exit 1)
```

**Recovery action:** re-sign the correct `SIGNING-MANIFEST.json` with the
approved key; re-export and redistribute the correct public keyring. In
production, a wrong-keyring failure also means: re-check which fingerprint
was published out-of-band (`docs/SIGNING_KEY_LIFECYCLE.md` §4) — a
keyring that does not match the ceremony record is itself a finding.

### DR-2 — tampered bundle

(a) Altered artifact bytes (signature stays valid — checksums must still
fail closed; harness §26 invariant 9):

```bash
cp -a "$BUNDLE" "$WORK/dr2a"
printf 'x\n' >> "$WORK/dr2a/pixel-bootstrap.sh"
bash scripts/verify-release-bundle.sh \
  --bundle="$WORK/dr2a" \
  --signature="$WORK/dr2a/SIGNING-MANIFEST.json.asc" \
  --keyring="$WORK/throwaway-signing.gpg" \
  --require-signature
# expected: verdict: failed-checksum (exit 1)
```

(b) Altered signed manifest:

```bash
cp -a "$BUNDLE" "$WORK/dr2b"
printf 'x\n' >> "$WORK/dr2b/SIGNING-MANIFEST.json"
bash scripts/verify-release-bundle.sh \
  --bundle="$WORK/dr2b" \
  --signature="$WORK/dr2b/SIGNING-MANIFEST.json.asc" \
  --keyring="$WORK/throwaway-signing.gpg" \
  --require-signature
# expected: verdict: failed-signature (exit 1)
```

(c) Altered metadata (manifest binding must catch it):

```bash
cp -a "$BUNDLE" "$WORK/dr2c"
sed -i -E 's/"created_at": "[0-9]{4}/"created_at": "2099/' \
  "$WORK/dr2c/RELEASE-METADATA.json"
bash scripts/verify-release-bundle.sh \
  --bundle="$WORK/dr2c" \
  --signature="$WORK/dr2c/SIGNING-MANIFEST.json.asc" \
  --keyring="$WORK/throwaway-signing.gpg" \
  --require-signature
# expected: verdict: failed-metadata (exit 1)
```

**Recovery action:** do not ship, do not "fix" the bundle in place.
Rebuild from the pinned commit (step 2 — a reproducible build must match
byte-for-byte), re-sign, re-verify. If a tampered bundle was already
published, treat it as a bad release: mark the pin-history row
`unsupported` and publish a corrected release
(`docs/BOOTSTRAP_RELEASE_PROCESS.md` §2/§5).

### DR-3 — lost key (destructive — runs last)

Simulate total loss of the private key (the backup is gone with it):

```bash
gpg --batch --yes --delete-secret-keys "$FPR"
gpg --list-secret-keys "$KEYID"
# expected: no output — the dry-run identity is gone (the second,
# wrong-key identity remains, by design)
```

Attempt to sign a new bundle — it must be impossible. The copied `.asc`
is removed first so a leftover valid signature cannot mask the failure:

```bash
cp -a "$BUNDLE" "$WORK/dr3"
rm -f "$WORK/dr3/SIGNING-MANIFEST.json.asc"
gpg --batch --yes --local-user "$KEYID" \
    --detach-sign --armor \
    --output "$WORK/dr3/SIGNING-MANIFEST.json.asc" \
    "$WORK/dr3/SIGNING-MANIFEST.json"
# expected: exit 2, "gpg: signing failed: No secret key"
```

Already-signed releases stay verifiable — the exported public keyring
survives the private-key loss:

```bash
bash scripts/verify-release-bundle.sh \
  --bundle="$BUNDLE" \
  --signature="$BUNDLE/SIGNING-MANIFEST.json.asc" \
  --keyring="$WORK/throwaway-signing.gpg" \
  --require-signature
# expected: verdict: verified-signed (exit 0)
```

**Recovery action (production, per `docs/SIGNING_KEY_LIFECYCLE.md`):**
restore the private key from the encrypted offline backup (§2); if the
backup is also lost or compromise is suspected, generate the replacement
key, publish it with a transition note, re-sign the current release, and
publish a new verification keyring (§5/§6). Retired keys stay in the
keyring history so old releases remain verifiable (§8). A release blocked
by an unavailable key may ship integrity-only, clearly labelled (§7).

## 7. Destroy the throwaway identity

The dry run leaves nothing behind:

```bash
gpgconf --homedir "$GNUPGHOME" --kill all
unset GNUPGHOME
rm -rf "$WORK"
ls -d "$WORK" 2>/dev/null || printf 'scratch root destroyed\n'
# expected: scratch root destroyed
```

Nothing in the repository changed; the only persistent artifacts of the
operator run are the operator's own notes.

---

## Operator-ceremony checklist

Execute in order; every command block above is copy-pasteable verbatim
after step 0 sets `WORK`/`GNUPGHOME`:

- [ ] 0. Setup: clean tree confirmed; scratch root created
- [ ] 1. Throwaway identity provisioned (THROWAWAY marker, no passphrase,
      1-day expiry); fingerprint recorded on paper/notes; keyring exported;
      second (wrong) key provisioned
- [ ] 2. Bundle built; required rebuild-compare byte-identical (STOP on
      any difference)
- [ ] 3. Manifest signed (exit 0)
- [ ] 4. `verified-integrity-only` then **`verified-signed`** observed
- [ ] 5. Publish checklist walked; every irreversible step confirmed as
      NOT executed (no tag, no push, no release)
- [ ] 6. DR-1 wrong artifact: `failed-signature` ×2 observed
- [ ] 6. DR-2 tampered bundle: `failed-checksum`, `failed-signature`,
      `failed-metadata` observed
- [ ] 6. DR-3 lost key (last — destructive): signing impossible; old
      bundle still `verified-signed`; recovery procedure read aloud
      against `docs/SIGNING_KEY_LIFECYCLE.md` §5–§7
- [ ] 7. Throwaway identity destroyed; scratch root gone
- [ ] Divergences (if any) recorded and handed back before proceeding to
      production key provisioning (roadmap 0.1)

## What this does NOT do

- No production key is generated, imported, stored, or used — the
  throwaway identity is marked NOT PRODUCTION, has no passphrase, expires
  in a day, and is destroyed at the end of the run.
- No tags, releases, packages, or images are created; nothing is pushed;
  no network is contacted; the publish checklist is a walkthrough, not an
  execution.
- No repository files change (the build writes only under `$WORK`; the
  verifier is read-only).
- A `verified-signed` verdict here establishes **mechanics only** — not
  production trust. Production trust requires the operator key ceremony
  (roadmap 0.1, `docs/SIGNING_KEY_LIFECYCLE.md`) and out-of-band public
  key publication.
- The throwaway key must never sign anything outside this run and must
  never be reused — same rule as the test fixtures
  (`docs/SIGNING_KEY_LIFECYCLE.md` §9).
