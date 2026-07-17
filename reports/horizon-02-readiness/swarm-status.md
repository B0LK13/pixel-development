# Horizon 0.2 Release Readiness — Swarm Status

Mission: execute the Horizon 0.2 release-readiness process end to end —
prove the release candidate builds deterministically, verifies, survives
all fail-closed scenarios, and is ready for an operator-controlled
production ceremony. **Rehearsal scope: no production release actions.**

Baseline: `main` @ `5fd735b351c50182d308725525e066cf6ec2514c` — clean,
green (327/0/0, ci-local exit 0, 0 pin violations), single-maintainer
protection active, no open PRs, no watchers.

Integration branch: `auto/integrate-horizon-02-readiness`

## Workstreams

| agent | scope | branch | depends on | status | blockers |
|---|---|---|---|---|---|
| A | baseline & repository integrity | coordinator-run gate; evidence committed to integration branch | — | in progress | — |
| B | build & reproducibility | `auto/horizon-02-reproducibility` | A green | dispatched | — |
| C | throwaway signing rehearsal | `auto/horizon-02-signing-rehearsal` | A green | dispatched | — |
| D | fail-closed adversarial validation | `auto/horizon-02-adversarial` | A green | dispatched | — |
| E | SBOM & provenance readiness | `auto/horizon-02-provenance` | A green | dispatched | — |
| F | rollback & disaster recovery | `auto/horizon-02-recovery` | A green | dispatched | — |
| G | security & evidence audit | `auto/horizon-02-security-audit` | all merged | pending | — |
| H | documentation & operator handoff | `auto/horizon-02-docs` | C/D/F merged | pending | — |

## Coordination notes

- The coordinator runs all heavy gates (suite, ci-local) serially as
  background tasks. Host constraint: this is a memory-pressured
  proot/Termux environment where parallel full-suite runs are SIGKILLed
  by the low-memory killer (the original Session 10 gate died this way).
- Agent A's baseline gate is coordinator-executed because the ~25-minute
  gate exceeds the 30-minute subagent timeout margin; its evidence and
  report are committed to the integration branch directly.
- Specialists work in isolated worktrees under `/tmp/h02-*`, never in the
  primary worktree, never push, never run the full suite.
- Merge order: A → B/C/D/E/F as completed → H → G → Phase 11 final
  rehearsal → Phase 12 final package → Phase 13 final gate.
- Publication boundary (Phase 14): no push, no PR without explicit
  operator authorization.

## Integration log

See `reports/horizon-02-readiness/integration-log.md` (created at the
first merge).
