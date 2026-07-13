# Branch Promotion Policy

Canonical path for moving integrated work to `main`. Normative gate commands
live in `docs/CLI_CONTRACT.md` and `docs/OPERATOR_COMMAND_INDEX.md`; this
document defines *when* they must have run and *who* approves movement.

## 1. Lifecycle

```
task branch (auto/<topic>)
  → integration branch (auto/integrate-session-N)
  → local full gate (scripts/ci-local.sh green)
  → remote branch push (operator-authorized)
  → pull request targeting main
  → required GitHub Actions jobs green
  → operator review
  → merge per §3 (operator-approved)
  → post-merge CI on main
```

Sessions may add evidence/report commits on top of a verified tip; the
verification evidence must name the commit it was captured at, and any commits
above it must be evidence/report-only (established session convention).

## 2. Promotion prerequisites

All must hold at the PR tip:

- clean working tree;
- full suite green (`bash tests/run_tests.sh`, current contract: 309/0/0);
- `bash scripts/ci-local.sh` exit 0 (whitespace, checksum lockstep, bash -n,
  shellcheck, suite);
- unsigned bundle verification green (verdict verified-integrity-only);
- signed fixture verification green with a throwaway key (verdict verified-signed);
- reproducibility green (two SDE-pinned builds byte-identical);
- key-material scan: zero files;
- all commits GPG-signed per repository policy (global commit.gpgsign);
- no unresolved critical/high audit findings;
- remote branch up to date with its local counterpart;
- required GitHub Actions jobs green at the PR tip;
- explicit operator approval.

## 3. Merge strategy

**Non-fast-forward merge commit** (`--no-ff`), preserving the validated
integration ancestry. Rationale: the session chain is the audit trail — merge
commits delimit workstreams, and evidence files cite commit hashes that must
remain reachable and unchanged.

Squash-merge and rebase-merge of session history are prohibited unless the
operator directs otherwise for a specific PR. Never silently squash a session
chain.

## 4. Failure policy — promotion is blocked when

- any required check fails (suite, parity gate, either release job leg);
- local and remote results disagree without a documented explanation;
- CI executes an unreviewed publication step (tag/release/upload/push);
- a secret-dependent job fails open;
- reproducibility differs between builds;
- the key-material scan detects any file;
- remote history diverges unexpectedly (never resolved by force-push);
- commits at the PR tip are not all signed.

`continue-on-error` must never be added to obtain green status. Failing checks
are fixed with narrow, tested commits or the promotion waits.

## 5. Rollback policy

- Revert a bad merge with `git revert -m 1 <merge-commit>` on a corrective
  branch; open it as a new PR under the same gate rules.
- Evidence of the failed promotion (CI run IDs, logs, reports) is preserved in
  `evidence/` — reverting never deletes evidence.
- Force-push is prohibited in all circumstances, including rollback. History is
  append-only; corrections are new commits.
- Tags, if ever created by the operator, are not deleted by agents.

## 6. Branch-protection recommendations (operator decision)

Not changes — recommendations, since protection changes are operator-owned:

- require a pull request before merging to `main`;
- required status checks: `suite` and `release-candidate-check`;
- require signed commits (matches repository policy);
- require conversation resolution before merge (lightweight review trail);
- no required approvals count imposed by tooling — the operator is the reviewer.

## 7. Current required-check inventory

Both jobs in `.github/workflows/test.yml` are required for promotion:

| job | what it proves |
|---|---|
| `suite` | whitespace/checksum lockstep/action-pin enforcement/syntax/shellcheck + full 326-assertion suite |
| `release-candidate-check` | fixture release build, unsigned + throwaway-signed verification, reproducibility |

Neither job publishes, tags, signs with a real identity, or mutates the repo.
