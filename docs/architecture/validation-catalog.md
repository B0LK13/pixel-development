# Validation Catalog

| section | name | invocation | trigger | targets | deps | fallback | timeout | evidence | tests | reliability |
|---|---|---|---|---|---|---|---|---|---|---|
| 0 | Required files | full gate | every run | required paths | - | fail closed | harness default | stdout + logs | full gate | high |
| 1 | Syntax | full gate | every run | tracked shell scripts | 0 | fail closed | harness default | syntax logs | full gate | high |
| 2 | Shellcheck | full gate | every run | tracked shell scripts | 1 | skip if tool absent | harness default | lint logs | full gate | high |
| 3 | CLI help contract | full gate | command contract | scripts | 0 | fail closed | harness default | contract output | full gate | high |
| 4 | .pixel-lab.json | full gate | metadata | repo root | 0 | skip if jq absent | harness default | JSON check | full gate | high |
| 5 | Autodev dry-run | full gate | autodev changes | `pixel-autodev.sh` | 0,4 | targeted fallback | harness default | dry-run logs | full gate | high |
| 6 | Timeout contract | full gate | autodev changes | `pixel-autodev.sh` | 5 | fail closed | harness default | timeout output | full gate | high |
| 7 | CLI extras | full gate | CLI docs | all scripts | 3,6 | fail closed | harness default | contract output | full gate | high |
| 8 | Clean-clone smoke | full gate + targeted | clone validation | harness | 0,1,3 | skip when requested | long | nested clone logs | full gate | high |
| 9 | SSH port contract | full gate | apps setup | `pixel-apps-setup.sh` | 3 | fail closed | harness default | stderr naming | full gate | high |
| 10 | Numeric flags | full gate | autodev numeric parsing | `pixel-autodev.sh` | 3,5 | fail closed | harness default | stderr naming | full gate | high |
| 11 | Agent enum | full gate | autodev backend selection | `pixel-autodev.sh` | 3,5 | fail closed | harness default | enum output | full gate | high |
| 12 | End-of-options | full gate | positional args | all scripts | 3 | fail closed | harness default | usage output | full gate | high |
| 13 | Preflight tools | full gate | autodev preflight | `pixel-autodev.sh` | 5 | fail closed | harness default | tool resolution logs | full gate | high |
| 14 | Line endings | full gate | repo policy | tracked scripts | 0 | fail closed | harness default | gitattributes check | full gate | high |
| 15 | Dependency seam | full gate | autodev tool override | `pixel-autodev.sh` | 5,13 | fail closed | harness default | seam diagnostics | full gate | high |
| 16 | Checksum lockstep | full gate | bootstrap manifest | bootstrap scripts | 0 | fail closed | short | checksum output | full gate | high |
| 17 | Download verification | full gate | bootstrap install flow | bootstrap scripts | 16 | fail closed | medium | temp-file logs | full gate | high |
| 18 | Anchor install flow | full gate | README bootstrap path | README | 16,17 | fail closed | medium | commit + digest checks | full gate | high |
| 19 | Signature fixtures | full gate | bootstrap signing | helper script | 18 | skip if gpg absent | medium | gpgv output | full gate | medium |
| 20 | Checksum lifecycle tool | full gate | manifest updater | update tool | 16 | fail closed | medium | manifest diff | full gate | high |
| 21 | Release process governance | full gate | release docs | release docs | 20 | fail closed | short | doc lockstep | full gate | high |
| 22 | CI parity static | full gate + ci-local | workflow parity | workflow + ci-local | 3,20 | fail closed | medium | workflow diff | full gate | high |
| 23 | Security invariants | full gate | bootstrap trust | bootstrap flow | 16,17,19 | fail closed | medium | signal cleanup logs | full gate | high |
| 24 | Candidate builder | full gate | release build | builder script | 21 | fail closed | medium | bundle layout + metadata | full gate | high |
| 25 | Bundle verifier integrity | full gate | release verification | verifier script | 24 | fail closed | medium | verdict logs | full gate | high |
| 26 | Bundle verifier signed | full gate | release verification | verifier script | 25 | skip if gpg absent | medium | verdict logs | full gate | medium |
| 27 | Reproducibility | full gate | SDE-pinned builds | builder script | 24 | fail closed | medium | byte comparison logs | full gate | high |
| 28 | Docs contracts | full gate | release docs | docs/release runbooks | 21,24,25,27 | fail closed | short | doc checks | full gate | high |
| 29 | Repository readiness | full gate | repo layout and docs | README / docs | 0 | fail closed | short | layout checks | full gate | high |
| 30 | Workflow action pins | full gate + CI parity | workflow supply chain | `.github/workflows` | 22 | fail closed | short | pin checker output | full gate | high |
| 31 | Agent OS checks | full gate | repository OS contract | docs, `.agent/`, schemas | 30 | fail closed | long | structured check output | full gate | high |
| 32 | Harness robustness / recovery | full gate | recursion and recovery | harness | 31 | fail closed | medium | recovery logs | full gate | high |

## Current gate behavior

- `.gitignore` mapping stays targeted at section 0
- Unknown paths fall back to the full gate
- Internal full runner is guarded against re-entry
- Clean-clone selector docs are checked against the live registry
- Current total: 33 validation sections (0-32)
