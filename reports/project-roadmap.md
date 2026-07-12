# Project Roadmap (Session 8)

Derived from `reports/technical-debt-register.md` — every item traces to a
register row (TD-n) with evidence. Horizons are sequenced by risk and
dependency, not by enthusiasm. Nothing here is started without the standard
discipline: reproduce, test, smallest change, full gate.

## Horizon 0 — before the first signed production release

| # | item | register | scope | owner |
|---|------|----------|-------|-------|
| 0.1 | Provision the production signing identity (custody, publication out of band, revocation plan) | TD-2 | operator ceremony per `docs/SIGNING_KEY_LIFECYCLE.md` | **operator** |
| 0.2 | First signed release dry run on a throwaway identity: build → sign → `verified-signed` → publish checklist walkthrough, including a disaster-recovery pass (lost key, wrong artifact, tampered bundle) | TD-2 | 1 session | agent prepares, operator executes |
| 0.3 | Vendor checksum pins for the three `curl \| bash` installers once upstream digests are publishable; fail closed like the bootstrap pins | TD-1 | bootstrap + harness §17 | agent-executable |
| 0.4 | Push `auto/integrate-session-8`, watch the remote CI run (the release job executes for the first time post-`66aedb9`), then merge to `main` | — | operator commands in the session-8 final report | **operator** |

Exit criteria: `verified-signed` on a production-key-signed bundle, published
digest verified from a second network, rollback reference retained.

## Horizon 1 — v1.0.x hardening

| # | item | register | scope |
|---|------|----------|-------|
| 1.1 | Action-pinning policy: SHA-pin GitHub Actions, documented update cadence, §22 assertion | TD-3 | workflow + docs + harness |
| 1.2 | Shellcheck provisioning via the same policy (replaces per-run apt) | TD-4 | workflow (after 1.1) |
| 1.3 | Remote CI and branch-promotion readiness: promote the local parity contract into a documented push→watch→merge operator flow with first-run evidence | ci-efficiency C1 follow-up | docs + evidence |

## Horizon 2 — v1.x maintainability

| # | item | register | scope |
|---|------|----------|-------|
| 2.1 | Canonical artifact table shared by builder/verifier, pinned by the harness | TD-5 | 3 files + harness |
| 2.2 | Single version source + cross-check assertion | TD-6 | small |
| 2.3 | Document the checksum-tool ↔ bootstrap case-arm contract in the bootstrap header + pin it | TD-7 | xs |
| 2.4 | Verifier message got-values (D6), warn remediations (D7), autodev counter split (D8) — one cosmetic diagnostics pass, each pin-checked | TD-9/10/11 | xs each |
| 2.5 | Unknown-flag stream consistency: revisit only if a real stderr consumer appears; otherwise keep the documented contract | TD-8 | small if ever |

## Horizon 3 — v2 architectural opportunities

| # | item | register | scope |
|---|------|----------|-------|
| 3.1 | Harness modularisation (per-area section files) only if it outgrows ~2k lines; the flat file remains correct and fully green today | TD-12 | large, deferred |
| 3.2 | Cross-platform validation (macOS GNU tooling matrix, WSL harness run) — requires non-Termux hosts; out of devbox scope until then | new | medium |

## Explicitly rejected / unnecessary (with rationale in the register)

- deterministic test sharding; parallelising ci-local gates 1–4;
  `docs/TROUBLESHOOTING.md`; structured diagnostic output modes; numeric
  error-code scheme; `--` end-of-options (until a concrete consumer exists)

## Suggested next session (detail in the Session 8 final report)

Remote CI and branch-promotion readiness (Horizon 1.3): the release job has
never executed remotely; `66aedb9` makes it runnable; the natural next
milestone is a pushed integration branch, an observed green run of both
jobs, and a documented promote-to-main flow — all operator-gated, with the
session preparing everything except the push itself.
