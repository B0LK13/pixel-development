# CLI Contract — pixel-development

Authoritative description of every documented and implemented command-line
flag, for maintainers and automation agents. Verified against the code on
`auto/integrate-session-4` and enforced where possible by `tests/run_tests.sh`.

## 1. Shared parsing conventions

All four scripts parse flags the same way (a `case` loop over `"$@"`):

- **Value flags use equals syntax only**: `--flag=value`. The space form
  (`--flag value`) is *not* supported — a bare `--flag` matches no case arm
  and falls through to the unknown-flag handler.
- **Duplicate flags**: processed left to right; the **last occurrence wins**.
- **`--` has no special meaning** today — it is treated as an unknown flag
  (exit 2). Documented here rather than changed, for backward compatibility
  (audit R4: no script forwards arguments to another command, so there is no
  concrete need for an end-of-options marker). Pinned for all four scripts by
  harness §7/§12, including `-- --help` (still exit 2 — `--` enables nothing).
- **Positional arguments are not accepted**: anything that is not a recognised
  flag hits the unknown-flag arm (exit 2), including trailing values after
  valid flags. Nothing is silently ignored or passed through (harness §12).
- **Unknown flag** → prints `Unknown flag: <flag> (try --help)` and exits **2**.
- **`--help` / `-h`** → prints the header comment block, exits **0**. Parsing
  happens before every preflight, so `--help` and usage errors behave
  identically on any host (no Termux required).
- **Exit codes**: `0` success · `1` runtime/preflight failure (`die`) ·
  `2` usage error (unknown flag or invalid flag value).
- **Validation timing**: value validation runs immediately after the parse
  loop — before colour setup, preflight, and every filesystem side effect
  (log files, `.autodev/` state, seeded files). A usage error therefore
  leaves no trace (harness §9a, §10g). Invalid-value diagnostics go to
  **stderr** and name the flag; the unknown-flag line is historical
  `stdout` (both exit 2).

## 2. pixel-bootstrap.sh

Termux entry point; installs shortcuts. Preflight requires Termux
(`$PREFIX` + `pkg`) for everything except `--help`/usage errors.

| flag | takes value | default | validation | invalid-value behavior | banner wording | impl | coverage |
|------|------------|---------|------------|----------------------|----------------|------|----------|
| `--open-store` | no | `0` (off) | — | n/a | `[--open-store]` | `pixel-bootstrap.sh:26` | help/unknown-flag contract |
| `--repo-base=URL` | yes | `$PIXEL_REPO_BASE` env, else the raw GitHub URL | none (used as a curl URL prefix, always quoted) | download or checksum-verification failure **aborts the run** (exit 1, fail closed — see §8 trust model) | `[--repo-base=URL]` | `:18`, `:27` | bare-form rejection + §17 download matrix |
| `--help` / `-h` | no | — | — | exit 0 | — | `:28` | `--help` contract |
| unknown | — | — | — | exit 2 | — | `:29` | unknown-flag + `--` + bare-flag tests |

Note: `--yes` is **not** accepted here (it is an unknown flag in this script).
The parity `--yes` lives in the other three scripts.

**Download verification (sessions 4–5).** The two setup scripts this script
fetches (`pixel-dev-setup.sh`, `pixel-apps-setup.sh`) are downloaded to a
temp file and verified against pinned SHA-256 digests *before* installation
(`pixel-bootstrap.sh:96-115`). Fail closed — exit 1, nothing installed, temp
removed by an `EXIT` trap (INT/TERM route through it, so a signal
mid-download also cleans up — harness §23) — on download failure, missing
digest, missing hash tool, or mismatch. Local/cached copies are operator-trusted and skip
verification. Pins: `config/bootstrap-checksums.txt` (source of truth, now
pinning all three entry points **including the anchor itself**) with the
dev/apps values embedded in the script (it must stay self-contained for
stand-alone use); harness §16 enforces the three-way lockstep with the actual
file contents, §17 proves the runtime behavior hermetically. The anchor pin
underwrites the verified install flow in `README.md` §1 (fetch →
`sha256sum -c` → run, commit-pinned; harness §18). Maintenance seam:
`PIXEL_BOOTSTRAP_CHECKSUM_FILE` supplies an alternate manifest (a missing
entry there still fails closed). Signature verification of the anchor
(`scripts/verify-bootstrap-signature.sh`, gpgv) is tier 2 — mechanics
implemented, production signing operator-blocked (harness §19; see
`docs/adr/ADR-BOOTSTRAP-ANCHOR-AUTHENTICITY.md`).

## 3. pixel-dev-setup.sh

Termux toolbelt + proot Ubuntu AI layer. Preflight requires Termux.

| flag | takes value | default | validation | invalid-value behavior | banner wording | impl | coverage |
|------|------------|---------|------------|----------------------|----------------|------|----------|
| `--minimal` | no | `0` | — | n/a | `[--minimal]` | `:30` | help/unknown-flag contract |
| `--no-ai` | no | `0` (AI on) | — | n/a | `[--no-ai]` | `:31` | help/unknown-flag contract |
| `--yes` / `-y` | no | `0` | — | n/a | `[--yes]` | `:32` | help/unknown-flag contract |
| `--help` / `-h` | no | — | — | exit 0 | — | `:33` | `--help` contract |
| unknown | — | — | — | exit 2 | — | `:36` | unknown-flag contract |

`--yes` is live here: non-interactive runs default `git user.name` to
`B0LK13` instead of prompting.

## 4. pixel-apps-setup.sh

Companion layer (daemons, fonts, autostart, app checklist). Preflight
requires Termux.

| flag | takes value | default | validation | invalid-value behavior | banner wording | impl | coverage |
|------|------------|---------|------------|----------------------|----------------|------|----------|
| `--open-stores` | no | `0` | — | n/a | `[--open-stores]` | `:30` | help/unknown-flag contract |
| `--with-tailscale-cli` | no | `0` | — | n/a | `[--with-tailscale-cli]` | `:31` | help/unknown-flag contract |
| `--no-font` | no | `0` | — | n/a | `[--no-font]` | `:32` | help/unknown-flag contract |
| `--yes` / `-y` | no | accepted no-op | — | n/a | `[--yes]` | `:33` | help/unknown-flag contract |
| `--ssh-port=N` | yes | `8022` | **integer 1–65535**; leading zeros tolerated + canonicalised (`08022`→`8022`) | exit **2** before any side effect: `pixel-apps-setup: --ssh-port must be an integer between 1 and 65535 (got '<v>')` | `[--ssh-port=N]` | `:25`, `:34`, `:40-51` | full matrix + duplicates (§9) |
| `--help` / `-h` | no | — | — | exit 0 | — | `:35` | `--help` contract |
| unknown | — | — | — | exit 2 | — | `:36` | unknown-flag + space-form tests |

`--yes` is accepted for CLI parity with `pixel-dev-setup.sh` but is a no-op:
this script never prompts. Kept deliberately (do not remove — see session-1
decision record in the audit doc).

## 5. pixel-autodev.sh

Autonomous backlog runner (runs inside the proot Ubuntu devbox).

| flag | takes value | default | validation | invalid-value behavior | banner wording | impl | coverage |
|------|------------|---------|------------|----------------------|----------------|------|----------|
| `--workspace=DIR` | yes | `$PIXEL_WORKSPACE` env, else `$HOME/pixel-lab` | existence checked in preflight (`die`, exit 1) | run aborts before touching tasks | `[--workspace=DIR]` | `:21`, `:40` | dry-run tests |
| `--backlog=FILE` | yes | `$WORKSPACE/BACKLOG.md` | seeded if absent | starter backlog written | `[--backlog=FILE]` | `:41` | seeding test |
| `--max-tasks=N` | yes | `3` | **integer 1–999999**, canonicalised (it drives the shell loop bound, so no leading zeros/overflow reach the arithmetic) | exit **2** `pixel-autodev: --max-tasks must be an integer between 1 and 999999 (got '<v>')` | `[--max-tasks=N]` | `:23`, `:42`, `:70-72` | full matrix + octal edge + duplicates (§10) |
| `--max-turns=N` | yes | `30` | **positive integer** (leading zeros tolerated, passed through) | exit **2** `… --max-turns must be a positive integer (got '<v>')` | `[--max-turns=N]` | `:24`, `:43`, `:67` | full matrix + duplicates (§10) |
| `--budget=USD` | yes | `2.00` | **positive decimal**: digits, at most one dot with a digit on each side, non-zero value (rejects `0`, `0.00`, `.5`, `2.`, `1.2.3`) | exit **2** `… --budget must be a positive number (e.g. 2.00) (got '<v>')` | `[--budget=USD]` | `:25`, `:44`, `:76-79` | full matrix (§10) |
| `--timeout=SECONDS` | yes | `1200` | **positive integer** (rejects empty, non-numeric, negative, zero; arithmetic-free — no octal/overflow edge) | exit **2** with `pixel-autodev: --timeout must be a positive integer (got '<v>')`, before any preflight | `[--timeout=SECONDS]` | `:26`, `:45`, `:66` | full matrix (§6, §10) |
| `--model=sonnet\|opus` | yes | `sonnet` | none (any string passed to `claude --model`) | agent CLI errors at dispatch | `[--model=...]` | `:27`, `:46` | — |
| `--agent=claude\|codex` | yes | `claude` | **enum: `claude`, `codex`** (case-sensitive); binary resolution runs in preflight on real runs only | bad value → exit **2** `… --agent must be one of: claude, codex (got '<v>')`; missing/Termux binary → `die` exit 1 | `[--agent=...]` | `:28`, `:47`, `:82-85` | enum matrix + duplicates (§11), preflight (§13) |
| `--yolo` | no | `dontAsk` | — | n/a | `[--yolo]` | `:48` | — |
| `--push` | no | `0` (never pushes) | — | n/a | `[--push]` | `:49` | — |
| `--dry-run` | no | `0` | — | n/a | `[--dry-run]` | `:50` | dry-run tests |
| `--yes` / `-y` | no | accepted no-op | — | n/a | `[--yes]` | `:51` | help/unknown-flag contract |
| `--help` / `-h` | no | — | — | exit 0 | — | `:52` | `--help` contract |
| unknown | — | — | — | exit 2 | — | `:53` | unknown-flag + bare-flag tests |

Environment override seams (not flags): `PIXEL_WORKSPACE`, `PIXEL_REPO_BASE`,
`CLAUDE_BIN`, `CODEX_BIN`, `TIMEOUT_BIN`, `GIT_BIN`. The four `*_BIN` vars
feed one resolver (`resolve_required_tool`, `pixel-autodev.sh:108-120`): unset
→ default PATH resolution (production behavior); set but empty → treated as
missing (hermetic absence simulation); path with `/` → must be an executable
file; bare name → PATH lookup. `CLAUDE_BIN`/`CODEX_BIN` default to the real
binary names and change nothing in normal use; the seam only affects
detection/reporting — validation runs earlier and is never bypassed, and
every resolved path is used quoted (harness §15).

All value validation runs right after parsing (`pixel-autodev.sh:56-85`),
before preflight: a usage error creates no `.autodev/` state and seeds
nothing (harness §10g). `--dry-run` additionally skips agent-binary
resolution in preflight, so a plan view needs no paid-agent executable and
never touches one (harness §13). Dispatch selects the backend strictly by
the validated enum: `codex` → `timeout "$TIMEOUT" "$CODEX_BIN" exec …`,
`claude` → `timeout "$TIMEOUT" "$CLAUDE_BIN" -p …`.

## 6. The `--timeout` contract (normative)

1. Default is **1200** seconds; the value is a per-agent-call wall-clock limit.
2. Accepted values: decimal positive integers only (digits with at least one
   non-zero digit; leading zeros tolerated, e.g. `--timeout=08` is 8 and is
   passed through unchanged). `0`/`000`, negative, non-numeric, and empty
   values are usage errors: exit **2** with a clear message, **before**
   preflight — no workspace or agent is touched. Validation is pure string
   logic (no arithmetic expansion), so there is no octal trap and no integer
   overflow at any magnitude.
3. Both backends run under the same resolved value:
   `timeout "$TIMEOUT" "$CLAUDE_BIN" …` / `timeout "$TIMEOUT" "$CODEX_BIN" …`.
   The argument is always quoted; after validation it is digits-only, so no
   shell injection is possible through it.
4. Duplicate `--timeout` flags: last wins.
5. Very large values are accepted and passed through (operator's choice).
6. Expiry is distinguishable: `timeout(1)` returns **124**; the runner warns
   `agent timed out after Ns (rc=124)`, reverts the task branch, leaves the
   backlog item open, and logs `RESULT: FAILED (timeout after Ns)`.
7. `--dry-run` never invokes an agent; the resolved value is shown in the
   preflight policy line (`timeout=Ns`), so dry-run output always reflects
   the configured timeout.
8. Portability: `timeout` is GNU coreutils — present in Termux (`pkg`) and in
   the proot Ubuntu devbox, the only supported runtime environments
   (see `docs/AUTONOMOUS_AUDIT.md` portability section).

Harness coverage (sections 6 and 10 of `tests/run_tests.sh`): invalid-value
matrix (0 / `000` / negative / non-numeric / empty), resolution (default /
explicit / duplicate-last-wins / huge / leading-zero `08`), mechanism rc=124,
both-backend wiring, and hermetic end-to-end success + per-backend timeout
paths with stub agents.

## 7. Recommendations register (status after session 5 — see `docs/AUTONOMOUS_AUDIT.md`)

- **R1**: **implemented (scoped), anchor gap reduced** — the two scripts
  `pixel-bootstrap.sh` fetches over the network are verified against vendored
  SHA-256 pins before installation, failing closed (§2, §8 trust model;
  harness §16/§17). The anchor itself is now (a) pinned in the manifest, (b)
  installed through a commit-pinned fetch → `sha256sum -c` → run flow with no
  pipe-to-shell (README §1, harness §18), and (c) covered by gpgv
  signature-verification mechanics (`scripts/verify-bootstrap-signature.sh`,
  harness §19) that a maintainer signing identity can activate without code
  changes. Residual: anchor *authenticity* still awaits an operator-provisioned
  signing key published out-of-band (blocked, prerequisites in the ADR); the
  third-party installer pipes inside `pixel-dev-setup.sh` remain under the
  charter's package-install exception.
- **R2**: **implemented** — `--ssh-port` validated as `1–65535` (§4, harness §9).
- **R3**: **implemented** — `--max-tasks` / `--max-turns` / `--budget`
  validated (§5, harness §10).
- **R4**: **not implemented (deliberate)** — `--` stays an unknown flag
  (exit 2). No script forwards arguments to another command, so no concrete
  need exists; the deterministic behavior is pinned by harness §7/§12.
  Revisit only if a pass-through consumer is added.
- **R5**: **implemented** — `--agent` validated against `claude|codex`
  before preflight (§5, harness §11).
- **R6**: **implemented** — `.gitattributes` pins `* text=auto eol=lf`
  (harness §14).

## 8. Dependencies & portability

Runtime dependency inventory (from the scripts themselves, not assumed):

| tool | class | used by | absent behavior |
|------|-------|---------|-----------------|
| bash | required | all scripts (shebang) | n/a |
| Termux runtime (`$PREFIX` + `pkg`) | required | bootstrap / dev-setup / apps-setup preflights | `die` exit 1, "Run inside Termux…" |
| git | required | autodev | `die` exit 1, "git not installed in devbox" |
| `timeout` (GNU coreutils) | required | autodev agent dispatch | `die` exit 1 at preflight with a clear message |
| `claude` / `codex` | conditionally required | autodev, **non-dry-run only** | `die` exit 1 naming the agent; `--dry-run` skips resolution entirely |
| jq | optional | autodev (JSON summaries), harness (JSON check) | degrades with a warning (apt-get install attempted; plain-text fallback); harness skips its check |
| curl | conditionally required | bootstrap downloads (when no local copy), dev-setup installers | bootstrap aborts (exit 1) if it cannot fetch a verified copy; local/cached copies need no curl |
| `sha256sum` or `shasum` | conditionally required | bootstrap download verification, checksum tool, README verified flow | `die` exit 1 — refuses to install unverified content |
| `gpgv` (`gnupg`) | optional | anchor signature verification (`scripts/verify-bootstrap-signature.sh`, tier 2) | helper dies exit 1 naming gpgv; only needed when a maintainer signature exists |
| sed / grep / date / mktemp / tr / cut / awk | required coreutils | all scripts | present in every supported environment |
| shellcheck | test-only | harness lint gate | gate skipped with a notice when absent |
| git (fixture repos) | test-only | harness workspaces | harness requires it (CI provides it) |
| gpg (ephemeral keys) | test-only | harness §19 signature fixtures | section skipped with a notice when absent |
| agent/tool stubs | test-only | harness via `CLAUDE_BIN` / `CODEX_BIN` / `TIMEOUT_BIN` / `GIT_BIN` / `GPGV_BIN` seams + a `pkg` stub | n/a |

Environment override seams (not flags): `PIXEL_WORKSPACE`, `PIXEL_REPO_BASE`,
`CLAUDE_BIN`, `CODEX_BIN`, `TIMEOUT_BIN`, `GIT_BIN`, `GPGV_BIN`,
`PIXEL_BOOTSTRAP_CHECKSUM_FILE`. `--help` and usage errors need none of the
above — parsing and validation run before every dependency check.

**Bootstrap trust model (session 4).** Network-fetched setup scripts are
integrity-locked: `config/bootstrap-checksums.txt` is the source of truth,
mirrored by the digests embedded in `pixel-bootstrap.sh`, and the harness
(§16) fails unless this file, the embedded digests, and the script contents
are in lockstep. **Checksum manifest ownership**: the operator/maintainer —
updates require intentional review of both version and digest, in the same
commit as the script change. **Update procedure**: `sha256sum
pixel-dev-setup.sh pixel-apps-setup.sh` → update the manifest AND the
embedded digests in the same commit → record the establishing commit in the
manifest header. The pins give drift/mirror/truncation integrity (a
`--repo-base` mirror is now safe to use for the pinned content); they are
**not** an authenticity anchor, because `pixel-bootstrap.sh` itself still
arrives over an unauthenticated `curl | bash` — see the audit addendum for
the blocked sub-item and its prerequisites. **Network-test strategy**:
hermetic only — `curl file://` fixtures and stub binaries; the suite never
touches the public network.

**Supported environments** (unchanged from `docs/AUTONOMOUS_AUDIT.md`, with
evidence there): Termux (F-Droid) on aarch64 Android; the proot Ubuntu
devbox; GitHub Actions `ubuntu-latest`. macOS, WSL, and Git Bash remain
**unsupported and unverified** — no claim is made.

**GNU-isms retained and documented** (all present in the supported
environments): `timeout(1)`, `sed -i` (apps-setup `sshd_config` edit),
`sed 's/…/\+/…'` (autodev `slugify`), `grep -E`. If wider support is ever
desired: a POSIX bracket class for `slugify`, a platform-guarded `sed -i`,
and `timeout`/`gtimeout` detection. No platform shim is added without an
environment that can test it.
