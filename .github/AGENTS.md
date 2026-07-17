# Scoped agent rules for `.github/`

- External actions/reusable workflows must be pinned to full 40-char SHAs with version comments.
- Keep workflow permissions least-privilege.
- Keep verification jobs non-mutating (no pushes/tags/releases).
- Preserve `fetch-depth: 0` where required by repository tests/contracts.
- Ensure workflow changes remain aligned with `scripts/ci-local.sh` parity gates.
- Keep protected workflow semantics deterministic and auditable.
- Shallow-clone behavior must fail clearly where ancestry is required.
