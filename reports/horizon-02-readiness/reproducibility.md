# Horizon 0.2 — Reproducibility Report (Agent B)

Date: 2026-07-13 (UTC) · branch `auto/horizon-02-reproducibility` ·
base commit `cc5c0d3b8f3e3e6fe9cea0e09f1b0d06e23debbf`.

Mission: prove the Horizon 0.2 release candidate builds deterministically
(mandate Phase 3). Rehearsal scope only — no tags, no push, no signing,
no release actions.

## 1. Procedure

Canonical build path from `docs/RELEASE_DRY_RUN.md` §2, executed in an
isolated worktree of the integration branch:

1. `SOURCE_DATE_EPOCH="$(git log -1 --format=%ct)"` → `1783977357`
   (the base commit's committer time; `= 2026-07-13T21:15:57Z`).
2. Build A: `SOURCE_DATE_EPOCH=1783977357 bash scripts/build-release-candidate.sh --version=1.0.0 --output-dir=<scratch-a>/dist` — exit 0, 3s.
3. Build B: identical command against the same clean worktree state into a
   second isolated scratch root — exit 0, 2s.
4. Compared the two bundles per the runbook §2 pattern (`diff -r`;
   `find -printf '%m %p'` mode manifest; sorted `sha256sum` digests), plus
   sizes (`find -printf '%s %p'`), mtimes (`find -printf '%T@ %p'`), and
   byte compares (`cmp`) of `SIGNING-MANIFEST.json` and
   `RELEASE-METADATA.json`.
5. Precondition gates exercised in a disposable scratch clone (never
   dirtying the build worktree): dirty-tree refusal and version/epoch
   validation.

Raw logs live on the host under `/tmp/h02/repro/` (ephemeral); the bounded
record is `evidence/horizon-02/reproducibility/reproducibility-record.txt`.

## 2. Results

| dimension | method | result |
|---|---|---|
| file names / counts | sorted `find .` lists; `wc -l` | identical (9 files, 1 dir each) |
| contents | `diff -r` | identical (no output) |
| file modes | `find -printf '%m %p' \| sort` | identical (0755 scripts, 0644 data) |
| file sizes | `find -printf '%s %p' \| sort` | identical (9 files, byte table in evidence record) |
| SHA-256 digests | sorted `sha256sum` of all files | identical (9/9 digests match) |
| timestamps | `find -printf '%T@ %p'` | identical; every mtime = `1783977357` (epoch-normalized) |
| manifest | `cmp SIGNING-MANIFEST.json` | identical; `release_metadata_sha256` binds metadata digest |
| metadata | `cmp RELEASE-METADATA.json` | identical; `created_at` = `2026-07-13T21:15:57Z` (epoch-derived, not wall clock) |
| archive ordering | sorted file list + `SHA256SUMS` line order + JSON artifact-array order | identical (builder emits a directory bundle, no tar archive) |

Builder preconditions (documented in `scripts/build-release-candidate.sh`):

| check | input | result |
|---|---|---|
| version validation | `--version=1.0` | refused, exit 2, "malformed version" |
| epoch validation | `SOURCE_DATE_EPOCH=notanumber` | refused, exit 1 |
| dirty-tree refusal | one untracked marker file | refused, exit 1, naming the file; nothing written |

Sanity (read-only): `sha256sum -c SHA256SUMS` inside the bundle → 4/4 OK;
`scripts/verify-release-bundle.sh --bundle=…` → `verified-integrity-only`
(exit 0).

## 3. Findings

- **No nondeterminism found.** Two builds from the same commit and the same
  `SOURCE_DATE_EPOCH` are byte-for-byte identical across every compared
  dimension, including mtimes and both JSON documents. There is no
  differing field to classify (deterministic vs environmental).
- The builder's determinism contract holds as documented: `created_at` and
  all mtimes derive from `SOURCE_DATE_EPOCH`; content is a pure function of
  the commit (artifact bytes, sorted tables, fixed JSON key order).
- Preconditions behave as documented: dirty tree and malformed inputs are
  refused before any output is written (atomicity confirmed).

## 4. Safety confirmation

- Work only in the `/tmp/h02-repro` worktree; the primary tree was never
  touched and no branches were switched there.
- No tags, no push, no packages/images/deployments, no network access.
- No signing operations; no key material generated, imported, or used (the
  configured commit-signing key `0F8A4FD173240A4B` was used only for the
  required git commit signatures).
- No production secrets observed or committed; evidence is bounded and
  non-sensitive; scratch state under `/tmp` is ephemeral.
- No build tooling modified — no reproducibility defect to escalate.

## 5. Disposition

Reproducibility gate: **green, with evidence**. Recommend the coordinator
merge `auto/horizon-02-reproducibility` into
`auto/integrate-horizon-02-readiness`. Signing/verifier depth remains with
Agents C/D; this report covers build determinism only.
