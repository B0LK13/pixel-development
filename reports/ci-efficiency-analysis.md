# Session 8 — CI Efficiency & Reliability Analysis

Scope: `.github/workflows/test.yml`, `scripts/ci-local.sh`, and the local
gate chain they share. Method: static analysis of the workflow against the
repo's CLI contract, per-gate wall-time measurement on this host
(`evidence/session-8/ci-timing-baseline.txt`, drift-pinned run), per-test
profiling (`PIXEL_TEST_TIMINGS=1`), and a full fixture simulation of the
release job in a clean clone.

Honesty note up front: remote CI has never run (nothing pushed since the
workflow exists), so all timings are this-host measurements on a thermally
throttled devbox, not CI measurements. Where this session made no
measurement-backed improvement, it says so.

## C1 — CONFIRMED DEFECT (fixed this session): release job used space-form flags against equals-only tools

- **Evidence**: `.github/workflows/test.yml:50,53,57,70-72` (pre-fix) invoked
  `--output-dir "$RUNNER_TEMP/rc"`, `--bundle "$B"`, `--signature …`,
  `--keyring …` with a space. Both release tools are equals-only by contract
  (`docs/CLI_CONTRACT.md`; parser arms `--output-dir=*)` / `--bundle=*)` with
  an exit-2 unknown-flag fallthrough). Empirical reproduction:
  `SOURCE_DATE_EPOCH=0 bash scripts/build-release-candidate.sh --version=0.0.0 --output-dir /tmp/x`
  → `unknown flag: --output-dir`, exit 2. Every step of the
  release-candidate-check job would have failed on the first remote run.
- **Why it survived**: the job was added in Session 6 but never executed
  (no push); harness §22 validated the workflow statically (mechanism
  presence greps) without executing its commands, and the greps match
  space-form too.
- **Fix** (`66aedb9` on `auto/session-8-ci-efficiency`): all six invocations
  converted to equals-form; a §22 regression pin rejects
  `--(version|output-dir|bundle|signature|keyring) ` (space form) in the
  workflow — verified both directions (6 matches pre-fix, 0 post-fix).
- **Validation**: full release-job simulation in a clean fixture clone with
  the exact post-fix commands — build, `verified-integrity-only`,
  reproducibility `diff -r`, throwaway-ed25519 signed verify
  `verified-signed`, all steps pass.
- **Trust impact**: none weakened; the fix makes the release-verification
  gate actually runnable in CI. Reliability improvement, not a speed one.

## C2 — shellcheck installed via apt on every suite run

- **Evidence**: `.github/workflows/test.yml:29-30`
  (`sudo apt-get update -qq && sudo apt-get install -y -qq shellcheck`).
  Cost: ~20–40s + a network dependency per run.
- **Options considered**: cache the apt package (needs an extra action —
  a mutable external dependency the repo's pinning policy does not yet
  cover; see configuration-quality F5); vendor a static shellcheck binary
  (large, platform-specific); keep as-is.
- **Verdict: keep as-is (no action).** The install is from the distro's
  pinned mirror set, the job has no secrets and read-only permissions, and
  the harness self-skips shellcheck when absent — a failed install fails
  the step loudly rather than weakening a gate silently. Revisit only with
  a repository-wide action-pinning policy (deferred to the debt register).

## C3 — gate-chain structure: ci-local.sh duplicates two suite-internal checks

- **Evidence**: ci-local gates 3/4 (`bash -n`, shellcheck) re-run checks the
  harness performs internally (§1/§2). Measured cost of gates 1–4 combined:
  **4s** of a 582s total — 0.7%.
- **Verdict: acceptable intentional duplication (no action).** The outer
  gates fail fast on syntax/lint before the multi-minute suite starts, and
  the workflow's suite job skips gates 3/4's duplication by running the
  suite directly (shellcheck is consumed inside it). Parallelizing gates
  1–4 would save ≤3s and interleave output — rejected.

## C4 — the clean-clone smoke is the suite's dominant cost

- **Evidence**: `TIMING 314s clean-clone smoke: suite passes from a fresh
  clone` — 54% of gate 5 (578s). It re-runs the entire suite nested from a
  fresh `git clone --local` (`tests/run_tests.sh` §8).
- **Verdict: no action (reducing it is forbidden).** The mandate bars
  reducing clean-clone coverage; this test is what makes "clone → run →
  green" a proven property rather than a claim. The documented escape valve
  already exists: `PIXEL_TESTS_NO_CLONE=1` (dev convenience only — the
  default gate and CI always run the full path). Distribution: 183 of 288
  tests complete in <1s; only 2 exceed 10s — no sharding justification
  (thermal noise dominates any split; a shard boundary would also weaken
  the "one command runs everything" contract).

## C5 — timeouts, concurrency, permissions, cancellation

- suite job `timeout-minutes: 10` vs measured 4–9.6 min on a throttled
  devbox (x86 CI runners are faster and steadier): **appropriate, keep**.
  A missed timeout fails loudly; an over-generous one wastes runner
  minutes.
- release job `timeout-minutes: 5` vs measured ~15–25s of work (builder ≈3s,
  verifier ≈3s, keygen seconds): **appropriate**.
- `concurrency: group per ref, cancel-in-progress: true`: correct for a
  push-per-branch workflow; stale runs cancel.
- `permissions: contents: read`, no secrets, no agents: matches the
  least-privilege pin in harness §22. Nothing to improve without adding
  capability, which is out of scope.

## C6 — failure diagnostics in CI

- **Evidence**: workflow steps are named per gate; ci-local prints
  `== [n/5]` headers and `ci-local: FAIL — <gate> (exit N)` preserving the
  gate's own exit status (`scripts/ci-local.sh:26`); the suite prints
  per-test ok/FAIL lines with ≤20 lines of detail on failure.
- **Gap found by the diagnostics review (D3)**: no failed-test recap in the
  suite summary, and a nested clean-clone failure was detail-free. Fixed on
  `auto/session-8-diagnostics` (additive; consumers read rc only).
- **Verdict: otherwise sufficient** — every CI failure mode maps to exactly
  one named step or one FAIL line.

## Measured improvements (honest accounting)

| item | before | after | kind |
|------|--------|-------|------|
| release job remote run | fails at step 1 (exit 2, space-form) | all steps pass (simulated) | reliability, not speed |
| local gate chain wall time | 582s | unchanged (no speed change claimed) | — |
| gates 1–4 | 4s | unchanged | — |
| suite | 578s (288 tests) | unchanged + new pins | — |

No caching, parallelism, or sharding was introduced: every candidate either
weakened a coverage guarantee, added an unpinned external dependency, or
saved seconds against minutes of thermal noise. The one change with a
measurable effect is C1 — it converts a 100%-failing remote job into a
passing one, and `evidence/session-8/ci-timing-final.txt` (captured at the
session tip) re-measures the local chain against this baseline.

## Forbidden-list compliance

No assertions removed; release verification, clean-clone coverage,
signature fixtures, and reproducibility checks untouched; no security gate
made advisory; no mutable external artifacts introduced; CI permissions
unchanged (`contents: read`); no new network dependency added.
