# Session 7 — Completion Report

Status: **complete**

## Base and integration

- working branch: `auto/repo-readiness-fixes`
- branch base: `auto/integrate-session-6` tip (`ce8cc92` merge chain)
- main commit: `711c23b41238528c64b5e9a59a5a6cb7ab2c5f9c` (unchanged;
  operator-owned merge, as in Sessions 4–6)
- Session 1–6 ancestry: intact — no history rewritten, no prior work
  duplicated or omitted
- commits this session (7, all GPG-signed, chronological):
  - `b0a8eda` fix: render backlog data as inert text in agent prompt construction
  - `9526e80` chore: add session 7 recovery report and baseline suite evidence
  - `5a0d1f6` docs: bring README repo layout current, pin script paths
  - `818daca` docs: fix verify-release-bundle invocations to equals-form flags
  - `4f64be3` test: keep fixture workspaces from inheriting host commit.gpgsign
  - `a2ed5e8` fix: end --help sed ranges at the banner border, refresh checksums
  - `e98a18d` docs: add session 7 audit follow-up (F17-F19, workstream verdicts)
- conflicts: none; no merges needed this session (single linear branch)
- deviations: the session recovered from two interruptions — the first
  reconstructed into `reports/session-7-recovery.md`, the second (mid-flight,
  after the fixes were staged but uncommitted) re-established from disk with
  the full gate chain re-run before any commit

## Session arc

1. **Recovery first.** Repository state was reconstructed and recorded
   (`reports/session-7-recovery.md`): one committed docs change, one
   uncommitted security-test hunk, no stash, no evidence.
2. **Root cause before code.** The in-flight finding — suspected command
   substitution when BACKLOG.md text flows into the agent prompt — was
   proven **non-exploitable** before any edit: bash does not rescan
   parameter-expanded values, so `$(...)`/backtick payloads are written
   literally. Proven in a minimal case and on the full dispatch path.
3. **Structural hardening anyway.** Prompt construction now routes all
   backlog-derived values through `printf %s` with a quoted-heredoc static
   body — byte-identical output for benign input, immune to future
   `eval`/`sh -c`/`echo -e` edits. Regression test 6f pins the invariant;
   timeout-path block renumbered 6f→6g.
4. **Verification workstreams executed** (below), evidence captured, then
   the full validation pipeline re-run at the final tip.

## Findings (audit addendum: `docs/AUTONOMOUS_AUDIT.md` §Session 7)

- **F17 — INFORMATIONAL** — backlog-derived prompt data verified inert;
  hardened structurally (`b0a8eda`). The drafted vulnerability test passes
  against the unmodified script; it now guards a structural invariant.
- **F18 — LOW, FIXED** — `mk_ws` fixture repos inherited the host's global
  `commit.gpgsign=true`, signing test commits with the operator's real
  keyring (hermeticity break + gpg lock failures). Fixed by pinning
  `commit.gpgsign false`, matching the existing `mk_rc_clone` convention
  (`4f64be3`).
- **F19 — LOW, FIXED** — three `--help` handlers printed live script source
  past the comment banner (stale `sed` ranges), violating the CLI contract.
  Ranges corrected (dev-setup `2,16`, apps-setup `2,17`, autodev `2,15`),
  contract pinned by a new suite assertion (every `--help` line ends with
  `#`), checksum manifest + embedded digests refreshed in lockstep
  (`a2ed5e8`).
- **Unknown-flag-on-stdout — reviewed, no action.** Documented contract
  decision (`docs/CLI_CONTRACT.md` §1: historical stdout, exit 2).

## Verification workstreams

1. **Documentation consistency — verified.** Living docs use the verifier's
   equals-only flag forms (`818daca`); README §10 layout current and pinned
   by harness §29a (`5a0d1f6`); final sweep found zero space-form
   bundle-verifier invocations in `docs/`/README; harness §28 doc contracts
   green.
2. **Dependency audit — clean.** External command inventory unchanged in
   kind (git, ssh/sshd, pkg/apt, curl installers, gpg/gpgv, jq, node/npm,
   python3/uv, sha256sum, GNU timeout, coreutils). No new third-party code;
   no version changes; network-touching paths unchanged (F8/R1 status quo).
3. **Security review — invariants hold.** All 18 release/security
   invariants re-verified by the full suite (§24–§28) at the session tip.
   The session's only security-relevant code change made an incidentally
   safe path structurally safe (F17).
4. **Reproducibility — proven.** Two `SOURCE_DATE_EPOCH=1700000000` builds
   from `a2ed5e8` byte-identical: content, modes, mtimes
   (`evidence/session-7/reproducibility.txt`).
5. **Release validation — proven.** Fixture build `0.0.0` from a clean
   clone of `a2ed5e8`: unsigned verify `verdict: verified-integrity-only`
   (exit 0); signed fixture verify with a throwaway ed25519 key
   `verdict: verified-signed` (exit 0)
   (`evidence/session-7/release-verify.txt`).
6. **Operator documentation — current.** Session 6's operator docs
   (`RELEASE_SIGNING.md`, `SIGNING_KEY_LIFECYCLE.md`,
   `REMOTE_CI_VERIFICATION.md`, `BOOTSTRAP_RELEASE_PROCESS.md`) re-verified
   against the CLIs; the only drift found was the flag-form fix above.
7. **Performance — measured, profile unchanged.** Full gate chain 4–9 min
   on this host (thermal throttling; `evidence/session-7/test-timings.txt`);
   isolated components stay fast (clone ≈2s, builder ≈3s, verifier ≈3s). No
   assertions removed; no harness filters added.
8. **Technical-debt inventory — stable.** R2/R3/R5/R6 implemented
   (Session 3); R1 (installer checksum pinning) and R4 (`--` end-of-options)
   remain deferred with the same rationale; no new R-items. Host-level
   observation outside repo scope: stale `~/.gnupg` lock files from killed
   gpg processes — reported, left untouched (no gpg process running;
   `gpgconf --kill all` + removing `.#lk*` files clears them if desired).
9. **Release-readiness score — READY (integrity-only).** Gates 5/5 green;
   tests 288/0/0; invariants 18/18; reproducibility and both verify
   verdicts evidence-backed; docs contracts green. Remaining items are
   operator-owned by charter: push, merge, production signing identity.
   Releases stay integrity-only until signing governance is approved.

## Tests

- session baseline: 284 passed / 0 failed / 0 skipped (post prompt-hardening;
  `evidence/session-7/test-results.txt`)
- final total: **288 passed / 0 failed / 0 skipped** (+4: the `--help`
  banner-only assertion runs once per product script)
- interim red runs: two — the truncated parity log (gpg locks from F18,
  fixed) and one docs-contract failure caused by this session's own audit
  addendum (a bare script-name mention tripped harness §29b; reworded,
  re-validated). Both caught by the gate chain before commit.
- skipped: 0 in every full gate

## CI

- local parity: `bash scripts/ci-local.sh` at `e98a18d` — ALL GATES PASSED
  (5/5): whitespace, checksum lockstep, bash -n, shellcheck, full suite
  (`evidence/session-7/ci-parity.txt`)
- release-candidate CI job (`release-candidate-check`): statically
  validated; its fixture flow was mirrored locally for the evidence capture
- remote CI run: **not run** — nothing was pushed; operator runbook in
  `docs/REMOTE_CI_VERIFICATION.md`

## Security invariants

All 18 required invariants **PASS** (unchanged set from Session 6,
re-verified at the session tip by harness §24–§28). Failed: none. Blocked:
none. Deferred: production signing itself (operator-owned by charter).

## Documentation

- audit: Session 7 addendum in `docs/AUTONOMOUS_AUDIT.md` (F17–F19 +
  workstream verdicts)
- recovery: `reports/session-7-recovery.md`
- living docs fixed: README §10 layout, verifier flag forms in
  `docs/RELEASE_SIGNING.md`
- CLI contract: unchanged (reviewed; the one ambiguity checked this session
  was already documented)

## Evidence

- CI parity: `evidence/session-7/ci-parity.txt` (final tip, 5/5 gates)
- release validation: `evidence/session-7/release-verify.txt` (build + both
  verdicts at `a2ed5e8`)
- reproducibility: `evidence/session-7/reproducibility.txt` (byte-identical
  builds at `a2ed5e8`)
- suite baseline: `evidence/session-7/test-results.txt`,
  `evidence/session-7/test-timings.txt`
- final report: `reports/session-7-final-report.md` (this file)

## Safety confirmation

- pushed: **no**
- main modified: **no** (still `711c23b`)
- tags created: **no**
- releases published: **no**
- production keys accessed: **no** (evidence signing used a throwaway
  ed25519 key, generated and discarded in a temp GNUPGHOME)
- secrets accessed: **no**
- paid agents invoked: **no**
- commits: 7, all GPG-signed with the operator's devbox key (consistent
  with branch history); no force operations; nothing outside the repository

## Operator choices

1. merge Session 7: `git switch main && git merge --no-ff auto/repo-readiness-fixes`
2. push the review branch and run remote CI (commands below)
3. provision the production signing identity per `docs/SIGNING_KEY_LIFECYCLE.md`
   (carried over from Session 6)
4. build and sign the first release candidate per `docs/RELEASE_SIGNING.md`
5. start the Session 8 workstreams (architecture review → roadmap, per
   `reports/session-7-recovery.md`)
6. optionally clear the stale `~/.gnupg` locks (`gpgconf --kill all`, then
   remove `.#lk*` files) — cosmetic; the suite no longer touches that keyring

## Operator-owned commands (not executed by this session)

Review the graph:

```bash
git log --oneline --decorate --graph --all | head -40
```

Review the Session 7 diff:

```bash
git diff --stat ce8cc92..auto/repo-readiness-fixes
git diff ce8cc92..auto/repo-readiness-fixes
```

Run local CI parity:

```bash
bash scripts/ci-local.sh
```

Run the full suite:

```bash
bash tests/run_tests.sh
```

Build a release candidate:

```bash
SOURCE_DATE_EPOCH="$(git log -1 --format=%ct)" \
  bash scripts/build-release-candidate.sh --version=1.0.0
```

Verify an unsigned bundle:

```bash
bash scripts/verify-release-bundle.sh --bundle=./dist/pixel-development-1.0.0
```

Verify a signed bundle:

```bash
bash scripts/verify-release-bundle.sh \
  --bundle=./dist/pixel-development-1.0.0 \
  --signature=./dist/pixel-development-1.0.0/SIGNING-MANIFEST.json.asc \
  --keyring=./pixel-release-signing.gpg \
  --require-signature
```

Push the review branch and watch remote CI:

```bash
git push origin auto/repo-readiness-fixes
gh run list --branch auto/repo-readiness-fixes
gh run watch <run-id>
```

Merge into main (after green CI on the exact commit):

```bash
git switch main
git merge --no-ff auto/repo-readiness-fixes
```

---

The repository is **ready for an operator-authorized push** of
`auto/repo-readiness-fixes`. No blocker remains within the session charter;
the open items are operator-owned by design (push, merge, production
signing identity) or scheduled (Session 8 workstreams).
