# Technical Debt Register

| id | area | description | evidence | impact | proposed remediation | dependencies | target phase | priority |
|---|---|---|---|---|---|---|---|---|
| TD-01 | shell architecture | the harness is still monolithic and hard to navigate | `tests/run_tests.sh` | higher maintenance cost | extract per-area section files only if growth demands it | none | phase 2 | low |
| TD-02 | command construction | release tooling repeats artifact tables and command fragments | `scripts/build-release-candidate.sh`, `scripts/verify-release-bundle.sh` | drift risk | centralize tables after baseline docs settle | stable harness pins | phase 2 | medium |
| TD-03 | evidence format | reports and evidence are convention-based rather than schema-unified | `reports/`, `evidence/` | provenance gaps | add immutable evidence bundle schema | runtime profiles | phase 4 | medium |
| TD-04 | runtime assumptions | Termux/proot PATH handling is manual and environment-specific | `pixel-bootstrap.sh`, `pixel-dev-setup.sh`, `pixel-autodev.sh` | environment drift | formalize runtime profiles and adapters | compatibility matrix | phase 1 | high |
| TD-05 | selector coverage | changed-path classification still depends on hand-maintained mappings | `tests/run_tests_support.sh` | missed coverage if new paths are added | keep conservative fallback, add mapping checks | registry coverage | phase 1 | medium |
| TD-06 | telemetry | process-level diagnostics are still script-local | `scripts/ci-local.sh`, `tests/run_tests.sh` | hard-to-aggregate failures | centralize process supervision later | runtime model | phase 2 | medium |
| TD-07 | contract drift | docs, scripts, and workflow policy are spread across multiple files | `docs/CLI_CONTRACT.md`, `.github/workflows/test.yml` | maintenance overhead | continue parity checks and add small doc consistency checks | docs baseline | phase 1 | medium |
| TD-08 | release evidence | release verification produces useful output but not one unified bundle contract | `scripts/verify-release-bundle.sh` | audit complexity | standardize bundle/evidence schema | signing work | phase 4 | medium |
| TD-09 | versioning | version truth is spread across docs and scripts | `VERSION`, `docs/BOOTSTRAP_RELEASE_PROCESS.md` | mismatch risk | add a single-source cross-check | harness assertion | phase 2 | medium |
| TD-10 | human-readable output | some failures still rely on prose parsing | `tests/run_tests.sh`, `scripts/ci-local.sh` | brittleness in docs/tests | prefer structured fields where it matters | JSON summaries | phase 3 | low |

## Confirmed vs preference

- Confirmed debt is tied to concrete evidence above.
- Architectural preference alone is not recorded here.
- Items that are already resolved or intentionally deferred stay out of this table.
