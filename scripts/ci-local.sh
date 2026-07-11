#!/usr/bin/env bash
###############################################################################
#  scripts/ci-local.sh — local parity for .github/workflows/test.yml          #
#                                                                             #
#  Runs the same essential gates, in the same order, with no network, no      #
#  secrets, no paid agents, and no repository mutation:                       #
#    1. git diff --check                        (whitespace/conflict markers) #
#    2. bash scripts/update-bootstrap-checksums.sh --check  (checksum gate)   #
#    3. bash -n on every tracked shell script   (syntax)                      #
#    4. shellcheck -S warning on every tracked shell script (skip if absent)  #
#    5. bash tests/run_tests.sh                 (full hermetic suite)         #
#                                                                             #
#  Runnable from any directory. Fail-fast: the first failing gate stops the   #
#  run and its own exit status becomes this script's exit status.             #
#  (Heredocs, not process substitution: /dev/fd is absent on some supported   #
#  environments.)                                                             #
###############################################################################
set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)" \
  || { echo "ci-local: cannot resolve script directory" >&2; exit 1; }
ROOT="$(dirname -- "$SCRIPT_DIR")"
cd "$ROOT" || { echo "ci-local: cannot cd to $ROOT" >&2; exit 1; }

step(){ printf '\n== [%s] %s\n' "$1" "$2"; }
fail(){ printf 'ci-local: FAIL — %s (exit %d)\n' "$1" "$2" >&2; exit "$2"; }
ok(){ printf '   ok %s\n' "$1"; }

shells="$(git ls-files | grep -E '\.sh$')"

step 1/5 "whitespace + conflict markers — git diff --check"
git diff --check || fail "git diff --check" $?
ok "git diff --check"

step 2/5 "checksum manifest lockstep — update-bootstrap-checksums.sh --check"
bash scripts/update-bootstrap-checksums.sh --check || fail "checksum --check" $?
ok "checksum --check"

step 3/5 "shell syntax — bash -n (every tracked shell script)"
n=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  n=$((n+1))
  bash -n "$f" || fail "bash -n $f" $?
done <<EOF
$shells
EOF
ok "bash -n ($n scripts)"

step 4/5 "shellcheck -S warning (every tracked shell script)"
if command -v shellcheck >/dev/null 2>&1; then
  set --
  while IFS= read -r f; do
    [ -n "$f" ] && set -- "$@" "$f"
  done <<EOF
$shells
EOF
  shellcheck -S warning "$@" || fail "shellcheck" $?
  ok "shellcheck"
else
  echo "   skipped — shellcheck not installed (CI installs it; harness gate also self-skips)"
fi

step 5/5 "full test suite — bash tests/run_tests.sh"
bash tests/run_tests.sh || fail "tests/run_tests.sh" $?

printf '\nci-local: ALL GATES PASSED\n'
