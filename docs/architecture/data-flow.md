# Data Flow

| data | source | destination | format | validation | persistence | redaction | trust |
|---|---|---|---|---|---|---|---|
| Git state | `git status`, `git log`, `git diff` | harness / reports | text | parsed by shell / Python checks | reports, evidence logs | none | high |
| Changed paths | `git diff --name-only` | selector logic | newline text | path classification | in-memory + report reasons | none | high |
| Action metadata | `.agent/task-router.yaml`, `.agent/skills/index.yaml` | agent-facing tooling | YAML | file existence / registry checks | repo files | none | medium |
| Environment variables | shell env / PATH | scripts and harness | strings | explicit preflight checks | ephemeral | none | medium |
| Validation plans | section selection + dependencies | harness core | text / JSON | section registry + dependency traversal | run output | none | high |
| Command output | scripts and checks | logs / summaries | text / JSON | exit code + check-specific assertions | `reports/logs/`, stdout | partial | medium |
| Logs | harness and CI runs | `reports/logs/` | text | command-specific assertions | filesystem | limited | medium |
| Results | harness / CI summaries | reports, JSON | text / JSON | schema checks where present | `reports/` | limited | high |
| Evidence | release bundles, run reports | `evidence/`, `reports/` | Markdown / JSON / logs | checksum / signature / path checks | append-only by convention | limited | high |
| Approvals | operator decisions | branch / release flow | human decision | policy and branch protection | reports / history | none | highest |
| Promotion decisions | review + validation | merge / publish gate | human + machine | required checks | reports / history | none | highest |

## Notes

- JSON extraction is used for structured CI and harness summaries.
- Shell output parsing is conservative and explicit.
- Evidence remains filesystem-based; there is no application database.
- External tool output is trusted only after the surrounding check validates it.
- Provenance is strongest when the output can be traced back to the exact commit
  and exact log file path.
