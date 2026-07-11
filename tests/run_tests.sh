#!/usr/bin/env bash
###############################################################################
#  tests/run_tests.sh — verification gate for the pixel-development kit.      #
#                                                                             #
#  Pure bash, no dependencies. Uses shellcheck / git when available.          #
#  Covers: required files · bash -n syntax · shellcheck (warning+, including  #
#  this harness) · --help/flag contract · .pixel-lab.json validity ·          #
#  pixel-autodev.sh behaviour (dry-run, seeding, --timeout contract,          #
#  end-to-end success/timeout paths via stub agents) · CLI contract extras ·  #
#  clean-clone smoke. Hermetic: no network, no paid agents, no repo writes.   #
#                                                                             #
#  Usage: bash tests/run_tests.sh        (exit 0 = all green)                 #
#  Set PIXEL_TESTS_NO_CLONE=1 to skip the nested clean-clone smoke test.      #
###############################################################################
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || { echo "cannot cd to repo root: $ROOT" >&2; exit 1; }

PASS=0; FAIL=0; SKIP=0
t_ok(){   PASS=$((PASS+1)); printf '  ok    %s\n' "$1"; }
t_fail(){ FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | head -20 | sed 's/^/        /'; }
t_skip(){ SKIP=$((SKIP+1)); printf '  skip  %s\n' "$1"; }

SCRIPTS=(pixel-bootstrap.sh pixel-dev-setup.sh pixel-apps-setup.sh pixel-autodev.sh)

echo "== pixel-development test suite =="

# --- 0. Required files --------------------------------------------------------
for f in "${SCRIPTS[@]}" .pixel-lab.json; do
  if [ -f "$f" ]; then t_ok "required file present: $f"; else t_fail "required file missing: $f"; fi
done

# --- 1. Syntax ----------------------------------------------------------------
for s in "${SCRIPTS[@]}"; do
  if err="$(bash -n "$s" 2>&1)"; then t_ok "syntax: $s"; else t_fail "syntax: $s" "$err"; fi
done

# --- 2. Shellcheck (severity warning and up), including this harness -----------
if command -v shellcheck >/dev/null 2>&1; then
  for s in "${SCRIPTS[@]}" tests/run_tests.sh; do
    if out="$(shellcheck -S warning "$s" 2>&1)"; then t_ok "shellcheck: $s"; else t_fail "shellcheck: $s" "$out"; fi
  done
else
  t_skip "shellcheck not installed — lint gate skipped (pkg install shellcheck)"
fi

# --- 3. --help / unknown-flag contract ------------------------------------------
for s in "${SCRIPTS[@]}"; do
  out="$(bash "$s" --help 2>&1)"; rc=$?
  if [ $rc -eq 0 ] && [ -n "$out" ]; then t_ok "--help exits 0 with usage: $s"; else t_fail "--help: $s" "rc=$rc"; fi
  bash "$s" --definitely-not-a-flag >/dev/null 2>&1; rc=$?
  if [ $rc -eq 2 ]; then t_ok "unknown flag exits 2: $s"; else t_fail "unknown flag: $s" "rc=$rc (want 2)"; fi
done

# --- 4. .pixel-lab.json validity ------------------------------------------------
if command -v jq >/dev/null 2>&1; then
  if jq -e '.name and .stack and .test' .pixel-lab.json >/dev/null 2>&1; then
    t_ok ".pixel-lab.json declares name/stack/test"
  else
    t_fail ".pixel-lab.json missing name/stack/test (or malformed JSON)"
  fi
else
  t_skip "jq not installed — .pixel-lab.json check skipped"
fi

# --- shared fixtures ------------------------------------------------------------
# Temp root intentionally contains a space to prove quoting works everywhere.
tmp="$(mktemp -d "${TMPDIR:-/tmp}/pixel tests.XXXXXX")"
cleanup(){ [ -n "${tmp:-}" ] && [ -d "$tmp" ] && rm -rf "$tmp"; }
trap cleanup EXIT

mkdir -p "$tmp/bin"
# stub agents/tools so the suite is hermetic on any host (CI may lack them).
# autodev's preflight resolves these by name; agent dispatch itself goes
# through the CLAUDE_BIN/CODEX_BIN seams, so no real agent is ever invoked.
for tool in claude codex; do
  printf '#!/usr/bin/env bash\nexit 0\n' > "$tmp/bin/$tool"
  chmod +x "$tmp/bin/$tool"
done
# jq stub: drains stdin, exits 1 ("not valid JSON") so autodev never tries to
# apt-get install jq (no network) and falls back to plain-text summaries.
printf '#!/usr/bin/env bash\ncat >/dev/null 2>&1\nexit 1\n' > "$tmp/bin/jq"
chmod +x "$tmp/bin/jq"
APATH="$tmp/bin:$PATH"

# mk_ws <dir>: fixture git workspace with a clean tree (repo-local identity,
# committed charter + .gitignore). Caller then writes BACKLOG.md and commits.
mk_ws(){
  local d="$1"; mkdir -p "$d"; git -C "$d" init -q 2>/dev/null
  git -C "$d" config user.name t; git -C "$d" config user.email t@t
  printf '# test charter\n' > "$d/PIXEL_AGENT.md"
  printf '.autodev/\n' > "$d/.gitignore"
  git -C "$d" add -A && git -C "$d" commit -qm init >/dev/null
}

# --- 5. pixel-autodev.sh dry-run behaviour --------------------------------------
# 5a. parses an open task, would cut a slug branch, leaves backlog alone
ws="$tmp/ws1"; mk_ws "$ws"
printf -- '- [ ] Add a .pixel-lab.json to fix stack detection\n' > "$ws/BACKLOG.md"
git -C "$ws" add -A && git -C "$ws" commit -qm task >/dev/null
out="$(PATH="$APATH" bash "$ROOT/pixel-autodev.sh" --dry-run --workspace="$ws" 2>&1)"; rc=$?
if [ $rc -eq 0 ] && case "$out" in *auto/add-a-pixel-lab-json*) true;; *) false;; esac; then
  t_ok "autodev --dry-run parses task and slugifies branch"
else
  t_fail "autodev --dry-run" "rc=$rc"$'\n'"$out"
fi
if grep -q '^- \[ \] Add a .pixel-lab.json' "$ws/BACKLOG.md"; then
  t_ok "dry-run leaves the backlog untouched"
else
  t_fail "dry-run must not modify the backlog"
fi

# 5b. absent backlog/charter are seeded, run still exits 0
ws2="$tmp/ws2"; mkdir -p "$ws2"
out="$(PATH="$APATH" bash "$ROOT/pixel-autodev.sh" --dry-run --workspace="$ws2" --max-tasks=1 2>&1)"; rc=$?
if [ $rc -eq 0 ] && [ -f "$ws2/BACKLOG.md" ] && [ -f "$ws2/PIXEL_AGENT.md" ]; then
  t_ok "autodev seeds BACKLOG.md + PIXEL_AGENT.md when absent"
else
  t_fail "autodev seeding" "rc=$rc"$'\n'"$out"
fi

# --- 6. --timeout contract --------------------------------------------------------
# 6a. invalid values fail fast (exit 2 + clear message) BEFORE preflight —
#     proven by pointing at a workspace that does not exist.
for bad in "--timeout=0" "--timeout=-5" "--timeout=abc" "--timeout="; do
  err="$(bash "$ROOT/pixel-autodev.sh" "$bad" --workspace=/nonexistent-pixel-ws 2>&1)"; rc=$?
  if [ $rc -eq 2 ] && case "$err" in *"positive integer"*) true;; *) false;; esac; then
    t_ok "rejects invalid $bad (exit 2, clear message)"
  else
    t_fail "invalid $bad must exit 2 with a message" "rc=$rc"$'\n'"$err"
  fi
done

# 6b. value resolution shown in the dry-run policy line
ws6="$tmp/ws6"; mk_ws "$ws6"
printf -- '- [ ] Placeholder timeout-resolution task\n' > "$ws6/BACKLOG.md"
git -C "$ws6" add -A && git -C "$ws6" commit -qm task >/dev/null
check_policy(){ # $1 expected substring, rest = extra flags
  local want="$1"; shift
  out="$(PATH="$APATH" bash "$ROOT/pixel-autodev.sh" --dry-run --workspace="$ws6" "$@" 2>&1)"; rc=$?
  if [ $rc -eq 0 ] && case "$out" in *"$want"*) true;; *) false;; esac; then
    t_ok "policy line shows $want"
  else
    t_fail "policy line must show $want" "rc=$rc"$'\n'"$out"
  fi
}
check_policy "timeout=1200s"                          # default
check_policy "timeout=45s"  --timeout=45              # explicit valid value
check_policy "timeout=90s"  --timeout=10 --timeout=90 # duplicate flags: last wins
check_policy "timeout=99999999s" --timeout=99999999   # very large value accepted

# 6c. the timeout mechanism itself enforces (short deterministic fixture)
if command -v timeout >/dev/null 2>&1; then
  timeout 1 sleep 30; rc=$?
  if [ $rc -eq 124 ]; then t_ok "timeout(1) enforces limit, returns 124"; else t_fail "timeout mechanism" "rc=$rc"; fi
else
  t_skip "timeout(1) not available on this platform"
fi

# 6d. both agent backends run under the same resolved timeout value
n="$(grep -c 'timeout "\$TIMEOUT"' "$ROOT/pixel-autodev.sh")"
if [ "$n" -eq 2 ]; then t_ok "claude + codex both wrapped in timeout \"\$TIMEOUT\""; else t_fail "timeout wiring" "found $n wrapped call(s), want 2"; fi

# 6e. end-to-end success path with a stub agent (hermetic — no paid calls)
printf '#!/usr/bin/env bash\necho fake-change > agent-made-change.txt\necho "fake claude: made one change"\nexit 0\n' > "$tmp/bin/fake-claude"
chmod +x "$tmp/bin/fake-claude"
ws7="$tmp/ws7"; mk_ws "$ws7"
printf -- '- [ ] Probe autonomous success path\n' > "$ws7/BACKLOG.md"
git -C "$ws7" add -A && git -C "$ws7" commit -qm task >/dev/null
out="$(env PATH="$APATH" CLAUDE_BIN="$tmp/bin/fake-claude" bash "$ROOT/pixel-autodev.sh" --workspace="$ws7" --timeout=30 2>&1)"; rc=$?
last="$(git -C "$ws7" log --format=%s -1 2>/dev/null)"
if [ $rc -eq 0 ] && [ "$last" = "feat(auto): Probe autonomous success path" ] \
   && grep -q '^- \[x\] Probe autonomous success path' "$ws7/BACKLOG.md"; then
  t_ok "success path: stub agent committed on green, backlog flipped"
else
  t_fail "autodev success path" "rc=$rc last=$last"$'\n'"$out"
fi

# 6f. end-to-end timeout path per backend (stub sleeps past a 1s limit)
printf '#!/usr/bin/env bash\nsleep 30\nexit 0\n' > "$tmp/bin/slow-agent"
chmod +x "$tmp/bin/slow-agent"
timeout_case(){ # $1 ws-dir  $2 task  $3 agent(claude|codex)
  local w="$1" task="$2" agent="$3"
  mk_ws "$w"
  printf -- '- [ ] %s\n' "$task" > "$w/BACKLOG.md"
  git -C "$w" add -A && git -C "$w" commit -qm task >/dev/null
  if [ "$agent" = codex ]; then
    out="$(env PATH="$APATH" CODEX_BIN="$tmp/bin/slow-agent" bash "$ROOT/pixel-autodev.sh" --workspace="$w" --agent=codex --timeout=1 2>&1)"; rc=$?
  else
    out="$(env PATH="$APATH" CLAUDE_BIN="$tmp/bin/slow-agent" bash "$ROOT/pixel-autodev.sh" --workspace="$w" --timeout=1 2>&1)"; rc=$?
  fi
  if [ $rc -eq 0 ] && case "$out" in *"timed out after 1s"*) true;; *) false;; esac \
     && [ -z "$(git -C "$w" branch --list 'auto/*')" ] \
     && grep -q "^- \[ \] $task" "$w/BACKLOG.md"; then
    t_ok "$agent backend: 1s timeout kills stub, branch reverted, task stays open"
  else
    t_fail "$agent timeout path" "rc=$rc"$'\n'"$out"
  fi
}
timeout_case "$tmp/ws8" "Probe claude timeout path" claude
timeout_case "$tmp/ws9" "Probe codex timeout path" codex

# --- 7. CLI contract extras (document current behaviour) -------------------------
# space-form value flags are NOT supported (equals syntax only) → usage error
bash "$ROOT/pixel-apps-setup.sh" --ssh-port 9022 >/dev/null 2>&1; rc=$?
if [ $rc -eq 2 ]; then t_ok "apps-setup '--ssh-port 9022' (space form) rejected with exit 2"; else t_fail "--ssh-port space form" "rc=$rc (want 2)"; fi
# bare value flags without '=' are treated as unknown flags
bash "$ROOT/pixel-autodev.sh" --timeout >/dev/null 2>&1; rc=$?
if [ $rc -eq 2 ]; then t_ok "autodev bare '--timeout' rejected with exit 2"; else t_fail "bare --timeout" "rc=$rc (want 2)"; fi
bash "$ROOT/pixel-bootstrap.sh" --repo-base >/dev/null 2>&1; rc=$?
if [ $rc -eq 2 ]; then t_ok "bootstrap bare '--repo-base' rejected with exit 2"; else t_fail "bare --repo-base" "rc=$rc (want 2)"; fi
# '--' is not special-cased today → unknown flag (documented, not changed)
bash "$ROOT/pixel-bootstrap.sh" -- >/dev/null 2>&1; rc=$?
if [ $rc -eq 2 ]; then t_ok "bootstrap '--' currently rejected as unknown flag"; else t_fail "'--' handling" "rc=$rc (want 2)"; fi

# --- 9. --ssh-port contract (pixel-apps-setup.sh) --------------------------------
# Throwaway HOME (with a space): any side effect (the log file) becomes
# observable. Valid ports pass validation and reach the Termux preflight,
# which exits 1 outside Termux — that distinguishes "accepted" from exit 2.
apps_home="$tmp/apps home"; mkdir -p "$apps_home"
run_apps(){ env HOME="$apps_home" bash "$ROOT/pixel-apps-setup.sh" "$@"; }

# 9a. invalid ports: exit 2, flag named on stderr, nothing on stdout.
#     Decided contract: empty / non-numeric / signed / zero / >65535 / >5 digits
#     / whitespace / shell metacharacters are all usage errors.
for bad in "--ssh-port=0" "--ssh-port=65536" "--ssh-port=-1" "--ssh-port=abc" \
           "--ssh-port=" "--ssh-port=22x" "--ssh-port= 22" "--ssh-port=22;reboot" \
           "--ssh-port=+22" "--ssh-port=99999" "--ssh-port=100000"; do
  out="$(run_apps "$bad" 2>"$tmp/err")"; rc=$?; err="$(cat "$tmp/err")"
  if [ $rc -eq 2 ] && [ -z "$out" ] && case "$err" in *"--ssh-port"*) true;; *) false;; esac; then
    t_ok "rejects invalid $bad (exit 2, stderr names flag)"
  else
    t_fail "invalid $bad" "rc=$rc stdout=$out stderr=$err"
  fi
done
if [ ! -f "$apps_home/pixel-apps-setup.log" ]; then
  t_ok "invalid ports create no log file (validation precedes side effects)"
else
  t_fail "invalid ports must not create the log file"
fi

# 9b. valid ports pass validation and reach the Termux preflight (exit 1 here).
#     Decided contract: leading zeros are tolerated (08022/008022 == 8022),
#     same convention as --timeout.
for good in "--ssh-port=1" "--ssh-port=22" "--ssh-port=65535" "--ssh-port=8022" \
            "--ssh-port=08022" "--ssh-port=008022"; do
  out="$(run_apps "$good" 2>&1)"; rc=$?
  if [ $rc -eq 1 ] && case "$out" in *"Run inside Termux"*) true;; *) false;; esac; then
    t_ok "accepts $good (validation passed, reached preflight)"
  else
    t_fail "valid $good" "rc=$rc"$'\n'"$out"
  fi
done

# 9c. duplicate flags: parser semantics are last-wins (documented). The FINAL
#     value is what gets validated — an earlier bad value is overwritten.
out="$(run_apps --ssh-port=1000 --ssh-port=2000 2>&1)"; rc=$?
if [ $rc -eq 1 ]; then t_ok "duplicate --ssh-port accepted (last-wins, documented)"; else t_fail "duplicate --ssh-port" "rc=$rc"; fi
out="$(run_apps --ssh-port=abc --ssh-port=2000 2>&1)"; rc=$?
if [ $rc -eq 1 ]; then t_ok "duplicate --ssh-port: later valid overrides earlier invalid"; else t_fail "duplicate ssh-port valid-last" "rc=$rc"; fi
err="$(run_apps --ssh-port=2000 --ssh-port=abc 2>&1 >/dev/null)"; rc=$?
if [ $rc -eq 2 ]; then t_ok "duplicate --ssh-port: later invalid rejected (last-wins validated)"; else t_fail "duplicate ssh-port invalid-last" "rc=$rc"; fi

# --- 8. clean-clone smoke (fast, hermetic, non-recursive) -------------------------
if [ "${PIXEL_TESTS_NO_CLONE:-0}" = 1 ]; then
  t_skip "clean-clone smoke (nested run)"
else
  clone="$tmp/clean clone"
  if git clone -q --local "$ROOT" "$clone" 2>/dev/null \
     && ( cd "$clone" && PIXEL_TESTS_NO_CLONE=1 bash tests/run_tests.sh >/dev/null 2>&1 ); then
    t_ok "clean-clone smoke: suite passes from a fresh clone"
  else
    t_fail "clean-clone smoke: suite must pass from a fresh clone"
  fi
fi

# --- 10. numeric flag contract (pixel-autodev.sh) --------------------------------
# 10a-c. malformed values are usage errors (exit 2, flag named on stderr) BEFORE
#        preflight — proven by a workspace that does not exist (preflight would
#        die exit 1 there). Matrix covers zero / negative / non-numeric / empty /
#        whitespace / shell metacharacters per flag.
badnum(){ # $1 flag  $2 value
  err="$(bash "$ROOT/pixel-autodev.sh" "$1=$2" --workspace=/nonexistent-pixel-ws 2>&1 >/dev/null)"; rc=$?
  if [ $rc -eq 2 ] && case "$err" in *"$1"*) true;; *) false;; esac; then
    t_ok "rejects invalid $1='$2' (exit 2 before preflight, stderr names flag)"
  else
    t_fail "invalid $1='$2'" "rc=$rc stderr=$err"
  fi
}
for v in 0 -1 abc "" " 3" "3;rm" 1000000; do badnum --max-tasks "$v"; done
for v in 0 -5 abc "" "1x";        do badnum --max-turns "$v"; done
for v in "" abc -1 0 0.00 1.2.3 .5 2. "1;rm"; do badnum --budget "$v"; done
badnum --timeout 000   # all-zeros: not positive

# 10d. octal/overflow edge: leading zeros are TOLERATED (documented --timeout
#      convention) — "08" must not trip shell arithmetic. Pass-through unchanged.
ws10="$tmp/ws10"; mk_ws "$ws10"
printf -- '- [ ] Placeholder numeric-resolution task\n' > "$ws10/BACKLOG.md"
git -C "$ws10" add -A && git -C "$ws10" commit -qm task >/dev/null
out="$(PATH="$APATH" bash "$ROOT/pixel-autodev.sh" --dry-run --workspace="$ws10" --timeout=08 2>&1)"; rc=$?
if [ $rc -eq 0 ] && case "$out" in *"timeout=08s"*) true;; *) false;; esac; then
  t_ok "--timeout=08 accepted (leading zeros tolerated, no octal trap)"
else
  t_fail "--timeout=08" "rc=$rc"$'\n'"$out"
fi

# 10e. valid values resolve and are observable in the dry-run policy line
check_policy10(){ # $1 expected substring, rest = flags
  local want="$1"; shift
  out="$(PATH="$APATH" bash "$ROOT/pixel-autodev.sh" --dry-run --workspace="$ws10" "$@" 2>&1)"; rc=$?
  if [ $rc -eq 0 ] && case "$out" in *"$want"*) true;; *) false;; esac; then
    t_ok "policy line shows $want"
  else
    t_fail "policy line must show $want" "rc=$rc"$'\n'"$out"
  fi
}
check_policy10 "max-turns=7"          --max-turns=7
check_policy10 "max-turns=7"          --max-turns=5 --max-turns=7   # duplicate: last wins
check_policy10 'budget/task=$0.50'    --budget=0.50
check_policy10 'budget/task=$2.00'    --budget=2.00
check_policy10 'budget/task=$10'      --budget=10
check_policy10 "max-turns=030"        --max-turns=030               # leading zeros pass through

# 10f. --max-tasks drives the loop bound — canonicalised so "08" is 8, not an
#      octal error. 10 open tasks + --max-tasks=08 → works exactly 8.
ws11="$tmp/ws11"; mk_ws "$ws11"
for i in 1 2 3 4 5 6 7 8 9 10; do printf -- '- [ ] task %s\n' "$i"; done > "$ws11/BACKLOG.md"
git -C "$ws11" add -A && git -C "$ws11" commit -qm tasks >/dev/null
out="$(PATH="$APATH" bash "$ROOT/pixel-autodev.sh" --dry-run --workspace="$ws11" --max-tasks=08 2>&1)"; rc=$?
if [ $rc -eq 0 ] && case "$out" in *"Working up to 8 task(s)"*) true;; *) false;; esac; then
  t_ok "--max-tasks=08 canonicalised to 8 (octal-safe loop bound)"
else
  t_fail "--max-tasks=08" "rc=$rc"$'\n'"$out"
fi
out="$(PATH="$APATH" bash "$ROOT/pixel-autodev.sh" --dry-run --workspace="$ws11" --max-tasks=9 --max-tasks=1 2>&1)"; rc=$?
if [ $rc -eq 0 ] && case "$out" in *"Working up to 1 task(s)"*) true;; *) false;; esac; then
  t_ok "duplicate --max-tasks: last wins (9 then 1 → 1)"
else
  t_fail "duplicate --max-tasks" "rc=$rc"$'\n'"$out"
fi

# 10g. validation precedes state creation: existing but EMPTY workspace must
#      stay empty (no .autodev, no seeded BACKLOG/charter) on a usage error.
ws12="$tmp/ws12"; mkdir -p "$ws12"
bash "$ROOT/pixel-autodev.sh" --max-tasks=0 --workspace="$ws12" >/dev/null 2>&1; rc=$?
if [ $rc -eq 2 ] && [ -z "$(ls -A "$ws12")" ]; then
  t_ok "invalid --max-tasks creates no .autodev state and seeds nothing"
else
  t_fail "validation-before-state" "rc=$rc contents=$(ls -A "$ws12")"
fi

# --- 11. --agent enum contract (pixel-autodev.sh) --------------------------------
# 11a. values outside {claude, codex} are usage errors (exit 2, flag named on
#      stderr) BEFORE preflight — an unknown name can never reach command
#      lookup or dispatch. Matrix: unknown / empty / wrong case / lookalike /
#      shell metacharacters / whitespace.
for v in foo "" CLAUDE Claude claude2 "claude;rm" "claude "; do
  err="$(bash "$ROOT/pixel-autodev.sh" --agent="$v" --workspace=/nonexistent-pixel-ws 2>&1 >/dev/null)"; rc=$?
  if [ $rc -eq 2 ] && case "$err" in *"--agent"*) true;; *) false;; esac; then
    t_ok "rejects invalid --agent='$v' (exit 2 before preflight, stderr names flag)"
  else
    t_fail "invalid --agent='$v'" "rc=$rc stderr=$err"
  fi
done

# 11b. both enumerated backends are accepted (dry-run, stub agents on PATH)
for v in claude codex; do
  out="$(PATH="$APATH" bash "$ROOT/pixel-autodev.sh" --dry-run --workspace="$ws10" --agent="$v" 2>&1)"; rc=$?
  if [ $rc -eq 0 ]; then t_ok "accepts --agent=$v"; else t_fail "--agent=$v" "rc=$rc"$'\n'"$out"; fi
done

# 11c. duplicate --agent: last wins, final value is the one validated
out="$(PATH="$APATH" bash "$ROOT/pixel-autodev.sh" --dry-run --workspace="$ws10" --agent=foo --agent=claude 2>&1)"; rc=$?
if [ $rc -eq 0 ]; then t_ok "duplicate --agent: later valid overrides earlier invalid"; else t_fail "duplicate --agent valid-last" "rc=$rc"; fi
bash "$ROOT/pixel-autodev.sh" --agent=claude --agent=foo --workspace=/nonexistent-pixel-ws >/dev/null 2>&1; rc=$?
if [ $rc -eq 2 ]; then t_ok "duplicate --agent: later invalid rejected (last-wins validated)"; else t_fail "duplicate --agent invalid-last" "rc=$rc"; fi

# --- summary ---------------------------------------------------------------------
echo
printf 'passed: %d   failed: %d   skipped: %d\n' "$PASS" "$FAIL" "$SKIP"
[ "$FAIL" -eq 0 ]
