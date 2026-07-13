# Session 10 — Remote CI Verification

Date: 2026-07-13 (UTC). Branch: `auto/session-10-actions-hardening`,
tip `d27f1c9`. PR: #2 (target `main`).

## Runs

| run | event | commit | suite | release-candidate-check | conclusion |
|---|---|---|---|---|---|
| 29234388613 | push | d27f1c9 | pass (43 s) | pass (7 s) | success |
| 29234401276 | pull_request | d27f1c9 | pass (41 s) | pass (9 s) | success |
| 29234404847 | dynamic | d27f1c9 | — | — | GitHub Copilot PR reviewer (`copilot-pull-request-reviewer`) — platform review agent, not a repository workflow, not a required check |

`gh pr checks 2`: 4/4 pass (both jobs on both runs).

## Session-10-specific verifications

| check | result |
|---|---|
| pinned action resolves remotely | `Download action repository 'actions/checkout@9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0'` — the exact pinned SHA is what ran |
| `Verify GitHub Action pins` step | `action-pin check: 1 workflow file(s), 2 uses ref(s), 0 violation(s)` — blocking step green on both runs |
| Node 20 deprecation annotation | **0 annotations** on the push run (was: one per run under `@v4`) — eliminated by v7.0.0 (node24) |
| full-history checkout | `fetch-depth: 0` preserved; ancestry-sensitive §18/§28 + clean-clone §8 all green remotely |
| remote suite count | `passed: 326 failed: 0 skipped: 0` — matches the local count exactly |
| release-candidate-check | fixture build + unsigned verify + reproducibility + throwaway-key signed verify green |
| credential persistence | `persist-credentials: false` active on both checkouts |
| secrets / publishing | none used; no publish, tag, or push steps ran |

## Annotations and warnings

None. The previous per-run Node 20 deprecation annotation is gone; no new
annotations were introduced.

## Verdict

Remote CI fully green on the session tip, with the pinning enforcement
itself executing as a blocking remote step. No remote-only defects
surfaced — the local/remote parity held on first push.
