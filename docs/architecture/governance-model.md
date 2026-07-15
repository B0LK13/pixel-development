# Governance Model

## Roles

| role | current authority | notes |
|---|---|---|
| Operator | approve protected actions, merge, sign releases, publish tags/releases | highest authority |
| Implementation agent | edit repository files, run checks, write reports | no push / merge / release |
| Review agent | inspect diffs and reports, produce review findings | read-only |
| Validation agent | run harness and parity checks | no mutation beyond test fixtures |
| Security reviewer | inspect boundaries, pinning, and trust controls | read-only |
| Promotion approver | approve PR / merge readiness | operator-owned in this repo |
| Release owner | authorize release ceremonies and signing | operator-owned |

## Autonomous actions allowed

- Read and write repository files within task scope
- Run repository-owned validation commands
- Produce deterministic docs, reports, and evidence

## Actions requiring operator authorization

- Push / merge / release / tag / deploy
- Production signing and key lifecycle operations
- Secret / credential changes
- Branch protection changes
- Force operations or destructive host actions

## Prohibited without explicit approval

- Force-push / history rewriting
- Publishing to main without promotion gates
- Treating adapter tooling as the source of truth
- Weakening SHA pinning, signature checks, or hermeticity

## Existing safeguards

- Signed commits required for promotion
- Clean-clone validation required before completion
- Full harness and ci-local remain mandatory
- No push / no merge / no release from autonomous sessions
- Branch-protection rules and parity checks gate promotion
