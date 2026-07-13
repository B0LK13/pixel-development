# Bootstrap Trust Model

How trust flows (and where it can break) when an operator installs the Pixel
Lab Kit. This document is the threat model behind the install flow in
`README.md` §1, the verification machinery in `pixel-bootstrap.sh`, the
checksum lifecycle in `scripts/update-bootstrap-checksums.sh`, and the
architecture decision in `docs/adr/ADR-BOOTSTRAP-ANCHOR-AUTHENTICITY.md`.

Status: current as of `auto/integrate-session-5`; the signing side is extended
by Session 11 (`docs/SIGNING_TRUST_MODEL.md`, `docs/SIGNING_THREAT_MODEL.md`,
`docs/PRODUCTION_SIGNING_ARCHITECTURE.md`). Normative behavior is
enforced by `tests/run_tests.sh` (sections 16–21); this prose explains *why*.

---

## 1. The trust chain

```
operator pastes command into Termux
  → shell parses the command line
  → DNS resolves raw.githubusercontent.com
  → TLS handshake + certificate validation
  → HTTP(S) GET (possibly via CDN cache / redirect)
  → pixel-bootstrap.sh arrives on disk
  → operator verifies it (SHA-256 pin, or signature when available)
  → pixel-bootstrap.sh runs
      → resolves REPO_BASE (embedded default, --repo-base, or PIXEL_REPO_BASE)
      → fetches config pins (embedded copy) / config/bootstrap-checksums.txt
      → downloads pixel-dev-setup.sh, pixel-apps-setup.sh to a temp file
      → verifies each against the pinned SHA-256 BEFORE install
      → installs to ~/.local/share/pixel, chmod +x
      → writes ~/.shortcuts launchers
  → setup scripts run (package installs, third-party installer pipes)
```

## 2. Trust assumptions at each boundary

| boundary | assumption | what protects it today |
|---|---|---|
| operator command | the pasted command is the one the operator intended | operator diligence; the README primary path is now a copy-paste block with a concrete commit + digest, not a bare pipe |
| shell / local PATH | no hostile alias/function shadows `curl`, `sha256sum`, `bash` | nothing (local environment is out of scope — see §4) |
| DNS resolution | `raw.githubusercontent.com` resolves to GitHub | TLS certificate validation (below) |
| TLS transport | GitHub's certificate chain is genuine | the platform CA store (Termux/proot Ubuntu); no pinning |
| CDN cache / redirect | content served is the repository object requested | for commit-pinned URLs: GitHub serves the immutable object; for branch URLs: whatever the branch currently points at |
| raw content URL | branch `main` is mutable; a full commit path is immutable | the README pins a full 40-hex commit SHA |
| `pixel-bootstrap.sh` itself | the downloaded file is the one the maintainer released | **SHA-256 pin (integrity, if the operator's digest is authentic) or a maintainer signature (authenticity, when provisioned)** — see §5 |
| embedded hashes | the pins inside the verified bootstrap are trustworthy | they are part of the file the operator just verified — integrity inherits from the anchor |
| `config/bootstrap-checksums.txt` | the manifest in the repo matches the shipped scripts | harness §16 lockstep + `scripts/update-bootstrap-checksums.sh --check` in CI; the manifest is governance, not an independent trust root |
| downstream scripts | match their pins after download | temp-file download → verify → install (fail closed); no `curl \| bash` |
| local hash utility | `sha256sum`/`shasum` computes SHA-256 correctly | coreutils in every supported environment; missing tool = abort, never skip-verify |
| third-party installer pipes inside `pixel-dev-setup.sh` (nodesource, claude.ai, astral.sh) | vendor domains + TLS | none — charter's package-install exception; a different trust boundary (vendor CLIs, not this repo's payloads) |

## 3. Attacker capabilities considered

| attacker capability | consequence today | mitigation status |
|---|---|---|
| compromised repository branch (`main` force-pushed) | branch-URL installs serve attacker content | **mitigated for the anchor**: README pins a full commit; branch URL no longer appears in the primary path. Downstream scripts are commit-pinned via `PIXEL_REPO_BASE` in the same block |
| compromised GitHub account | attacker can rewrite any branch, publish releases, edit release notes | partially mitigated: commit-pinned objects they *rewrite* would change the object hash (a force-push creates new objects; the pinned SHA still resolves to the original object while it is retained); a fully compromised account can still delete/hide objects and publish attacker-signed releases if they also hold the signing key |
| malicious force-push | as above | as above |
| stale CDN / mirror | serves older (but authentic) pinned content, or wrong content | wrong content fails the SHA-256/signature check (fail closed); stale pinned content installs an older but genuine kit — rollback semantics, acceptable |
| network truncation | partial download | curl `-f` + temp-file + digest check: partial never matches, never installs |
| local PATH manipulation (hostile `curl`/`sha256sum` shim) | arbitrary local code regardless of our flow | out of scope: a hostile local shell already owns the operator; documented in §4 |
| altered checksum manifest alone | nothing: the manifest is not consulted at install time by `pixel-bootstrap.sh` (it verifies against embedded pins); CI/tool gates go red | lockstep tests; manifest drift is a governance failure, not a code-exec path |
| altered bootstrap **and** manifest together | attacker content verifies against attacker pins | **the residual authenticity gap** — only a signature verified against an independently distributed public key closes this; see the ADR |
| compromised signing key | attacker signs malicious releases that verify | key-rotation + revocation procedure in `docs/BOOTSTRAP_RELEASE_PROCESS.md`; the operator's trusted keyring is the root, so key compromise is a governance incident, not a silent failure mode |
| malicious local shell environment | anything | out of scope (§4) |

## 4. Out of scope

- A hostile *local* environment (compromised Termux, PATH shims, evil
  `sha256sum`). An attacker with local code execution already has everything
  this kit installs; no remote-verification scheme helps.
- The third-party vendor installer pipes inside `pixel-dev-setup.sh`
  (nodesource, claude.ai, astral.sh). Those fetch vendor CLIs under the
  charter's package-install exception and are a separate trust boundary from
  this repository's payloads.
- Platform support beyond the evidenced set (Termux F-Droid aarch64, proot
  Ubuntu, GitHub Actions `ubuntu-latest`). macOS/WSL/Git Bash remain
  unverified.

## 5. Integrity vs. authenticity — the distinction that matters

- **Integrity** = "the bytes I downloaded are the bytes someone intended at
  pin-time." SHA-256 pins provide this *if the pin itself is authentic*.
- **Authenticity** = "the bytes come from the maintainer I trust." Only a
  signature verified against a public key obtained through an independent
  channel provides this.

The Session 4 pins give the downstream scripts integrity once the anchor is
trusted. Session 5 upgrades the anchor: the README primary path now fetches
`pixel-bootstrap.sh` from an **immutable commit URL** and verifies it against
a **SHA-256 published in this document set** (integrity), with a **gpgv
signature-verification helper** (`scripts/verify-bootstrap-signature.sh`)
whose mechanics are implemented and hermetically tested so that a maintainer
signing identity can be added without code changes (authenticity —
operator-blocked: a human must provision and publish the key; see the ADR).

## 6. Failure behavior summary

Every verification failure is **fail closed**: exit 1, nothing installed, temp
files removed by an `EXIT` trap (which also runs after signal-triggered
exits), and a diagnostic naming the artifact. There is no "warn and continue"
path for verification failures anywhere in the bootstrap chain.
