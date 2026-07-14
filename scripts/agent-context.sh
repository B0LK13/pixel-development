#!/usr/bin/env bash
###############################################################################
# scripts/agent-context.sh — deterministic, path-aware agent context snapshot #
###############################################################################
set -uo pipefail

FORMAT='markdown'
while [ $# -gt 0 ]; do
  case "$1" in
    --format=*) FORMAT="${1#*=}" ;;
    --format) [ $# -ge 2 ] || { echo "agent-context: --format needs a value" >&2; exit 2; }; FORMAT="$2"; shift ;;
    --help|-h) sed -n '2,4p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "agent-context: unknown argument: $1 (try --help)" >&2; exit 2 ;;
  esac
  shift
done
case "$FORMAT" in markdown|json) ;; *) echo "agent-context: --format must be markdown|json (got '$FORMAT')" >&2; exit 2 ;; esac

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)" || { echo "agent-context: cannot resolve script dir" >&2; exit 1; }
ROOT="$(dirname -- "$SCRIPT_DIR")"
cd "$ROOT" || { echo "agent-context: cannot cd to $ROOT" >&2; exit 1; }

branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
commit="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
dirty='clean'
git diff --quiet --ignore-submodules -- 2>/dev/null || dirty='dirty'
git diff --cached --quiet --ignore-submodules -- 2>/dev/null || dirty='dirty'
remote='none'
if git remote get-url origin >/dev/null 2>&1; then
  remote='origin'
fi
sync_state='unknown'
if [ "$remote" = origin ] && git rev-parse "@{u}" >/dev/null 2>&1; then
  ahead="$(git rev-list --count @{u}..HEAD 2>/dev/null || echo 0)"
  behind="$(git rev-list --count HEAD..@{u} 2>/dev/null || echo 0)"
  sync_state="ahead:$ahead behind:$behind"
fi

changed_files="$( { git diff --name-only --cached 2>/dev/null; git diff --name-only 2>/dev/null; } | awk 'NF' | sort -u )"
[ -n "$changed_files" ] || changed_files='(none)'

nearest_agents_for(){
  local p="$1" d f
  d="$(dirname -- "$p")"
  while :; do
    [ "$d" = "." ] && d=""
    f="${d:+$d/}AGENTS.md"
    if [ -f "$f" ]; then
      printf '%s\n' "$f"
      return 0
    fi
    [ -z "$d" ] && break
    d="$(dirname -- "$d")"
    [ "$d" = "/" ] && break
  done
  printf '%s\n' "AGENTS.md"
}

risk_for(){
  case "$1" in
    .github/*|scripts/*|tests/*|pixel-*.sh) echo high ;;
    docs/*|reports/*|evidence/*|.agent/*|schemas/*) echo medium ;;
    *) echo low ;;
  esac
}

route_for(){
  case "$1" in
    .github/*) echo github-workflows ;;
    tests/*) echo tests ;;
    scripts/*|pixel-*.sh) echo cli-changes ;;
    docs/*) echo documentation ;;
    evidence/*|reports/*) echo evidence-and-reports ;;
    .agent/*|schemas/*|AGENTS.md) echo security-review ;;
    *) echo documentation ;;
  esac
}

required_check_for_route(){
  case "$1" in
    github-workflows) echo "python3 scripts/check-github-action-pins.py; bash tests/run_tests.sh --test workflow.action-pins" ;;
    tests) echo "bash tests/run_tests.sh --changed" ;;
    cli-changes) echo "python3 scripts/check-cli-contracts.py; bash tests/run_tests.sh --tag cli" ;;
    evidence-and-reports) echo "python3 scripts/check-evidence-links.py; python3 scripts/check-doc-command-parity.py" ;;
    security-review) echo "python3 scripts/check-agent-instructions.py; python3 scripts/check-test-registration.py" ;;
    *) echo "bash tests/run_tests.sh --changed" ;;
  esac
}

active_blockers='none'
if [ "$(git rev-parse --is-shallow-repository 2>/dev/null || echo false)" = true ]; then
  active_blockers='shallow-clone (run: git fetch --unshallow)'
fi

recent_reports="$(ls -1t reports/*final-report.md 2>/dev/null | head -5 || true)"
[ -n "$recent_reports" ] || recent_reports='(none)'

operator_only='push/merge/tag/release/deploy, signing-key operations, secret changes, branch-protection changes, force operations'

json_escape(){ printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\n/\\n/g'; }

if [ "$FORMAT" = json ]; then
  printf '{\n'
  printf '  "repository_root": "%s",\n' "$(json_escape "$ROOT")"
  printf '  "branch": "%s",\n' "$(json_escape "$branch")"
  printf '  "commit": "%s",\n' "$(json_escape "$commit")"
  printf '  "remote": "%s",\n' "$(json_escape "$remote")"
  printf '  "working_tree": "%s",\n' "$(json_escape "$dirty")"
  printf '  "active_blockers": "%s",\n' "$(json_escape "$active_blockers")"
  printf '  "operator_only_actions": "%s",\n' "$(json_escape "$operator_only")"
  printf '  "changed_files": ['
  first=1
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    [ "$first" -eq 1 ] || printf ', '
    first=0
    printf '{"path":"%s","risk":"%s","scoped_instruction":"%s","route":"%s","required_checks":"%s"}' \
      "$(json_escape "$f")" "$(json_escape "$(risk_for "$f")")" \
      "$(json_escape "$(nearest_agents_for "$f")")" "$(json_escape "$(route_for "$f")")" \
      "$(json_escape "$(required_check_for_route "$(route_for "$f")")")"
  done <<EOF
$changed_files
EOF
  printf '],\n'
  printf '  "remote_sync": "%s",\n' "$(json_escape "$sync_state")"
  printf '  "recent_reports": ['
  first=1
  while IFS= read -r r; do
    [ -n "$r" ] || continue
    [ "$first" -eq 1 ] || printf ', '
    first=0
    printf '"%s"' "$(json_escape "$r")"
  done <<EOF
$recent_reports
EOF
  printf ']\n}\n'
  exit 0
fi

cat <<EOF
# Agent context

- repository root: \`$ROOT\`
- branch: \`$branch\`
- commit: \`$commit\`
- remote sync: $sync_state
- working tree: **$dirty**
- active blockers: $active_blockers
- operator-only actions: $operator_only

## Changed paths (path-aware context)
EOF
while IFS= read -r f; do
  [ -n "$f" ] || continue
  if [ "$f" = "(none)" ]; then
    echo "- (none)"
  else
    route="$(route_for "$f")"
    echo "- $f"
    echo "  - risk: $(risk_for "$f")"
    echo "  - scoped instruction: $(nearest_agents_for "$f")"
    echo "  - task route: $route"
    echo "  - required checks: $(required_check_for_route "$route")"
  fi
done <<EOF
$changed_files
EOF

cat <<EOF

## Recent reports
EOF
while IFS= read -r r; do
  [ -n "$r" ] || continue
  echo "- $r"
done <<EOF
$recent_reports
EOF
