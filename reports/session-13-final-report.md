# Session 13 Final Report — Release Dry-Run Preparation (Roadmap 0.2)

Date: 2026-07-13 (UTC)
Branch: `auto/session-13-release-dry-run-prep`
Base: `main` @ `0508a044e059db1d2d20f240f6694b44e1a02b7b`
Mandate: `reports/project-roadmap.md` Horizon 0 item 0.2 — prepare the
first signed-release dry run on a throwaway identity (build → sign →
`verified-signed` → publish checklist walkthrough + disaster-recovery
pass). **Agent prepares, operator executes.** Docs + evidence only.

## 1. What was prepared

- `docs/RELEASE_DRY_RUN.md` — the complete operator runbook:
  - §0–1: throwaway identity provisioning — isolated `GNUPGHOME` under
    `mktemp`, ed25519, no passphrase, identity string marked
    `THROWAWAY ... (NOT PRODUCTION)`, 1-day expiry; a second throwaway
    key for the wrong-keyring scenario; public keyring export.
  - §2–4: build (`SOURCE_DATE_EPOCH`-pinned, output under `$WORK`),
    optional byte-identical rebuild-compare, offline `gpg --detach-sign
    --armor` of `SIGNING-MANIFEST.json`, then both verifier modes —
    `verified-integrity-only` and the target `verified-signed` with
    `--require-signature`.
  - §5: publish checklist walkthrough mirroring
    `docs/BOOTSTRAP_RELEASE_PROCESS.md` §3 — every irreversible step
    (tag, push, GitHub release, second-network digest check, fresh
    install) listed with placeholder commands and explicitly NOT
    executed.
  - §6: disaster-recovery pass — DR-1 wrong artifact (genuine signature
    over the wrong file; right signature under the wrong keyring), DR-2
    tampered bundle (altered artifact / manifest / metadata), DR-3 lost
    key (destructive, runs last) — each with expected verifier output
    and the production recovery action cross-referenced to
    `docs/SIGNING_KEY_LIFECYCLE.md` §2/§5–§8.
  - §7: destruction of the throwaway identity (`gpgconf --kill all`,
    `rm -rf "$WORK"`).
  - Closing operator-ceremony checklist and a "what this does NOT do"
    boundary (no production keys, no tags/releases/packages, no real
    publish, mechanics-only trust).

Every command is copy-pasteable and hermetic: no network, no keyservers,
no package installs, no paid agents. All state lives under one `mktemp`
root; the repository tree is untouched by the run.

- `evidence/session-13/baseline-record.txt` — date, branch, base
  commit, commands, toolchain, boundaries.
- `evidence/session-13/dry-run-rehearsal.txt` — bounded output of the
  full rehearsal (header records command + commit per
  `evidence/README.md`).

## 2. Rehearsal results (evidence: `evidence/session-13/dry-run-rehearsal.txt`)

The runbook was executed end to end at commit `6494af7` from the
repository root. **All expectations met:**

| step | expected | got |
|---|---|---|
| build (pinned epoch) | exit 0, 9-file bundle | exit 0 |
| rebuild-compare | byte-identical | 0 diff lines |
| unsigned verify | `verified-integrity-only` | yes, exit 0 |
| signed verify | **`verified-signed`** | **yes, exit 0** |
| DR-1a wrong artifact | `failed-signature`, exit 1 | pass |
| DR-1b wrong keyring | `failed-signature`, exit 1 | pass |
| DR-2a altered artifact | `failed-checksum`, exit 1 | pass |
| DR-2b altered manifest | `failed-signature`, exit 1 | pass |
| DR-2c altered metadata | `failed-metadata`, exit 1 | pass |
| DR-3 lost key: re-sign | impossible, exit 2 | `No secret key` |
| DR-3 lost key: old bundle | still `verified-signed` | pass |
| destruction | scratch root gone, tree clean | pass |

### Divergence found and fixed during rehearsal (the rehearsal earned its keep)

The first pass ran the scenarios in the roadmap's list order (lost key
first). Two defects surfaced, both fixed in the runbook before the clean
pass:

1. **Scenario-order dependency:** with the secret key deleted first, the
   wrong-artifact scenario could not create its replacement signature
   (the `gpg` failure was silenced by redirection), so the copied
   *original* valid signature verified — a **false `verified-signed`**
   on a scenario that must fail. Fix: DR-3 (lost key, destructive) runs
   **last**; the runbook states the ordering rule explicitly.
2. **Wrong expected output:** `gpg --list-secret-keys` after deletion
   still listed the second throwaway key. Fix: the expectation is
   narrowed to `gpg --list-secret-keys "$KEYID"` → empty output.

The recorded rehearsal (`evidence/session-13/dry-run-rehearsal.txt`) is
the clean second pass at the final runbook commit.

## 3. Operator handoff checklist

1. Review `docs/RELEASE_DRY_RUN.md` end to end; confirm the §0 scratch
   setup and the "what this does NOT do" boundary.
2. Execute the runbook's operator-ceremony checklist (its final section)
   on any offline host with `git`, `gpg`/`gpgv`, `sha256sum`, GNU
   `date`/`touch`. Expected total runtime: a few minutes.
3. Confirm the target verdicts: one `verified-signed` on the happy path,
   five fail-closed negatives, `No secret key` after key destruction.
4. Record any divergence and hand it back **before** starting roadmap
   0.1 (production key provisioning) — do not improvise around a
   mismatch.
5. Destroy the throwaway identity (§7) even if the run diverges midway.

## 4. Boundaries

- No production key generated, imported, stored, or used; throwaway
  keys only, created and destroyed inside the rehearsal.
- No tags, no push, no PR, no releases/packages/images; no network.
- `main`, `auto/session-10-signed-commit-evidence`, and the Session
  11/12 branches untouched. Session 11/12 material is cited as
  local-only context (e.g. `docs/SIGNING_ROADMAP.md` phase 2 = the
  operator ceremony this dry run prepares for); nothing was merged from
  those branches.
- All three commits are GPG-signed with `0F8A4FD173240A4B`
  (`git log --show-signature` spot-checked: Good signature).

## 5. Gaps found

- **None requiring code.** The existing scripts and suite cover every
  mechanic the dry run exercises: build gates, both verifier modes, and
  all five negative scenarios mirror harness §19/§25/§26 fixtures
  (wrong-file signature §26-s9, wrong keyring §26-s4, altered
  artifact/manifest/metadata §26-s6/s5/s7). No gap justified adding
  code; the deliverable is docs + evidence only, per the mandate's
  preference.
- Minor doc-level notes (handled in the runbook, not gaps): scenario
  execution order (§2 above) and the `list-secret-keys` expectation.

## 6. Quick checks at branch tip (full gate left to the parent agent)

- `git diff --check`: clean (all files, each commit)
- `python3 scripts/check-github-action-pins.py`: 0 violations
- `bash -n`: no scripts touched (docs/evidence/report only)
- Full `tests/run_tests.sh` + `scripts/ci-local.sh`: not run here by
  instruction; the branch changes no code or test paths.

## 7. Commits (all signed)

- `6494af7` docs(release): add throwaway-identity release dry-run runbook (roadmap 0.2)
- `7877ee3` docs(evidence): record session 13 dry-run rehearsal (verified-signed + 5 fail-closed scenarios)
- (this report — added after the evidence commit)
