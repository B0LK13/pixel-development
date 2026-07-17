#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PY="$REPO_ROOT/scripts/supervisor.py"
if [ "$#" -lt 1 ]; then
  echo "usage: $0 start --command '...' | status <id> | list | check <id> | resume <id>"
  exit 2
fi
cmd="$1"; shift
case "$cmd" in
  start)
    # pass through remaining args
    python3 "$PY" start "$@"
    ;;
  status|list|check|resume|init)
    python3 "$PY" "$cmd" "$@"
    ;;
  *)
    echo "unknown subcommand: $cmd" >&2
    exit 2
    ;;
esac
