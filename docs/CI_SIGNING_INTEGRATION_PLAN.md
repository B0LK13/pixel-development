# CI Signing Integration Plan

How CI integrates with the release-trust program — by design, without ever
holding signing material. Session 12 (2026-07-13), design only: **no workflow
is modified by this document**; the changes below are specifications for the
B2/B3 build-session tasks (`docs/IMPLEMENTATION_BACKLOG.md`: RT-05, RT-06,
RT-07, RT-08). Architecture: `docs/PRODUCTION_SIGNING_ARCHITECTURE.md` §5;
enforcement invariants: §5.3 there; contracts: the design spec
(`docs/superpowers/specs/2026-07-13-production-signing-architecture-design.md`)
§7.

---

## 1. Current CI state (accurate as of Session 12)

`.github/workflows/test.yml`, two jobs, both `contents: read`, both checkouts
SHA-pinned with `fetch-depth: 0` and `persist-credentials: false`
(`docs/GITHUB_ACTIONS_PINNING_POLICY.md`):

- **`suite`** — pin check → shellcheck install → whitespace gate → checksum
  lockstep → `bash tests/run_tests.sh` (327 assertions).
- **`release-candidate-check`** — builds a fixture bundle (version `0.0.0`,
  reserved for CI), verifies unsigned, verifies reproducibility, and already
  runs an **ad-hoc fixture sign/verify cycle**: generates a throwaway ed25519
  key in `$RUNNER_TEMP/gnupg`, signs `SIGNING-MANIFEST.json`, and asserts
  `verdict: verified-signed`.

Local parity: `scripts/ci-local.sh` gates 1–6 (whitespace, checksum lockstep,
action pins, `bash -n`, shellcheck, full suite), fail-fast in order.

What is missing: the ad-hoc fixture cycle proves the *verifier* but not the
*protocol* — the prepare/record tooling, the evidence schema, and the
fingerprint check have no CI coverage until B2 lands.

## 2. Design principles

1. **Fixture-only**: CI generates and discards throwaway keys per run; no
   production material can exist on a runner (`docs/SIGNING_TRUST_MODEL.md`
   D2).
2. **Least privilege**: `contents: read` suffices for every planned step; no
   new permissions, secrets, or environments.
3. **Parity lockstep**: every workflow gate must exist in
   `scripts/ci-local.sh` in the same order (existing CI-parity harness
   section); local and remote results must agree
   (`docs/BRANCH_PROMOTION_POLICY.md` §4).
4. **Fail closed**: new steps are blocking; `continue-on-error` is prohibited.
5. **Cheap gates first**: fast checks precede the expensive suite/dry-run.

## 3. Planned changes

### 3.1 RT-05 — Protocol dry-run step (B2), `release-candidate-check`

Replace the ad-hoc "Sign with a throwaway CI fixture key, verify signed"
step with protocol-driven steps (design sketch — **not applied**):

```yaml
      - name: Protocol dry-run: prepare (fixture)
        run: bash scripts/prepare-signing-session.sh --version=0.0.0 --commit=HEAD
      - name: Protocol dry-run: fixture key + sign
        run: |
          set -e
          export PIXEL_FIXTURE_GNUPGHOME="$RUNNER_TEMP/fx-gnupg"
          mkdir -p "$PIXEL_FIXTURE_GNUPGHOME"; chmod 700 "$PIXEL_FIXTURE_GNUPGHOME"
          printf 'Key-Type: eddsa\nKey-Curve: ed25519\nKey-Usage: sign\nName-Real: CI Fixture\nName-Email: ci@example.invalid\n%%no-protection\n%%commit\n' > "$RUNNER_TEMP/keyparams"
          GNUPGHOME="$PIXEL_FIXTURE_GNUPGHOME" gpg --batch --gen-key "$RUNNER_TEMP/keyparams"
          B="$(ls -d dist/pixel-development-0.0.0)"
          GNUPGHOME="$PIXEL_FIXTURE_GNUPGHOME" gpg --batch --yes --local-user ci@example.invalid \
            --detach-sign --armor --output "$B/SIGNING-MANIFEST.json.asc" "$B/SIGNING-MANIFEST.json"
      - name: Protocol dry-run: record + assert evidence
        run: |
          FP="$(GNUPGHOME="$PIXEL_FIXTURE_GNUPGHOME" gpg --list-keys --with-colons ci@example.invalid | awk -F: '/^fpr:/{print $10; exit}')"
          bash scripts/record-signing-evidence.sh --fixture \
            --bundle=dist/pixel-development-0.0.0 \
            --signature=dist/pixel-development-0.0.0/SIGNING-MANIFEST.json.asc \
            --expect-fingerprint="$FP" --evidence-out="$RUNNER_TEMP/evidence"
          grep -q '"verdict": "verified-signed"' "$RUNNER_TEMP/evidence/signing-evidence.json"
```

Rationale for replacement rather than addition: `record-signing-evidence.sh`
runs `scripts/verify-release-bundle.sh --require-signature` internally, so
verifier coverage is preserved; the unsigned-verification and reproducibility
steps stay unchanged. The exact bundle path handling is an implementation
detail of RT-01's output contract (design spec §6.2).

### 3.2 RT-06 — Enforcement tests (B2), suite-only

New harness assertions (no workflow change): scan `.github/workflows/` and
fail on any signing-secret reference (`secrets.*SIGN`, `secrets.*KEY`,
`secrets.*GPG`, case-insensitive) and on any `gpg --detach-sign` outside a
fixture context (fixture context = the step sets `PIXEL_FIXTURE_GNUPGHOME` or
`GNUPGHOME` under `$RUNNER_TEMP`). This converts capstone §5.3 invariants 1–2
from convention to test.

### 3.3 RT-07 — Parity (B2), `scripts/ci-local.sh`

Add gates 7+ in the same order as the workflow: protocol fixture dry-run
(using a local temp `GNUPGHOME`, network-free) and the enforcement scan.
Update the header comment's gate list and the CI-parity harness section so
the two gate lists cannot drift. Cheap-first ordering: enforcement scan
before the dry-run; the full suite stays last.

### 3.4 RT-08 — Evidence subset re-verification (B3), `release-candidate-check`

New step after the dry-run:

```yaml
      - name: Re-verify committed evidence subsets
        run: bash scripts/verify-release-evidence.sh --all   # RT-08; passes vacuously when evidence/releases/ is empty
```

For each `evidence/releases/<version>/signing-evidence.json`: check out the
referenced commit into a temp worktree, rebuild with the recorded epoch,
re-verify against the committed keyring reference, and compare digests.
Attestational only (capstone §7.2): failure blocks promotion but never
invalidates a published release — the signature + independent keyring remain
authoritative. The helper script is part of RT-08's scope; its contract is
specified in `docs/RELEASE_ACCEPTANCE_CRITERIA.md` AC-B3.

## 4. OIDC option (deferred — design only)

If the operator ever reverses the no-automatic-signing rule
(`docs/SIGNING_KEY_LIFECYCLE.md` §9; revisit conditions in the design spec
§13), the only acceptable workflow shape is:

- a dedicated `release-sign` job in a **separate workflow** triggered by tag
  push, inside a GitHub `environment` with required reviewers;
- `permissions: id-token: write, contents: read` on that job only — all other
  jobs keep `contents: read`;
- OIDC token exchanged for an ephemeral, identity-bound signing capability
  (Sigstore Fulcio model) or a cloud KMS key with an OIDC-only access policy;
- signature + certificate published to a transparency log;
- the environment's required-reviewers gate preserves a human checkpoint
  before any signing step.

This session takes no step toward it; the paragraph exists so the evaluation
is never repeated from scratch.

## 5. Invariant-to-test mapping

| invariant (capstone §5.3) | enforced by |
|---|---|
| 1. no signing secrets in workflows | RT-06 suite scan |
| 2. no non-fixture signing step | RT-06 suite scan (fixture-context rule) |
| 3. verification jobs need no secrets | existing workflow review + RT-06 |
| 4. no publish step reachable from verification triggers | existing workflow shape (no publish steps exist); RT-06 asserts it stays so |
| 5. no `continue-on-error` for green | existing policy (`docs/BRANCH_PROMOTION_POLICY.md` §4); suite review |

## 6. What this session does NOT change

No workflow file, `scripts/ci-local.sh`, or harness content is modified by
Session 12. The YAML above is a design sketch inside documentation; the
§30 action-pin checker scans only `.github/workflows/*.yml` and is
unaffected. All current gates remain exactly as verified at the Session 11
baseline (327/0/0, `ci-local` exit 0, pins 0 violations).

## 7. Validation plan for the build session

After implementing RT-05–RT-08: `bash tests/run_tests.sh` (new total
recorded), `bash scripts/ci-local.sh` (new gates green),
`python3 scripts/check-github-action-pins.py` (0 violations), then the remote
run on the PR — confirming the dry-run step executes the fixture protocol
end-to-end and the evidence re-verification step passes vacuously.
