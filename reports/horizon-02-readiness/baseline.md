# Horizon 0.2 Baseline Report — Repository Integrity (Agent A)

Date: 2026-07-13 (UTC)
Role note: Agent A's gate was coordinator-executed — the ~25-minute gate
exceeds the 30-minute subagent timeout margin, and this host serializes
heavy gates to avoid low-memory SIGKILLs. Evidence:
`evidence/horizon-02/baseline/baseline-record.txt`.

## 1. Starting state

- Baseline: `main` @ `5fd735b351c50182d308725525e066cf6ec2514c` — local
  equals origin, tree clean.
- Integration branch: `auto/integrate-horizon-02-readiness` @ `cc5c0d3`
  (tracker + evidence-structure commit, GPG-signed).
- Governance: single-maintainer protection active — approvals 0, checks
  `suite` + `release-candidate-check` (strict), required signatures,
  conversation resolution, `enforce_admins`, no force-push, no deletion,
  no linear history (`docs/MAIN_BRANCH_PROTECTION.md` §7).
- No open PRs; no watchers or cron jobs.

## 2. Gate results

| check | result |
|---|---|
| `git diff --check` | clean (rc 0) |
| `scripts/check-github-action-pins.py` | 0 violations (rc 0) |
| `bash tests/run_tests.sh` | 327 passed / 0 failed / 0 skipped (rc 0) |
| `bash scripts/ci-local.sh` | ALL GATES PASSED (rc 0) |
| working tree | clean at start and finish |

Gate window 21:16:19Z → 21:32:59Z. Raw logs host-only (`/tmp/h02/`).

Suite-covered guarantees re-verified on this baseline: unsigned
integrity verdict, signed fixture + failure injection, byte-identical
reproducibility, key-material scan (0 markers), pin enforcement.

## 3. Release tooling inventory (tracked)

- `scripts/build-release-candidate.sh` — deterministic bundle builder
  (dirty-tree refusal, version/epoch validation, atomic write).
- `scripts/verify-release-bundle.sh` — integrity/signature/metadata
  verifier with the documented verdict vocabulary.
- `scripts/verify-bootstrap-signature.sh` — detached anchor-signature
  verifier (gpgv).
- `scripts/ci-local.sh`, `scripts/check-github-action-pins.py`,
  `scripts/update-bootstrap-checksums.sh` — parity and policy gates.
- `config/bootstrap-checksums.txt` — checksum manifest (lockstep-checked).
- `.github/workflows/test.yml` — two required jobs, no secrets, no
  publishing, pinned actions.

## 4. Conclusion

Baseline green. All downstream workstream outputs merge onto this
verified state. No integrity findings.
