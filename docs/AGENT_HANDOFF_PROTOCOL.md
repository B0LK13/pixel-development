# Agent Handoff Protocol

Use this format for every session handoff.

## Required sections

1. **Starting state** (branch, base commit, tree state)
2. **Changes** (what changed and why)
3. **Commits** (if applicable)
4. **Tests/gates** (targeted + full + ci-local)
5. **Evidence** (paths produced/updated)
6. **Security invariants** (confirm no boundary violations)
7. **Deferred work** (explicit backlog)
8. **Safety confirmation** (no push/merge/release actions)
9. **Readiness decision** (ready / blocked + reason)
10. **Operator commands** (copy-paste next steps)

## Standard report block

```markdown
## Session handoff
- Starting state: <branch, commit, tree>
- Changes: <summary>
- Commits: <hashes or n/a>
- Validation:
  - targeted: <commands + status>
  - full harness: <status>
  - ci-local: <status>
- Evidence: <paths>
- Security invariants: <confirmed list>
- Deferred: <none|items>
- Safety confirmation: <no operator-only actions performed>
- Readiness: <ready|blocked>
- Operator commands:
  1. <next command>
  2. <next command>
```

## Resumability

A follow-up agent must be able to resume from:

- `AGENTS.md`,
- latest `scripts/agent-context.sh --format markdown`,
- latest report in `reports/`.

