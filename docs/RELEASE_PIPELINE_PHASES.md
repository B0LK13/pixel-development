# Release Pipeline Phases

Phase-by-phase evolution of the release pipeline from today's integrity-only
flow to fully trusted releases. Session 12 (2026-07-13), design only.
Program overview: `docs/RELEASE_IMPLEMENTATION_BLUEPRINT.md`; tasks:
`docs/IMPLEMENTATION_BACKLOG.md`; acceptance detail:
`docs/RELEASE_ACCEPTANCE_CRITERIA.md`; rollback per phase:
`docs/ROLLBACK_AND_RECOVERY_PLAN.md`.

Each phase lists: trigger, inputs, steps, outputs, gates, owner, and
entry/exit criteria. "Pipeline" means the release path in
`docs/BOOTSTRAP_RELEASE_PROCESS.md` §3 plus the CI that guards it.

---

## Phase 0 — Current pipeline (as verified at the Session 11 baseline)

- **Trigger**: operator decision to cut a release.
- **Inputs**: green integration branch, clean tree, `VERSION`, checksum
  lockstep.
- **Steps**: build (`scripts/build-release-candidate.sh`,
  `SOURCE_DATE_EPOCH`-pinned) → verify unsigned + fixture-signed → review
  diff → release commit (VERSION bump, pin-history row, README pin) → tag →
  publish → post-publish digest verification → fresh-install test.
- **Outputs**: `dist/pixel-development-X.Y.Z/` (9 files), tag, release
  assets; verdict `verified-integrity-only`.
- **Gates**: suite 327/0/0; `scripts/ci-local.sh` exit 0; action pins 0
  violations; reproducibility byte-identical; key-material scan 0.
- **Owner**: operator (publish steps); autonomous sessions prepare up to the
  tag.

## Phase B1 — Signing-session tooling lands

- **Trigger**: build-session PRs (RT-01–RT-04).
- **Inputs**: design-spec contracts (§6.2).
- **Steps**: implement `scripts/prepare-signing-session.sh`,
  `scripts/record-signing-evidence.sh`, harness sections, doc pointers.
- **Outputs**: protocol tooling with `--fixture` mode; new suite sections;
  new authoritative test total (327 + additions, recorded).
- **Gates**: all Phase-0 gates + new harness sections; no consumer of the
  tooling exists yet — production behavior unchanged.
- **Owner**: build session (autonomous), no secrets.
- **Entry**: C3 (build session authorized). **Exit**: AC-B1 complete.

## Phase B2 — CI integration lands

- **Trigger**: build-session PRs (RT-05–RT-07).
- **Inputs**: B1 tooling; current workflow shape
  (`docs/CI_SIGNING_INTEGRATION_PLAN.md` §1).
- **Steps**: protocol dry-run replaces the ad-hoc fixture cycle in
  `release-candidate-check`; enforcement scans join the suite;
  `scripts/ci-local.sh` gains the same gates in lockstep.
- **Outputs**: CI exercises prepare → fixture sign → record → evidence
  assertions on every PR and main push; workflow secret/signing scans
  blocking.
- **Gates**: Phase-0/B1 gates + dry-run step green + parity lockstep +
  enforcement scans.
- **Owner**: build session, no secrets.
- **Entry**: AC-B1. **Exit**: AC-B2 complete; remote run shows the dry-run
  executing end-to-end.

## Phase B3 — Evidence plane lands

- **Trigger**: build-session PRs (RT-08–RT-09).
- **Inputs**: B1 evidence schema; empty `evidence/releases/`.
- **Steps**: subset re-verification helper + CI step (vacuous while empty);
  operator registry template.
- **Outputs**: `evidence/releases/` convention live; CI drift detector in
  place for future subsets.
- **Gates**: prior gates + vacuous re-verification green.
- **Owner**: build session (RT-08), operator adopts the template (RT-09).
- **Entry**: AC-B2. **Exit**: AC-B3 complete.

## Phase B4 — Release activation (operator-gated)

- **Trigger**: operator go at C4/C5.
- **Inputs**: B1–B3 complete; key ceremony executed (RT-11:
  `docs/SIGNING_RUNBOOKS.md` §1); public key + keyring published via the
  independent channel.
- **Steps** (procedure: `docs/SIGNING_RUNBOOKS.md` §2; sequence diagram:
  `docs/RELEASE_IMPLEMENTATION_BLUEPRINT.md` §3): checklist integration
  (RT-10) → prepare/rebuild-and-compare → human sign → verify
  `verified-signed` → record evidence (public subset committed) → tag →
  publish with signature + keyring → independent-machine verification →
  rehearsal first (RT-12: re-sign the current release) → README tier-2
  co-primary (RT-13).
- **Outputs**: first `verified-signed` release; first real
  `evidence/releases/<version>/signing-evidence.json`; README co-primary
  block.
- **Gates**: all prior gates + `verified-signed` from an independent
  machine + evidence re-verification no longer vacuous + harness §18 pin
  tests green after the README edit.
- **Owner**: operator (RT-11–RT-13 are operator-executed by design).
- **Entry**: AC-B3 + C4. **Exit**: AC-B4 complete (C5, C6).

## Phase B5 — Trust enhancements (optional, per-option decision)

- **Trigger**: operator decision at C8 per option.
- **Options**: SPDX SBOM publication (RT-14), signed provenance statement
  (RT-15), OIDC/keyless revisit (RT-16 — only under the design spec §13
  revisit conditions).
- **Outputs/gates**: per `docs/RELEASE_ACCEPTANCE_CRITERIA.md` AC-B5; each
  option is independently revertible and none changes the operator-signature
  gate.

## Phase-transition summary

| transition | entry criteria | exit criteria | approval |
|---|---|---|---|
| 0 → B1 | C3 build session authorized | AC-B1 | C3 |
| B1 → B2 | AC-B1 | AC-B2 + remote dry-run green | PR review |
| B2 → B3 | AC-B2 | AC-B3 (vacuous checks green) | PR review |
| B3 → B4 | AC-B3 + C4 key ceremony | AC-B4 (first `verified-signed` release) | C4, C5, C6 |
| B4 → B5 | C8 per option | AC-B5 per option | C8 |

At every transition the full gate set runs: `bash tests/run_tests.sh`,
`bash scripts/ci-local.sh`, `python3 scripts/check-github-action-pins.py`,
plus the phase-specific gates above. Integrity-only releases remain valid at
every phase (`docs/SIGNING_KEY_LIFECYCLE.md` §7); no transition has a flag
day.
