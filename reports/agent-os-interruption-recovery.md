# Agent OS Harness Interruption Recovery Report

**Date:** 2026-07-14 (UTC)  
**Branch:** `auto/integrate-horizon-02-readiness`  
**HEAD Commit:** `0dabaaef3bcb6e00c5709507fcde2c85f8b4ac14 merge(horizon-02): integrate Agent B reproducibility evidence`  
**Status:** Recovering from interrupted Session 15 full gate (`scripts/ci-local.sh --json → tests/run_tests.sh → tests/run_tests_full.sh`)

---

## 1. Environment & Working Tree Capture

### Git & Worktree State
- **Current Branch:** `auto/integrate-horizon-02-readiness`
- **HEAD Commit:** `0dabaaef3bcb6e00c5709507fcde2c85f8b4ac14` (`merge(horizon-02): integrate Agent B reproducibility evidence`)
- **Active Worktrees:**
  - `/root/pixel-development` (`0dabaae` `[auto/integrate-horizon-02-readiness]`)
  - `/tmp/h02-adv` (`f1eeb74` `[auto/horizon-02-adversarial]`)
  - `/tmp/h02-prov` (`44c72df` `[auto/horizon-02-provenance]`)
  - `/tmp/h02-rec` (`80e93d6` `[auto/horizon-02-recovery]`)
  - `/tmp/h02-repro` (`168b268` `[auto/horizon-02-reproducibility]`)
  - `/tmp/h02-sign` (`aa8e643` `[auto/horizon-02-signing-rehearsal]`)

### Modified Files (`M`)
1. `.github/workflows/test.yml`
2. `README.md`
3. `docs/CONTRIBUTOR_QUICKSTART.md`
4. `docs/OPERATOR_COMMAND_INDEX.md`
5. `reports/horizon-02-readiness/integration-log.md`
6. `scripts/ci-local.sh`
7. `tests/run_tests.sh`

### Untracked Files (`??`)
- `.agent/repository-manifest.yaml`, `.agent/task-router.yaml`, `.agent/skills/index.yaml`, `.agent/skills/*` (14 skills), `.agent/templates/*` (8 templates)
- `.github/AGENTS.md`, `.github/copilot-instructions.md`, `AGENTS.md`, `CLAUDE.md`, `docs/AGENTS.md`, `scripts/AGENTS.md`, `tests/AGENTS.md`
- `docs/AGENT_*.md` (5 docs), `docs/MCP_INTEGRATION.md`
- `evidence/SIGNING-EVIDENCE.json`, `evidence/releases/.gitkeep`
- `harness/*`, `reports/agent-os-recovery-inventory.md`, `reports/agent-os/harness-inventory.md`, `reports/session-14-final-report.md`
- `schemas/*.schema.json` (6 schemas)
- `scripts/agent-context.sh`, `scripts/check-*.py` (9 scripts)
- `tests/run_tests_full.sh`, `tests/section-map.tsv`

### Active Processes & Cleanliness Confirmation
- Verified via `ps aux | grep -E "(run_tests|ci-local|pytest)"` that **no previous `run_tests`, `run_tests_full`, or `ci-local` processes remain running or orphaned**.
- Partial work from Session 14 / Session 15 foundation has been preserved exactly without resetting, stashing, amending, or deleting.

---

## 2. Signal-9 Interruption Investigation

We investigated the signal-9 (`SIGKILL`) interruption reported during execution of `scripts/ci-local.sh --json → tests/run_tests.sh → tests/run_tests_full.sh`. Rather than making unverified claims, we inspected the exact mechanics across `scripts/ci-local.sh`, `tests/run_tests.sh`, and `tests/run_tests_full.sh`.

### Evidence & Root Cause Analysis

1. **In-Memory Buffering of Full Logs (`run_and_capture` in `tests/run_tests.sh`)**:
   - In `tests/run_tests.sh`, execution of `bash "$CORE"` (`tests/run_tests_full.sh`) is performed inside command substitution: `out="$("$@" 2>&1)"`.
   - `tests/run_tests_full.sh` executes over 31 comprehensive test sections, running nested `git clone` operations, spinning up mock agent servers (`slow-agent`, `fake-claude`), checking timeouts, and emitting thousands of lines of diagnostic output.
   - Buffering the entire combined stream (`stdout` and `stderr`) in memory inside a single subshell variable `out` consumes substantial subshell/variable memory, creates pipeline bottlenecks, and prevents real-time diagnostic visibility while the subshell runs. When memory pressure (`OOM`/cgroup limits inside container/sandbox environments) or execution timeouts hit during `ci-local.sh --json`, the kernel terminates the subshell with Signal 9 (`exit 137`).

2. **JSON Stream Pollution & Shell Variable Output**:
   - When `AS_JSON=1` is passed to `tests/run_tests.sh`, the script executes `printf '%s\n' "$out"` directly to `stdout` immediately before printing the JSON structure (`printf '\n{\n...'`).
   - Similarly, when `scripts/ci-local.sh --json` runs, individual step commands (`python3 scripts/check-*.py`, `bash scripts/update-bootstrap-checksums.sh --check`, `git diff --check`, and `bash tests/run_tests.sh`) emit their raw text diagnostics directly to `stdout`.
   - As a result, `stdout` receives tens of thousands of lines of raw diagnostic text prepended to the JSON output. This violates the strict schema and architectural contract that **JSON stdout must contain JSON only, diagnostics must go to stderr or durable log files, and JSON mode must stream logs to files instead of shell variables**.

3. **Recursive & Nested Harness Invocation (`tests/run_tests_full.sh` Section 8)**:
   - In `tests/run_tests_full.sh` line 315, clean-clone verification runs:
     `git clone -q --local "$ROOT" "$clone" && ( cd "$clone" && PIXEL_TESTS_NO_CLONE=1 bash tests/run_tests.sh >"$tmp/nested-clone.log" 2>&1 )`
   - Notice that invoking `bash tests/run_tests.sh` with no arguments defaults `mode` to `full`. When `ci-local.sh` or `tests/run_tests.sh` runs `tests/run_tests_full.sh`, Section 8 invokes `tests/run_tests.sh` inside the cloned repository, which in turn invokes `tests/run_tests_full.sh` inside the clone (skipping only Section 8 via `PIXEL_TESTS_NO_CLONE=1` but running all 30 other sections inside the nested clone subshell).
   - This doubles the memory footprint and execution duration during full gate runs, exacerbating the risk of cgroup/timeout Signal 9 termination.

4. **Missing `--json` Propagation in `ci-local.sh`**:
   - In `scripts/ci-local.sh` line 122, `run_step "full harness" bash tests/run_tests.sh` invokes the test harness without forwarding `--json` or `--format json` when `AS_JSON=1`.
   - If `tests/run_tests.sh` is called without `--json` while `ci-local.sh` is in JSON mode, `run_tests.sh` prints unstructured text to `stdout` and never emits a structured JSON summary.

---

## 3. Remediation Strategy & Action Plan

To establish stable, interruption-safe, clean-clone reproducible, and fully documented behavior across text and JSON modes, we will perform the following systematic repairs across `scripts/ci-local.sh`, `tests/run_tests.sh`, `tests/run_tests_full.sh`, `tests/section-map.tsv`, and supporting checkers:

1. **Durable Log Streaming & JSON Separation (`tests/run_tests.sh` & `scripts/ci-local.sh`)**:
   - Refactor `tests/run_tests.sh` and `scripts/ci-local.sh` when `AS_JSON=1` (or durable logging is requested) to stream diagnostic outputs directly to durable log files (e.g., under `reports/logs/` or `PIXEL_LOG_DIR`) instead of capturing massive outputs in shell variables.
   - Enforce strict separation: when `--json` is active, `stdout` will receive **only** valid, schema-compliant JSON (`tests/run_tests.sh --json` matching `test-result.schema.json` and `ci-local.sh --json` matching `ci-result.schema.json`). All step diagnostics, warning messages, and progress outputs will be routed to `stderr` or durable log files.

2. **Interruption Safety & Non-Zero Exit Guarantee**:
   - Ensure `trap` handlers across `run_tests.sh`, `run_tests_full.sh`, and `ci-local.sh` preserve partial log files, terminate any child/stub processes (`pkill -P $$` or process group cleanup if applicable), and ensure interrupted/timed-out runs exit non-zero and **never** report success in JSON or text summaries.

3. **Conservative `--changed` & Selector Verification**:
   - Audit and harden `tests/run_tests.sh --changed` to ensure conservative check selection across all Git states (untracked, modified, staged, shallow clone, missing base ref, unknown changed-file mappings). If mapping certainty is lost, `--changed` must select broader checks or the full gate (`mode=full`).
   - Ensure targeted runs (`--section`, `--test`, `--tag`, `--changed`) explicitly report `"full_gate": false` in JSON and never claim full-gate completion.
   - Ensure `no-argument "tests/run_tests.sh"` executes the full legacy suite (`mode=full`).

4. **Eliminate Recursive Full-Gate Invocation & Ensure Single-Pass Execution**:
   - Refactor `tests/run_tests_full.sh` Section 8 clean-clone verification to invoke `bash tests/run_tests.sh --section=1,2,3` (or targeted smoke checks) inside the clone rather than triggering a nested full-gate execution of all 31 sections.
   - Ensure the full harness runs exactly once per gate execution.

5. **Security & Evidence Scaffolding Hardening**:
   - Enforce that `evidence/SIGNING-EVIDENCE.json` (or any placeholder/scaffolding evidence) explicitly sets `"valid_for_release": false` and cannot satisfy release completion gates (`scripts/verify-release-bundle.sh` or registry checks).
   - Ensure registry (`section-map.tsv`) and configuration files cannot execute arbitrary commands (`awk` parsing hardened against command injection/backticks).

6. **Sequential Verification Gates & Regression Tests**:
   - Add new regression coverage in `tests/run_tests_full.sh` verifying child failure, interruption handling, malformed registry, duplicate/orphan check IDs, dirty tree, shallow clone, missing base ref, unknown `--changed` mapping, invalid selector, and JSON write failure.
   - Execute verification gates sequentially:
     1. Lightweight checks (`bash -n`, Python syntax, `git diff --check`, `check-*.py`)
     2. Targeted Agent OS checks (`run_tests.sh --section=...`)
     3. Full harness text mode with durable logs (`run_tests.sh`)
     4. `ci-local.sh` text mode
     5. `ci-local.sh --json` (schema validation against `ci-result.schema.json`)
     6. Clean-clone validation (`reports/agent-os-clean-clone-validation.md`)
     7. Final full gate on the committed tree with signed, logical commits.
