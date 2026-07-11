# CLI Contract — pixel-development

Authoritative description of every documented and implemented command-line
flag, for maintainers and automation agents. Verified against the code on
`auto/integrate-session-1` and enforced where possible by `tests/run_tests.sh`.

## 1. Shared parsing conventions

All four scripts parse flags the same way (a `case` loop over `"$@"`):

- **Value flags use equals syntax only**: `--flag=value`. The space form
  (`--flag value`) is *not* supported — a bare `--flag` matches no case arm
  and falls through to the unknown-flag handler.
- **Duplicate flags**: processed left to right; the **last occurrence wins**.
- **`--` has no special meaning** today — it is treated as an unknown flag
  (exit 2). Documented here rather than changed, for backward compatibility.
- **Unknown flag** → prints `Unknown flag: <flag> (try --help)` and exits **2**.
- **`--help` / `-h`** → prints the header comment block, exits **0**. Parsing
  happens before every preflight, so `--help` and usage errors behave
  identically on any host (no Termux required).
- **Exit codes**: `0` success · `1` runtime/preflight failure (`die`) ·
  `2` usage error (unknown flag or invalid flag value).

## 2. pixel-bootstrap.sh

Termux entry point; installs shortcuts. Preflight requires Termux
(`$PREFIX` + `pkg`) for everything except `--help`/usage errors.

| flag | takes value | default | validation | invalid-value behavior | banner wording | impl | coverage |
|------|------------|---------|------------|----------------------|----------------|------|----------|
| `--open-store` | no | `0` (off) | — | n/a | `[--open-store]` | `pixel-bootstrap.sh:26` | help/unknown-flag contract |
| `--repo-base=URL` | yes | `$PIXEL_REPO_BASE` env, else the raw GitHub URL | none (used as a curl URL prefix) | per-script download fails with a warning, run continues | `[--repo-base=URL]` | `:18`, `:27` | bare-form rejection test |
| `--help` / `-h` | no | — | — | exit 0 | — | `:28` | `--help` contract |
| unknown | — | — | — | exit 2 | — | `:29` | unknown-flag + `--` + bare-flag tests |

Note: `--yes` is **not** accepted here (it is an unknown flag in this script).
The parity `--yes` lives in the other three scripts.

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
| `--ssh-port=N` | yes | `8022` | none (any string accepted) | written to `sshd_config` verbatim when ≠ 8022 (see audit R2) | `[--ssh-port=N]` | `:25`, `:34` | space-form rejection test |
| `--help` / `-h` | no | — | — | exit 0 | — | `:35` | `--help` contract |
| unknown | — | — | — | exit 2 | — | `:36` | unknown-flag + space-form tests |

`--yes` is accepted for CLI parity with `pixel-dev-setup.sh` but is a no-op:
this script never prompts. Kept deliberately (do not remove — see session-1
decision record in the audit doc).

## 5. pixel-autodev.sh

Autonomous backlog runner (runs inside the proot Ubuntu devbox).

| flag | takes value | default | validation | invalid-value behavior | banner wording | impl | coverage |
|------|------------|---------|------------|----------------------|----------------|------|----------|
| `--workspace=DIR` | yes | `$PIXEL_WORKSPACE` env, else `$HOME/pixel-lab` | existence checked in preflight (`die`, exit 1) | run aborts before touching tasks | `[--workspace=DIR]` | `:21`, `:38` | dry-run tests |
| `--backlog=FILE` | yes | `$WORKSPACE/BACKLOG.md` | seeded if absent | starter backlog written | `[--backlog=FILE]` | `:39` | seeding test |
| `--max-tasks=N` | yes | `3` | none (see audit R3) | passed to arithmetic; non-numeric breaks the loop bound | `[--max-tasks=N]` | `:23`, `:40` | — |
| `--max-turns=N` | yes | `30` | none (see audit R3) | passed to `claude --max-turns` | `[--max-turns=N]` | `:24`, `:41` | — |
| `--budget=USD` | yes | `2.00` | none | passed to `claude --max-budget-usd` | `[--budget=USD]` | `:25`, `:42` | — |
| `--timeout=SECONDS` | yes | `1200` | **positive integer** (rejects empty, non-numeric, negative, zero) | exit **2** with `pixel-autodev: --timeout must be a positive integer (got '<v>')`, before any preflight | `[--timeout=SECONDS]` | `:26`, `:43`, `:55-60` | full matrix (§6) |
| `--model=sonnet\|opus` | yes | `sonnet` | none (any string passed to `claude --model`) | agent CLI errors at dispatch | `[--model=...]` | `:27`, `:44` | — |
| `--agent=claude\|codex` | yes | `claude` | binary must resolve in preflight | `die` exit 1 if missing / Termux path | `[--agent=...]` | `:28`, `:45` | codex backend test |
| `--yolo` | no | `dontAsk` | — | n/a | `[--yolo]` | `:46` | — |
| `--push` | no | `0` (never pushes) | — | n/a | `[--push]` | `:47` | — |
| `--dry-run` | no | `0` | — | n/a | `[--dry-run]` | `:48` | dry-run tests |
| `--yes` / `-y` | no | accepted no-op | — | n/a | `[--yes]` | `:49` | help/unknown-flag contract |
| `--help` / `-h` | no | — | — | exit 0 | — | `:50` | `--help` contract |
| unknown | — | — | — | exit 2 | — | `:51` | unknown-flag + bare-flag tests |

Environment override seams (not flags): `PIXEL_WORKSPACE`, `PIXEL_REPO_BASE`,
`CLAUDE_BIN`, `CODEX_BIN`. The last two exist so tests inject stub agents;
they default to the real binaries and change nothing in normal use
(`pixel-autodev.sh:31-32`). A `--agent` value other than `codex` takes the
claude dispatch branch.

## 6. The `--timeout` contract (normative)

1. Default is **1200** seconds; the value is a per-agent-call wall-clock limit.
2. Accepted values: decimal positive integers only (`[1-9][0-9]*`, leading
   zeros tolerated). `0`, negative, non-numeric, and empty values are usage
   errors: exit **2** with a clear message, **before** preflight — no
   workspace or agent is touched.
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

Harness coverage (section 6 of `tests/run_tests.sh`): invalid-value matrix
(0 / negative / non-numeric / empty), resolution (default / explicit /
duplicate-last-wins / huge), mechanism rc=124, both-backend wiring, and
hermetic end-to-end success + per-backend timeout paths with stub agents.

## 7. Recommendations (not implemented — see `docs/AUTONOMOUS_AUDIT.md`)

- **R2**: validate `--ssh-port` as `1–65535`.
- **R3**: validate `--max-tasks` / `--max-turns` / `--budget` numerically.
- **R4**: support `--` as end-of-options (only if a concrete need appears).
- **R5**: validate `--agent` against the `claude|codex` enum early.
