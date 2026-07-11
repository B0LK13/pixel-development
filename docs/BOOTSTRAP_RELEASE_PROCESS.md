# Bootstrap Release Process

How the pinned bootstrap artifacts are versioned, released, verified, updated,
and rolled back. Companion to `docs/BOOTSTRAP_TRUST_MODEL.md` and
`docs/adr/ADR-BOOTSTRAP-ANCHOR-AUTHENTICITY.md`. This document governs
*operator* actions (tags, releases, keys) — an autonomous session may prepare
everything up to the tag, and must not publish.

---

## 1. Versioning model

- The three pinned entry points (`pixel-bootstrap.sh`, `pixel-dev-setup.sh`,
  `pixel-apps-setup.sh`) version **together** with the repository: one
  `VERSION` file (SemVer, currently `1.0.0`), one git tag `vX.Y.Z` per
  release. No per-file versions.
- **Immutable artifact reference**: the full-commit raw URL,
  `https://raw.githubusercontent.com/B0LK13/pixel-development/<full-commit>/<file>`.
  Tags are the human-readable alias (`.../v1.0.0/<file>`), but the tag →
  commit resolution is recorded in the pin history below so the immutable
  form is always recoverable.
- **Checksum manifest schema**: `config/bootstrap-checksums.txt` carries
  `schema v1` in its header. Schema changes (new artifacts, new fields)
  require a schema-version bump, a migration note here, and the tool
  (`scripts/update-bootstrap-checksums.sh`) updated in the same commit.
- **Compatibility guarantees**: within a major version, documented flags keep
  their syntax and ranges; pins only get stricter (never silently removed);
  the verified install flow stays fetch → verify → run.
- **Minimum supported bootstrap version**: the first release carrying the
  verified install flow (this document's seed pin, below). Older
  pipe-to-shell installs are legacy — re-run the current verified flow to
  upgrade; re-running is idempotent.

## 2. Pin history (rollback references)

Append one row per release. The README primary path always shows the **latest
current** row; every older row remains a valid rollback target (an old pin
installs the old, genuine kit).

| version | commit (full) | `pixel-bootstrap.sh` SHA-256 | date | status |
|---|---|---|---|---|
| 1.0.0 | `c8a5466c31d0a8dc4a461da0d3acc2c7ac487610` | `5bbec677ddfbe5fb853686954743b90637479f26ae1f8487622b4572aa0e6785` | 2026-07-11 | current |

(Status values: `current` → `deprecated` → `unsupported`. Deprecated pins
still verify and install; unsupported pins are documented as known-broken and
should not be used.)

## 3. Release checklist (operator)

1. **Update artifacts** — land all script changes through the normal
   branch-per-task flow; full suite green on the integration branch.
2. **Run the checksum tool** — `bash scripts/update-bootstrap-checksums.sh --write`
   in the release commit (updates embedded digests + manifest in lockstep),
   then `bash scripts/update-bootstrap-checksums.sh --check` must exit 0.
3. **Run the full suite** — `bash tests/run_tests.sh` (includes harness §16
   lockstep, §18 README pin, §19 signature fixtures, §20 tool tests).
4. **Review the diff** — `git diff <prev-tag>..HEAD -- pixel-*.sh config/`.
5. **Create the release commit** — bump `VERSION`; add the pin-history row
   below (version, commit, `sha256sum pixel-bootstrap.sh`, date, `current`);
   update the README §1 pin block to the new commit + digest (harness §18
   goes red if the README pin disagrees with the pinned object).
6. **Create the tag** — `git tag -a vX.Y.Z` (annotated; sign it if the
   maintainer signing identity exists: `git tag -s`).
7. **Publish** (operator-owned, this loop never does it): push the branch +
   tag; create the GitHub release; attach `pixel-bootstrap.sh` and, when a
   signing identity exists, `pixel-bootstrap.sh.sig`
   (`gpg --detach-sign --armor`).
8. **Verify the published digest** — from a *different* machine/network:
   fetch the release asset, `sha256sum` it, and compare with the pin-history
   row AND the value published out-of-band (release notes / project site).
9. **Test a fresh installation** — run the README §1 verified flow verbatim
   on a clean Termux install (or the closest available clean environment).
10. **Retain the rollback reference** — flip the previous pin-history row to
    `deprecated` (never delete it).

## 4. Signing (tier 2 — once a maintainer key exists)

- Key provisioning is **operator-owned** (an autonomous session must not
  create production keys): generate offline, passphrase-protect, back up.
- Publish the public key through a channel **independent** of the raw content
  host (project site + keyserver fingerprint cross-posted in release notes).
- Sign at tag time: `gpg --detach-sign --armor -o pixel-bootstrap.sh.sig pixel-bootstrap.sh`.
- Operators verify: `bash scripts/verify-bootstrap-signature.sh --keyring=<pub> --signature=pixel-bootstrap.sh.sig pixel-bootstrap.sh`.
- **Key rotation**: publish the new key + a transition note signed by the old
  key; both keys accepted for one release window; update the docs.
- **Compromised key**: revoke immediately, publish revocation out-of-band,
  re-sign the current release with the replacement key, mark affected rows
  `unsupported`. The README never embeds a private key or a "trusted"
  fingerprint that has not been established out-of-band.

## 5. Rollback procedure

1. Pick the target row from the pin history (§2).
2. Re-run the verified flow with that row's commit + digest:
   ```bash
   curl -fL -o pixel-bootstrap.sh \
     "https://raw.githubusercontent.com/B0LK13/pixel-development/<row-commit>/pixel-bootstrap.sh"
   printf '%s  %s\n' "<row-sha256>" "pixel-bootstrap.sh" | sha256sum -c -
   PIXEL_REPO_BASE="https://raw.githubusercontent.com/B0LK13/pixel-development/<row-commit>" \
     bash pixel-bootstrap.sh
   ```
3. The kit re-installs the pinned (older) setup scripts; no state migration
   is needed. If the rollback is due to a bad release, mark that row
   `unsupported` in the next docs commit.

## 6. Archive handling

**Decision: the canonical release artifact is the bundle *directory*.** Core
tooling (`scripts/build-release-candidate.sh`) produces the directory only;
archives are derived conveniences created by the operator or CI, never a
release gate.

Rationale:

- A directory verifies directly with `scripts/verify-release-bundle.sh`; an
  archive adds an extract step whose safety (path traversal, symlink
  entries) would also need verification.
- Deterministic `.tar.gz` needs GNU flags (`--sort=name`, `--owner=0`,
  `--group=0`, `--numeric-owner`, `--mtime`). All three supported
  environments ship GNU tar (Termux `tar` package, proot Ubuntu,
  `ubuntu-latest`), but the kit's rule is to not *assume* GNU-only behavior
  without a fallback — so archiving is documented, not gated.
- `.zip` is non-deterministic by default (entry order, per-entry timestamps)
  and is not produced.

Operator/CI command (deterministic; use the epoch recorded at build time):

```bash
SOURCE_DATE_EPOCH=<unix-timestamp>
tar --sort=name --owner=0 --group=0 --numeric-owner \
    --mtime="@${SOURCE_DATE_EPOCH}" \
    -czf pixel-development-<version>.tar.gz \
    pixel-development-<version>
```

If `tar --sort=name` is unsupported on a host, the directory bundle remains
fully valid — ship the directory or archive from a host with GNU tar.
Directory-bundle reproducibility is proven by harness §27 and
`evidence/session-6/reproducibility.txt`.

## 7. What this session did NOT do

No tag was created, no release was published, no signing key was provisioned,
and nothing was pushed. The pin history above is seeded from the verified
Session 4 integration tip (`c8a5466`), which is the first installable pin of
the verified flow.
