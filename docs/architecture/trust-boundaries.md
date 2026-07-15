# Trust Boundaries

| boundary | assets | threats | existing controls | known limitations | required future controls | owning phase |
|---|---|---|---|---|---|---|
| Human instruction -> agent execution | task intent | ambiguous or unsafe instructions | AGENTS / scoped instructions | agent still interprets intent | tighter structured task routing | phase 1+ |
| Agent execution -> shell | repository files, commands | command injection | explicit quoting, equals-form flags, usage checks | shell remains the execution substrate | stronger command broker | phase 1+ |
| Shell -> repository | source tree | accidental mutation | clean-tree gates, fail-closed writes | many scripts still inline | narrower mutation surfaces | phase 1-2 |
| Repository -> runtime | PATH, toolchain, env | PATH drift, unsupported hosts | explicit PATH exports and preflight checks | Termux/proot assumptions are manual | runtime profiles / explicit adapters | phase 1-4 |
| Runtime -> external network | downloads, vendor CLIs | MITM, stale mirrors, truncation | commit-pinned URLs, checksum verification, temp-file install | authenticity depends on future signing key | operator signing key + verified signatures | phase 1 |
| Untrusted code -> host | backlog tasks, downloaded content | arbitrary code execution | quoted prompt construction, verification before install | `pixel-autodev.sh` still executes repo test commands | stronger sandboxing / isolation | phase 7+ |
| Command output -> parser | logs, JSON, status text | malformed output | exit-code checks, explicit grep/awk rules | prose parsing can drift | structured output where it matters | phase 3+ |
| Evidence -> promotion | reports, bundles | fabricated or stale evidence | required gates, clean-clone parity, signed-commit policy | evidence is still file-based | immutable evidence bundles | phase 4 |
| Local system -> remote Git hosting | branches, PRs | unauthorized push/merge/release | operator-only boundaries, branch protection | push/merge remain human ceremonies | policy-aware promotion service | phase 8+ |
| Source commit -> built artifact | release candidate | tampering, mismatch | reproducible build, manifest checks, bundle verifier | authenticity not yet universal | signed provenance + release ceremony | phase 1 |
| Recursion guard | harness integrity | nested full-gate loops | env flag + lock dir + targeted clone guards | still shell-local | dedicated supervisor/process model | phase 2 |
| Environment sanitation | toolchain and PATH | hidden host tools | explicit PATH handling and tool override seams | host assumptions can still leak in | clearer runtime contracts | phase 1 |
| Bubblewrap / sandbox boundary | host filesystem | sandbox escape | no canonical bwrap runtime in current harness | unsupported in current path | explicit isolation layer | phase 7 |
| Git signature checks | commit identity | forged or unverified commits | required signed commits policy | GitHub verification still external | richer provenance and attestations | phase 4 / 11 |
| Clean-clone parity | source vs clone | divergence, selector drift | nested clean-clone smoke and parity checks | only a subset of behaviors are cloned | immutable clone evidence bundles | phase 4 |
| Central redaction | secrets, tokens | leakage into logs/reports | secret scan checks | prose-only scanning is imperfect | schema-aware redaction | phase 3 |
| Operator authorization | protected repo actions | unauthorized promotion | branch protection and repo policy | still manual approvals | explicit promotion workflow | phase 8 |
| No-push / no-merge constraints | repo history | history rewrite or premature publication | documented operator-only boundaries | depends on discipline | enforcement hooks and policy automation | phase 1-8 |
