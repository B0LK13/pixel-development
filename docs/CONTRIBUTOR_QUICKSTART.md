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
| `bash tests/run_tests.sh --list` | list stable section/test IDs for targeted iteration |
| `bash tests/run_tests.sh --test=<id>` | run targeted harness scope by stable test ID (still finish with full gate) |
| `bash tests/run_tests.sh --section=<n>` | run targeted harness scope by section number |
| `bash tests/run_tests.sh --changed` | infer targeted scope from changed files |
| `bash tests/run_tests.sh --json` | full harness + structured JSON summary |
| `PIXEL_TESTS_NO_CLONE=1 bash tests/run_tests.sh` | fast local pass (dev convenience; never the final gate) |
| `PIXEL_TEST_TIMINGS=1 bash tests/run_tests.sh` | per-test elapsed times on stderr |
| `bash scripts/ci-local.sh` | the CI gate chain locally: whitespace, checksum lockstep, policy checks, syntax, shellcheck, full suite — fail-fast |
| `bash scripts/ci-local.sh --json` | same CI gate chain with structured JSON summary |
| `python3 scripts/check-github-action-pins.py` | enforce the workflow pinning policy (`docs/GITHUB_ACTIONS_PINNING_POLICY.md`): every external action SHA-pinned with a version comment |
| `python3 scripts/check-agent-instructions.py` | verify required agent-instruction hierarchy and manifest/router scaffolding |
| `python3 scripts/check-doc-command-parity.py` | detect stale command references across key docs |
| `python3 scripts/check-evidence-links.py` | detect broken `evidence/...` references in docs/reports |
| `python3 scripts/check-cli-contracts.py` | detect CLI contract drift between scripts and `docs/CLI_CONTRACT.md` |
| `python3 scripts/check-test-registration.py` | ensure harness sections are registered in `tests/section-map.tsv` |

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
