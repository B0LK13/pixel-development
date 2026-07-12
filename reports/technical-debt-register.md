# Technical Debt Register (Session 8)

Consolidated from the Session 8 review set (`reports/architecture-review.md`,
`reports/developer-experience-review.md`, `reports/diagnostics-review.md`,
`reports/configuration-quality.md`, `reports/ci-efficiency-analysis.md`) and
the standing registers in `docs/AUTONOMOUS_AUDIT.md` (R-items) and
`docs/CLI_CONTRACT.md` §7. Only items with real evidence are listed; settled
or rejected work is marked as such, not re-opened.

Fields: id · category · evidence · impact · likelihood · priority ·
recommended action · scope · dependencies · target · owner (operator /
agent-executable).

## Open

| id | category | evidence | impact | likelihood | priority | action | scope | depends on | target | owner |
|----|----------|----------|--------|-----------|----------|--------|-------|-----------|--------|-------|
| TD-1 | trust | `docs/AUTONOMOUS_AUDIT.md` R1: `curl \| bash` installers unpinned (bootstrap pins only its own 3 artifacts) | compromised upstream installer runs on the phone | low (upstream compromise) | high before signing | vendor SHA-256 pins for the 3 installers into bootstrap + verify on download, once upstream publishes stable digests | M: bootstrap + harness §17 + checksum tool | upstream-published digests | before first signed release | agent-executable |
| TD-2 | ops | no production signing identity exists (session 6/7 carry-over) | releases stay integrity-only | certain until provisioned | high | provision key per `docs/SIGNING_KEY_LIFECYCLE.md`; sign offline per `docs/RELEASE_SIGNING.md` | S: operator ceremony | operator decision | before first signed release | **operator** |
| TD-3 | ci | `actions/checkout@v4` floating tags, no stated pinning policy (config review F5) | supply-chain drift in CI | low (read-only perms, no secrets) | medium | adopt a repo-wide action-pinning policy (SHA pins + documented update cadence) | S: workflow + docs + §22 pin | none | v1.0.x hardening | agent-executable |
| TD-4 | ci | shellcheck apt-installed every suite run (ci-efficiency C2) | ~20–40s/run + network dependency | certain | low (blocked) | keep as-is until TD-3 exists, then pin via the same policy | XS | TD-3 | v1.0.x hardening | agent-executable |
| TD-5 | maintainability | artifact table materialised in builder, verifier, and harness (arch A1) | adding an artifact means editing 3 places; drift risk | medium | medium | extract one canonical table (sourced by builder/verifier; harness pins it) | M: 3 files + harness | none | v1.x maintainability | agent-executable |
| TD-6 | maintainability | version truth scattered: `VERSION`, 2×`SCRIPT_VERSION`, `--version`, README pin row (arch A9) | release-checklist toil; mismatched versions possible | medium | medium | single source + a harness cross-check assertion | S-M | none | v1.x maintainability | agent-executable |
| TD-7 | maintainability | checksum tool rewrites `pixel-bootstrap.sh` case arms via format-sensitive regex (arch A12) | silent breakage if the case-arm format changes | low | medium | document the contract in `pixel-bootstrap.sh` header + harness assertion on the format | XS | none | v1.x maintainability | agent-executable |
| TD-8 | diagnostics | unknown-flag line on stdout in the 4 entry scripts vs prefixed stderr in `scripts/` tools (diag D5, DX I-3) | stream inconsistency; interactive-only | certain (by design) | low | either move to stderr + update `docs/CLI_CONTRACT.md` "historical" clause, or keep and document — adjudicated "keep" twice (session 7, D5); revisit only if a consumer needs stderr parsing | S: 4 files + doc + checksums | none | v1.x (optional) | agent-executable |
| TD-9 | diagnostics | thin got-values in some verifier metadata failures (diag D6) | slower fault localisation | low | low | enrich messages (harness asserts verdict words only, so additive) | XS | none | v1.x (optional) | agent-executable |
| TD-10 | diagnostics | bare `warn`s without remediation in dev/apps-setup (diag D7) | operator guesses next step | low | low | fold hints into the messages (unpinned sites) | XS | none | v1.x (optional) | agent-executable |
| TD-11 | diagnostics | autodev summary conflates SKIP/NO-OP with FAILED (diag D8) | miscounts in multi-task runs | low | low | split counters; distinct labels already exist per case | S | none | v1.x (optional) | agent-executable |
| TD-12 | architecture | flat 1544-line harness; inline builder/verifier bodies (arch A20) | navigation cost; no functional risk | certain | low | extract per-area section files only if the harness outgrows ~2k lines; not before | L | none | v2 (architectural) | agent-executable |
| TD-13 | contract | `--` is not an end-of-options marker (R4/F15) | none today (no script forwards args) | n/a | low | implement only with a concrete need; documented in `docs/CLI_CONTRACT.md` §1 | XS | a real consumer | rejected-until-needed | agent-executable |

## Resolved this session (for the record)

| id | resolution | commit(s) |
|----|-----------|-----------|
| arch A6/A7/A8 | die2 dead logic removed; lint fallback covers all 10 scripts; §8/§9 physical order fixed; harness header current | `97dc178`, `6ea4dc2` |
| ci C1 | CI release job space-form flags → equals-form + §22 regression pin | `66aedb9` |
| config F2 | autodev no longer marks tasks done when `git commit` fails; §6h regression pin | `dcd3bb3` |
| config F3 | CLI_CONTRACT autodev line refs corrected (+2 drift, resolver bounds) | `884abe9` |
| config F4 | bootstrap mktemp failure dies instead of falling through | `c306e7f` |
| DX A-6/I-1/I-2 | 4 release-script `--help` ranges fixed; ci-local `--help`/unknown-arg added; §3 contract extended to release tools | dx branch |
| DX I-4/I-5/I-6/I-7 | README parity+knobs; bash ≥4 floor documented; release checklist bridges to bundle flow; install hints on bare deaths | dx branch |
| diag D1–D4 | bootstrap fail-closed install paths; false opener success fixed; harness failed-test recap + nested-clone detail; apps-setup FATAL logging | diag branch |

## Explicitly rejected / unnecessary

- **Deterministic test sharding** (ci-efficiency C4): thermal noise dominates;
  would weaken the one-command gate contract; clean-clone coverage is
  mandatory.
- **Parallelising ci-local gates 1–4** (C3): saves ≤3s of 582s; interleaves
  output.
- **`docs/TROUBLESHOOTING.md`** (DX §3): would duplicate harness-pinned
  message text and rot; a 4-line "first move" block lives in
  `docs/CONTRIBUTOR_QUICKSTART.md` instead.
- **Structured/machine-readable diagnostic output** (diag Q1): exactly one
  real consumer exists (the `verdict:` protocol); no new mode justified.
- **Stable numeric error-code scheme** (diag Q2): ~100 harness text-assertion
  sites make it pure churn; the existing greppable conventions suffice.
- **R2/R3/R5/R6**: implemented in Session 3 (`--ssh-port`, numeric flags,
  `--agent` enum, `.gitattributes`); kept here only as history.
