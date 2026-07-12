#!/data/data/com.termux/files/usr/bin/bash
###############################################################################
#  pixel-autodev.sh — autonomous backlog runner (runs INSIDE the devbox)      #
#                                                                             #
#  Reads BACKLOG.md, then works tasks one at a time with a real agent loop:   #
#    per-task git branch → agent edits → repo tests → commit on green only.   #
#  Never auto-pushes. Caps turns + $ per task. Resets cleanly on failure.     #
#                                                                             #
#  Run it from the Ubuntu AI layer:  devbox → bash pixel-autodev.sh           #
#  Usage:                                                                     #
#    bash pixel-autodev.sh [--workspace=DIR] [--backlog=FILE] [--max-tasks=N] #
#         [--max-turns=N] [--budget=USD] [--timeout=SECONDS]                  #
#         [--model=sonnet|opus] [--agent=claude|codex]                        #
#         [--yolo] [--push] [--dry-run] [--yes]                               #
###############################################################################
set -uo pipefail

# ---------------------------------------------------------------------------
# 0. Defaults / flags
# ---------------------------------------------------------------------------
WORKSPACE="${PIXEL_WORKSPACE:-$HOME/pixel-lab}"
BACKLOG=""
MAX_TASKS=3
MAX_TURNS=30
BUDGET="2.00"
TIMEOUT=1200        # per-agent-call wall-clock limit (seconds)
MODEL="sonnet"
AGENT="claude"
# Agent binary override seam — lets tests inject a stub agent without touching
# PATH (defaults resolve to the real installed agents; no behavior change).
# Note: ${VAR-default} (no colon) so an explicitly EMPTY override stays empty —
# preflight then treats the agent as missing. Unset keeps the default binary.
CLAUDE_BIN="${CLAUDE_BIN-claude}"
CODEX_BIN="${CODEX_BIN-codex}"
PMODE="dontAsk"     # CI-safe: no prompts, honors allow/deny lists
PUSH=0; DRY=0
CHARTER="PIXEL_AGENT.md"

for a in "$@"; do case "$a" in
  --workspace=*) WORKSPACE="${a#*=}" ;;
  --backlog=*)   BACKLOG="${a#*=}" ;;
  --max-tasks=*) MAX_TASKS="${a#*=}" ;;
  --max-turns=*) MAX_TURNS="${a#*=}" ;;
  --budget=*)    BUDGET="${a#*=}" ;;
  --timeout=*)   TIMEOUT="${a#*=}" ;;
  --model=*)     MODEL="${a#*=}" ;;
  --agent=*)     AGENT="${a#*=}" ;;
  --yolo)        PMODE="bypassPermissions" ;;
  --push)        PUSH=1 ;;
  --dry-run)     DRY=1 ;;
  --yes|-y)      : ;;  # accepted for CLI parity with pixel-dev-setup.sh (autodev never prompts)
  --help|-h) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) echo "Unknown flag: $a (try --help)"; exit 2 ;;
esac; done
[ -z "$BACKLOG" ] && BACKLOG="$WORKSPACE/BACKLOG.md"

# Validate numeric flags before any environment checks — a usage error is
# exit 2, names the flag on stderr, and touches no state. Validation is pure
# string logic (no arithmetic expansion), so there are no octal/overflow edge
# cases; leading zeros are tolerated (0800 == 800).
bad_value(){ echo "pixel-autodev: $1 must be $2 (got '$3')" >&2; exit 2; }
is_posint(){ # digits only, with at least one non-zero digit
  case "$1" in ''|*[!0-9]*) return 1 ;; esac
  [ -n "${1#"${1%%[!0]*}"}" ]
}
is_posint "$TIMEOUT"    || bad_value --timeout "a positive integer" "$TIMEOUT"
is_posint "$MAX_TURNS"  || bad_value --max-turns "a positive integer" "$MAX_TURNS"
# --max-tasks drives shell arithmetic at the loop bound, so it is canonicalised
# (leading zeros stripped) and range-checked: 1–999999.
is_posint "$MAX_TASKS"  || bad_value --max-tasks "an integer between 1 and 999999" "$MAX_TASKS"
MAX_TASKS="${MAX_TASKS#"${MAX_TASKS%%[!0]*}"}"
[ "${#MAX_TASKS}" -le 6 ] || bad_value --max-tasks "an integer between 1 and 999999" "$MAX_TASKS"
# --budget is decimal dollars passed to the agent CLI; bash never does float
# math with it. Require digits with at most one dot, a digit on each side of
# it, and a non-zero value (rejects "0", "0.00", ".5", "2.", "1.2.3").
case "$BUDGET" in
  ''|*[!0-9.]*|*.*.*|.*|*.) bad_value --budget "a positive number (e.g. 2.00)" "$BUDGET" ;;
esac
[ -n "${BUDGET//[0.]/}" ] || bad_value --budget "a positive number (e.g. 2.00)" "$BUDGET"
# --agent selects the dispatch backend; anything outside the enum is a usage
# error, so an unknown name can never reach command lookup in preflight.
case "$AGENT" in
  claude|codex) ;;
  *) bad_value --agent "one of: claude, codex" "$AGENT" ;;
esac

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_R=$'\033[0m'; C_B=$'\033[1m'; C_DIM=$'\033[2m'
  RED=$'\033[38;5;203m'; BLU=$'\033[38;5;39m'; GRN=$'\033[38;5;42m'; YLW=$'\033[38;5;221m'
else C_R=; C_B=; C_DIM=; RED=; BLU=; GRN=; YLW=; fi
LOG="$WORKSPACE/.autodev/run-$(date +%Y%m%d-%H%M%S).md"
step(){ printf '\n%s%s▌ %s%s\n' "$C_B" "$BLU" "$*" "$C_R"; }
info(){ printf '  %s•%s %s\n' "$BLU" "$C_R" "$*"; }
ok(){   printf '  %s✔%s %s\n' "$GRN" "$C_R" "$*"; }
warn(){ printf '  %s▲%s %s\n' "$YLW" "$C_R" "$*" >&2; }
die(){  printf '\n%s✖ %s%s\n' "$RED" "$*" "$C_R" >&2; exit 1; }
have(){ command -v "$1" >/dev/null 2>&1; }
rec(){  mkdir -p "$(dirname "$LOG")"; printf '%s\n' "$*" >> "$LOG"; }

# Resolve a required dependency to a path, honouring a narrow per-tool
# override seam (TIMEOUT_BIN, GIT_BIN, CLAUDE_BIN, CODEX_BIN):
#   override UNSET           → default PATH resolution (production behaviour)
#   override SET but empty   → treated as missing (lets tests simulate absence)
#   override SET with '/'    → must be an executable file; used as-is
#   override SET, bare name  → resolved through PATH like the default
# The seam only affects detection/reporting — CLI validation runs earlier and
# is never bypassed, and every resolved path is used quoted.
resolve_required_tool(){ # $1 display name  $2 override var name → prints path; rc 1 if unresolvable
  local name="$1" ovar="$2" val path
  if declare -p "$ovar" >/dev/null 2>&1; then
    val="${!ovar}"
    [ -n "$val" ] || return 1
    case "$val" in
      */*) [ -x "$val" ] && { printf '%s\n' "$val"; return 0; }; return 1 ;;
      *) path="$(command -v "$val" 2>/dev/null)" && [ -n "$path" ] && { printf '%s\n' "$path"; return 0; }; return 1 ;;
    esac
  fi
  path="$(command -v "$name" 2>/dev/null)" || return 1
  [ -n "$path" ] && printf '%s\n' "$path"
}

# ---------------------------------------------------------------------------
# 1. Preflight — must be in the glibc devbox, agent authed, git ready
# ---------------------------------------------------------------------------
preflight(){
  step "1. Preflight"
  # Scrub any Termux PATH leak so the guest node/agent win (the codex-shadow bug).
  export PATH="/root/.npm-global/bin:/root/.local/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
  hash -r
  if [ "$DRY" = 1 ]; then
    info "dry-run: skipping agent resolution (no agent is invoked)"
  else
    local agent_bin_var agent_path
    case "$AGENT" in
      claude) agent_bin_var=CLAUDE_BIN ;;
      codex)  agent_bin_var=CODEX_BIN ;;
    esac
    agent_path="$(resolve_required_tool "$AGENT" "$agent_bin_var")" \
      || die "'$AGENT' not found. Enter the devbox and install the AI stack first."
    case "$agent_path" in
      *com.termux*) die "'$AGENT' is resolving to the Termux binary. You are not in the devbox — run: devbox, then retry." ;;
    esac
    ok "agent: $AGENT ($agent_path)"
  fi
  resolve_required_tool timeout TIMEOUT_BIN >/dev/null || die "GNU timeout (coreutils) is required in the devbox — install with: apt-get install -y coreutils"
  have jq || { info "installing jq…"; apt-get install -y -qq jq >/dev/null 2>&1 || warn "jq missing (JSON parse limited)"; }
  resolve_required_tool git GIT_BIN >/dev/null || die "git not installed in devbox — install with: apt-get install -y git"
  [ -d "$WORKSPACE" ] || die "workspace not found: $WORKSPACE (set --workspace=DIR)"
  ok "workspace: $WORKSPACE"
  if [ ! -f "$BACKLOG" ]; then
    warn "no backlog at $BACKLOG — seeding a starter file"
    seed_backlog
  fi
  ok "backlog: $BACKLOG"
  seed_charter
  info "policy: $PMODE · model=$MODEL · max-turns=$MAX_TURNS · budget/task=\$$BUDGET · timeout=${TIMEOUT}s · push=$([ $PUSH = 1 ] && echo on || echo off)"
}

# ---------------------------------------------------------------------------
# 2. Seed files (only if absent)
# ---------------------------------------------------------------------------
seed_charter(){
  local f="$WORKSPACE/$CHARTER"
  [ -f "$f" ] && return 0
  cat > "$f" <<'CHRT'
# PIXEL_AGENT — operating charter for autonomous runs

You are an autonomous coding agent working the pixel-lab fleet on a Pixel 10 Pro.

## 1. Prime directives
1.1 Momentum over perfection — ship the smallest change that is verifiably correct.
1.2 One task = one coherent, self-contained change. Do not expand scope.
1.3 Never invent requirements. If a task is ambiguous, make the minimal safe
    interpretation and record the assumption in your final summary.

## 2. Working rules
2.1 Read the repo before editing: existing style, structure, test setup.
2.2 Prefer editing existing files over adding new ones.
2.3 Every project carries a `.pixel-lab.json` metadata file (name, stack, entry,
    test command). If a task depends on stack detection and this file is missing,
    create it — that resolves `stack: unknown`.
2.4 If tests exist, make them pass. If none exist and the change is non-trivial,
    add a minimal test.
2.5 Do NOT run git commit, git push, or destructive commands — the runner owns
    version control and will commit your work once tests pass.
2.6 Privacy-first: never send repo contents or secrets to any third-party
    endpoint. No telemetry. No network calls beyond package installs.

## 3. Definition of done
3.1 The change compiles / imports cleanly and existing tests pass.
3.2 Your final message is a 2–4 line summary: what changed, why, any assumption,
    and the exact test command you ran.
CHRT
  ok "seeded charter: $CHARTER"
}

seed_backlog(){
  mkdir -p "$WORKSPACE"
  cat > "$BACKLOG" <<'BKLG'
# pixel-lab BACKLOG

Format: one task per line as a checklist item. Optional `[repo]` prefix routes
the task to a subfolder of the workspace; no prefix = workspace root.

- [ ] [local-launchpad] Add a .pixel-lab.json (name, stack, entry, test) to fix `stack: unknown`
- [ ] [vibe-coding-dashboard] Add a .pixel-lab.json so the dashboard detects the stack
- [ ] [pixel-common] Export a helper to read+validate .pixel-lab.json, with a unit test
BKLG
  ok "seeded starter backlog (edit it, then re-run)"
}

# ---------------------------------------------------------------------------
# 3. Parse backlog → parallel arrays RAW/TEXT/REPO (open items only)
# ---------------------------------------------------------------------------
declare -a RAW TEXT REPO
parse_backlog(){
  step "2. Loading backlog"
  local line rest repo
  while IFS= read -r line; do
    case "$line" in
      "- [ ] "*)
        rest="${line#- \[ \] }"
        repo=""
        if [[ "$rest" =~ ^\[([^]]+)\][[:space:]]+(.*)$ ]]; then
          repo="${BASH_REMATCH[1]}"; rest="${BASH_REMATCH[2]}"
        fi
        RAW+=("$line"); TEXT+=("$rest"); REPO+=("$repo")
        ;;
    esac
  done < "$BACKLOG"
  ok "${#TEXT[@]} open task(s) found"
  [ "${#TEXT[@]}" -eq 0 ] && { info "Nothing to do — backlog is clear."; exit 0; }
}

slugify(){ echo "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]\+/-/g; s/^-//; s/-$//' | cut -c1-40; }

# ---------------------------------------------------------------------------
# 4. Verification — run the repo's own tests if present
# ---------------------------------------------------------------------------
run_tests(){ # cwd = repo
  if [ -f .pixel-lab.json ] && have jq; then
    local t; t="$(jq -r '.test // empty' .pixel-lab.json 2>/dev/null)"
    [ -n "$t" ] && { info "test: $t"; bash -c "$t"; return $?; }
  fi
  if [ -f package.json ] && jq -e '.scripts.test' package.json >/dev/null 2>&1; then
    info "test: npm test"; npm test --silent; return $?
  fi
  if [ -f pyproject.toml ] || ls tests/ >/dev/null 2>&1; then
    have pytest && { info "test: pytest -q"; pytest -q; return $?; }
  fi
  if [ -f justfile ] && just --summary 2>/dev/null | grep -qw test; then
    info "test: just test"; just test; return $?
  fi
  info "no tests found — treating as pass (change is its own verification)"
  return 0
}

# ---------------------------------------------------------------------------
# 5. Drive one task
# ---------------------------------------------------------------------------
mark_done(){ # $1 raw line
  local tmp; tmp="$(mktemp)"
  while IFS= read -r l; do
    if [ "$l" = "$1" ]; then echo "${l/- \[ \]/- [x]}"; else echo "$l"; fi
  done < "$BACKLOG" > "$tmp" && mv "$tmp" "$BACKLOG"
}

agent_run(){ # $1 repo_dir  $2 prompt_file
  local dir="$1" pf="$2"
  local allow="Read,Edit,Write,Glob,Grep,Bash(npm *),Bash(pnpm *),Bash(yarn *),Bash(node *),Bash(python *),Bash(python3 *),Bash(pytest *),Bash(uv *),Bash(pip *),Bash(just *),Bash(make *),Bash(cargo *),Bash(go *),Bash(ls *),Bash(cat *),Bash(mkdir *),Bash(cp *),Bash(mv *),Bash(rg *),Bash(git status *),Bash(git diff *),Bash(git log *)"
  local deny="Bash(git push *),Bash(git commit *),Bash(git reset *),Bash(git checkout *),Bash(rm -rf *),Bash(sudo *),Bash(curl * | *),WebFetch"
  ( cd "$dir" || exit 90
    if [ "$AGENT" = "codex" ]; then
      timeout "$TIMEOUT" "$CODEX_BIN" exec --full-auto "$(cat "$pf")" 2>&1
    else
      timeout "$TIMEOUT" "$CLAUDE_BIN" -p "$(cat "$pf")" \
        --output-format json --model "$MODEL" \
        --permission-mode "$PMODE" \
        --allowedTools "$allow" --disallowedTools "$deny" \
        --max-turns "$MAX_TURNS" --max-budget-usd "$BUDGET" \
        --append-system-prompt "Follow $CHARTER in the workspace. Do not commit or push."
    fi )
}

do_task(){ # $1 index
  local i="$1"
  local text="${TEXT[$i]}" repo="${REPO[$i]}" raw="${RAW[$i]}"
  local dir="$WORKSPACE"; [ -n "$repo" ] && dir="$WORKSPACE/$repo"
  local slug; slug="$(slugify "$text")"
  step "Task $((i+1)): ${repo:+[$repo] }$text"
  rec "## Task: $text"; rec "- repo: ${repo:-<root>}  · started: $(date '+%F %T')"

  [ -d "$dir" ] || { warn "repo dir missing: $dir — skipped"; rec "- SKIP: dir missing"; return 1; }
  ( cd "$dir" && git rev-parse --git-dir >/dev/null 2>&1 ) || { warn "not a git repo: $dir — skipped"; rec "- SKIP: not git"; return 1; }
  if [ -n "$(cd "$dir" && git status --porcelain)" ]; then
    warn "working tree dirty in $dir — skipping to avoid clobbering your changes"; rec "- SKIP: dirty tree"; return 1
  fi

  if [ "$DRY" = 1 ]; then info "[dry-run] would branch auto/$slug and dispatch agent"; rec "- DRY-RUN"; return 0; fi

  local base; base="$(cd "$dir" && git branch --show-current)"
  ( cd "$dir" && git switch -c "auto/$slug" >/dev/null 2>&1 || git switch "auto/$slug" >/dev/null 2>&1 )

  local pf; pf="$(mktemp)"
  # Backlog text is DATA, never code: every backlog-derived value ($text, and
  # $dir via the [repo] prefix) goes through printf %s, and the static body is
  # a quoted heredoc — no expansion of $(...)/backticks in task text can ever
  # occur, even after future edits to this block. Pinned by tests §6f.
  {
    printf 'Task from BACKLOG.md: %s\n\n' "$text"
    printf 'Work in the current repository (%s). Read %s/%s and follow it.\n' "$dir" "$WORKSPACE" "$CHARTER"
    cat <<'EOF'
Make the smallest verified change that completes the task. Run the project's
tests if any exist. Do not commit, push, or run destructive git commands —
version control is handled for you. End with a 2–4 line summary.
EOF
  } > "$pf"

  info "dispatching agent (max-turns=$MAX_TURNS, budget=\$$BUDGET)…"
  local out; out="$(agent_run "$dir" "$pf")"; local rc=$?
  rm -f "$pf"
  local summary cost; summary=""; cost=""
  if [ "$AGENT" = "claude" ] && have jq && printf '%s' "$out" | jq -e . >/dev/null 2>&1; then
    summary="$(printf '%s' "$out" | jq -r '.result // empty')"
    cost="$(printf '%s' "$out" | jq -r '.total_cost_usd // empty')"
  else summary="$out"; fi
  rec "- agent rc=$rc  cost=\$${cost:-?}"
  rec "- summary: ${summary:0:600}"

  if [ $rc -ne 0 ]; then
    if [ $rc -eq 124 ]; then
      warn "agent timed out after ${TIMEOUT}s (rc=124) — reverting branch"
      rec "- RESULT: FAILED (timeout after ${TIMEOUT}s)"
    else
      warn "agent errored (rc=$rc) — reverting branch"
      rec "- RESULT: FAILED (agent)"
    fi
    ( cd "$dir" && git checkout -- . 2>/dev/null; git switch "$base" 2>/dev/null; git branch -D "auto/$slug" 2>/dev/null )
    return 1
  fi

  if [ -z "$(cd "$dir" && git status --porcelain)" ]; then
    warn "agent made no changes — leaving task open"
    ( cd "$dir" && git switch "$base" 2>/dev/null; git branch -D "auto/$slug" 2>/dev/null )
    rec "- RESULT: NO-OP"; return 1
  fi

  info "verifying…"
  if ( cd "$dir" && run_tests ); then
    if ( cd "$dir" && git add -A && git commit -q -m "feat(auto): $text" ); then
      [ "$PUSH" = 1 ] && ( cd "$dir" && git push -u origin "auto/$slug" 2>/dev/null && info "pushed auto/$slug" || warn "push failed" )
      mark_done "$raw"
      ok "task complete → branch auto/$slug${cost:+  (\$$cost)}"
      rec "- RESULT: DONE on auto/$slug"; return 0
    fi
    # commit failed (e.g. broken signing config): never claim done — the
    # task stays open and the branch keeps the agent's work for review
    warn "commit failed — task stays open; branch auto/$slug kept with the agent's work for manual review"
    rec "- RESULT: COMMIT FAILED (branch kept)"; return 1
  else
    warn "tests failed — keeping branch auto/$slug for review, task stays open"
    if ( cd "$dir" && git add -A && git commit -q -m "wip(auto): $text (tests failing)" ); then
      ( cd "$dir" && git switch "$base" 2>/dev/null )
      rec "- RESULT: TESTS FAILED (branch kept)"; return 1
    fi
    warn "wip commit also failed — branch auto/$slug left checked out with uncommitted work"
    rec "- RESULT: TESTS FAILED + COMMIT FAILED (branch kept)"; return 1
  fi
}

# ---------------------------------------------------------------------------
main(){
  printf '%s%s▌ PIXEL // AUTODEV%s  %s%s%s\n' "$C_B" "$RED" "$C_R" "$C_DIM" "autonomous backlog runner" "$C_R"
  preflight
  parse_backlog
  rec "# autodev run $(date '+%F %T')"; rec "workspace=$WORKSPACE agent=$AGENT model=$MODEL policy=$PMODE"
  local done=0 fail=0 n="${#TEXT[@]}"
  [ "$MAX_TASKS" -lt "$n" ] && n="$MAX_TASKS"
  step "3. Working up to $n task(s)"
  local i
  for ((i=0; i<n; i++)); do
    if do_task "$i"; then done=$((done+1)); else fail=$((fail+1)); fi
  done

  step "4. Summary"
  ok "completed: $done   ·   open/failed: $fail   ·   log: $LOG"
  printf '  %sReview:%s cd %s && git branch --list "auto/*"   ·   inspect diffs before merging.\n' "$C_B" "$C_R" "$WORKSPACE"
  [ "$PUSH" = 0 ] && info "Nothing was pushed. Merge locally, or re-run with --push."
  printf '\n%s%s✔ Autodev pass finished.%s\n' "$C_B" "$GRN" "$C_R"
}
main "$@"
