# GitHub Actions Pinning Policy

Supply-chain policy for every GitHub Actions reference in this repository.
Adopted in session 10; enforced by `scripts/check-github-action-pins.py`,
which runs in `scripts/ci-local.sh`, in the `suite` job of
`.github/workflows/test.yml`, and in the hermetic test harness (§30).

## 1. Rule

Every external action or reusable-workflow reference in
`.github/workflows/*.yml` must be pinned to an **immutable full-length
(40-character) commit SHA**, with the corresponding release tag as an
inline comment:

```yaml
- uses: actions/checkout@9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0 # v7.0.0
```

A commit SHA cannot be retargeted by a compromised publisher account, a
force-pushed tag, or a registry mishap. A version tag can.

## 2. Covered references

- GitHub-maintained actions (`actions/*`, `github/*`);
- third-party actions (`owner/repo@ref`, including `owner/repo/path@ref`);
- external reusable workflows (`owner/repo/.github/workflows/x.yml@ref`);
- container actions (`docker://...`), which must pin by `@sha256:` digest.

## 3. Allowed references

| form | status |
|---|---|
| `@<40-hex-sha>` + `# vX.Y.Z` comment | required for all external refs |
| `./local/path` (repository-local action) | allowed — reviewed with the repo |
| `docker://image@sha256:<64-hex>` | allowed — digest is immutable |

## 4. Prohibited references

- `@main`, `@master`, `@latest`, `@HEAD` or any other branch name;
- mutable version tags (`@v4`, `@v4.2.2`);
- short SHAs (7–39 hex chars — ambiguous and spoofable by collision);
- external references with no `@ref` at all;
- SHA pins without the `# vX.Y.Z` version comment;
- `docker://` images without a `@sha256:` digest.

## 5. Version annotation

The comment records the human-readable release the SHA corresponds to:

```yaml
uses: owner/repo@<full-sha> # v1.2.3
```

The comment must be accurate at pin time: map the upstream release tag to
its commit before writing the pin (see §7). The checker enforces comment
presence and shape; accuracy is a review duty, and Dependabot keeps the
comment in step with the SHA afterwards (§8).

## 6. Exceptions

No exceptions are currently granted. An exception requires, in this file:

- action and reference;
- reason;
- owner;
- risk assessment;
- expiry or review date;
- compensating control.

Repository-local actions (`./...`) are not exceptions — they are reviewed
as part of the repository itself.

## 7. Update process (manual)

1. Identify the upstream release (release notes, changelog).
2. Verify the publisher (GitHub-maintained org, marketplace-verified
   creator, or an explicitly trusted third party).
3. Map the release tag to its immutable commit, e.g.
   `gh api repos/<owner>/<repo>/git/refs/tags/vX.Y.Z --jq .object.sha`
   (dereference annotated tags to the commit object).
4. Review the upstream diff between the old and new commit.
5. Update the SHA **and** the `# vX.Y.Z` comment together.
6. Run `python3 scripts/check-github-action-pins.py`.
7. Run the full local gate (`bash scripts/ci-local.sh`).
8. Open a PR; require the remote `suite` + `release-candidate-check` jobs
   green before merge.

## 8. Controlled automatic updates (Dependabot)

`.github/dependabot.yml` enables weekly `github-actions` ecosystem updates.
For SHA-pinned actions Dependabot bumps the pin to the new release's commit
SHA and updates the trailing version comment in the same PR
(GitHub changelog, 2022-10-31). Constraints:

- no automatic merging — every update PR gets operator review;
- the pin checker and the full remote gate run on every update PR;
- a Dependabot PR that cannot keep SHA and comment in step (known upstream
  limitation when the pre-existing comment is wrong) is reconciled manually
  per §7 before merge;
- grouped into one PR per week to keep review load bounded.

## 9. Enforcement

`scripts/check-github-action-pins.py` (stdlib-only Python 3, no network,
deterministic output) scans every workflow file and fails on any reference
violating §3/§4. It runs:

- locally: gate 3 of `scripts/ci-local.sh` (fails before the expensive
  suite);
- remotely: step `Verify GitHub Action pins` of the `suite` job — blocking,
  never `continue-on-error`;
- under test: harness §30 exercises the checker against fixture workflows
  (valid pin, short SHA, major tag, `@main`, local action, reusable
  workflow, missing comment, commented-out lines, docker digest).

## 10. Runtime-deprecation tracking

Action runtimes deprecate on GitHub's schedule (e.g. the Node 20
deprecation that forced `actions/checkout@v4` onto Node 24 with an
annotation). The pin comment makes the running version explicit; when
GitHub announces a runtime deprecation, the update process in §7 applies —
select the newest stable release on a supported runtime, verify
`fetch-depth: 0` and checkout semantics are unchanged for our jobs, and
land it as an ordinary reviewed pin update.
