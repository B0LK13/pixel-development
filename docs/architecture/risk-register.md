# Risk Register

| id | risk | category | likelihood | impact | current controls | evidence | residual risk | owner | target phase | status |
|---|---|---|---|---|---|---|---|---|---|---|
| R-01 | recursive orchestration causes nested or duplicate harness runs | recursive orchestration | medium | high | env guards, lockdir, clone guards | `tests/run_tests.sh`, `scripts/ci-local.sh` | shell-only guard still fragile | repo | phase 2 | open |
| R-02 | environment drift changes PATH or tool resolution | environment drift | medium | high | explicit PATH exports, preflight checks | `pixel-bootstrap.sh`, `pixel-dev-setup.sh`, `pixel-autodev.sh` | host assumptions remain manual | repo | phase 1 | open |
| R-03 | evidence is lost or overwritten | evidence loss | low | high | append-only convention, report paths | `reports/`, `evidence/` | temp files still overwrite during runs | repo | phase 4 | open |
| R-04 | ambiguous exit state obscures whether a run succeeded | ambiguous exit state | medium | moderate | explicit exit codes, verdict labels | `docs/CLI_CONTRACT.md`, harness | prose parsing still mixed with code | repo | phase 3 | open |
| R-05 | unsupported path classification silently narrows coverage | unsupported path classification | medium | high | conservative full fallback | `tests/run_tests_support.sh` | new paths still require mapping updates | repo | phase 1 | open |
| R-06 | secret leakage appears in logs or reports | secret leakage | low | high | secret scan checks | `scripts/check-agent-secrets.py` | plaintext scans can miss novel formats | repo | phase 3 | open |
| R-07 | signature trust remains integrity-only | signature trust | medium | high | checksum pins, verifier mechanics, signed fixture tests | `docs/BOOTSTRAP_TRUST_MODEL.md`, `docs/RELEASE_SIGNING.md` | production authenticity still operator-provisioned | operator | phase 1 | open |
| R-08 | clean-clone drift hides source/clone divergence | clean-clone drift | low | high | nested clean-clone smoke | `tests/run_tests.sh --section=8` | only selected behaviors are cloned | repo | phase 4 | open |
| R-09 | agent overreach mutates protected state | agent overreach | low | high | no push / no merge / no release | `AGENTS.md`, `docs/AGENT_SECURITY_BOUNDARIES.md` | discipline-based until stronger enforcement exists | operator | phase 8 | open |
| R-10 | process leaks or orphaned children survive interrupts | process leaks | medium | moderate | traps and explicit child cleanup | `tests/run_tests.sh`, `scripts/ci-local.sh` | shell process control is not centralized | repo | phase 2 | open |
| R-11 | cache correctness is assumed before it is proven | cache correctness | low | moderate | no canonical caching path yet | current repo baseline | caching is not yet a live contract | repo | phase 6 | deferred |
| R-12 | current shell logic is too monolithic to evolve safely | correctness | certain | moderate | tests pin behavior | `tests/run_tests.sh`, `scripts/ci-local.sh` | maintainability cost rises over time | repo | phase 2 | open |
| R-13 | Termux stability varies across devices and package states | Termux stability | medium | high | explicit Termux preflight and supported PATH | `pixel-bootstrap.sh`, `pixel-dev-setup.sh` | device variance still exists | repo | phase 1 | open |
| R-14 | Bubblewrap compatibility is assumed without a live path | Bubblewrap compatibility | low | moderate | none in canonical path | current repo baseline | bwrap is future-state only | repo | phase 7 | deferred |
| R-15 | performance degrades as the monolithic harness grows | performance degradation | medium | low | targeted sections, cached logs, stable IDs | `tests/section-map.tsv` | flat harness still scales by convention | repo | phase 6 | open |

## Rank order

1. R-01 recursive orchestration
2. R-02 environment drift
3. R-03 evidence loss
4. R-07 signature trust
5. R-05 unsupported path classification
