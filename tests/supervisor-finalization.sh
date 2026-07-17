#!/usr/bin/env bash
set -euo pipefail
DB=reports/run-supervision/supervisor.db
# Ensure DB exists
if [ ! -f "$DB" ]; then
  echo "DB missing: $DB" >&2
  exit 2
fi
# 1) Completion case
OUT=$(python3 scripts/supervisor.py start --command 'sleep 1' --workdir /tmp/test-final-1 --timeout 5 --grace 1)
RUN_UUID=$(echo "$OUT" | sed -n 's/.*"run_uuid": "\([^"]*\)".*/\1/p')
sleep 2
jq . reports/run-supervision/$RUN_UUID/monitor.finalization.json >/dev/null
# 2) Failure case
OUT=$(python3 scripts/supervisor.py start --command "bash -c 'exit 7'" --workdir /tmp/test-final-2 --timeout 5 --grace 1)
RUN_UUID=$(echo "$OUT" | sed -n 's/.*"run_uuid": "\([^"]*\)".*/\1/p')
sleep 2
jq . reports/run-supervision/$RUN_UUID/monitor.finalization.json >/dev/null
# 3) Injected retry case
SUPERVISOR_INJECT_FINALIZE_ERROR=1 python3 scripts/supervisor.py start --command 'sleep 1' --workdir /tmp/test-final-3 --timeout 5 --grace 1 >/dev/null 2>&1 || true
# give monitor time to finalize (avoid race on fast test runner)
sleep 2
# find last run dir
LAST=$(ls -1tr reports/run-supervision | tail -1)
jq . reports/run-supervision/$LAST/monitor.finalization.json >/dev/null
echo "supervisor-finalization: OK"
