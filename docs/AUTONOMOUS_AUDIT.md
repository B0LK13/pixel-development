# Autonomous Audit — pixel-development

Security, hygiene, and portability review performed on the integration branch
`auto/integrate-session-1` (base: `main` @ `bf8109c`). Method: targeted
`grep`/`shellcheck` scans, full manual read of all four scripts, the harness,
and the CI workflow; every finding below lists evidence and verification.

Scope: `pixel-*.sh`, `tests/run_tests.sh`, `.github/workflows/test.yml`,
`.pixel-lab.json`, README/KICKSTART. No secrets were accessed; no agent was
invoked; no network calls were made by the audit itself.

## Severity summary

| severity | count | fixed this session | deferred (recommendation) |
|----------|-------|--------------------|---------------------------|
| critical | 0 | — | — |
| high | 0 | — | — |
| medium | 1 | 1 | — |
| low | 6 | 3 | 3 |
| informational | 7 | — | — |

## Findings

### F1 — MEDIUM — `--timeout` accepted arbitrary strings (FIXED)
- **Evidence**: session-1 `pixel-autodev.sh` passed `$TIMEOUT` straight to
  `timeout "$TIMEOUT" …`; `--timeout=abc` would fail cryptically mid-run and
  `--timeout=0` silently disabled the safety cap.
- **Impact**: confusing failures; operator could unknowingly remove the
  per-task wall-clock guard.
- **Action**: positive-integer validation before preflight, exit 2 with a
  clear message (`pixel-autodev.sh:55-60`). Default unchanged (1200).
- **Verification**: harness §6a (4 invalid values) + §6b (resolution) — green.

### F2 — LOW — agent dispatch was not hermetically testable (FIXED)
- **Evidence**: `agent_run` invoked `claude`/`codex` via PATH; the preflight
  PATH scrub puts `/root/.local/bin` etc. first, so a stub on PATH loses to a
  real installed agent — a test could have triggered a paid API call.
- **Impact**: un-testable safety-critical path; paid-call risk in tests.
- **Action**: `CLAUDE_BIN` / `CODEX_BIN` override seams defaulting to the real
  binaries (`pixel-autodev.sh:31-32`); behavior unchanged in normal use.
- **Verification**: harness §6e/§6f run full success + timeout paths against
  stub agents — green; no agent invoked.

### F3 — LOW — timeout expiry indistinguishable from agent failure (FIXED)
- **Evidence**: any non-zero agent rc produced the same "agent errored"
  warning and log line.
- **Impact**: operator could not tell a slow task from a broken one.
- **Action**: rc==124 branch — distinct warning + `RESULT: FAILED (timeout
  after Ns)` in the run log (`pixel-autodev.sh:262-272`).
- **Verification**: harness §6c (mechanism rc=124) + §6f (both backends).

### F4 — LOW — harness did not lint itself / `cd` unchecked (FIXED)
- **Evidence**: `shellcheck -S warning tests/run_tests.sh` flagged SC2164
  (`cd "$ROOT"` without `|| exit`); the gate only linted product scripts.
- **Action**: `cd … || exit 1`; harness added to its own shellcheck gate.
- **Verification**: harness §2 self-lint — green.

### F5 — LOW — `bash -c "$t"` executes the configured test command (ACCEPTED)
- **Evidence**: `pixel-autodev.sh:185` runs `.pixel-lab.json`'s `test` field.
- **Impact**: that is the runner's purpose; the trust boundary is the
  workspace. The agent never writes `.pixel-lab.json` autonomously without a
  task; commits happen only on green, never pushed.
- **Action**: none — documented here and in the CLI contract; recommendation:
  only point autodev at trusted workspaces.
- **Verification**: inspection; harness exercises the dry-run/seeding paths.

### F6 — LOW — `--ssh-port` unvalidated (DEFERRED → R2)
- **Evidence**: `pixel-apps-setup.sh:34` accepts any string; a non-numeric
  port would be written verbatim into `sshd_config` (Termux-only path).
- **Impact**: broken sshd config on fat-finger; no security impact (userspace).
- **Action**: documented in `CLI_CONTRACT.md`; recommend `1–65535` validation.

### F7 — LOW — `--max-tasks` / `--max-turns` / `--budget` unvalidated (DEFERRED → R3)
- **Evidence**: `pixel-autodev.sh:40-42`; non-numeric `--max-tasks` breaks the
  arithmetic loop bound.
- **Action**: documented; recommend positive-integer validation like `--timeout`.

### F8 — INFORMATIONAL — `curl | bash` installers
- **Evidence**: `pixel-dev-setup.sh` (nodesource, claude.ai, astral.sh),
  `pixel-bootstrap.sh:65` (raw GitHub fetch of the setup scripts).
- **Impact**: TLS-only integrity; supply-chain trust in those endpoints.
  Matches the charter's package-install exception and the README's privacy §9.
- **Action**: none; future hardening idea R1: checksum/signature pinning.

### F9 — INFORMATIONAL — SC2015 (`A && B || C`) notes ×8
- **Evidence**: shellcheck info notes at `pixel-bootstrap.sh:47`,
  `pixel-dev-setup.sh:138,204`, `pixel-apps-setup.sh:86,120,261`,
  `pixel-autodev.sh:244,288`.
- **Impact**: reviewed each site — in every case `C` is the *desired* outcome
  when `B` fails (fall back / warn / default), so the idiom is correct.
- **Action**: none; justified here (gate is `-S warning`; these are info).

### F10 — INFORMATIONAL — no secrets in the repository
- **Evidence**: scans for password/token/key patterns find only placeholders
  (`ANTHROPIC_API_KEY=...` in README/KICKSTART docs) and the chartered
  privacy text. `.gitignore` excludes `.env`, `*.key`, `*.pem`.
- **Action**: none.

### F11 — INFORMATIONAL — `--yes` is a deliberate no-op in two scripts
- **Evidence**: `pixel-apps-setup.sh:33`, `pixel-autodev.sh:49`.
- **Impact**: accepted for CLI parity with `pixel-dev-setup.sh` (where it is
  live); neither script prompts. Session-1 decision: keep, do not remove.
- **Action**: documented in `CLI_CONTRACT.md`.

### F12 — INFORMATIONAL — resilient-installer error model
- **Evidence**: `trap … ERR` + per-item continue in `pixel-dev-setup.sh:57`
  and `pixel-apps-setup.sh:52`; failures are logged and summarised
  (`FAILED` array), never hidden.
- **Action**: none — intentional for a best-effort phone installer.

### F13 — INFORMATIONAL — filesystem destructive-ops review
- **Evidence**: `rm -f` only on mktemp files (`pixel-autodev.sh:258`,
  `pixel-apps-setup.sh:161`); harness `rm -rf` is guarded to its own
  `mktemp -d` root (`tests/run_tests.sh:70`); `mv` only for atomic backlog
  updates (`pixel-autodev.sh:207`). No broad `rm`/`mv`/`cp`.
- **Action**: none.

### F14 — INFORMATIONAL — no `readlink -f` / `realpath` anywhere
- **Impact**: one classic macOS/Git-Bash portability trap is simply absent.
- **Action**: none.

### F15 — LOW — `--` is not an options terminator; `--agent` has no enum check (DEFERRED → R4/R5)
- **Evidence**: `--` hits the unknown-flag arm (exit 2) in all scripts;
  `--agent=foo` passes preflight only if a `foo` binary exists, then takes the
  claude dispatch branch.
- **Action**: documented as current contract (harness pins `--` → exit 2);
  change only if a concrete need appears.

### F16 — INFORMATIONAL — no `.gitattributes`
- **Evidence**: all files are LF ASCII; product scripts are mode 100755.
- **Impact**: on Windows with `autocrlf`, checkout would break shebangs — but
  Windows is unsupported (see portability). Recommend R6: add
  `.gitattributes` (`* text=auto eol=lf`) as cheap insurance.

## Portability review (Workstream 7)

**Supported environments — determined from docs + implementation, with evidence:**

1. **Termux (F-Droid) on aarch64 Android** — the primary target. Evidence:
   README §1/§4; Termux shebangs; preflights die elsewhere
   (`pixel-bootstrap.sh:47`, `pixel-dev-setup.sh:76-78`, `pixel-apps-setup.sh:86`).
2. **proot Ubuntu devbox (glibc)** — the AI/autodev layer. Evidence:
   `pixel-autodev.sh` preflight PATH scrub + Termux-binary leak guard.
3. **GitHub Actions `ubuntu-latest`** — the harness/CI gate. Evidence:
   `.github/workflows/test.yml`; the suite is designed for it (stubs, no
   network, repo-local git identity in fixtures).

**Not supported (no claim made):**

- **macOS**: product scripts require Termux; additionally GNU-isms would
  break: `sed 's/…/\+/…'` in `slugify` (`pixel-autodev.sh:177`), GNU-style
  `sed -i` (`pixel-apps-setup.sh:115`), and `timeout(1)` (absent from base
  macOS). bash 3.2 itself would mostly cope, but the sed/timeout gaps are fatal.
- **WSL**: product scripts die at the Termux preflight by design. The
  *harness* would likely run (Linux bash + coreutils), but this is untested —
  no claim.
- **Git Bash on Windows**: no `timeout`, no Termux, CRLF/autocrlf risk
  (F16) — unsupported.

**Recommendations if wider support is ever desired**: replace `sed \+` with a
POSIX bracket class, guard `sed -i` by platform, and detect `timeout` vs
`gtimeout`. Until then, the supported matrix above is the contract.

## Recommendations register (backlog candidates, not implemented)

- **R1**: pin checksums/signatures for the `curl | bash` installers.
- **R2**: validate `--ssh-port` as `1–65535`.
- **R3**: validate `--max-tasks` / `--max-turns` / `--budget` numerically.
- **R4**: support `--` as end-of-options (only with a concrete need).
- **R5**: validate `--agent` against `claude|codex` early.
- **R6**: add `.gitattributes` with `* text=auto eol=lf`.

## Decision records (this loop)

- **D1**: integration happens on `auto/integrate-session-1`; `main` is never
  merged to without explicit operator direction; nothing is pushed.
- **D2**: `--yes` stays a no-op in apps-setup/autodev (CLI parity; F11).
- **D3**: `CLAUDE_BIN`/`CODEX_BIN` seams are the sanctioned way to test agent
  dispatch without paid calls (F2).
- **D4**: shellcheck gate is `-S warning`; the 9 remaining info notes
  (SC2015 ×8, SC2016 ×1) are individually justified (F9 + harness line 162,
  where the single-quoted `'timeout "\$TIMEOUT"'` pattern is intentional —
  it must match the literal text in `pixel-autodev.sh`).

## Session 3 follow-up (auto/integrate-session-3)

Decisions on the deferred register, each validated against the current code
before any change:

- **F6 / R2 — implemented.** `--ssh-port` is validated as an integer in
  1–65535 before the log file is created or preflight runs (exit 2, flag
  named on stderr). Leading zeros are tolerated and canonicalised
  (`08022` → `8022`), matching the `--timeout` convention; the canonical
  value is what every consumer sees, so the `sed -i` replacement can no
  longer receive a metacharacter payload. Harness §9.
- **F7 / R3 — implemented.** `--max-tasks` (1–999999, canonicalised because
  it drives the loop-bound arithmetic), `--max-turns` (positive integer,
  passed through), `--budget` (positive decimal: digits, ≤1 dot, digit each
  side, non-zero). All exit 2 before preflight and before any `.autodev`
  state or seed file exists. Harness §10.
- **F1 follow-up — implemented.** The `--timeout` check was rewritten with
  the same arithmetic-free logic: the old `[ -gt 0 ]` rejected
  `--timeout=08` as an octal error and wrapped huge values, contradicting
  the documented "leading zeros tolerated / very large values accepted".
  Values now pass through unchanged. Harness §10d.
- **F15 / R5 — implemented.** `--agent` is validated against the
  `claude|codex` enum before preflight (exit 2). The preflight/dispatch
  mismatch (an unknown name resolving a real binary, then taking the claude
  branch) is gone; an unenumerated name can never reach command lookup.
  Harness §11.
- **F15 / R4 — deferred deliberately.** `--` remains an unknown flag
  (exit 2). No script forwards arguments to another command, so there is no
  concrete need; the deterministic behavior and positional-argument
  rejection are pinned by harness §7/§12 and documented in the contract §1.
- **R1 — deferred.** Checksum/signature pinning for the `curl | bash`
  installers needs upstream-published checksums and a network fixture to
  test — both outside hermetic scope. Safest future path: vendor SHA-256
  pins of the three scripts into `pixel-bootstrap.sh` and verify on
  download, once the pins themselves have a distribution story.
- **R6 — implemented.** `.gitattributes` (`* text=auto eol=lf`); all blobs
  are already LF, so there is no renormalisation churn. Harness §14.
- **Workstream 8 extras — implemented.** Preflight dies clearly when GNU
  `timeout` is missing (previously a cryptic rc=127 per task), and
  `--dry-run` skips agent resolution so it requires no paid-agent
  executable. Harness §13.

Coverage caveat (honest): the missing-tool `die` paths (`timeout`, `git`,
agent binary) are verified by inspection. On every supported host — and on
CI — those binaries occupy the preflight's scrubbed PATH prefix
(`/root/.npm-global/bin:/root/.local/bin:/usr/local/bin:/usr/bin:/bin`), so
a controlled-PATH absence test cannot be made hermetic without a new seam,
and no seam is added solely for testing.

## Session 4 follow-up (main @ 711c23b + auto/integrate-session-4)

- **Integration.** Session 3 (`79617f4`, carrying Session 1–2 via `2bb8df1`)
  was promoted to `main` as `711c23b` (`--no-ff`, not pushed). Session 4
  follow-up work rides `auto/integrate-session-4` for operator review.
- **Preflight testability — implemented.** The caveat above is closed:
  dependency resolution is centralized in `resolve_required_tool`
  (`pixel-autodev.sh:99-117`) with per-tool override seams (`TIMEOUT_BIN`,
  `GIT_BIN`, `CLAUDE_BIN`, `CODEX_BIN`). Set-empty simulates absence, so the
  missing-`timeout`/missing-`git`/missing-agent die paths are now hermetically
  tested (harness §15), including validation-before-resolution ordering and
  no-state-on-failure. Production behavior with seams unset is byte-identical.
- **R1 — implemented (scoped).** `pixel-bootstrap.sh` now downloads the two
  setup scripts to a temp file, verifies SHA-256 against vendored pins
  (`config/bootstrap-checksums.txt` + embedded copies, sync enforced by
  harness §16), and installs only on match — failing closed on download
  failure, missing digest, missing hash tool, or mismatch (temp removed via
  `EXIT` trap). This also fixes the latent defect where a failed curl left a
  partial, later-executed file in `$DEST`. Hermetic proof via `curl file://`
  fixtures (harness §17): no public network needed.
  - **Threat model / what the pins do and do not buy.** They give integrity
    against drift, mirror substitution (a `--repo-base` mirror is now safe
    for the pinned content), truncation, and maintainer inconsistency
    (lockstep test goes red). They do **not** give authenticity: the trust
    anchor — `pixel-bootstrap.sh` itself — still arrives over the same
    unauthenticated `curl | bash` channel as the payloads, so an attacker who
    can substitute payloads can substitute the anchor and its embedded pins.
  - **Residual blocked sub-item (formal).** Authenticity for the anchor
    itself. Prerequisites: (1) upstream signed releases (minisign/gpg) or an
    out-of-band checksum channel the user verifies once (e.g. a digest
    published on an independent page and pasted at install time); (2) a
    signature-verification tool present in Termux; (3) migration of the
    README one-liner to "fetch → verify → execute". Acceptance criteria:
    anchor verified before execution with a key established out of band;
    hermetic fixture tests mirroring §17. Until then the README privacy
    section documents the TLS-only trust level.
  - The third-party installer pipes inside `pixel-dev-setup.sh`
    (nodesource, claude.ai, astral.sh) remain as-is under the charter's
    package-install exception — different trust boundary (vendor CLIs, not
    this repo's payloads), out of R1's scope.
- **CI.** Added the one gate the workflow did not execute directly
  (`git diff --check`); trigger rules unchanged, `auto/*` still covered.
  Remote CI remains operator-owned (no push this session).
- **R4** — unchanged: document-only; `--` stays an unknown flag (exit 2),
  pinned by harness §7/§12.

## Session 5 follow-up (main @ 711c23b + auto/integrate-session-5)

- **R1 anchor authenticity — materially reduced (Tier 1 implemented; Tier 2
  mechanics ready; production signing operator-blocked).** The Session 4
  residual sub-item now has an architecture
  (`docs/adr/ADR-BOOTSTRAP-ANCHOR-AUTHENTICITY.md`, target Option D:
  versioned release + immutable reference + SHA-256 + detached signature)
  and a formal trust model (`docs/BOOTSTRAP_TRUST_MODEL.md`):
  - *Tier 1 (implemented).* The README one-liner is replaced by a verified
    flow: fetch `pixel-bootstrap.sh` from an immutable commit-pinned URL,
    verify its SHA-256 obtained out of band, run it with `PIXEL_REPO_BASE`
    pinned to the same commit so both payloads come from the same immutable
    ref. The pin contract is tested against the real git object (harness
    §18). No `curl | bash` path remains in the primary documentation.
  - *Tier 2 (mechanics implemented).* `scripts/verify-bootstrap-signature.sh`
    verifies a detached gpg signature with an operator-supplied keyring
    (`GPGV_BIN` seam; usage errors exit 2, verification failures exit 1).
    Hermetic ed25519 fixtures in harness §19. Production signing — a real
    project key, a published fingerprint, signed release artifacts — is
    operator-blocked: the loop must not invent a trusted identity.
    Prerequisites and acceptance criteria live in the ADR.
  - *Residual risk (reduced, not eliminated).* Repository-host or account
    compromise still defeats Tier 1; authenticity today rests on the
    out-of-band digest channel, and from the first signed release onward on
    the published key fingerprint. Documented in the trust model.
- **Checksum lifecycle governance — implemented.**
  `scripts/update-bootstrap-checksums.sh` (`--check` default, non-mutating,
  exit 1 when stale with itemized drift; `--write` updates the embedded
  digests first, then atomically replaces the manifest; rejects malformed,
  duplicate, or unexpected entries, symlink escapes, and missing artifacts;
  no network). The two sources of truth — manifest and embedded pins — can
  no longer drift silently: check mode is a local gate, a CI step, and
  harness §16/§20.
- **CI operational verification — implemented locally.** The workflow gained
  the checksum lockstep step; `scripts/ci-local.sh` runs the same five gates
  network-free from any cwd (`git diff --check`, checksum `--check`,
  `bash -n` on all tracked shell scripts, ShellCheck on all tracked shell
  scripts, full suite), failing fast with the failing step's exit status.
  Parity is pinned by harness §22. Remote CI remains operator-owned: nothing
  was pushed; triggers already cover `auto/*`.
- **Release readiness — documented.** `docs/BOOTSTRAP_RELEASE_PROCESS.md`:
  SemVer + signed-tag model, immutable commit references, checksum manifest
  schema v1, compatibility guarantees, minimum supported bootstrap,
  update/rollback and key-compromise procedures, operator release checklist.
  Governance test §21 ties the documented current pin to the git object.
- **Signal hardening — implemented.** `pixel-bootstrap.sh` routes INT/TERM
  through the EXIT trap, so a mid-download interrupt removes the temp
  download dir (harness §23). Installed-script permissions are pinned at
  755 by test.
- **Lint coverage defect fixed.** Harness §0/§1/§2 previously covered only
  the top-level scripts; they now iterate `git ls-files '*.sh'` (8 scripts),
  closing the `scripts/*.sh` blind spot.
- **Performance budget — measured, not optimized.** Full suite 3m31s
  (baseline ≈2m45s); the nested clean-clone proof is ≈48–50% of wall time
  (101–109s) and is retained per charter. Opt-in per-section profiler:
  `PIXEL_TEST_TIMINGS=1` (evidence/session-5/test-timings.txt). No assertion
  removed; correctness took priority over the modest available reduction.
- **R4** — unchanged: document-only; `--` stays an unknown flag (exit 2),
  pinned by harness §7/§12.
- **Remote CI** — not run (no push). Static workflow validation plus local
  parity only; operator-triggered run instructions are in
  `reports/session-5-final-report.md`.
