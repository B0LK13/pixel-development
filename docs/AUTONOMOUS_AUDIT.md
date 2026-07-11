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
