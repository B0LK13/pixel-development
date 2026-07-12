# Developer-Experience & Operator-Workflow Review (Session 8)

Two personas walked the repo end to end: a new contributor who just cloned, and
an operator building/verifying a release. Method: read the docs a newcomer would
open, ran `--help` on all 9 scripts, inspected the error paths in scripts and
harness, and checked what `tests/run_tests.sh` pins. No files modified except
this report; the full suite was not run (background run in progress; last green
evidence: `evidence/session-7/test-results.txt` — 284 passed, 0 failed).

Disclosure: while probing help output I ran `bash scripts/ci-local.sh --help`.
The script has no argument handling, so it ignored `--help` and began running
the five gates; my 60s tool timeout killed it mid-suite. Completed gates were
green and `git status` was unchanged (the harness writes only to `mktemp`
dirs). That accident is itself finding A-5 below.

---

## 1. Journey findings

### Persona A — new contributor

**A-1. Orientation works.** README §1 gives the verified install, §10 names
every directory (pinned against reality by harness §29a,
`tests/run_tests.sh:1519-1530`), and §11 answers "how do I run the gate" in one
command (`README.md:236-240`) and links the contract/audit/release docs
(`README.md:260-264`, link presence pinned by §28e). No "read this first" map.

**A-2. Prerequisite discovery is partial.** The harness degrades gracefully —
`tests/run_tests.sh:66`: "shellcheck not installed — lint gate skipped (pkg
install shellcheck)"; jq likewise (`:92`). But the only full dependency
inventory is `docs/CLI_CONTRACT.md` §8 (`:204-221`), which a contributor may
never open. The **bash floor is undocumented**: the checksum tool uses
`declare -A` (`scripts/update-bootstrap-checksums.sh:55`, bash ≥4), while
`docs/AUTONOMOUS_AUDIT.md:153` still claims "bash 3.2 itself would mostly
cope" — stale since the checksum tool landed.

**A-3. Local-vs-CI parity is real but under-signposted.** `scripts/ci-local.sh`
runs the same five gates as `.github/workflows/test.yml`, drift statically
pinned by harness §22 (`tests/run_tests.sh:882-929`). Yet README §11 never
mentions it; pointers exist only in the script header (`scripts/ci-local.sh:2-17`),
`docs/AUTONOMOUS_AUDIT.md:314`, and `docs/REMOTE_CI_VERIFICATION.md:60,77`.
Running only `tests/run_tests.sh` misses gates 1-2 (`git diff --check`,
checksum lockstep).

**A-4. No test selection.** The harness has no top-level argument loop — any
argument (including `--help`) is silently ignored and the full suite runs. The
only knobs are env vars, documented **only in the harness header**:
`PIXEL_TESTS_NO_CLONE=1` (`tests/run_tests.sh:13`) and `PIXEL_TEST_TIMINGS=1`
(`:21-28`; also `docs/AUTONOMOUS_AUDIT.md:388`, "documented dev convenience
only"). Cost is real: ~1m50s outer run (`evidence/session-5/test-timings.txt:14`)
plus a nested clean-clone run.

**A-5. Checksum-refresh workflow is discoverable only at failure time.** After
editing a pinned script, the gate fails with itemized `STALE: <artifact>` lines
and the exact fix (`scripts/update-bootstrap-checksums.sh:163`): "checksum
manifest is STALE — run: bash scripts/update-bootstrap-checksums.sh --write".
But the *workflow* (run `--write` in the same commit as the edit) is documented
only in release context (`docs/BOOTSTRAP_RELEASE_PROCESS.md:52-54`) and the
tail of CLI_CONTRACT §8. README §11 is silent; a contributor learns from a red
gate — which at least tells them exactly what to do.

**A-6. Help output is inconsistent across the nine scripts.** The 4 product
scripts print clean banner-only `--help` (pinned by harness §3,
`tests/run_tests.sh:69-82`; fixed in `a2ed5e8`). All 5 release scripts leak
source lines past the banner border (verified by running each): `sed -n` ranges
overshoot — `build-release-candidate.sh:35` prints 2-30 vs. border `:25`;
`verify-release-bundle.sh:33` 2-30 vs. `:23`; `verify-bootstrap-signature.sh:24`
2-19 vs. `:16` (leaks `set -uo pipefail`, `KEYRING='' SIG='' ARTIFACT=''`);
`update-bootstrap-checksums.sh:23` 2-17 vs. `:15` (leaks `set -uo pipefail` +
blank, confirmed via `cat -A`). And `scripts/ci-local.sh` has **no `--help`
handler and no arg loop** — any argument runs the full gate sequence (see
disclosure). Banner-only is pinned only for the product scripts, so nothing
guards the release scripts. README §8's "Every script supports `--help`"
(`README.md:191`) is false for `ci-local.sh` (and `tests/run_tests.sh`). Minor:
banners disagree on the alias — bootstrap/apps show `[-h]`, dev-setup
`[--help]`, autodev lists neither, though all four handlers accept both
(`pixel-bootstrap.sh:28`, `pixel-dev-setup.sh:33`, `pixel-apps-setup.sh:35`,
`pixel-autodev.sh:52`).

**A-7. Error-stream inconsistency, documented but odd.** Invalid values go to
stderr naming flag+constraint+value (`pixel-apps-setup.sh:43`;
`pixel-autodev.sh:61`), but "Unknown flag: … (try --help)" goes to **stdout**
in all four product scripts (`pixel-bootstrap.sh:29`, `pixel-dev-setup.sh:36`,
`pixel-apps-setup.sh:36`, `pixel-autodev.sh:53`) while every release script
uses stderr. CLI_CONTRACT §1 documents this: "the unknown-flag line is
historical `stdout`" (`docs/CLI_CONTRACT.md:33`).

### Persona B — release operator

**B-1. A real release checklist exists.** `docs/BOOTSTRAP_RELEASE_PROCESS.md`
§3 is a 10-step operator checklist (`:48-74`) with pin history (§2), signing
policy (§4), rollback (§5), archive decision (§6); the `current` pin row is
machine-checked against the git object (§21, `tests/run_tests.sh:865-880`).

**B-2. The checklist never mentions the bundle.** The build → sign → verify
flow lives in `docs/RELEASE_SIGNING.md` §2-4 with exact commands; the docs
cross-link ("Companion to…"), but no checklist step says "build and verify the
candidate bundle". The seam is exactly where a step gets skipped.

**B-3. The verification journey is well served.** Unsigned: `--bundle=DIR` →
`verdict: verified-integrity-only`; signed: add `--signature= --keyring=
--require-signature` → `verified-signed` (`docs/RELEASE_SIGNING.md:67-85`,
policy table §5). The verifier `--help` documents the trust order (layout →
metadata → manifest → signature → checksums) and all seven verdicts; failures
are precise — `verdict: failed-checksum` on stdout plus `digest mismatch:
<file>` on stderr (`scripts/verify-release-bundle.sh:47-49,210`).
Side-effect-free verification is pinned by §28g.

**B-4. Build-gate messages name the fix.** Dirty tree
(`scripts/build-release-candidate.sh:86`): "working tree is not clean — commit
or stash first:" + the actual porcelain output. Malformed version (`:49-50`):
"malformed version: X (want strict SemVer X.Y.Z, e.g. 1.0.0)". Existing output
(`:123`): "output already exists: … (remove it or choose another
--output-dir)". `SOURCE_DATE_EPOCH` validated up front (`:53-54`) and
documented in the builder banner (`:22`), `docs/RELEASE_SIGNING.md:39`, and
`docs/BOOTSTRAP_RELEASE_PROCESS.md:129-133` (deterministic-tar recipe).

**B-5. Operator-facing env vars: mostly covered.** `SOURCE_DATE_EPOCH` (B-4);
`GPGV_BIN` (signature-helper banner); autodev seams `CLAUDE_BIN`/`CODEX_BIN`/
`TIMEOUT_BIN`/`GIT_BIN` (CLI_CONTRACT §8, `:224-226`; README §11, `:246`).
`GNUPGHOME` appears only in harness/workflow/reports (`tests/run_tests.sh:703`)
— acceptable: signing assumes the operator's own keyring on a trusted machine
and CI never touches the default keyring.

---

## 2. Improvement candidates

**I-1. `ci-local.sh`: add `--help`, reject unknown args (exit 2).** Problem: any
argument is silently ignored; `--help` runs the full suite (A-6). Improvement:
print the existing header on `--help|-h` (same `sed` idiom as the others) and
`echo "ci-local: unknown argument: $a (try --help)" >&2; exit 2` otherwise.
Safe: additive; gate order, fail-fast, and exit-status passthrough
(`scripts/ci-local.sh:28`, pinned by §22) untouched; nothing suppressed. Tests:
new §22 assertions (`--help` exits 0 with banner; `--bogus` exits 2) — additive
harness update, no pinned text changes. Makes README §8's claim true.

**I-2. Fix the four overshooting `--help` sed ranges (release scripts).**
Problem: banner-only leak (A-6; the bug class `a2ed5e8` fixed for product
scripts). Improvement: end each range at the border — 2,25 / 2,23 / 2,16 / 2,15
per A-6. Safe: output-only; these scripts are not in
`config/bootstrap-checksums.txt` (pins only the three `pixel-*.sh`), so no
checksum churn; exit codes and stderr untouched. Tests: extend the §3
banner-only check (`grep -v '#$'`, `tests/run_tests.sh:75-79`) to `scripts/*.sh`
— requires harness update; the release banners' interior lines already end in
`#`, so the existing assertion shape works.

**I-3. Move "Unknown flag" to stderr in the 4 product scripts.** Problem: usage
diagnostics split across streams (A-7). Improvement: `>&2` at the four sites
(A-7); delete the "historical stdout" clause (`docs/CLI_CONTRACT.md:33`). Safe:
exit code stays 2 — the only pinned property (`tests/run_tests.sh:80-81`
redirects both streams to null, checks rc); stderr gains content, nothing
hidden. These files ARE checksummed → needs the A-5 `--write` refresh in the
same commit. Tests: none required (optionally assert the stream in §3); doc
update required.

**I-4. Document harness knobs + ci-local in README §11.** Problem: A-3/A-4 —
`PIXEL_TESTS_NO_CLONE`, `PIXEL_TEST_TIMINGS`, `bash scripts/ci-local.sh` are
invisible from the contributor entry point. Improvement: three lines in §11
(fast run, profiler, "reproduce CI exactly"). Safe: doc-only; §28e pins only
the presence of the three release-doc links (kept verbatim); §29a pins §10
(untouched). Tests: none.

**I-5. State the bash ≥4 floor; fix the stale portability claim.** Problem:
`declare -A` (`scripts/update-bootstrap-checksums.sh:55`) vs. "bash 3.2 … would
mostly cope" (`docs/AUTONOMOUS_AUDIT.md:153`). Improvement: add a versioned bash
row to the CLI_CONTRACT §8 table; qualify the audit sentence (product scripts
vs. release tooling). Safe: doc-only. Tests: none.

**I-6. Bridge the release checklist to the bundle flow.** Problem: B-2.
Improvement: one additive step in `docs/BOOTSTRAP_RELEASE_PROCESS.md` §3 —
build with the commit-pinned `SOURCE_DATE_EPOCH`, run both verifier modes,
linking (not restating) `docs/RELEASE_SIGNING.md` §2-4. Safe: doc-only; §21
greps the pin row + "Rollback procedure" + "operator-owned", §28f greps
"Archive handling" — all preserved. Tests: none.

**I-7. Append install hints to the two bare missing-tool deaths.** Problem:
`pixel-autodev.sh:145` ("GNU timeout (coreutils) is required in the devbox")
and `:147` ("git not installed in devbox") name the component but not the fix,
unlike the agent-missing message at `:139` ("Enter the devbox and install the
AI stack first."). Improvement: append "— install with: apt-get install -y
coreutils" / "… -y git", keeping the existing sentences as verbatim prefix.
Safe: stderr text, still `die` exit 1; §15a/b match by substring
(`tests/run_tests.sh:496-499`, `seam_fail` uses `*"$want"*`), so appending
after the pinned prefix cannot break them. Tests: none; §15 keeps pinning the
prefix.

---

## 3. Deliverables recommendation

**`docs/CONTRIBUTOR_QUICKSTART.md` — CREATE.** The content exists but is
scattered across README §11, CLI_CONTRACT §8, the release-process step, and the
harness header; a one-screen pointer page has clear marginal value. Keep it
link-driven (no restated message text, which would rot against pinned strings).
TOC sketch:
1. Scope: contributing to this repo (not using the kit on a Pixel)
2. Prerequisites: bash ≥4, git; shellcheck + jq optional (gates skip cleanly)
3. Run the gates: full suite; `PIXEL_TESTS_NO_CLONE=1`; `PIXEL_TEST_TIMINGS=1`; `bash scripts/ci-local.sh`
4. Editing a pinned `pixel-*.sh`: `scripts/update-bootstrap-checksums.sh --write` in the same commit
5. Contracts you must not break: CLI_CONTRACT; harness §28/§29 doc pins
6. Where to read next (links to canonical docs)

**`docs/OPERATOR_COMMAND_INDEX.md` — CREATE (table-only).** The release-cutting
operator has the §3 checklist, but the *verifying* operator (handed a bundle or
checking a bootstrap asset) must stitch RELEASE_SIGNING §4,
BOOTSTRAP_RELEASE_PROCESS §5, and README §1. Value is real only as a table of
commands + verdicts + links, never a second prose source. TOC sketch:
1. Verify a bootstrap asset (sha256 pin; tier-2 signature helper)
2. Verify a release bundle unsigned / signed (verdicts, one row each)
3. Build a candidate (`SOURCE_DATE_EPOCH` from the release commit)
4. Refresh checksums after editing a pinned script
5. Local CI parity + remote run inspection (link REMOTE_CI_VERIFICATION)
6. Exit-code legend (0/1/2) + pointers to canonical docs

**`docs/TROUBLESHOOTING.md` — SKIP.** Every audited failure already names the
component and the fix (§4); a standalone doc would duplicate exact message text
the harness pins (§15 substrings, §17b "checksum mismatch for
pixel-dev-setup.sh", §20 "STALE:" lines) and rot silently. Fold a 4-line
"gate failed → first move" block into CONTRIBUTOR_QUICKSTART instead (stale
checksums → `--write`; shellcheck gap → install or accept the skip; dirty-tree
refusal → commit/stash; suite slow → `PIXEL_TESTS_NO_CLONE=1`).

---

## 4. Negative results — what already works well

- **Usage-error discipline**: unknown flag → exit 2 with "(try --help)" in all
  8 arg-parsing scripts; invalid values exit 2 *before any side effect* —
  pinned by §9a ("invalid ports create no log file"), §10g, §15e. The
  `--ssh-port` matrix (§9) covers 15 malformed forms incl. `22;reboot`.
- **Value-validation messages** name flag + constraint + received value
  (`pixel-apps-setup.sh:43`, `pixel-autodev.sh:61`,
  `scripts/build-release-candidate.sh:49-50`).
- **The checksum gate is self-healing guidance**: itemized `STALE:`/`EMBEDDED
  STALE:` + the exact `--write` command (`update-bootstrap-checksums.sh:107,114,163`);
  `--check` proven non-mutating (§20j); interrupted `--write` leaves the
  manifest byte-identical (§20k).
- **Autodev preflight deaths are actionable**: PATH-leak guard says "run:
  devbox, then retry" (`pixel-autodev.sh:141`); agent-missing names the devbox
  remedy (`:139`).
- **Bootstrap downloads fail closed with causes** (`pixel-bootstrap.sh:111`:
  "checksum mismatch … NOT installed (source may be tampered, or the pin is
  stale)"); temp cleaned via EXIT trap, including on SIGTERM (§17b, §23a).
- **Docs are held honest by the harness**: README layout vs. reality (§29a),
  script-path references (§29b), release-doc contracts (§28), CI parity (§22),
  README pin vs. git object (§21, §18). This review found no drift the harness
  would have caught — every gap above lives in unpinned whitespace.
- **Hermetic suite**: stub agents via seams, fixture repos with repo-local
  identity and `commit.gpgsign false` (`tests/run_tests.sh:119-127`), temp
  paths containing a space (`:97`), tree left clean.
