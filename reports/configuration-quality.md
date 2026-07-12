# Session 8 — Configuration Quality & Portability Review

**Scope**: every configuration surface of the repo — environment variables,
defaults, CLI flag contracts, GitHub Actions, shell options, path/temp
handling, file modes, locale/timestamp handling, GPG isolation, user-global
state leakage. **Audited tree**: `auto/integrate-session-8` @ `e4304d5`
(worktree clean except untracked `evidence/session-8/`). Method: full read of
all 9 shell scripts + `tests/run_tests.sh` (1544 lines) + workflow + docs,
targeted greps, and cheap fail-fast invocations with invalid env/flags. No
files were modified; `tests/run_tests.sh` / `ci-local.sh` were not run
(background suite in flight — `evidence/session-8/test-results.txt` is all
green so far); no gpg against the default keyring (probes below used an
isolated throwaway `HOME`).

## 1. Findings table

| # | finding | severity | verdict | evidence |
|---|---------|----------|---------|----------|
| F1 | CI release job uses space-form flags; all six invocations exit 2 — job can never pass on this HEAD | high (CI-red), zero-risk fix | **fix-this-session** (fix exists: `66aedb9` on `auto/session-8-ci-efficiency` — merge it) | §2.1, empirical |
| F2 | autodev commits inherit user-global git config (`commit.gpgsign`, identity); commit rc unchecked → failed commit still flips backlog to done | medium | **fix-this-session** | §2.2, empirical probe |
| F3 | `docs/CLI_CONTRACT.md` line refs for `pixel-autodev.sh` stale (+2 lines parse/validation; resolver off ~9) | low | **fix-this-session** (doc-only) | §2.3 |
| F4 | `mktemp -d` failure unchecked in `pixel-bootstrap.sh:53` — empty `DLTMP` falls through to `curl -o "/$s"` | low | **fix-this-session** (one-line `\|\| die`) | §2.4 |
| F5 | Actions pinned to floating major tags (`@v4`); pinning policy stated nowhere | low | **deferred** — state the policy explicitly | §2.5 |
| F6 | `NO_COLOR`/`TMPDIR`/`HOME`/`PREFIX` absent from the CLI_CONTRACT env-seam list | cosmetic | acceptable / optional doc line | §3 |
| F7 | bootstrap shortcut `6-SSH-Info` hardcodes `Port: 8022` while `--ssh-port` can change it | cosmetic | acceptable | §2.6 |
| F8 | empty `--output-dir=` silently falls back to `$ROOT/dist` | cosmetic | acceptable (treated as unset) | §2.6 |

## 2. Detailed findings

### 2.1 F1 — space-form flags in the CI release job (empirically confirmed)

`docs/CLI_CONTRACT.md:11-13` is normative: value flags are equals-syntax
**only**; the space form hits the unknown-flag arm (exit 2). The workflow's
`release-candidate-check` job violates this six times on the audited HEAD:
`.github/workflows/test.yml:50,53,57` (`--output-dir "$RUNNER_TEMP/rc"`,
`--bundle "$RUNNER_TEMP/rc/…"`) and `:70-72` (`--bundle "$B"`,
`--signature "$B/…"`, `--keyring "$RUNNER_TEMP/…"`). Empirical:

```
$ bash scripts/build-release-candidate.sh --version=0.0.0 --output-dir /tmp/s8x
build-release-candidate: unknown flag: --output-dir (try --help)   rc=2
$ bash scripts/verify-release-bundle.sh --bundle /tmp/s8x          rc=2
$ bash scripts/verify-release-bundle.sh --bundle=/tmp/s8x          rc=1, verdict: failed-layout (correct class)
```

The job's first step exits 2 on any runner. (Remote confirmation via
`gh run list` was inconclusive — API 404 for this token — but the local repro
is decisive.) A complete fix for all six invocations already exists as commit
`66aedb9` ("fix: use equals-form release flags in the CI release job") on
branch `auto/session-8-ci-efficiency`, created during this session; the
audited HEAD predates it. **Harness gap**: the §22 CI-parity checks
(`tests/run_tests.sh:890-924`) are prefix greps (`grep -qF -- "$mech"`) that
match regardless of `=` vs space — pin the equals form (e.g. grep
`--output-dir=`) or dry-run the first job step hermetically.

### 2.2 F2 — autodev commit path leaks user-global git config; commit rc never checked

`pixel-autodev.sh:350-352` (and the same shape at `:357`):

```bash
( cd "$dir" && git add -A && git commit -q -m "feat(auto): $text" )  # rc discarded
mark_done "$raw"          # runs unconditionally
```

1. **Global git config leaks into autonomous commits.** This host's operator
   config is `commit.gpgsign=true` + `user.signingkey=…` (verified via
   `git config --global --list`). The harness guards only *its own* fixtures
   (session-7 fix present at `tests/run_tests.sh:123` `mk_ws` and `:1001`
   `mk_rc_clone`), never the production path.
2. **Commit failure is invisible.** `mark_done` flips the backlog and the run
   log records `RESULT: DONE` regardless of the commit outcome.

Empirical probe (throwaway HOME with `commit.gpgsign=true` +
`signingkey=DEADBEEF`, stub agent, hermetic; gpg touched only the isolated
`$HOME/.gnupg`): `git commit` failed ("gpg failed to sign the data … No
secret key"), yet the backlog flipped to `- [x]`, stdout printed
`✔ task complete → branch auto/audit-gpgsign-probe`, the run log recorded
`RESULT: DONE`, rc was 0 — and `git log --all` contained **no task commit**.
This breaks the header contract ("commit on green only",
`pixel-autodev.sh:6`) and the no-partial-output claim. Adjacent observation:
with no identity configured anywhere, git's auto-ident fallback authored
`root <root@localhost.localdomain>` — the devbox provision heredoc
(`pixel-dev-setup.sh:212-280`) never runs `git config`; identity is only set
in the Termux layer (`pixel-dev-setup.sh:143-156`), yet autodev runs
*inside* the devbox.

Suggested fix (low risk): check the commit rc and route failure to the
existing "branch kept, task stays open" path; commit with
`git -c commit.gpgsign=false` for deterministic unsigned auto-commits; seed a
devbox identity in the provision heredoc. **Coverage note**: no harness
fixture exercises a poisoned *global* gitconfig — add one mirroring the probe
(isolated HOME, `GIT_CONFIG_NOSYSTEM=1`, gpgsign with a missing key; assert
backlog stays open and the failure is reported).

### 2.3 F3 — stale line references in docs/CLI_CONTRACT.md (doc-only)

Every `impl` cell cross-checked against the code. Refs for
`pixel-bootstrap.sh`, `pixel-dev-setup.sh`, `pixel-apps-setup.sh` are exact
(e.g. `--ssh-port` `:25`,`:34`,`:40-51` matches `pixel-apps-setup.sh:25,34,43-51`).
`pixel-autodev.sh` refs drifted +2 lines: parse block `:38`-`:51` → actual
`pixel-autodev.sh:40-53`; `--timeout` validation `:64` → `:66`; `--agent`
enum `:80-83` → `:82-85`; "validation … `:55-83`" → `:57-85`;
`resolve_required_tool` `:99-117` → `:108-120`; bootstrap download block
`:96-115` → `:99-117`. Default-value refs (`:21`,`:23-28`) remain correct.
Zero-risk doc touch-up; consider a grep-based doc-ref lint — drift happened
precisely because nothing pins these.

### 2.4 F4 — unchecked `mktemp -d` in pixel-bootstrap.sh

`pixel-bootstrap.sh:53`: if `TMPDIR` points at an unwritable/nonexistent
dir, `mktemp` fails, `DLTMP` is empty (no `set -e`), and the download target
becomes `curl -o "$DLTMP/$s"` = `/<script>` (`:106`). On Termux `/` is
unwritable so curl fails and the run dies "could not download" — fail-closed
but misdiagnosed; on a root shell the file lands in `/`, is hash-verified,
then `mv`'d correctly (content safety holds, path hygiene does not). The
sibling script does it right (`scripts/update-bootstrap-checksums.sh:138-139`
uses `mktemp … || die`). One-line fix:
`|| die "cannot create temp dir (TMPDIR=${TMPDIR:-/tmp})"`.

### 2.5 F5 — GitHub Actions pinning policy unstated

`.github/workflows/test.yml:28,48` use `actions/checkout@v4` (floating major
tag, not a SHA); no policy is stated anywhere (grep across docs: none).
Inconsistent with the repo's otherwise total pinning discipline, but
exposure is modest: the job is `permissions: contents: read` (`:12-13`),
uses no secrets, and harness §22 fails the build if any secret/paid-agent
reference appears (`tests/run_tests.sh:900-904`). Deferred governance item:
write the policy down either way ("@v4 accepted, reviewed on major bumps" or
SHA-pin with an update procedure) rather than leaving it implicit.

### 2.6 Minor acceptables (F6–F8)

- **F7**: `pixel-bootstrap.sh:178` prints `Port: 8022` unconditionally in the
  generated `6-SSH-Info` shortcut while `--ssh-port=N` edits the real config
  (`pixel-apps-setup.sh:126-132`). Informational text only; acceptable.
- **F8**: empty `--output-dir=` is treated as unset → `$ROOT/dist`
  (`build-release-candidate.sh:65`). Consistent defaulting; acceptable.
- Workflow `set -e` (`test.yml:61`) is redundant under GHA's default
  `bash -eo pipefail` wrapper but harmless; `concurrency`, both
  `timeout-minutes` bounds (`:23,43`, pinned by harness §22), and
  `shell: bash` defaults (`:24-26,44-46`) are all sane.

## 3. Environment-variable inventory

Legend: **seam** = the `resolve_required_tool` contract (unset→PATH default ·
empty→missing · path→must be executable · bare name→PATH lookup),
`pixel-autodev.sh:108-120`, mirrored for gpgv at
`scripts/verify-bootstrap-signature.sh:42-52`.

| var | where read | default | validated? | documented? |
|-----|-----------|---------|-----------|-------------|
| `PIXEL_REPO_BASE` | `pixel-bootstrap.sh:18` | raw GitHub `main` URL | not validated; quoted curl prefix, fail-closed on fetch/checksum (`:102-116`, harness §17e) | CLI_CONTRACT §2, README:30 |
| `PIXEL_BOOTSTRAP_CHECKSUM_FILE` | `pixel-bootstrap.sh:59-62` | embedded pins | missing entry fails closed (exit 1, harness §17d) | CLI_CONTRACT §2/§8 |
| `PIXEL_WORKSPACE` | `pixel-autodev.sh:21` | `$HOME/pixel-lab` | existence preflight, exit 1 (`:148`) | CLI_CONTRACT §5 |
| `CLAUDE_BIN`/`CODEX_BIN` | `pixel-autodev.sh:33-34` | `claude`/`codex` | seam; metachar values never executed (harness §15i) | CLI_CONTRACT §5/§8, README:246 |
| `TIMEOUT_BIN`/`GIT_BIN` | `pixel-autodev.sh:145,147` | PATH lookup | seam (harness §15a-h) | CLI_CONTRACT §5/§8 |
| `GPGV_BIN` | `verify-bootstrap-signature.sh:42` | `gpgv` | seam (harness §19e/g) | helper header `:13-15`, CLI_CONTRACT §8 |
| `SOURCE_DATE_EPOCH` | `build-release-candidate.sh:53,145,249` | unset → `date -u` now | non-numeric → exit 1 before any side effect (`:53-56`; empirically verified); `date -d`/`touch -d` failure → exit 1 (`:146-147,250-252`) | header `:22-23`, RELEASE_SIGNING.md:38, harness §24r/§27a-c |
| `GNUPGHOME` | `run_tests.sh:703`, `test.yml:62` | n/a | always a fresh temp dir, `chmod 700`, set **before** any gpg call | implicit (harness/workflow comments) |
| `PIXEL_TESTS_NO_CLONE` | `run_tests.sh:313` | `0` | `=1` skips the nested clone; anything else runs it | harness header `:13` |
| `PIXEL_TEST_TIMINGS` | `run_tests.sh:23` | `0` | `=1` enables the profiler, else no-op | harness comment `:21-22` |
| `HOME` | all scripts (paths, logs, `~/.shortcuts`, `~/.ssh`) | platform | not validated; quoting proven with space-containing HOME fixtures (harness §9, §17) | convention (undocumented — F6) |
| `PREFIX` | `pixel-bootstrap.sh:80`, `pixel-dev-setup.sh:76`, `pixel-apps-setup.sh:99` | n/a | required non-empty + `pkg` present, exit 1 | CLI_CONTRACT §8 |
| `PATH` | `pixel-autodev.sh:128` (scrub), `pixel-dev-setup.sh:222,273` | n/a | scrub unconditional + `hash -r`; harness stubs ride `$PATH` | CLI_CONTRACT §8 |
| `TMPDIR` | `pixel-bootstrap.sh:53`, `run_tests.sh:97,607,939` | `/tmp` | **not validated** (F4) | undocumented (F6) |
| `NO_COLOR` | `pixel-bootstrap.sh:33`, `pixel-dev-setup.sh:41,216`, `pixel-apps-setup.sh:53`, `pixel-autodev.sh:87` | colors on tty | honored consistently | undocumented (F6) |
| `LANG`/`LC_*` | — | — | **never read or set anywhere** (grep: zero hits); locale-invariant formats used instead | n/a |
| `RUNNER_TEMP` | `test.yml:50-72` | GHA-provided | n/a | n/a |
| `DEBIAN_FRONTEND` | `pixel-dev-setup.sh:221` (export) | `noninteractive` | set, not read | n/a |

## 4. Negative results — surfaces already handled well

- **Validation ordering / exit classes.** Every validator runs before colour
  setup, preflight, and any side effect. Empirical spot checks (all correct
  class, flag named on stderr, nothing written): `--version=1.0` → rc 2;
  `--timeout=0` → rc 2; `--ssh-port=abc` → rc 2 with no log file; no-args /
  unknown-flag on all three helper scripts → rc 2; `--check` on a dirty tree
  → rc 1 naming the untracked file (`?? evidence/session-8/` trips the
  clean-tree gate by design). Deeper matrices (octal, duplicates last-wins,
  metacharacters, space-form, `--`, no-state-on-usage-error) are pinned by
  harness §6/§7/§9-§12/§15e and green in the session-8 partial run.
- **GPG isolation is complete on the verify/test side.** Production
  verification uses only `gpgv --keyring` (`verify-bootstrap-signature.sh:58`)
  — no import, no trustdb, no default keyring. Harness gpg use is preceded by
  `GNUPGHOME="$tmp/gnupg"; export` (`run_tests.sh:703`); the workflow uses
  `GNUPGHOME="$RUNNER_TEMP/gnupg"` (`test.yml:62-63`). The session-7
  `commit.gpgsign` fix exists in **both** fixture paths (`run_tests.sh:123`,
  `:1001`) — and this host runs `commit.gpgsign=true` globally, so the green
  session-8 suite is a live proof the isolation works. (The remaining gap is
  the *production* commit path — F2.)
- **Temp dirs + traps.** Bootstrap: `mktemp -d` + EXIT trap + INT/TERM routed
  through it (`pixel-bootstrap.sh:53-56`; SIGTERM cleanup proven by harness
  §23a). Checksum tool: `TEMPS` array + `trap … EXIT INT TERM`, atomic
  temp+rename with mode preservation (`update-bootstrap-checksums.sh:44-46,122-156`;
  no-leftovers pinned §20b/k). Builder: staging dir + EXIT cleanup honoring
  `--keep-partial`, atomic rename (`build-release-candidate.sh:67-70,255`);
  dirty/stale/missing/symlink/existing-output gates all exit 1 with no
  partial bundle (harness §24l-p).
- **File modes.** Builder emits exactly 0755 scripts / 0644 data
  (`build-release-candidate.sh:102,131,201,246`), enforced by the verifier
  (`verify-release-bundle.sh:126-129,211-217` — mode drift = failed-checksum)
  and harness §24b/§25c2. No umask reliance: every mode-bearing write has an
  explicit `chmod`; `~/.ssh` gets 700/600 (`pixel-apps-setup.sh:123-124`);
  §23b pins installed-script modes ≤755.
- **Locale.** Zero `LANG`/`LC_*` references; all `date` output is
  locale-invariant numeric formats with `-u` where it matters
  (`build-release-candidate.sh:146,149`). SHA256SUMS/JSON order comes from
  statically sorted arrays (`:100-103`) — no `sort` in the builder at all.
  The three `sort` uses elsewhere compare lowercase-ASCII names or same-host
  same-locale pairs (`update-bootstrap-checksums.sh:82`,
  `run_tests.sh:1022,1402-1403`) — theoretical-only risk.
- **Portability guards.** `stat -c` degrades gracefully
  (`verify-release-bundle.sh:65` → `MODE_NOTE` `:207-233`;
  `update-bootstrap-checksums.sh:126,142` → `|| printf 644`). GNU `date -d` /
  `touch -d` guarded with clear `die` incl. `touch -h` fallback
  (`build-release-candidate.sh:146-147,250-252`). `/dev/fd` avoided by
  contract — heredocs everywhere (`ci-local.sh:15-16`, `run_tests.sh:36`).
  `sed -i`, `grep -E`, `timeout(1)` documented GNU-isms scoped to the three
  supported environments (CLI_CONTRACT §8 `:250-255`). `sha256sum`→`shasum`
  fallback in all four hash sites; missing tool = abort, never skip-verify
  (harness §17). `cd` failures guarded everywhere (`ci-local.sh:23`,
  `run_tests.sh:18`, `pixel-autodev.sh:272` uses `|| exit 90`).
- **Shell options.** Uniform `set -uo pipefail` in all 9 scripts; the
  deliberate no-`set -e` resilience model uses ERR traps in the two setup
  scripts (`pixel-dev-setup.sh:57`, `pixel-apps-setup.sh:65`) and explicit rc
  checks elsewhere. No global `IFS` mutation — `IFS=` is per-`read` only.
- **Defaults.** `--timeout=1200`, `--max-tasks=3`, `--max-turns=30`,
  `--budget=2.00`, `--ssh-port=8022`, `--model=sonnet`, `--agent=claude`:
  sane, documented (CLI_CONTRACT §4-§6), consistent across banner/policy
  line/docs; workflow timeouts (10/5 min) bracket observed suite runtime
  (session-7 timings evidence).

## 5. Residual risks / follow-up

- F2's identity half: out-of-the-box autodev commits in a fresh devbox are
  authored by git auto-ident (`root@<hostname>`) — seed `git config` in the
  provision heredoc.
- `pixel-autodev.sh:262,304` temp files rely on `rm -f`/rename without a
  trap; a SIGKILL mid-task leaves a `tmp.*` in `/tmp`. Cosmetic; deferred.
- `--model` is unvalidated by design (CLI_CONTRACT §5); with `--agent=codex`
  the value is silently unused. Acceptable, noted.

## 6. Empirical log (read-only or throwaway-temp, this session)

```
build --output-dir /tmp/x (space form)     → rc 2 "unknown flag: --output-dir"
verify --bundle /tmp/x (space form)        → rc 2 "unknown flag: --bundle"
verify --bundle=/tmp/x                     → rc 1 failed-layout (correct)
build --version=1.0                        → rc 2 "malformed version"
SOURCE_DATE_EPOCH=abc build … --check      → rc 1 "must be unix seconds: abc"
autodev --timeout=0                        → rc 2 "must be a positive integer"
apps --ssh-port=abc (throwaway HOME)       → rc 2, no log file created
verify-bootstrap-signature (no args)       → rc 2 usage
build --check, untracked evidence/ present → rc 1 "working tree is not clean", nothing written
autodev + global gpgsign=true, missing key → commit fails; backlog still flipped
  to [x], RESULT: DONE, no commit in git log      (F2 repro, isolated HOME)
autodev + no identity anywhere             → commit authored root@localhost.localdomain
gh run list … test.yml                     → HTTP 404 (inconclusive; local repro stands)
```
