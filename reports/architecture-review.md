# Architecture & Maintainability Review — Session 8

Scope: all 10 tracked shell scripts (3600 lines total), the harness, the CI
workflow, and the docs, at `main` tip `e4304d5`. Method: full manual read of
every script plus `tests/run_tests.sh`, targeted grep/awk measurements, and
read-only verification (`bash -n` ×10, `update-bootstrap-checksums.sh --check`).
The full suite was not run (a run is already in progress); nothing was modified
except this report. Calibration: `docs/AUTONOMOUS_AUDIT.md` (F1–F19, R1–R6,
sessions 1–7), `docs/CLI_CONTRACT.md`, README §10–11, `scripts/ci-local.sh`.
Settled items from sessions 1–7 are deliberately not re-reported.

## 1. Summary

| id | title | category | severity | verdict |
|----|-------|----------|----------|---------|
| A1 | four-artifact table defined 3×, inlined 6× in the verifier | duplication | low | maintainability risk |
| A2 | `sha256_of` ×4 and `SCRIPT_DIR`/`ROOT` ×4 across standalone scripts | duplication | low | acceptable intentional duplication |
| A3 | flag-parse loops, colour palettes, log helpers ×4 | duplication | low | acceptable intentional duplication |
| A4 | integer/port validation idioms ×3 sites | duplication | low | acceptable intentional duplication |
| A5 | manifest-reading awk duplicated; lenient vs strict parsers diverge | policy duplication | low | no-action observation |
| A6 | `die2` dead logic in SemVer validation | dead code / naming | low | confirmed defect (fix this session, low risk) |
| A7 | harness lint fallback list is stale (misses `scripts/*.sh`) | test harness | low | confirmed defect (fix this session, low risk) |
| A8 | harness §8/§9 physically swapped; header comment predates §16–29 | maintainability | low | confirmed defect (fix this session, low risk) |
| A9 | version truth scattered: `VERSION`, `SCRIPT_VERSION` ×2, `--version`, doc pin row | undocumented invariant | low | maintainability risk |
| A10 | harness pins product source text (grep counts/line order) | tight coupling | low | acceptable intentional duplication |
| A11 | harness pins message text beyond the documented contract | tight coupling | low | no-action observation |
| A12 | checksum tool depends on bootstrap case-arm formatting | undocumented invariant | low | maintainability risk |
| A13 | verifier banner says "standalone"; signature path needs the repo | naming | low | no-action observation |
| A14 | unknown-flag → stdout in `pixel-*.sh`, stderr in `scripts/*.sh` | error handling | low | no-action observation |
| A15 | `die()` in apps-setup omits the FATAL log line dev-setup writes | error handling | low | no-action observation |
| A16 | magic `exit 90` in `agent_run` undocumented | error handling | low | no-action observation |
| A17 | shebang convention inconsistent (Termux-absolute vs `env`) | portability | low | no-action observation |
| A18 | `sort` without `LC_ALL`; GNU-isms otherwise documented/guarded | portability | low | no-action observation |
| A19 | KICKSTART commit policy diverges from seeded charter rule 2.5 | documentation | low | no-action observation |
| A20 | oversized units: 1544-line flat harness; 175-line inline verifier body | size | low | deferred redesign opportunity |

## 2. Findings

### A1 — four-artifact table defined three times, inlined six times in one file
- **Evidence**: the canonical list `bootstrap-checksums.txt pixel-apps-setup.sh
  pixel-bootstrap.sh pixel-dev-setup.sh` (with roles/modes) is materialised in
  `scripts/build-release-candidate.sh:100-103` (four parallel arrays
  `ART_PATHS`/`ART_SRCS`/`ART_MODES`/`ART_ROLES`, iterated by five separate
  `while` loops at :105, :128, :137, :166, :191); in
  `scripts/verify-release-bundle.sh` as `CORE_FILES` (:70), `WANT_ROLE`/
  `WANT_MODE` (:124-129), **six** inline repetitions (:136, :150, :171, :208,
  :224, :229), plus numeric count checks (:118, :149, :177); and again
  hardcoded in the harness (:1021 exact layout, :1060, :1067, :1083).
- **Why it matters**: adding or renaming a bundle artifact touches ~10 sites
  across 3 files. Drift is caught (harness §24a pins the exact layout, §25
  exercises the verifier), so it fails safe — but the cost is real and the
  six in-file repetitions in the verifier buy nothing.
- **Verdict**: maintainability risk. Local consolidation (one `ARTIFACTS` var
  in the verifier) is cheap and behavior-neutral; cross-file sharing is not
  (see A2).

### A2 — `sha256_of` and `SCRIPT_DIR`/`ROOT` duplicated across standalone scripts
- **Evidence**: `sha256_of` at `pixel-bootstrap.sh:71-75`,
  `scripts/update-bootstrap-checksums.sh:48-52`,
  `scripts/build-release-candidate.sh:72-76`,
  `scripts/verify-release-bundle.sh:60-64` (plus `file_sha` in the harness,
  `tests/run_tests.sh:552`). The root-resolution block at `scripts/ci-local.sh:20-22`,
  `build-release-candidate.sh:59-61`, `update-bootstrap-checksums.sh:35-37`,
  `verify-release-bundle.sh:55-57`.
- **Why it matters**: a shared `scripts/lib.sh` looks tempting but would break
  two load-bearing properties: (a) `pixel-bootstrap.sh` must be self-contained —
  it runs alone on a phone with no repo checkout; (b) the harness copies
  **single files** into fixtures (`mk_fx` copies only the checksum tool,
  `tests/run_tests.sh:762-766`; `mk_rc_clone` copies only the builder, :998) —
  a sourced library would silently break those fixtures and the "one file"
  invocation contract.
- **Verdict**: acceptable intentional duplication — self-containment is a
  tested feature here, not an accident.

### A3 — flag-parse loops, colour palettes, log helpers ×4
- **Evidence**: parse loops `pixel-bootstrap.sh:24-31`, `pixel-dev-setup.sh:28-38`,
  `pixel-apps-setup.sh:28-38`, `pixel-autodev.sh:39-54`; colour/helper blocks
  `pixel-bootstrap.sh:33-42`, `pixel-dev-setup.sh:41-55`,
  `pixel-apps-setup.sh:53-64`, `pixel-autodev.sh:87-97`.
- **Why it matters**: `docs/CLI_CONTRACT.md:9` explicitly sanctions this
  ("All four scripts parse flags the same way"); the four scripts ship to
  different layers (Termux, proot Ubuntu) with no shared-lib channel.
- **Verdict**: acceptable intentional duplication, per documented contract.

### A4 — integer/port validation idioms duplicated
- **Evidence**: `is_posint` (`pixel-autodev.sh:62-65`) vs the port check
  (`pixel-apps-setup.sh:44-51`); the leading-zero strip idiom
  `"${V#"${V%%[!0]*}"}"` at `pixel-autodev.sh:64`, `:71`, `pixel-apps-setup.sh:47`.
  `scripts/verify-bootstrap-signature.sh:42-52` reimplements the
  `resolve_required_tool` seam contract inline (`pixel-autodev.sh:108-120`) —
  and says so in its banner (:14-15).
- **Why it matters**: per-flag messages differ and are contractual
  (CLI_CONTRACT §4/§5/§6 quote them verbatim); a shared helper would save ~10
  lines per script but still need per-flag wrappers.
- **Verdict**: acceptable intentional duplication (same rationale as A2/A3;
  the seam duplication is explicitly documented).

### A5 — manifest-reading awk duplicated; lenient vs strict parsers diverge
- **Evidence**: `pixel-bootstrap.sh:60` and `tests/run_tests.sh:550` carry the
  same awk (`$1 ~ /^[0-9a-fA-F]{64}$/ … tolower`), while
  `scripts/update-bootstrap-checksums.sh:75` parses the same manifest strictly
  (`^[0-9a-f]{64}\ \ ([a-z.-]+)$`, lowercase, two spaces, anchored).
- **Why it matters**: the divergence is sound — the lifecycle gate enforces
  canonical form, the runtime reader tolerates hand-edits and still fails
  closed on digest mismatch — but it is nowhere documented. One comment line
  would close the gap.
- **Verdict**: no-action observation (safe as-is; document if touched).

### A6 — `die2` dead logic in SemVer validation
- **Evidence**: `scripts/build-release-candidate.sh:45-48`:
  ```bash
  case "$VERSION" in
    *[!0-9.]*) die2=1 ;; *) die2=0 ;;
  esac
  if [ "${die2:-0}" = 1 ] || ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  ```
  The regex already rejects every value the case arm catches (`1.0.x`, `abc`,
  `v1.0.0` all fail `^[0-9]+\.[0-9]+\.[0-9]+$`); the case and the `die2`
  variable — a name that reads like a function — are unreachable dead weight.
- **Why it matters**: readers must prove the redundancy for themselves; the
  variable name is actively misleading.
- **Verdict**: confirmed defect (fix this session, low risk) — delete the
  case/`die2`, keep the regex. Harness §24i (`tests/run_tests.sh:1133-1140`)
  already pins the full malformed-version matrix, so behavior cannot drift.

### A7 — harness lint fallback list is stale
- **Evidence**: `tests/run_tests.sh:37-40`:
  ```bash
  lint_files="$(git ls-files '*.sh' 2>/dev/null)" || lint_files=
  if [ -z "$lint_files" ]; then
    lint_files="$(printf '%s\n' pixel-bootstrap.sh pixel-dev-setup.sh pixel-apps-setup.sh pixel-autodev.sh tests/run_tests.sh)"
  fi
  ```
  The fallback predates `scripts/` and covers 5 of the 10 tracked shell
  scripts; the header (:35) promises "Every tracked shell script".
- **Why it matters**: in a non-git copy (tarball export) the syntax/shellcheck
  gates silently skip `scripts/*.sh`. Degraded-mode coverage hole only — the
  git path is correct — but the fix is one line.
- **Verdict**: confirmed defect (fix this session, low risk) — add the five
  `scripts/*.sh` paths to the fallback. Harness-only change.

### A8 — harness §8/§9 physically swapped; header comment predates §16–29
- **Evidence**: section banners run §7 (:251) → §9 (:264) → §8 (:312) → §10
  (:325); the header coverage list (`tests/run_tests.sh:6-10`) stops at
  "clean-clone smoke" and mentions none of §16–§29 (checksum lifecycle,
  release builder/verifier, reproducibility, doc contracts).
- **Why it matters**: the audit and docs reference section numbers
  ("harness §16", "§24–§28"); a stale map of a 1544-line file costs real
  navigation time. Assertion text carries no section numbers, so comment-only
  edits cannot break the suite.
- **Verdict**: confirmed defect (fix this session, low risk) — swap the two
  comment banners, refresh the header. Comment-only; edit between suite runs
  (bash reads scripts incrementally, and a suite is running).

### A9 — version truth scattered across four sites, none cross-checked
- **Evidence**: `VERSION:1` (`1.0.0`, read by **no** code — grep finds only
  doc references: README §10 layout block, `docs/BOOTSTRAP_RELEASE_PROCESS.md:15,58`);
  `SCRIPT_VERSION="1.0.0"` in `pixel-dev-setup.sh:22` and
  `pixel-apps-setup.sh:23`; the release version comes from the `--version`
  flag (`build-release-candidate.sh:31`), never from `VERSION`; harness §21
  pins the release doc's commit+digest but not its version number.
- **Why it matters**: a release that bumps `VERSION` but forgets one
  `SCRIPT_VERSION` (or vice versa) passes every gate; the banner on a user's
  phone then disagrees with the release tag.
- **Verdict**: maintainability risk — a two-line grep assertion
  (`VERSION` == both `SCRIPT_VERSION`s) closes it; requires a harness change.

### A10 — harness pins product source text
- **Evidence**: `tests/run_tests.sh:194-195` counts literal `timeout "\$TIMEOUT"`
  occurrences (want 2); :588-594 counts curl wiring patterns; :977-983 pins the
  download-then-verify line order; :957-961 matches the trap regex; :551
  extracts embedded digests by grepping the case-arm syntax.
- **Why it matters**: any refactor of `pixel-autodev.sh`/`pixel-bootstrap.sh`
  internals breaks the suite without a behavior change. This is a recorded
  decision — `docs/AUTONOMOUS_AUDIT.md` D4 ("the single-quoted pattern is
  intentional — it must match the literal text") — and the white-box pins have
  caught real regressions (F19).
- **Verdict**: acceptable intentional duplication (coupling documented and
  deliberate; brittleness is the price of pinning wiring, not text).

### A11 — harness pins message text beyond the documented contract
- **Evidence**: contractual messages (quoted in `docs/CLI_CONTRACT.md` §4/§5/§6)
  are pinned, but so are undocumented strings: `"Working up to 8 task(s)"`
  (:378), `"dry-run: skipping agent resolution"` (:449), `"agent: claude ("`
  (:460), `"authenticity NOT established"` (:1256), `"is current"` (:775),
  `"already current"` (:814), `"checksum mismatch for pixel-dev-setup.sh"` (:631).
- **Why it matters**: for the undocumented subset, the harness is the only
  spec — rewording output requires a harness edit even when no contract
  changes. This is the repo's deliberate tests-as-spec model; the cost is
  bounded because pins are substrings, not whole lines.
- **Verdict**: no-action observation.

### A12 — checksum tool depends on bootstrap's case-arm formatting
- **Evidence**: `scripts/update-bootstrap-checksums.sh:99` (`grep -A1 -- "$1)"`)
  and :124/:128 (`^[[:space:]]*${name}\).*[0-9a-f]{64}`) require each embedded
  digest to sit on the same line as its `name)` case arm in
  `pixel-bootstrap.sh:64-68`. Nothing in `pixel-bootstrap.sh` says so.
- **Why it matters**: a well-meaning reformat of `expected_sha256` (e.g.
  multi-line case arms) silently breaks `--write` — though it fails closed
  ("expected 1 line") and harness §16/§20l go red immediately.
- **Verdict**: maintainability risk — a one-line comment at
  `pixel-bootstrap.sh:58` documenting the external consumer fixes it. Note:
  any edit to this pinned file requires the lockstep `--write` refresh
  (manifest re-pins the anchor), so bundle the comment with real work.

### A13–A19 — minor observations (all no-action; evidence kept for the record)

- **A13** — verifier banner says "standalone" (`scripts/verify-release-bundle.sh:3`)
  but the signature phase needs `HELPER="$ROOT/scripts/verify-bootstrap-signature.sh"`
  (:55-58, :195). Integrity checks are self-contained; a missing helper fails
  closed (`failed-policy`), and bundle `VERIFY.md` instructs repo-root
  invocation. Safe; "standalone" is only a wording nuance.
- **A14** — unknown-flag line goes to stdout in `pixel-*.sh`
  (`pixel-bootstrap.sh:29`, `pixel-dev-setup.sh:36`, `pixel-apps-setup.sh:36`,
  `pixel-autodev.sh:53`) but stderr in `scripts/*.sh`. Documented historical
  contract (`docs/CLI_CONTRACT.md:33-34`); explicitly reviewed in session 7
  ("Unknown-flag-on-stdout — reviewed, no action"). Settled.
- **A15** — `die()` in apps-setup (`pixel-apps-setup.sh:63`) omits the `FATAL`
  log line dev-setup's writes (`pixel-dev-setup.sh:54`); its `_log` also
  suppresses errors (`:58`). Cosmetic; the contract mandates no log format.
- **A16** — magic `exit 90` on `cd` failure in `agent_run`
  (`pixel-autodev.sh:272`) lands correctly in the generic agent-error revert
  path (:330-339) but is documented nowhere. Behavior right, meaning tribal.
- **A17** — shebangs: Termux-absolute on `pixel-bootstrap.sh:1`,
  `pixel-apps-setup.sh:1`, `pixel-autodev.sh:1` vs `#!/usr/bin/env bash` on
  `pixel-dev-setup.sh:1` and all `scripts/*.sh`. Autodev's Termux shebang
  cannot resolve in its proot-Ubuntu runtime — but every invocation is
  `bash <script>` (README, shortcuts at `pixel-bootstrap.sh:138-139`, harness,
  CI), so no shebang is ever executed. Cosmetic.
- **A18** — `sort` without `LC_ALL` (`update-bootstrap-checksums.sh:82`,
  `tests/run_tests.sh:1030,1402-1403`); compared names are lowercase ASCII,
  so ordering is locale-stable in practice. Positives verified: zero process
  substitution anywhere (`/dev/fd` avoidance is deliberate —
  `scripts/ci-local.sh:15-16`, `tests/run_tests.sh:36`); `stat -c` guarded
  (`update-bootstrap-checksums.sh:126,142`, `verify-release-bundle.sh:65,233`);
  `date -d`/`touch -d` guarded (`build-release-candidate.sh:146-147,250-252`);
  retained GNU-isms documented (`docs/CLI_CONTRACT.md:250-254`).
- **A19** — `KICKSTART.md:56-59` has the (manual, pasted) agent commit on
  green and grants `Bash(git commit *)` (:8), while the charter autodev seeds
  forbids agent commits (`pixel-autodev.sh:184-185`, rule 2.5). Two
  legitimate modes with opposite VCS policies; nothing states the divergence
  is intentional. One clarifying sentence would do, if KICKSTART is touched.

### A20 — oversized units
- **Evidence** (measured): `tests/run_tests.sh` 1544 lines, effectively one
  flat procedure (helpers are ≤16 lines; the gaps between them are 50–230
  lines of straight-line assertions); `scripts/verify-release-bundle.sh` runs
  ~175 lines inline after `jget` (:68→EOF) with the five verification phases
  as comments, not functions; `scripts/build-release-candidate.sh` ~185 lines
  inline after `sha256_of`. Largest product function: `do_task`,
  `pixel-autodev.sh:285-361` (77 lines) — acceptable: one phase per guard.
- **Why it matters**: the flat harness is navigable only via the §-banners
  (see A8); the inline verifier/builder bodies are linear and readable, so
  functionalising them churns test-pinned text for no behavior gain.
- **Verdict**: deferred redesign opportunity — not this session; if it ever
  happens, extract verifier phases into functions first (highest payoff,
  fewest external pins).

## 3. Recommended implementations for this session

Ordered by benefit/risk. All are report-level recommendations; this review
modified no code.

1. **A6 — delete the `die2` case in `build-release-candidate.sh:45-48`.**
   Behavior identical; harness §24i pins the malformed-version matrix, so no
   harness change is needed and any regression goes red immediately.
   Coverage needed: existing §24i.
2. **A7 — add `scripts/verify-bootstrap-signature.sh`,
   `scripts/update-bootstrap-checksums.sh`, `scripts/ci-local.sh`,
   `scripts/build-release-candidate.sh`, `scripts/verify-release-bundle.sh`
   to the `lint_files` fallback (`tests/run_tests.sh:39`).** Harness-only;
   no assertion text changes. Coverage needed: none beyond §1/§2, which
   exercise the list.
3. **A1 (local half) — replace the six inline artifact lists in
   `scripts/verify-release-bundle.sh` with one `ARTIFACTS` var.** Verifier is
   not a checksum-pinned artifact, so no lockstep churn; verdicts are pinned
   by §25/§26, so no harness change. Coverage needed: existing §25/§26.
4. **A8 — swap the §8/§9 comment banners and refresh the harness header
   (:6-10).** Comment-only; edit between suite runs. Coverage needed: none.
5. **A12 — add a comment at `pixel-bootstrap.sh:58` noting the checksum
   tool consumes the case-arm layout.** Caveat: any edit to this pinned file
   changes the anchor digest; the same commit must run
   `scripts/update-bootstrap-checksums.sh --write` and ship the refreshed
   manifest (§16/§23d and CI gate 2 go red otherwise). Coverage needed:
   existing §16/§20.
6. **A9 — add a grep assertion `VERSION` == both `SCRIPT_VERSION`s.**
   Requires a harness change (new §-assertion); alternative: delete
   `SCRIPT_VERSION` from the banners if the duplication is not wanted.
   Coverage needed: the new assertion itself.

Explicitly deferred: A20 (verifier functionalisation), A2/A3/A4 (no shared
library — justified above), A14 (settled contract).

## 4. Checked and found clean (negative results)

- **Syntax**: `bash -n` passes on all 10 tracked shell scripts (verified this
  session). Checksum lockstep green: `update-bootstrap-checksums.sh --check`
  → rc 0, manifest + embedded digests + file contents agree (verified).
- **Circular dependencies / layering**: none. Call graph is a DAG:
  harness → all; builder → checksum tool (`build-release-candidate.sh:89`);
  verifier → signature helper (`verify-release-bundle.sh:196`); bootstrap
  standalone. No product script calls the harness; no script reads another's
  variables.
- **gpg**: single invocation site (`verify-bootstrap-signature.sh:58`); the
  bundle verifier delegates to it rather than reimplementing — the
  anticipated gpg duplication does not exist.
- **Portability**: no process substitution / `/dev/fd` use anywhere (grep
  verified); `eval` appears only inside the `.bashrc` snippet dev-setup
  *generates* (starship/zoxide init, `pixel-dev-setup.sh:179-180`) — never in
  executed repo code; no `readlink -f`/`realpath` (F14 still holds).
- **Exit-code classes**: 0/1/2 consistent with `docs/CLI_CONTRACT.md:27-28`
  across all nine scripts; the one borderline case (non-numeric
  `SOURCE_DATE_EPOCH` → exit 1, `build-release-candidate.sh:53-56`) is
  documented in the banner and pinned by §27c.
- **Validation-before-side-effect ordering** holds everywhere checked
  (contract §1; harness §9a/§10g/§15e pin it).
- **Dead code/files**: none beyond A6/A7. `CHECK`, `KEEP_PARTIAL`,
  `MODE_NOTE`, `SEEN_*`, `RAW`, `INSTALLED`, `FAILED` are all live;
  `.autodev/` is untracked and gitignored (`.gitignore:3`); `reports/` and
  `evidence/` are tracked, documented append-only stores (README §10);
  `VERSION` and `KICKSTART.md` are documentary, not dead (see A9/A19).
- **Message/stream consistency within classes**: invalid-value diagnostics on
  stderr naming the flag in every script (contract §1:32-34); unknown-flag
  stdout is the documented exception (A14).
- **Repo state**: tree clean except untracked `evidence/session-8/` (the
  background suite's output); nothing pushed, nothing committed by this review.
