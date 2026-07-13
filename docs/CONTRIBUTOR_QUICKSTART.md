# Contributor Quickstart

Contributing to **this repository** (the pixel-development kit). To *use*
the kit on a Pixel phone, start at the README instead.

## Prerequisites

- **bash** — ≥4 for the release tooling (`declare -A` in
  `scripts/update-bootstrap-checksums.sh` and
  `scripts/verify-release-bundle.sh`); the product scripts cope with 3.2
  modulo the GNU-isms documented in `docs/AUTONOMOUS_AUDIT.md`
- **git**
- **python3** — for the GitHub Actions pin gate
  (`scripts/check-github-action-pins.py`, stdlib only; preinstalled on
  GitHub runners)
- optional: **shellcheck** (the lint gate self-skips when absent), **jq**
  (JSON checks degrade to a skip)

## Run the gates

| command | what it does |
|---------|--------------|
| `bash tests/run_tests.sh` | the full hermetic suite — the only sanctioned gate; ends with a clean-clone smoke |
| `PIXEL_TESTS_NO_CLONE=1 bash tests/run_tests.sh` | fast local pass (dev convenience; never the final gate) |
| `PIXEL_TEST_TIMINGS=1 bash tests/run_tests.sh` | per-test elapsed times on stderr |
| `bash scripts/ci-local.sh` | the CI gate chain locally: whitespace, checksum lockstep, action pins, syntax, shellcheck, full suite — fail-fast |
| `python3 scripts/check-github-action-pins.py` | enforce the workflow pinning policy (`docs/GITHUB_ACTIONS_PINNING_POLICY.md`): every external action SHA-pinned with a version comment |

## Editing a checksummed script

`pixel-bootstrap.sh`, `pixel-dev-setup.sh`, and `pixel-apps-setup.sh` are
SHA-256-pinned (embedded digests plus `config/bootstrap-checksums.txt`).
After editing any of them, run **in the same commit**:

```bash
bash scripts/update-bootstrap-checksums.sh --write
bash scripts/update-bootstrap-checksums.sh --check   # must exit 0
```

## Contracts you must not break

- `docs/CLI_CONTRACT.md` — equals-only flag syntax, exit classes 0/1/2,
  validation before any side effect
- harness doc pins — `tests/run_tests.sh` §28/§29 grep specific phrases in
  the README and `docs/`; changing documented behavior means updating the
  code, the contract, and the assertions together
- hermeticity — fixtures never touch the network, paid agents, or the
  host's git/GPG state (`CLAUDE_BIN`/`CODEX_BIN` seams,
  `commit.gpgsign false` in every fixture)

## A gate failed — first move

| symptom | first move |
|---------|------------|
| `checksum manifest is stale` / `STALE:` lines | `bash scripts/update-bootstrap-checksums.sh --write`, re-run |
| shellcheck gate skipped | `apt-get install -y shellcheck`, or accept the documented self-skip |
| `working tree is not clean` (release builder) | commit or stash — the builder refuses dirty trees by design |
| suite too slow for iteration | `PIXEL_TESTS_NO_CLONE=1` locally; always finish with the full gate |

## Where to read next

- `docs/CLI_CONTRACT.md` — normative CLI contract
- `docs/AUTONOMOUS_AUDIT.md` — security audit, finding register,
  per-session follow-ups
- `docs/BOOTSTRAP_TRUST_MODEL.md` — the trust model the gates enforce
- `docs/adr/` — architecture decision records
- `reports/` — per-session completion reports and review documents
