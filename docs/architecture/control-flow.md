# Control Flow

## Standard action flow

```
instruction
-> route lookup / task selection
-> parameter validation
-> capability check
-> environment preparation
-> command execution
-> result parsing
-> reporting
```

## Changed validation flow

```
git change set
-> path classification
-> selector mapping
-> targeted validation
-> conservative full fallback
-> result aggregation
```

## Full validation flow

```
top-level entry
-> recursion guard
-> harness core
-> ordered sections
-> terminal summary
```

## Clean-clone flow

```
source commit
-> clean clone
-> bootstrap / validate
-> parity check
-> evidence
```

## Promotion flow

```
candidate
-> source validation
-> clean-clone validation
-> merge simulation
-> promotion approval
-> local promotion
-> post-promotion validation
```

## Re-entry boundaries

- `tests/run_tests.sh` cannot recursively invoke itself as the full gate
- `scripts/ci-local.sh` terminates children on interrupt instead of re-entering
- `pixel-autodev.sh` isolates dry-run from real dispatch
- Clean-clone runs are explicit and bounded; they do not spawn the top-level gate again
