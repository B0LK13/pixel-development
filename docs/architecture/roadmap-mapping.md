# Roadmap Mapping

## Phase overview

| phase | objective | prerequisite | major deliverables | exit gate | principal risks |
|---|---|---|---|---|---|
| 1 | core stabilization | baseline docs, current registry, compatibility matrix | deterministic contracts, runtime normalization, evidence model, path checks | current baseline validated and documented | environment drift, signature trust |
| 2 | modular architecture | stable behavior and section IDs | extracted helpers, process supervision, smaller modules | no behavior change, full gate green | monolithic-shell drift |
| 3 | observability | stable validation and evidence capture | structured run manifests, stronger diagnostics | reports explain runs without guesswork | ambiguous exit state |
| 4 | evidence and provenance | current evidence model understood | immutable evidence bundles, clone parity, provenance schema | source/clone and artifact provenance align | evidence loss, clean-clone drift |
| 5 | intelligent selection | stable classification baseline | stronger change intelligence, advisory scoring | targeted selection remains conservative | unsupported path classification |
| 6 | performance and caching | baseline reliability proven | measured caching, lower overhead, performance baselines | no trust regression | cache correctness, performance degradation |
| 7 | runtime isolation | runtime compatibility understood | sandbox boundary, clearer host isolation | isolation model explicit and tested | Bubblewrap compatibility |
| 8 | agent governance | operator boundaries documented | explicit agent scopes, budgets, approvals | no agent overreach | governance drift |
| 9 | self-healing | failure modes well characterized | controlled recovery behaviors | recovery does not hide failures | recursion, ambiguous state |
| 10 | distributed execution | core contract stable | worker registry, remote execution model | distributed path does not weaken trust | process leaks, policy drift |
| 11 | supply-chain security | signing and pinning matured | provenance and stronger release trust | release authenticity model is explicit | signature trust |
| 12 | predictive optimization | observability and data quality strong | advisory optimization only | never overrides policy | overfitting, false confidence |
| 13 | production maturity | all core controls stable | long-term operational hardening | operator-run maturity path | scope creep |

## Item mapping

| item | target phase |
|---|---|
| R-01 recursive orchestration | 2 / 9 |
| R-02 environment drift | 1 |
| R-03 evidence loss | 4 |
| R-04 ambiguous exit state | 3 |
| R-05 unsupported path classification | 1 / 5 |
| R-06 secret leakage | 3 / 11 |
| R-07 signature trust | 1 / 11 |
| R-08 clean-clone drift | 4 |
| R-09 agent overreach | 8 |
| R-10 process leaks | 2 |
| R-11 cache correctness | 6 |
| R-12 monolithic shell logic | 2 |
| R-13 Termux stability | 1 |
| R-14 Bubblewrap compatibility | 7 |
| R-15 performance degradation | 6 |
| TD-01 shell architecture | 2 |
| TD-02 command construction | 2 |
| TD-03 evidence format | 4 |
| TD-04 runtime assumptions | 1 |
| TD-05 selector coverage | 1 / 5 |
| TD-06 telemetry | 3 |
| TD-07 contract drift | 1 |
| TD-08 release evidence | 4 |
| TD-09 versioning | 2 |
| TD-10 human-readable output | 3 |
