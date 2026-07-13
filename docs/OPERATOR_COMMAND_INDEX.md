# Operator Command Index

Tables only — canonical prose lives in the linked documents. Verdicts and
exit codes are normative in `docs/CLI_CONTRACT.md` and
`docs/RELEASE_SIGNING.md`.

## Verify a bootstrap asset

| task | command | success signal |
|------|---------|----------------|
| checksum-verify a pinned script | `sha256sum pixel-dev-setup.sh`, compare with `config/bootstrap-checksums.txt` | digests equal |
| verify an anchor signature (tier 2) | `bash scripts/verify-bootstrap-signature.sh --keyring=PUBKEY_FILE --signature=SIG_FILE ARTIFACT` | exit 0 |

## Verify a release bundle

| task | command | success signal |
|------|---------|----------------|
| unsigned (integrity only) | `bash scripts/verify-release-bundle.sh --bundle=DIR` | `verdict: verified-integrity-only`, exit 0 — authenticity NOT established |
| signed | `bash scripts/verify-release-bundle.sh --bundle=DIR --signature=DIR/SIGNING-MANIFEST.json.asc --keyring=PUBKEY_FILE --require-signature` | `verdict: verified-signed`, exit 0 |

## Build and maintain

| task | command | notes |
|------|---------|-------|
| build a release candidate | `SOURCE_DATE_EPOCH="$(git log -1 --format=%ct)" bash scripts/build-release-candidate.sh --version=X.Y.Z` | refuses dirty trees; `--check` validates without writing |
| refresh checksum pins after editing a pinned script | `bash scripts/update-bootstrap-checksums.sh --write`, then `--check` | same commit as the edit |
| local CI parity | `bash scripts/ci-local.sh` | same gates as `.github/workflows/test.yml`, fail-fast |
| inspect a remote CI run | `gh run list --branch <branch>`, `gh run watch <run-id>` | runbook: `docs/REMOTE_CI_VERIFICATION.md` |

## Audit CI supply chain

| task | command | success signal |
|------|---------|----------------|
| enforce workflow action pins | `python3 scripts/check-github-action-pins.py` | exit 0, `0 violation(s)` — policy: `docs/GITHUB_ACTIONS_PINNING_POLICY.md` |
| update a pinned action | map tag→SHA (`gh api repos/OWNER/REPO/git/refs/tags/vX.Y.Z --jq .object.sha`; for **annotated** tags this returns the tag object — dereference via `gh api repos/OWNER/REPO/git/tags/<tag-object-sha> --jq .object.sha`), update SHA + `# vX.Y.Z` comment together | pin checker + full gate green (policy §7) |
| review action update PRs | Dependabot opens weekly grouped PRs (`.github/dependabot.yml`) | operator review + green remote gate; never auto-merged |

## Exit-code legend

| code | meaning |
|------|---------|
| 0 | success / verified |
| 1 | runtime or trust failure (preflight, build refusal, or a `failed-*` verify verdict) |
| 2 | usage error (unknown flag, invalid value) — never touches state |

Canonical docs: `docs/CLI_CONTRACT.md` · `docs/RELEASE_SIGNING.md` ·
`docs/BOOTSTRAP_RELEASE_PROCESS.md` · `docs/REMOTE_CI_VERIFICATION.md` ·
`docs/SIGNING_KEY_LIFECYCLE.md`
