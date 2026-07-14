#!/usr/bin/env bash
###############################################################################
#  scripts/ci-local.sh — local parity for .github/workflows/test.yml          #
#                                                                             #
#  Default mode: fail-fast, human-readable.                                   #
#  JSON mode: add --json for machine-readable summary (same gates).           #
###############################################################################
set -uo pipefail

AS_JSON=0
while [ $# -gt 0 ]; do
  case "$1" in
    --json) AS_JSON=1 ;;
    --format=json) AS_JSON=1 ;;
    --format) [ $# -ge 2 ] || { echo "ci-local: --format needs a value" >&2; exit 2; }; [ "$2" = json ] || { echo "ci-local: --format must be json" >&2; exit 2; }; AS_JSON=1; shift ;;
    --help|-h) sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "ci-local: unknown argument: $1 (try --help)" >&2; exit 2 ;;
  esac
  shift
done

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)" \
  || { echo "ci-local: cannot resolve script directory" >&2; exit 1; }
ROOT="$(dirname -- "$SCRIPT_DIR")"
cd "$ROOT" || { echo "ci-local: cannot cd to $ROOT" >&2; exit 1; }

START_TS="$(date +%s)"
STEPS=''
LOG_DIR="${PIXEL_LOG_DIR:-$ROOT/reports/logs/ci-local_${START_TS}}"
mkdir -p "$LOG_DIR" 2>/dev/null || {
  echo "ci-local: cannot create log directory $LOG_DIR" >&2
  exit 1
}

INTERRUPTED=0
CHILD_PID=''
EMITTED_JSON=0

emit_json(){
  local rc="$1" end dur
  [ "$AS_JSON" -eq 1 ] || return 0
  [ "$EMITTED_JSON" -eq 0 ] || return 0
  EMITTED_JSON=1
  end="$(date +%s)"; dur="$((end-START_TS))"
  if [ "$INTERRUPTED" -eq 1 ]; then rc=130; fi
  printf '{\n'
  printf '  "exit_code": %s,\n' "$rc"
  printf '  "duration_seconds": %s,\n' "$dur"
  printf '  "log_dir": "%s",\n' "$(json_escape "$LOG_DIR")"
  printf '  "steps": [\n'
  local first=1 name status code
  while IFS='|' read -r name status code; do
    [ -n "${name:-}" ] || continue
    [ "$first" -eq 1 ] || printf ',\n'
    first=0
    printf '    {"name":"%s","status":"%s","exit_code":%s}' \
      "$(json_escape "$name")" "$(json_escape "$status")" "$code"
  done <<EOF
$STEPS
EOF
  printf '\n  ]\n}\n'
}

on_signal(){
  INTERRUPTED=1
  printf 'ci-local: interrupted by signal. Terminating child processes...\n' >&2
  if [ -n "${CHILD_PID:-}" ] && kill -0 "$CHILD_PID" 2>/dev/null; then
    kill -TERM "$CHILD_PID" 2>/dev/null || true
    sleep 0.1
    kill -9 "$CHILD_PID" 2>/dev/null || true
  fi
  pkill -P $$ 2>/dev/null || true
  emit_json 130
  exit 130
}
trap 'on_signal' INT TERM HUP

cleanup(){
  local orig_rc=$?
  if [ -n "${CHILD_PID:-}" ] && kill -0 "$CHILD_PID" 2>/dev/null; then
    kill -TERM "$CHILD_PID" 2>/dev/null || true
    sleep 0.1
    kill -9 "$CHILD_PID" 2>/dev/null || true
  fi
  emit_json "$orig_rc"
  exit "$orig_rc"
}
trap cleanup EXIT

json_escape(){ printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\n/\\n/g'; }
record_step(){ # name status rc
  STEPS="${STEPS}${STEPS:+
}$1|$2|$3"
}

step(){ [ "$AS_JSON" = 1 ] || printf '\n== %s\n' "$1"; }
ok(){ [ "$AS_JSON" = 1 ] || printf '   ok %s\n' "$1"; }
fail(){
  local name="$1" rc="$2"
  record_step "$name" "failed" "$rc"
  printf 'ci-local: FAIL — %s (exit %d)\n' "$name" "$rc" >&2
  if [ -f "$LOG_DIR/$(printf '%s' "$name" | tr -c 'A-Za-z0-9_-' '_').log" ]; then
    printf 'ci-local: partial logs available at: %s\n' "$LOG_DIR/$(printf '%s' "$name" | tr -c 'A-Za-z0-9_-' '_').log" >&2
  fi
  exit "$rc"
}
run_step(){ # name cmd...
  local name="$1"; shift
  step "$name"
  local log_slug
  log_slug="$(printf '%s' "$name" | tr -c 'A-Za-z0-9_-' '_')"
  local log_file="$LOG_DIR/${log_slug}.log"
  local rc=0
  if [ "$AS_JSON" = 1 ]; then
    "$@" > "$log_file" 2>&1 &
    CHILD_PID=$!
    wait "$CHILD_PID" || rc=$?
    CHILD_PID=''
  else
    "$@" 2>&1 | tee "$log_file" &
    CHILD_PID=$!
    wait "$CHILD_PID" || rc=$?
    CHILD_PID=''
  fi
  if [ "$rc" -eq 0 ]; then
    record_step "$name" "ok" 0
    ok "$name"
  else
    fail "$name" "$rc"
  fi
}

shells="$(git ls-files | grep -E '\.sh$' || true)"

run_step "whitespace + conflict markers" git diff --check
run_step "checksum manifest lockstep" bash scripts/update-bootstrap-checksums.sh --check
run_step "GitHub Action pins" python3 scripts/check-github-action-pins.py
run_step "agent instruction drift" python3 scripts/check-agent-instructions.py
run_step "doc command parity" python3 scripts/check-doc-command-parity.py
run_step "evidence links" python3 scripts/check-evidence-links.py
run_step "CLI contract drift" python3 scripts/check-cli-contracts.py
run_step "test registration" python3 scripts/check-test-registration.py
run_step "context freshness" python3 scripts/check-context-freshness.py
run_step "stale claims" python3 scripts/check-stale-claims.py
run_step "agent secret scan" python3 scripts/check-agent-secrets.py
run_step "skill index" python3 scripts/check-skill-index.py

step "shell syntax"
n=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  n=$((n+1))
  bash -n "$f" || fail "shell syntax ($f)" $?
done <<EOF
$shells
EOF
record_step "shell syntax" "ok" 0
ok "bash -n ($n scripts)"

step "shellcheck"
if command -v shellcheck >/dev/null 2>&1; then
  set --
  while IFS= read -r f; do
    [ -n "$f" ] && set -- "$@" "$f"
  done <<EOF
$shells
EOF
  run_step "shellcheck" shellcheck -S warning "$@"
else
  record_step "shellcheck" "skipped" 0
  [ "$AS_JSON" = 1 ] || echo "   skipped — shellcheck not installed (CI installs it; harness gate also self-skips)"
fi

if [ "${PIXEL_CI_SKIP_FULL_HARNESS:-0}" = 1 ]; then
  record_step "full harness" "skipped" 0
  [ "$AS_JSON" = 1 ] || echo "   skipped — PIXEL_CI_SKIP_FULL_HARNESS=1"
else
  if [ "$AS_JSON" = 1 ]; then
    run_step "full harness" bash tests/run_tests.sh --json
  else
    run_step "full harness" bash tests/run_tests.sh
  fi
fi

[ "$AS_JSON" = 1 ] || printf '\nci-local: ALL GATES PASSED\n'
exit 0
