# Session 10 — Actions Security Review

Scope: `.github/workflows/test.yml` after Session 10 hardening, the
pinning policy, the enforcement checker, and Dependabot configuration.
Date: 2026-07-13 (UTC).

## Threat review

| vector | assessment | severity | disposition |
|---|---|---|---|
| Malicious action substitution (tag retargeting) | Before: `@v4` mutable — a compromised `actions` org account or tag force-push could swap code under the same tag. After: full-SHA pin to `9c091bb…` (v7.0.0); substitution requires a SHA-1 collision against a reviewed commit. Checker rejects any non-SHA ref. | was HIGH → now LOW | fixed by pinning + enforcement |
| Compromised publisher | `actions/*` is GitHub-maintained; even so, the SHA pin means new upstream code never enters a run without a reviewed PR changing the pin. Dependabot PRs get full CI + operator review, no auto-merge. | LOW | accepted, monitored via policy §8 |
| Excessive token permissions | Workflow-level `contents: read`; no job widening; no `id-token`; no secrets context anywhere in the workflow (harness §22 asserts this). | LOW | compliant — least privilege |
| Unsafe `pull_request_target` | Not used. Only `pull_request`, which runs fork code with a read-only token and no secrets. | INFORMATIONAL | compliant |
| Secret exposure | No secrets referenced; `release-candidate-check` generates a throwaway ed25519 key per run inside `$RUNNER_TEMP`. | INFORMATIONAL | compliant |
| Artifact poisoning | No artifacts are uploaded or downloaded; no caches. | INFORMATIONAL | not applicable |
| Untrusted checkout execution | PR code *is* executed by the suite (it is the point of CI), but with `contents: read`, no secrets, no publish path, and now `persist-credentials: false` so PR code cannot read a stored token from git config to escalate. | LOW | hardened this session |
| Credential persistence | checkout v4 left the workflow token in `.git/config` for later steps. Both jobs are verification-only and never push; `persist-credentials: false` removes the token from the workspace entirely. | was MEDIUM → now LOW | fixed |
| Reusable workflow trust | None used. The checker treats external reusable workflows as external refs requiring SHA pins if ever added. | INFORMATIONAL | covered by policy |
| Container image mutability | No container actions. Policy requires `@sha256:` digest if ever added; checker enforces. | INFORMATIONAL | covered by policy |
| Dependabot supply-chain handling | Weekly grouped PRs, `open-pull-requests-limit: 3`, labels only, **no auto-merge**. A malicious bump still needs operator review + green gate; the pin checker validates SHA+comment shape on the PR. Residual: Dependabot itself runs with GitHub's infrastructure trust — same trust as Actions generally. | LOW | accepted |
| Bypass of the pinning checker | Checker runs as a blocking step in the `suite` job and as ci-local gate 3 before the expensive suite. §30 of the harness exercises bypass-shaped inputs (commented-out uses, quoted values, job-level reusable `uses:`, empty values). A workflow could theoretically hide a `uses:` in a YAML anchor/alias — anchors inside `uses` values are not valid Actions syntax, and `on:`-level aliases don't create steps; the checker's line scan plus GitHub's own schema validation cover the practical surface. Residual: a workflow renamed to a non-`.yml`/`.yaml` extension would not run on GitHub either, so it cannot execute. | LOW | accepted, documented |
| Node runtime deprecation drift | Pin comment makes the running version explicit; policy §10 defines the deprecation response path (exactly how this session's v7.0.0 update was selected). | LOW | process in place |

## Findings

- **F-1 (was HIGH, fixed)**: mutable `@v4` checkout reference — retargetable
  supply-chain dependency. Fixed: SHA pin + inline version comment +
  blocking enforcement locally and remotely.
- **F-2 (was MEDIUM, fixed)**: persisted workflow token in checked-out
  workspaces (`persist-credentials` default). Fixed: `false` on both
  checkouts; no step requires authenticated git operations.
- **F-3 (LOW, accepted)**: Dependabot update PRs rely on operator review;
  no auto-merge is configured and none may be enabled without a separate
  reviewed policy change.
- **F-4 (INFORMATIONAL)**: the checker is intentionally line-oriented
  (stdlib-only, no YAML dependency in the supply-chain tool itself); the
  practical bypass surface is covered as described above.

## Final severity status

No open CRITICAL or HIGH findings. Two findings fixed this session, one
LOW accepted with compensating controls, one INFORMATIONAL documented.
