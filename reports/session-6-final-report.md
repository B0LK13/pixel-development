# Session 6 — Completion Report

Status: **complete**

## Base and integration

- selected base: `auto/integrate-session-5`
- base commit: `a97d95b` (Session 5 integration tip)
- main commit: `711c23b41238528c64b5e9a59a5a6cb7ab2c5f9c` (unchanged; Session 5
  never merged into main — main still contains only Session 3 content)
- Session 5 ancestry: intact — `auto/integrate-session-6` was created from
  `a97d95b`; no Session 1–5 work duplicated or omitted
- integration branch: `auto/integrate-session-6`
- final integration commit: tip of `auto/session-6-evidence` at report time (see evidence/session-6/final-status.txt); the merge commit into `auto/integrate-session-6` is recorded in the session chat report
- conflicts: none (all six merges clean, `ort` strategy)
- deviations: the prompt's separate docs branches (`auto/remote-ci-docs`,
  `auto/signing-key-lifecycle-docs`, `auto/release-signing-workflow`) were
  consolidated into one `auto/release-docs` branch — the three documents
  cross-reference each other and are pinned by a single harness section (§28);
  one extra fix branch (`auto/fix-rc-fixture-clone`) was needed when the
  committed builder made the fixture clone's `cp` a no-op (now idempotent)

## Release candidate

- build command: `bash scripts/build-release-candidate.sh --version=X.Y.Z`
  (optional `--check`, `--output-dir=DIR`, `--keep-partial`; `--help`)
- output layout (9 files): `pixel-bootstrap.sh`, `pixel-dev-setup.sh`,
  `pixel-apps-setup.sh` (0755), `bootstrap-checksums.txt` (0644),
  `SHA256SUMS`, `RELEASE-METADATA.json`, `SIGNING-MANIFEST.json`,
  `INSTALL.md`, `VERIFY.md`
- atomic behavior: built in a temp dir and renamed into place; incomplete
  output removed on failure unless `--keep-partial`
- dirty-tree handling: refuses tracked *and* untracked changes
  (`git status --porcelain`), exit 1, nothing built (harness §24l)
- version validation: strict SemVer `X.Y.Z`, equals-sign only, malformed
  forms exit 2
- artifact inventory: exactly the 4 hashed artifacts + 5 generated docs;
  allowlist enforced by the verifier

## Release metadata

- schema: `schema_version: 1.0`, deterministic key ordering, one-line sorted
  artifact objects
- version: SemVer, must match the signing manifest
- commit binding: full 40-hex git SHA, cross-checked against the manifest
- checksum binding: lowercase SHA-256 per artifact + `release_metadata_sha256`
  in the manifest; verifier re-hashes everything
- mode validation: scripts `0755`, manifest `0644`; inconsistent modes rejected
- path safety: normalized relative paths only; traversal, duplicates, and
  unexpected entries rejected (harness §24o/§25e)

## Signing

- signing manifest: binds project + version + commit + artifact digests +
  metadata digest + expected signature filename
- fixture algorithm: OpenPGP detached signatures, ephemeral ed25519 keys
  generated per test/CI run, marked non-production
- operator signing command:
  `gpg --local-user "<approved-key>" --detach-sign --armor --output SIGNING-MANIFEST.json.asc SIGNING-MANIFEST.json`
- verification command:
  `bash scripts/verify-release-bundle.sh --bundle <dir> --signature <asc> --keyring <pub> --require-signature`
- production key status: **operator-blocked** — no production key exists in
  the repo or CI; lifecycle governance documented in
  `docs/SIGNING_KEY_LIFECYCLE.md`
- authenticity status: releases are **integrity-only** until an operator
  signs with a key whose fingerprint was published out of band

## Bundle verification

- unsigned result: `verdict: verified-integrity-only` (explicitly no
  authenticity claim)
- signed result: `verdict: verified-signed` (fixture-proven, harness §26)
- failure modes: `failed-layout`, `failed-metadata`, `failed-signature`,
  `failed-checksum`, `failed-policy` — each with dedicated injection tests
- exit behavior: 0 verified, 1 trust failure, 2 usage error; one actionable
  diagnostic per failure

## Reproducibility

- first build: `SOURCE_DATE_EPOCH=1700000000` from fixture commit
- second build: same commit, same epoch, independent output dir
- comparison: `diff -r` + mode/mtime listing + sha256 listing — byte-identical
- SOURCE_DATE_EPOCH: pins `created_at` and all mtimes; non-numeric values
  rejected with exit 1 before any output
- conclusion: **byte-for-byte reproducible** for a pinned epoch (directory
  bundle); evidence/session-6/reproducibility.txt

## CI

- local parity: `bash scripts/ci-local.sh` — ALL GATES PASSED (5/5) from an
  arbitrary cwd (evidence/session-6/ci-parity.txt)
- release-candidate gate: `release-candidate-check` job, ubuntu-latest,
  5-minute cap, `contents: read`
- signature fixture gate: per-run throwaway ed25519 key signs the fixture
  bundle; `--require-signature` verify must print `verified-signed`
- reproducibility gate: second `SOURCE_DATE_EPOCH=0` build + `diff -r` in CI
- remote CI run: **not run** — nothing was pushed; operator runbook in
  `docs/REMOTE_CI_VERIFICATION.md`
- operator action required: push the review branch and watch the run
  (commands below)

## Tests

- starting baseline: 199 passed / 0 failed / 0 skipped
- final total: 281 passed / 0 failed / 0 skipped
- failed: 0 (interim red runs fixed before commit: grep `--` separator in
  §22, doc line-wrap in §28a — both caught by the fast suite pre-commit)
- skipped: 0 in every full gate
- clean-clone: nested clean-clone smoke passes in every full gate
- release-specific: §24 builder (24), §25 verifier failure injection (24),
  §26 signed fixtures (11), §27 reproducibility (3), §28 docs + verifier
  hygiene (7 + side-effect proof), §22 release-job contract (7)
- duration: full gates 4m–8m on this host (thermal throttling; isolated
  components: clone ≈2s, builder ≈3s, verifier ≈3s — no suite defect found,
  no assertions removed)

## Security invariants

All 18 required invariants **PASS**:

1. artifacts hashed before signing — builder writes SHA256SUMS/manifest in the
   same atomic pass (§24)
2. signature covers artifact hash list + release identity — manifest binds
   version/commit/digests (§24e, §26)
3. signed metadata cannot reference a different commit unnoticed — manifest ↔
   metadata cross-check (§25 c3, §26 s7)
4. signature verification precedes trusting signed hashes — verifier order
   (§26 s6/s7)
5. checksums verified after signature verification — verifier order (§26 s6)
6. unsigned verification never claims authenticity — `verified-integrity-only`
   wording (§25a/25x)
7. `--require-signature` fails when absent — `failed-policy` (§25b)
8. invalid signature fails closed — `failed-signature` (§26 s3–s5)
9. valid signature + altered artifact fails checksum (§26 s6)
10. valid artifacts + altered metadata fails consistency (§26 s7)
11. release tools include no files outside the repository (§24o)
12. unsafe symlinks rejected (§25e)
13. dirty trees cannot produce release candidates (§24l)
14. no production keys in tests or CI — fixture-only ed25519, workflow comment
15. CI cannot publish/tag/push/invoke agents — §22 no-publish check,
    `contents: read`
16. incomplete directories cannot be mistaken for complete bundles — atomic
    rename + layout allowlist (§24, §25)
17. reproducibility claims evidence-backed — §27 + reproducibility.txt
18. operator verification side-effect free — bundle byte-identical after a
    verify run (§28g)

Failed: none. Blocked: none. Deferred: production signing itself
(operator-owned by charter).

## Documentation

- signing workflow: `docs/RELEASE_SIGNING.md`
- release process: `docs/BOOTSTRAP_RELEASE_PROCESS.md` (+ §6 archive decision)
- remote CI: `docs/REMOTE_CI_VERIFICATION.md`
- key lifecycle: `docs/SIGNING_KEY_LIFECYCLE.md`
- README: §11 links the three new docs
- audit: Session 6 addendum in `docs/AUTONOMOUS_AUDIT.md`

## Evidence

- release candidate: evidence/session-6/release-verify.txt (build + both
  verdicts)
- reproducibility: evidence/session-6/reproducibility.txt
- signature fixtures: covered in evidence/session-6/test-results.txt (§26)
- CI parity: evidence/session-6/ci-parity.txt
- baseline + gate chain: evidence/session-6/baseline-record.txt,
  test-results.txt, test-timings.txt
- final report: reports/session-6-final-report.md (this file)

## Safety confirmation

- pushed: **no**
- main modified: **no** (still `711c23b`)
- tags created: **no**
- releases published: **no**
- production keys accessed: **no**
- secrets accessed: **no**
- paid agents invoked: **no**

## Operator choices

1. merge Session 6: `git switch main && git merge --no-ff auto/integrate-session-6`
2. push the review branch and run remote CI (see commands below)
3. provision the production signing identity per `docs/SIGNING_KEY_LIFECYCLE.md`
4. build and sign the first release candidate per `docs/RELEASE_SIGNING.md`
5. retain integrity-only releases until signing governance is approved

## Operator-owned commands (not executed by this session)

Review the graph:

```bash
git log --oneline --decorate --graph --all | head -40
```

Review the Session 6 diff:

```bash
git diff --stat a97d95b..auto/integrate-session-6
git diff a97d95b..auto/integrate-session-6
```

Build a release candidate:

```bash
SOURCE_DATE_EPOCH="$(git log -1 --format=%ct)" \
  bash scripts/build-release-candidate.sh --version=1.0.0
```

Verify an unsigned bundle:

```bash
bash scripts/verify-release-bundle.sh --bundle ./dist/pixel-development-1.0.0
```

Verify a signed bundle:

```bash
bash scripts/verify-release-bundle.sh \
  --bundle ./dist/pixel-development-1.0.0 \
  --signature ./dist/pixel-development-1.0.0/SIGNING-MANIFEST.json.asc \
  --keyring ./pixel-release-signing.gpg \
  --require-signature
```

Run local CI parity:

```bash
bash scripts/ci-local.sh
```

Run the full suite:

```bash
bash tests/run_tests.sh
```

Push the review branch and watch remote CI:

```bash
git push origin auto/integrate-session-6
gh run list --branch auto/integrate-session-6
gh run watch <run-id>
```

Merge into main (after green CI on the exact commit):

```bash
git switch main
git merge --no-ff auto/integrate-session-6
```

---

The repository is **ready for an operator-authorized push** of
`auto/integrate-session-6`. No blocker remains within the session charter;
the only open items are operator-owned by design (push, merge, production
signing identity).
