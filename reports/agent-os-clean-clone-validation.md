# Agent OS Clean-Clone Validation

- Clone: `/tmp/agent-os-clean-clone`
- Candidate commit: `5c454f73f63294b998ce646ab45b1629d7e4a404`
- Status: **passed**

## Evidence

- Interrupted log: `/tmp/agent-os-clean-clone-ci-local.txt`
- Replacement log: `/tmp/agent-os-clean-clone-ci-local-rerun-20260714T164852Z.txt`
- Replacement exit status: `0`

## Result

- `bash scripts/ci-local.sh` completed successfully in the clean clone.
- The clean-clone HEAD matches the source repository HEAD.

## Notes

- The rerun wrote its evidence to `/tmp` and left the clone clean.
- The earlier interrupted run ended at the `ci-local: interrupted by signal` marker and was not treated as a terminal failure.
- `.codebase-memory/` is local generated state, ignored by `.gitignore`, and intentionally not part of the clean-clone evidence set.
