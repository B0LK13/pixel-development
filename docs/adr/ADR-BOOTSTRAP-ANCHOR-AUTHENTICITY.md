# ADR: Bootstrap Anchor Authenticity

- **Status**: Accepted — primary model implemented; production signing operator-blocked
- **Date**: 2026-07-11 (Session 5, `auto/integrate-session-5`)
- **Deciders**: autonomous session, for operator ratification
- **Related**: `docs/BOOTSTRAP_TRUST_MODEL.md`, `docs/BOOTSTRAP_RELEASE_PROCESS.md`,
  `docs/AUTONOMOUS_AUDIT.md` (R1 history), `scripts/verify-bootstrap-signature.sh`,
  `scripts/update-bootstrap-checksums.sh`

---

## Context

`pixel-bootstrap.sh` is the trust anchor for the whole kit: it fetches and
verifies the two setup scripts against SHA-256 pins embedded in itself
(Session 4, audit R1). That protects the *downstream* scripts, but the anchor
itself arrived over `curl .../main/pixel-bootstrap.sh | bash` — a mutable
branch URL piped straight to a shell. Anyone who could rewrite `main`
(repository compromise, account takeover, malicious force-push) could replace
the anchor and its embedded pins in one move, and every downstream
verification would pass against attacker content. Session 4 classified this
residual gap as a formally blocked sub-item: closing it needs either upstream
signed releases or an out-of-band checksum channel.

Constraints: supported environments are Termux (F-Droid, aarch64), the proot
Ubuntu devbox, and GitHub Actions `ubuntu-latest`; everything must be testable
hermetically (no network, no secrets, no production keys in tests); no signing
infrastructure exists yet and this session may not create production keys.

## Decision

Adopt a **two-tier model**:

1. **Tier 1 — Immutable reference + out-of-band SHA-256 (implemented, now the
   documented operator default).** The README primary install path fetches
   `pixel-bootstrap.sh` from a **full-commit raw URL** and verifies it against
   a **SHA-256 published in the repository's documentation set** before
   execution. The same commit pins `PIXEL_REPO_BASE`, so the two downstream
   scripts also come from the immutable object and match the anchor's
   embedded pins. This is Option A + Option B combined, using the channel
   separation that actually exists today: the digest travels in the docs
   (README / release notes / this ADR set), the script travels over the raw
   content URL, and an operator who distrusts the docs channel can establish
   the digest from a `git clone` instead (git's object model makes the clone
   self-authenticating to the refs the operator fetched).

2. **Tier 2 — Detached gpgv signature (mechanics implemented; production use
   operator-blocked).** `scripts/verify-bootstrap-signature.sh` verifies a
   detached signature against an operator-supplied public keyring using
   `gpgv` (present in Termux via `gnupg`, in proot Ubuntu, and on
   `ubuntu-latest`; no keyserver, no network). The release process
   (`docs/BOOTSTRAP_RELEASE_PROCESS.md`) defines signing at tag time. What is
   *not* done and may not be done by an autonomous session: provisioning a
   maintainer signing key, publishing the public key through an independent
   channel, and blessing it in the README. Those are human trust acts; the
   code is ready for them (see "Blocked prerequisites").

This realizes **Option D** (versioned release + immutable reference + SHA-256
+ detached signature + documented key fingerprint) as the target state, with
every part implemented except the human-owned key material.

## Evaluated alternatives

| option | verdict | why |
|---|---|---|
| A — immutable commit URL | **adopted (Tier 1)** | no new tooling, immutable object reference, trivial operator workflow; alone it still trusts host+account, so it is paired with B |
| B — out-of-band SHA-256 | **adopted (Tier 1)** | separates retrieval from the integrity reference; channels available today: docs/release-notes/clone. Real independence requires the operator to obtain the digest from a different channel than the script — documented, not enforceable in code |
| C — signed release artifact | **adopted as Tier 2 mechanics, production-blocked** | gpgv wins the verifier comparison for this repo: already present in every supported environment (Termux `gnupg`, proot Ubuntu, `ubuntu-latest`), offline verification, no daemon or keyserver needed (`gpgv --keyring`). minisign/signify were evaluated and are the better *ergonomic* long-term choice (tiny binary, simple keys), but minisign is **not** present in the harness environments today and a scheme that cannot be exercised by deterministic fixtures may not ship; cosign is container-oriented and heavier than this repo needs. Key distribution, rotation, and compromised-key response are specified in the release process doc |
| D — combined model | **adopted as the target** | Tier 1 + Tier 2 + versioned tag = D; the only missing piece is human key material |
| status quo (Session 4) | rejected | anchor authenticity formally blocked; README still recommended pipe-to-shell |

## Security properties

- A rewritten `main` branch no longer affects operators who follow the primary
  path: the commit-pinned URL serves the original immutable object (or 404s),
  and a substituted body fails the SHA-256 check.
- A stale CDN/mirror can at worst serve an older genuine pinned kit
  (rollback-grade content), never attacker bytes.
- A manifest-only or script-only alteration is caught by the lockstep gates
  (harness §16/§19) in CI.
- A joint anchor+manifest substitution remains detectable **only** via Tier 2
  (signature against an independently distributed key). Until a maintainer key
  is published, the residual authenticity risk is exactly: "the operator
  trusts that the docs channel that gave them the digest was not
  co-compromised with the raw content channel." This is stated plainly in
  `docs/BOOTSTRAP_TRUST_MODEL.md` §5; nothing in this ADR claims authenticity
  where only integrity is proven.

## Limitations

- Tier 1's digest lives in the same repository as the scripts (README). Its
  independence is procedural (release notes, clone, separate docs page), not
  cryptographic.
- TLS + GitHub account integrity remain part of the trusted computing base
  for Tier 1.
- Signature UX depends on the operator importing the maintainer's public key
  correctly; a wrong keyring yields a clean failure, not a warning.

## Supported environments

All Tier 1 commands run unmodified in Termux (F-Droid) and the proot Ubuntu
devbox: `curl`, `sha256sum` (Termux coreutils / Ubuntu coreutils), `bash`.
Tier 2 needs `gpgv` (`pkg install gnupg` on Termux; present on Ubuntu and
`ubuntu-latest`). The helper skips nothing: a missing verifier is a hard
error, never a silent pass. Hermetic fixtures (harness §18) exercise the full
matrix with ephemeral keys generated inside the test tempdir.

## Migration plan

1. README §1 primary path becomes the pinned+verified block (done, this
   session); the pipe-to-shell one-liner is removed from the primary path.
2. `pixel-bootstrap.sh`'s own header stops advertising the one-liner and
   points at the README verified flow (done).
3. `PIXEL_REPO_BASE` in the documented flow is pinned to the same commit, so
   downstream fetches are immutable too (done).
4. On the next release: maintainer follows
   `docs/BOOTSTRAP_RELEASE_PROCESS.md` — tag, sign, publish digest +
   signature, then advance the README pin.
5. Once a maintainer public key is published out-of-band, the README gains
   the Tier 2 verification block as co-primary.

## Rollback plan

- Any historical full-commit URL is a rollback reference by construction:
  re-run the verified flow with the previous release's commit + digest
  (listed in `docs/BOOTSTRAP_RELEASE_PROCESS.md` §"deprecated-version
  handling"). No state migration is needed; re-running `pixel-bootstrap.sh`
  is idempotent.
- If a pin is found wrong after merge: revert the manifest/README pin commit;
  `scripts/update-bootstrap-checksums.sh --check` and harness §16/§19 go red
  on any inconsistency, so a bad pin cannot be committed green.

## Operator workflow (current, Tier 1)

```bash
curl -fL -o pixel-bootstrap.sh \
  "https://raw.githubusercontent.com/B0LK13/pixel-development/<pinned-commit>/pixel-bootstrap.sh"
printf '%s  %s\n' "<pinned-sha256>" "pixel-bootstrap.sh" | sha256sum -c -
PIXEL_REPO_BASE="https://raw.githubusercontent.com/B0LK13/pixel-development/<pinned-commit>" \
  bash pixel-bootstrap.sh
```

The README §1 block carries the concrete values (no placeholders in the
primary path). Tier 2 adds, once a key is published:

```bash
pkg install gnupg   # Termux; already present on Ubuntu
gpg --import maintainer-bootstrap.pub        # obtained out-of-band
bash scripts/verify-bootstrap-signature.sh \
  --keyring=maintainer-bootstrap.pub \
  --signature=pixel-bootstrap.sh.sig \
  pixel-bootstrap.sh
```

## Acceptance criteria

- [x] Primary install documentation contains no unverified pipe-to-shell.
- [x] Primary path pins a full 40-hex commit and a concrete SHA-256; a harness
      test asserts README pin == the digest of the pinned git object.
- [x] Downstream fetches in the documented flow use the same immutable ref.
- [x] Signature-verification mechanics implemented with `gpgv`, all paths
      quoted, usage errors exit 2, verification failures exit 1 fail-closed,
      covered by hermetic ephemeral-key fixtures.
- [x] Production signing classified operator-blocked with exact prerequisites.
- [x] Trust model, release/rollback process, and this ADR agree on what is
      integrity vs. authenticity.

## Blocked prerequisites (operator-owned)

1. Provision a maintainer signing key (offline, passphrase-protected).
2. Publish the public key through a channel independent of the raw content
   host (project site, keyserver fingerprint cross-posted, release notes).
3. Sign the bootstrap artifact at the next tag and attach the detached
   signature as a release asset.
4. Only then promote Tier 2 to co-primary in the README.
