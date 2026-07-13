# Session 7 — Recovery Report

Date: 2026-07-12
Recovered by: Session 7 follow-up execution (this session)

## Repository state at recovery

- repo: `/root/pixel-development`
- current branch: `auto/repo-readiness-fixes`
- branch base: `auto/integrate-session-6` tip (`ce8cc92` merge chain)
- committed Session 7 work: exactly one commit —
  `5a0d1f6 docs: bring README repo layout current, pin script paths`
- working tree at recovery: dirty — one uncommitted hunk in
  `tests/run_tests.sh` adding security test "6g" (backlog text inertness)
- no stash entries; no `auto/integrate-session-7` branch; no `reports/session-7-*`
  files; no `evidence/session-7/` directory
- `main` untouched at `711c23b` (Session 3 content; operator-owned merges)

## Completed work (verified)

1. **README layout commit** (`5a0d1f6`) — committed, tree-clean at that point.
2. **Security regression test drafted** — `tests/run_tests.sh` gained a test
   asserting that a `$(...)`/backtick payload in a BACKLOG.md task line never
   executes while `pixel-autodev.sh` builds the agent prompt file.

## Root-cause analysis of the in-flight finding (done before touching code)

The drafted test targets the unquoted heredoc at `pixel-autodev.sh:305`
(`cat > "$pf" <<EOF ... Task from BACKLOG.md: $text ...`).

Empirical verification (stand-alone repro mirroring the harness fixture,
full dispatch path reached — branch created, stub agent ran, task flipped):

- **The suspected vulnerability does not reproduce.** Bash performs command
  substitution on the literal text of an unquoted heredoc, but values
  introduced by parameter expansion (`$text`, `$dir`) are **not rescanned**.
  A `$(touch …)` payload inside `$text` is written into the prompt file
  literally and never executed. Minimal-case proof and full-path proof both
  recorded; the payload files were never created.
- Downstream uses are likewise safe: the prompt is passed as one quoted
  argument (`-p "$(cat "$pf")"`), and commit messages use quoted expansion.

Conclusion: the drafted test **passes against the unmodified script** — it is
a valid regression guard for an invariant that currently holds incidentally
(via a subtle bash semantic) rather than structurally.

## Unfinished work at interruption

1. The test hunk was never committed.
2. Test numbering inconsistency: the new block is labelled `6g` but was
   inserted *before* the existing `6f` (end-to-end timeout path) block.
3. The test comment asserts the invariant holds because of "an unquoted
   heredoc" — misleading once the semantics are understood; needs correction.
4. Structural hardening not applied: backlog-derived data still flows through
   an unquoted heredoc (safe today, fragile to future edits such as `eval`,
   `sh -c`, or `echo -e` refactors).
5. All Session 7 verification workstreams pending: documentation consistency,
   dependency audit, security review, reproducibility, release validation,
   operator documentation, performance measurements, technical-debt
   inventory, release-readiness score.
6. No `evidence/session-7/` captures, no final report.

## Remaining risks

- **Fragile invariance (low, now understood):** prompt construction depends
  on bash's non-rescanning semantics. Mitigation: route all backlog-derived
  values through `printf %s` with a quoted-heredoc static body (byte-identical
  output for benign input), pinned by the regression test.
- **Suite runtime:** full gates take 4–8 min on this host (Session 6 note:
  thermal throttling). Plan validations around background runs.
- **Scope creep:** Session 8 adds eight workstreams; every change must stay
  incremental, test-backed, and inside the repository.

## Next execution order

1. Harden `pixel-autodev.sh` prompt construction (printf %s + quoted heredoc,
   byte-identical for benign input).
2. Fix test numbering (`6g`→`6f`, old `6f`→`6g`) and correct the comment to
   describe the verified invariant.
3. Run the full suite (red→green check already done analytically; expect all
   green) and capture `evidence/session-7/` baseline.
4. Execute the Session 7 verification workstreams; record evidence.
5. Full validation pipeline (ci-local + release build/verify +
   reproducibility), then `reports/session-7-final-report.md`.
6. Session 8 workstreams (architecture review → roadmap), each change
   verified, then the comprehensive completion report.

## Governance carried forward (unchanged)

No force pushes · no history rewriting · no production signing keys · no
secrets · no weakening of tests · no skipped verification · no changes outside
repository scope · `main` untouched (operator-owned merge) · nothing pushed.
