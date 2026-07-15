# Runtime Compatibility

| runtime | support | isolation | known constraints | required PATH | validation status |
|---|---|---|---|---|---|
| Native Linux | supported for harness and CI | shell + repo boundaries | must have bash, git, coreutils; optional shellcheck/jq/gpg | standard Linux toolchain | validated by harness and ci-local |
| WSL | not a canonical target | host-managed | unverified in current repo baseline | not specified | no claim beyond "Linux-like host" |
| Termux | canonical for bootstrap/dev setup | userspace only | requires Termux preflight; `pixel-bootstrap.sh` / setup scripts fail outside Termux | repo-defined PATH prefix in the bootstrap/dev scripts | validated by contract tests |
| PRoot | canonical for the devbox layer | proot userspace | AI stack lives here; not a host sandbox | repo-defined PATH prefix plus devbox additions | validated by autodev tests |
| Bubblewrap | unsupported in the canonical harness path | future sandbox boundary | no current canonical bwrap execution path in the repo scripts | n/a | no claim made |
| Container | not canonical | future abstraction | repo remains shell-first and host-native | n/a | no claim made |

## Current Termux facts

- `pixel-bootstrap.sh` and `pixel-autodev.sh` export a fixed PATH prefix
- `pixel-dev-setup.sh` appends the repo's local bin paths to the shell PATH
- The exact Node path is environment-managed, not repo-pinned
- `pixel-autodev.sh` avoids Termux-binary leakage by resolving tool binaries explicitly
- Dry-run skips agent resolution entirely
- Child-process handling is still shell-local; no separate runtime supervisor exists

## Prior PATH drift

- The PATH contract is encoded in the bootstrap/dev setup scripts, not inferred from the host
- The repo treats PATH as explicit configuration, not ambient luck
- Any new runtime support must state the PATH contract before it can be treated as live

## Unsupported assumptions

- `bwrap` is not part of the current canonical path
- macOS, Git Bash, and other non-Linux hosts are not claimed as supported runtimes here
- A successful host test does not imply universal platform support
