# Remote CI Verification (Operator Runbook)

The autonomous loops never push. Remote CI therefore runs only when the
operator pushes a review branch. This runbook covers the full cycle: push,
watch, inspect, clean up, merge.

---

## 1. Push the review branch

```bash
git push origin auto/integrate-session-6
```

This triggers the `tests` workflow (`.github/workflows/test.yml`), which runs
on pushes to `main` and `auto/*` and on pull requests.

## 2. What the workflow runs

Workflow `tests`, two jobs, least privilege (`permissions: contents: read`),
no secrets, no paid agents, no pushes, no repository mutation:

| job | gates | timeout |
|---|---|---|
| `suite` | `git diff --check` → checksum-manifest lockstep → full test suite (`bash tests/run_tests.sh`) | 10 min |
| `release-candidate-check` | fixture build (version `0.0.0`, `SOURCE_DATE_EPOCH=0`) → unsigned verify (`verified-integrity-only`) → reproducibility (second build, `diff -r`) → throwaway ed25519 key → signed verify (`--require-signature`, `verified-signed`) | 5 min |

The release job uses only fixture identities generated per run; version
`0.0.0` is reserved for CI/fixtures and never denotes a real release.

## 3. Watch and inspect

```bash
gh run list --branch auto/integrate-session-6
gh run watch <run-id>
gh run view <run-id> --log-failed        # failing steps only
gh run view <run-id> --log               # full log
gh run download <run-id>                 # artifacts, if any
gh run rerun <run-id>                    # retry after an infra flake
```

Confirm the run tested the commit you pushed: `gh run view <run-id> --json
headSha -q .headSha` must equal `git rev-parse auto/integrate-session-6`.

## 4. Verify no secrets or paid agents ran

- The workflow declares `permissions: contents: read` and references no
  `secrets.` context — there is nothing to leak.
- Every step is a local command on the checked-out tree; the suite stubs
  agent binaries (`CLAUDE_BIN`/`CODEX_BIN`) and the release job signs with a
  per-run throwaway key.
- Inspect with `gh run view <run-id> --log` and confirm no `claude`/`codex`
  invocation, no `gpg` import of external keys, no `git push`.

## 5. Infrastructure vs. repository failures

- **Infra flake**: runner provisioning errors, network/apt hiccups, job
  cancelled without a red test step → `gh run rerun <run-id>`.
- **Repository failure**: a red step with harness output (`FAIL …`, nonzero
  gate) → fix locally, run `bash scripts/ci-local.sh` (same gates, offline),
  push again.

## 6. Clean up and merge

After a green run on the correct commit:

```bash
# merge (operator-owned)
git switch main
git merge --no-ff auto/integrate-session-6

# delete the remote review branch
git push origin --delete auto/integrate-session-6
```

Merge criteria: both jobs green on the exact commit being merged, local
`bash scripts/ci-local.sh` green on the same commit, and the diff reviewed
(`git diff main...auto/integrate-session-6`).

Nothing in this runbook is executed by the autonomous loops; every command
above is operator-owned.
