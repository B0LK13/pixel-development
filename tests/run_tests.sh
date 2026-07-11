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
# pkg backs the bootstrap Termux preflight so download-verification tests can
# run outside Termux.
for tool in claude codex pkg; do
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

# --- 12. end-of-options + positional arguments (all scripts) ----------------------
# Contract: '--' has no special meaning (unknown flag → exit 2) and no script
# accepts positional arguments — nothing is silently ignored or passed through.
# (bootstrap '--' is already pinned in section 7.)
for s in pixel-dev-setup.sh pixel-apps-setup.sh pixel-autodev.sh; do
  bash "$ROOT/$s" -- >/dev/null 2>&1; rc=$?
  if [ $rc -eq 2 ]; then t_ok "'--' rejected as unknown flag: $s"; else t_fail "'--' handling: $s" "rc=$rc (want 2)"; fi
done
for s in "${SCRIPTS[@]}"; do
  bash "$ROOT/$s" -- --help >/dev/null 2>&1; rc=$?
  if [ $rc -eq 2 ]; then t_ok "'-- --help' still exit 2 ('--' does not enable pass-through): $s"; else t_fail "'--' pass-through: $s" "rc=$rc (want 2)"; fi
  bash "$ROOT/$s" extra-positional-arg >/dev/null 2>&1; rc=$?
  if [ $rc -eq 2 ]; then t_ok "positional argument rejected: $s"; else t_fail "positional arg: $s" "rc=$rc (want 2)"; fi
done
# positional trailing AFTER a valid flag is still rejected (nothing trailing is
# silently ignored)
bash "$ROOT/pixel-autodev.sh" --max-tasks=1 extra >/dev/null 2>&1; rc=$?
if [ $rc -eq 2 ]; then t_ok "trailing positional after valid flag rejected: pixel-autodev.sh"; else t_fail "trailing positional" "rc=$rc (want 2)"; fi

# --- 13. tool preflight contract (pixel-autodev.sh) --------------------------------
# 13a. dry-run must not require paid-agent executables: preflight skips agent
#      resolution entirely (asserted via the skip line — hermetic on any host).
out="$(PATH="$APATH" bash "$ROOT/pixel-autodev.sh" --dry-run --workspace="$ws10" 2>&1)"; rc=$?
if [ $rc -eq 0 ] && case "$out" in *"dry-run: skipping agent resolution"*) true;; *) false;; esac; then
  t_ok "dry-run skips agent resolution (no paid-agent executable required)"
else
  t_fail "dry-run agent skip" "rc=$rc"$'\n'"$out"
fi
# 13b. non-dry-run still resolves the agent in preflight. CLAUDE_BIN is pinned
#      to the no-op stub so dispatch can never reach a real (paid) agent.
ws13="$tmp/ws13"; mk_ws "$ws13"
printf -- '- [ ] Probe preflight agent resolution\n' > "$ws13/BACKLOG.md"
git -C "$ws13" add -A && git -C "$ws13" commit -qm task >/dev/null
out="$(env PATH="$APATH" CLAUDE_BIN="$tmp/bin/claude" bash "$ROOT/pixel-autodev.sh" --workspace="$ws13" --max-tasks=1 2>&1)"; rc=$?
if [ $rc -eq 0 ] && case "$out" in *"agent: claude ("*) true;; *) false;; esac; then
  t_ok "non-dry-run resolves the agent in preflight (dispatch stays stub-pinned)"
else
  t_fail "non-dry-run agent resolution" "rc=$rc"$'\n'"$out"
fi

# --- 14. line-ending contract (audit R6) --------------------------------------------
# CRLF checkouts would break shebangs; .gitattributes pins LF so an autocrlf
# client cannot silently corrupt the scripts. Adding it must not renormalise
# the tree (all blobs are already LF — the clean tree proves it).
if [ -f .gitattributes ] && grep -q 'text=auto eol=lf' .gitattributes; then
  t_ok ".gitattributes pins LF endings (text=auto eol=lf)"
else
  t_fail ".gitattributes must pin LF endings (text=auto eol=lf)"
fi
attr="$(git check-attr eol -- pixel-bootstrap.sh 2>/dev/null)"
if case "$attr" in *"eol: lf"*) true;; *) false;; esac; then
  t_ok "git check-attr confirms eol=lf for tracked scripts"
else
  t_fail "git check-attr eol" "got: $attr"
fi

# --- 15. dependency-resolution seam (pixel-autodev.sh preflight) -------------------
# Seam: TIMEOUT_BIN / GIT_BIN / CLAUDE_BIN / CODEX_BIN. Set-empty simulates a
# missing tool hermetically. Every failure must be exit 1, name the tool on
# stderr, and leave the workspace untouched (no .autodev, no seeded files).
seam_fail(){ # $1 want-substring  $2 ws-dir  $3.. env-assignments + args
  local want="$1" w="$2"; shift 2
  mkdir -p "$w"
  err="$(env "$@" 2>&1 >/dev/null)"; rc=$?
  if [ $rc -eq 1 ] && case "$err" in *"$want"*) true;; *) false;; esac && [ -z "$(ls -A "$w")" ]; then
    t_ok "preflight fails closed: $want (exit 1, no state created)"
  else
    t_fail "preflight failure: $want" "rc=$rc stderr=$err ws=$(ls -A "$w")"
  fi
}
seam_fail "GNU timeout (coreutils) is required" "$tmp/ws15a" \
  CLAUDE_BIN="$tmp/bin/claude" TIMEOUT_BIN= bash "$ROOT/pixel-autodev.sh" --workspace="$tmp/ws15a"
seam_fail "git not installed in devbox" "$tmp/ws15b" \
  CLAUDE_BIN="$tmp/bin/claude" GIT_BIN= bash "$ROOT/pixel-autodev.sh" --workspace="$tmp/ws15b"
seam_fail "'claude' not found" "$tmp/ws15c" \
  CLAUDE_BIN= bash "$ROOT/pixel-autodev.sh" --workspace="$tmp/ws15c"
seam_fail "'codex' not found" "$tmp/ws15d" \
  CODEX_BIN= bash "$ROOT/pixel-autodev.sh" --agent=codex --workspace="$tmp/ws15d"

# 15e. CLI validation beats dependency resolution: usage error stays exit 2 even
#      when every tool is "missing", and still creates nothing.
mkdir -p "$tmp/ws15e"
err="$(env TIMEOUT_BIN= GIT_BIN= CLAUDE_BIN= CODEX_BIN= bash "$ROOT/pixel-autodev.sh" --max-tasks=0 --workspace="$tmp/ws15e" 2>&1 >/dev/null)"; rc=$?
if [ $rc -eq 2 ] && case "$err" in *"--max-tasks"*) true;; *) false;; esac && [ -z "$(ls -A "$tmp/ws15e")" ]; then
  t_ok "usage error (exit 2) precedes dependency resolution"
else
  t_fail "validation ordering" "rc=$rc stderr=$err"
fi

# 15f. dry-run with BOTH agents "missing" still succeeds (skips resolution)
out="$(env CLAUDE_BIN= CODEX_BIN= bash "$ROOT/pixel-autodev.sh" --dry-run --workspace="$tmp/ws15e" 2>&1)"; rc=$?
if [ $rc -eq 0 ] && case "$out" in *"dry-run: skipping agent resolution"*) true;; *) false;; esac; then
  t_ok "dry-run requires no agent executable even via the seam"
else
  t_fail "dry-run seam" "rc=$rc"$'\n'"$out"
fi

# 15g. path override resolves an explicit executable (timeout via /bin/true)
out="$(env TIMEOUT_BIN=/bin/true bash "$ROOT/pixel-autodev.sh" --dry-run --workspace="$tmp/ws15e" 2>&1)"; rc=$?
if [ $rc -eq 0 ]; then t_ok "path override resolves (/bin/true as timeout)"; else t_fail "path override" "rc=$rc"$'\n'"$out"; fi

# 15h. bare-name override resolves through PATH and dispatch stays on that stub
printf '#!/usr/bin/env bash\nexit 0\n' > "$tmp/bin/pixel-stub-agent"; chmod +x "$tmp/bin/pixel-stub-agent"
ws15h="$tmp/ws15h"; mk_ws "$ws15h"
printf -- '- [ ] Probe bare-name seam resolution\n' > "$ws15h/BACKLOG.md"
git -C "$ws15h" add -A && git -C "$ws15h" commit -qm task >/dev/null
out="$(env PATH="$APATH" CLAUDE_BIN=pixel-stub-agent bash "$ROOT/pixel-autodev.sh" --workspace="$ws15h" --max-tasks=1 2>&1)"; rc=$?
if [ $rc -eq 0 ] && case "$out" in *"agent: claude ("*"pixel-stub-agent)"*) true;; *) false;; esac; then
  t_ok "bare-name override resolves through PATH; dispatch runs the stub"
else
  t_fail "bare-name override" "rc=$rc"$'\n'"$out"
fi

# 15i. a metacharacter override value is never executed
pwn="$tmp/pwned-seam"; rm -f "$pwn"
env CLAUDE_BIN='$(touch '"$pwn"')' bash "$ROOT/pixel-autodev.sh" --workspace="$tmp/ws15e" >/dev/null 2>&1; rc=$?
if [ $rc -eq 1 ] && [ ! -e "$pwn" ]; then
  t_ok "metacharacter seam value is never executed (quoted throughout)"
else
  t_fail "seam injection" "rc=$rc pwned=$([ -e "$pwn" ] && echo yes || echo no)"
fi

# --- 16. bootstrap checksum manifest lockstep (audit R1) --------------------------
MANIFEST="config/bootstrap-checksums.txt"
manifest_sha(){ awk -v n="$1" '$1 ~ /^[0-9a-fA-F]{64}$/ && $2 == n {print tolower($1); f=1} END{exit !f}' "$MANIFEST" 2>/dev/null; }
embedded_sha(){ grep -A1 -- "$1)" "$ROOT/pixel-bootstrap.sh" | grep -oE '[0-9a-f]{64}' | head -1; }
file_sha(){ (sha256sum "$1" 2>/dev/null || shasum -a 256 "$1") | awk '{print $1}'; }

if [ -f "$MANIFEST" ] && manifest_sha pixel-dev-setup.sh >/dev/null \
   && manifest_sha pixel-apps-setup.sh >/dev/null && manifest_sha pixel-bootstrap.sh >/dev/null; then
  t_ok "checksum manifest exists and covers all three pinned artifacts"
else
  t_fail "checksum manifest must pin all three artifacts (dev-setup, apps-setup, bootstrap)"
fi
for s in pixel-dev-setup.sh pixel-apps-setup.sh; do
  if [ "$(manifest_sha "$s")" = "$(file_sha "$ROOT/$s")" ]; then
    t_ok "manifest pin matches repo content: $s (lockstep)"
  else
    t_fail "manifest out of sync with $s" "manifest=$(manifest_sha "$s") file=$(file_sha "$ROOT/$s")"
  fi
  if [ "$(embedded_sha "$s")" = "$(manifest_sha "$s")" ]; then
    t_ok "embedded digest matches manifest: $s"
  else
    t_fail "embedded digest out of sync: $s" "embedded=$(embedded_sha "$s") manifest=$(manifest_sha "$s")"
  fi
done
# The anchor is pinned too, but carries no embedded copy of its own digest —
# a script cannot hash itself. Two-way check only.
if [ "$(manifest_sha pixel-bootstrap.sh)" = "$(file_sha "$ROOT/pixel-bootstrap.sh")" ]; then
  t_ok "manifest pin matches repo content: pixel-bootstrap.sh (anchor lockstep)"
else
  t_fail "manifest out of sync with pixel-bootstrap.sh" "manifest=$(manifest_sha pixel-bootstrap.sh) file=$(file_sha "$ROOT/pixel-bootstrap.sh")"
fi
# The R1-scoped downloads never pipe remote content into a shell. The only
# piped installer left in the file is the chartered claude.ai updater inside
# the quoted 5-Update-AI shortcut body (audit F8 — out of scope here).
pipes="$(grep -cE 'curl[^#]*\|[[:space:]]*(bash|sh)\b' "$ROOT/pixel-bootstrap.sh")"
if [ "$pipes" -eq 1 ] && grep -E 'curl[^#]*\|[[:space:]]*(bash|sh)\b' "$ROOT/pixel-bootstrap.sh" | grep -q 'claude.ai/install.sh'; then
  t_ok "no unverified curl|bash in bootstrap downloads (only chartered updater shortcut remains)"
else
  t_fail "unexpected curl|bash in pixel-bootstrap.sh" "matches: $pipes"
fi
n="$(grep -c 'curl -fsSL -o "\$DLTMP/\$s" "\$REPO_BASE/\$s"' "$ROOT/pixel-bootstrap.sh")"
d="$(grep -c 'curl -fsSL -o "\$DEST/' "$ROOT/pixel-bootstrap.sh" || true)"
if [ "$n" -eq 1 ] && [ "$d" -eq 0 ]; then
  t_ok "downloads land in a temp file, never directly in \$DEST"
else
  t_fail "download-to-temp wiring" "temp=$n direct=$d"
fi

# --- 17. bootstrap download verification, functional (audit R1) --------------------
# Hermetic "web root": curl's file:// scheme, no network. The Termux preflight
# is satisfied by the pkg stub + PREFIX; each case gets a fresh HOME (with a
# space) and runs from a neutral cwd so the download path is forced.
dlroot="$tmp/dlroot"; mkdir -p "$dlroot/valid" "$dlroot/corrupt"
cp "$ROOT/pixel-dev-setup.sh" "$ROOT/pixel-apps-setup.sh" "$dlroot/valid/"
cp "$ROOT/pixel-dev-setup.sh" "$ROOT/pixel-apps-setup.sh" "$dlroot/corrupt/"
printf 'tampered\n' >> "$dlroot/corrupt/pixel-dev-setup.sh"
dlurl(){ printf 'file://%s' "${1// /%20}"; }   # percent-encode the space in $tmp
BOOT_DEST=; BOOT_SHORT=
run_boot(){ # env-assignments… then: bash "$ROOT/pixel-bootstrap.sh" args…
  local h; h="$(mktemp -d "${tmp}/boot home.XXXXXX")"
  BOOT_DEST="$h/.local/share/pixel"; BOOT_SHORT="$h/.shortcuts"
  out="$(cd "$tmp" && env HOME="$h" PREFIX="$h/prefix" PATH="$APATH" "$@" 2>&1)"; rc=$?
}
dl_leftovers(){ ls -d /tmp/pixel-dl.* 2>/dev/null | wc -l; }

# 17a. valid content verifies against the EMBEDDED digests (production path) and
#      gets installed; shortcuts then get created.
run_boot bash "$ROOT/pixel-bootstrap.sh" --repo-base="$(dlurl "$dlroot/valid")"
if [ $rc -eq 0 ] && case "$out" in *"pixel-dev-setup.sh (downloaded, sha256 verified)"*"pixel-apps-setup.sh (downloaded, sha256 verified)"*) true;; *) false;; esac \
   && [ -f "$BOOT_DEST/pixel-dev-setup.sh" ] && [ -f "$BOOT_DEST/pixel-apps-setup.sh" ]; then
  t_ok "valid downloads verify (sha256) and install"
else
  t_fail "valid download path" "rc=$rc"$'\n'"$out"
fi
if [ -f "$BOOT_SHORT/3-Apps-Setup" ]; then
  t_ok "shortcuts created only after verified installs"
else
  t_fail "shortcuts missing after verified install"
fi

# 17b. mismatched content fails closed BEFORE install — nothing in DEST, no
#      shortcut files, no temp leftovers.
run_boot bash "$ROOT/pixel-bootstrap.sh" --repo-base="$(dlurl "$dlroot/corrupt")"
if [ $rc -eq 1 ] && case "$out" in *"checksum mismatch for pixel-dev-setup.sh"*) true;; *) false;; esac \
   && [ ! -e "$BOOT_DEST/pixel-dev-setup.sh" ] && [ "$(find "$BOOT_SHORT" -type f 2>/dev/null | wc -l)" -eq 0 ] \
   && [ "$(dl_leftovers)" -eq 0 ]; then
  t_ok "checksum mismatch fails closed (no install, no shortcuts, no temp)"
else
  t_fail "mismatch path" "rc=$rc"$'\n'"$out"
fi

# 17c. failed download: die clearly, no partial file in DEST, temp cleaned.
run_boot bash "$ROOT/pixel-bootstrap.sh" --repo-base="$(dlurl "$dlroot/nonexistent")"
if [ $rc -eq 1 ] && case "$out" in *"could not download pixel-dev-setup.sh"*) true;; *) false;; esac \
   && [ -z "$(ls -A "$BOOT_DEST" 2>/dev/null)" ] && [ "$(dl_leftovers)" -eq 0 ]; then
  t_ok "failed download installs no partial content (temp cleaned)"
else
  t_fail "download-failure path" "rc=$rc"$'\n'"$out"
fi

# 17d. missing checksum entry fails closed via the seam manifest (dev-setup is
#      pinned there, apps-setup is not → run stops at apps-setup).
printf '%s  pixel-dev-setup.sh\n' "$(file_sha "$ROOT/pixel-dev-setup.sh")" > "$tmp/manifest-missing.txt"
run_boot env PIXEL_BOOTSTRAP_CHECKSUM_FILE="$tmp/manifest-missing.txt" \
  bash "$ROOT/pixel-bootstrap.sh" --repo-base="$(dlurl "$dlroot/valid")"
if [ $rc -eq 1 ] && case "$out" in *"no pinned checksum for pixel-apps-setup.sh"*) true;; *) false;; esac \
   && [ ! -e "$BOOT_DEST/pixel-apps-setup.sh" ]; then
  t_ok "missing checksum entry fails closed (apps-setup not installed)"
else
  t_fail "missing-entry path" "rc=$rc"$'\n'"$out"
fi

# 17e. metacharacters in the repo-base URL reach curl only as a quoted argument.
pwn="$tmp/pwned-dl"; rm -f "$pwn"
run_boot bash "$ROOT/pixel-bootstrap.sh" "--repo-base=file:///tmp/nope;\$(touch $pwn)"
if [ $rc -eq 1 ] && [ ! -e "$pwn" ]; then
  t_ok "metacharacter repo-base value is never executed"
else
  t_fail "repo-base injection" "rc=$rc pwned=$([ -e "$pwn" ] && echo yes || echo no)"
fi

# --- 18. bootstrap anchor install-flow contract (README §1) ---------------------
# The primary documented install path must be fetch→verify→run from an
# immutable commit URL, with a digest that really is the digest of the pinned
# git object, and no pipe-to-shell anywhere in the primary block.
readme_block="$(awk '/^## 1\./{f=1} f&&/^```bash/{c=1;next} c&&/^```/{exit} c{print}' "$ROOT/README.md")"
pin_commit="$(printf '%s\n' "$readme_block" | grep -oE 'raw\.githubusercontent\.com/B0LK13/pixel-development/[0-9a-f]{40}/pixel-bootstrap\.sh' | head -1 | grep -oE '[0-9a-f]{40}')"
pin_digest="$(printf '%s\n' "$readme_block" | grep -oE '[0-9a-f]{64}' | head -1)"
blob_sha(){ git -C "$ROOT" show "$1:pixel-bootstrap.sh" 2>/dev/null | (sha256sum 2>/dev/null || shasum -a 256) | awk '{print $1}'; }
[ "${#pin_commit}" -eq 40 ] || pin_commit=
[ "${#pin_digest}" -eq 64 ] || pin_digest=
if [ -n "$pin_commit" ] && [ -n "$pin_digest" ]; then
  t_ok "README §1 pins a full-commit URL and a SHA-256"
else
  t_fail "README §1 pin shape" "commit=$pin_commit digest=$pin_digest"
fi
if [ -n "$pin_commit" ] && [ "$(blob_sha "$pin_commit")" = "$pin_digest" ]; then
  t_ok "README pin digest == sha256 of the pinned git object"
else
  t_fail "README pin does not match the pinned commit" "blob=$(blob_sha "$pin_commit") readme=$pin_digest"
fi
if printf '%s\n' "$readme_block" | grep -qE '\|[[:space:]]*(bash|sh)\b'; then
  t_fail "README §1 primary block still pipes a download into a shell"
else
  t_ok "README §1 primary block has no pipe-to-shell"
fi
if printf '%s\n' "$readme_block" | grep -q "PIXEL_REPO_BASE=\"https://raw.githubusercontent.com/B0LK13/pixel-development/$pin_commit\""; then
  t_ok "PIXEL_REPO_BASE pins the same immutable commit"
else
  t_fail "PIXEL_REPO_BASE does not pin the same commit as the download"
fi

# --- 19. signature verification fixtures (bootstrap trust model, tier 2) --------
HELPER="$ROOT/scripts/verify-bootstrap-signature.sh"
if command -v gpg >/dev/null 2>&1 && command -v gpgv >/dev/null 2>&1; then
  GNUPGHOME="$tmp/gnupg"; export GNUPGHOME; mkdir -p "$GNUPGHOME"; chmod 700 "$GNUPGHOME"
  printf 'Key-Type: eddsa\nKey-Curve: ed25519\nKey-Usage: sign\nName-Real: Pixel Test\nName-Email: t@example.invalid\n%%no-protection\n%%commit\n' > "$tmp/keyparams"
  gpg --batch --gen-key "$tmp/keyparams" >/dev/null 2>&1
  printf 'genuine bootstrap artifact\n' > "$tmp/artifact"
  gpg --batch --yes --local-user t@example.invalid --detach-sign --output "$tmp/artifact.sig" "$tmp/artifact" >/dev/null 2>&1
  gpg --export t@example.invalid > "$tmp/trusted.pub" 2>/dev/null
  # a second, untrusted key for the wrong-keyring case
  printf 'Key-Type: eddsa\nKey-Curve: ed25519\nKey-Usage: sign\nName-Real: Other\nName-Email: o@example.invalid\n%%no-protection\n%%commit\n' > "$tmp/keyparams2"
  gpg --batch --gen-key "$tmp/keyparams2" >/dev/null 2>&1
  gpg --export o@example.invalid > "$tmp/untrusted.pub" 2>/dev/null

  # 19a. a genuine signature verifies
  out="$(bash "$HELPER" --keyring="$tmp/trusted.pub" --signature="$tmp/artifact.sig" "$tmp/artifact" 2>&1)"; rc=$?
  if [ $rc -eq 0 ] && case "$out" in *"signature verified"*) true;; *) false;; esac; then
    t_ok "valid detached signature verifies (gpgv)"
  else t_fail "valid signature" "rc=$rc"$'\n'"$out"; fi

  # 19b. a tampered artifact fails closed
  cp "$tmp/artifact" "$tmp/artifact-tampered"; printf 'x\n' >> "$tmp/artifact-tampered"
  err="$(bash "$HELPER" --keyring="$tmp/trusted.pub" --signature="$tmp/artifact.sig" "$tmp/artifact-tampered" 2>&1 >/dev/null)"; rc=$?
  if [ $rc -eq 1 ] && case "$err" in *"FAILED"*) true;; *) false;; esac; then
    t_ok "tampered artifact fails signature verification (exit 1)"
  else t_fail "tampered artifact" "rc=$rc"$'\n'"$err"; fi

  # 19c. the right signature under the wrong keyring fails
  err="$(bash "$HELPER" --keyring="$tmp/untrusted.pub" --signature="$tmp/artifact.sig" "$tmp/artifact" 2>&1 >/dev/null)"; rc=$?
  if [ $rc -eq 1 ]; then t_ok "untrusted keyring rejects a genuine signature"; else t_fail "wrong keyring" "rc=$rc"$'\n'"$err"; fi

  # 19d. missing signature file is a clear error
  err="$(bash "$HELPER" --keyring="$tmp/trusted.pub" --signature="$tmp/nope.sig" "$tmp/artifact" 2>&1 >/dev/null)"; rc=$?
  if [ $rc -eq 1 ] && case "$err" in *"signature not found"*) true;; *) false;; esac; then
    t_ok "missing signature file is a clear error"
  else t_fail "missing signature" "rc=$rc"$'\n'"$err"; fi

  # 19e. missing verifier (seam set-empty) fails clearly
  err="$(env GPGV_BIN= bash "$HELPER" --keyring="$tmp/trusted.pub" --signature="$tmp/artifact.sig" "$tmp/artifact" 2>&1 >/dev/null)"; rc=$?
  if [ $rc -eq 1 ] && case "$err" in *gpgv*) true;; *) false;; esac; then
    t_ok "missing gpgv fails with a named dependency (exit 1)"
  else t_fail "missing verifier" "rc=$rc"$'\n'"$err"; fi

  # 19f. usage errors exit 2 and precede dependency resolution
  bash "$HELPER" >/dev/null 2>&1; rc=$?
  [ $rc -eq 2 ] && t_ok "signature helper: no args is a usage error (exit 2)" || t_fail "helper usage" "rc=$rc"
  bash "$HELPER" --bogus=1 >/dev/null 2>&1; rc=$?
  [ $rc -eq 2 ] && t_ok "signature helper: unknown flag is a usage error (exit 2)" || t_fail "helper unknown flag" "rc=$rc"

  # 19g. a metacharacter verifier value is never executed
  pwn="$tmp/pwned-gpgv"; rm -f "$pwn"
  env GPGV_BIN='$(touch '"$pwn"')' bash "$HELPER" --keyring="$tmp/trusted.pub" --signature="$tmp/artifact.sig" "$tmp/artifact" >/dev/null 2>&1; rc=$?
  if [ $rc -eq 1 ] && [ ! -e "$pwn" ]; then
    t_ok "metacharacter GPGV_BIN value is never executed"
  else t_fail "gpgv seam injection" "rc=$rc pwned=$([ -e "$pwn" ] && echo yes || echo no)"; fi
else
  t_skip "gpg/gpgv not installed — signature fixtures skipped (install gnupg to run)"
fi

# --- 20. checksum lifecycle tool (scripts/update-bootstrap-checksums.sh) ----------
CKTOOL="$ROOT/scripts/update-bootstrap-checksums.sh"
mk_fx(){ # $1 fixture dir — a mini repo root (scripts/ + config/ + 3 artifacts)
  local d="$1"; mkdir -p "$d/scripts" "$d/config"
  cp "$CKTOOL" "$d/scripts/"
  cp "$ROOT/pixel-bootstrap.sh" "$ROOT/pixel-dev-setup.sh" "$ROOT/pixel-apps-setup.sh" "$d/"
  cp "$ROOT/config/bootstrap-checksums.txt" "$d/config/"
}
fxrun(){ # $1 fixture  $2.. args → rc/out; runs from a neutral cwd (outside root)
  local d="$1"; shift
  out="$(cd "$tmp" && bash "$d/scripts/update-bootstrap-checksums.sh" "$@" 2>&1)"; rc=$?
}
ck_leftovers(){ ls "$1"/.embedded.* "$1"/config/.bootstrap-checksums.* 2>/dev/null | wc -l; }

# 20a. current manifest passes; the fixture path contains a space (proves quoting)
mk_fx "$tmp/fx a"; fxrun "$tmp/fx a" --check
if [ $rc -eq 0 ] && case "$out" in *"is current"*) true;; *) false;; esac && case "$tmp/fx a" in *' '*) true;; *) false;; esac; then
  t_ok "checksum tool: current manifest passes --check (path with spaces)"
else t_fail "tool current" "rc=$rc"$'\n'"$out"; fi

# 20b+c. stale manifest fails --check naming the artifact; --write repairs it
mk_fx "$tmp/fx b"; printf 'tamper\n' >> "$tmp/fx b/pixel-apps-setup.sh"
fxrun "$tmp/fx b" --check
if [ $rc -eq 1 ] && case "$out" in *"STALE: pixel-apps-setup.sh"*) true;; *) false;; esac; then
  t_ok "checksum tool: stale manifest fails --check naming the artifact"
else t_fail "tool stale" "rc=$rc"$'\n'"$out"; fi
fxrun "$tmp/fx b" --write; wrc=$rc
fxrun "$tmp/fx b" --check
if [ $wrc -eq 0 ] && [ $rc -eq 0 ] && [ "$(ck_leftovers "$tmp/fx b")" -eq 0 ]; then
  t_ok "checksum tool: --write repairs stale manifest+embedded (no temp leftovers)"
else t_fail "tool write" "write_rc=$wrc recheck_rc=$rc"; fi

# 20d. missing artifact
mk_fx "$tmp/fx d"; rm "$tmp/fx d/pixel-dev-setup.sh"; fxrun "$tmp/fx d" --check
if [ $rc -eq 1 ] && case "$out" in *"missing artifact: pixel-dev-setup.sh"*) true;; *) false;; esac; then
  t_ok "checksum tool: missing artifact fails clearly"
else t_fail "tool missing artifact" "rc=$rc"$'\n'"$out"; fi

# 20e/f/g. malformed / duplicate / unexpected manifest entries are rejected
mk_fx "$tmp/fx e"; printf 'not a digest line\n' >> "$tmp/fx e/config/bootstrap-checksums.txt"
fxrun "$tmp/fx e" --check
[ $rc -eq 1 ] && case "$out" in *"malformed"*) true;; *) false;; esac \
  && t_ok "checksum tool: malformed manifest line rejected" || t_fail "tool malformed" "rc=$rc"$'\n'"$out"
mk_fx "$tmp/fx f"; printf '%s  pixel-apps-setup.sh\n' "$(file_sha "$ROOT/pixel-apps-setup.sh")" >> "$tmp/fx f/config/bootstrap-checksums.txt"
fxrun "$tmp/fx f" --check
[ $rc -eq 1 ] && case "$out" in *"duplicate"*) true;; *) false;; esac \
  && t_ok "checksum tool: duplicate manifest entry rejected" || t_fail "tool duplicate" "rc=$rc"$'\n'"$out"
mk_fx "$tmp/fx g"; printf '%s  evil.sh\n' "0000000000000000000000000000000000000000000000000000000000000000" >> "$tmp/fx g/config/bootstrap-checksums.txt"
fxrun "$tmp/fx g" --check
[ $rc -eq 1 ] && case "$out" in *"unexpected artifact: evil.sh"*) true;; *) false;; esac \
  && t_ok "checksum tool: unexpected artifact name rejected" || t_fail "tool unexpected" "rc=$rc"$'\n'"$out"

# 20h. deterministic ordering + idempotent write
mk_fx "$tmp/fx h"; fxrun "$tmp/fx h" --write; fxrun "$tmp/fx h" --write
order="$(grep -E '^[0-9a-f]{64}' "$tmp/fx h/config/bootstrap-checksums.txt" | awk '{print $2}' | tr '\n' ' ')"
if [ $rc -eq 0 ] && case "$out" in *"already current"*) true;; *) false;; esac \
   && [ "$order" = "pixel-apps-setup.sh pixel-bootstrap.sh pixel-dev-setup.sh " ]; then
  t_ok "checksum tool: deterministic sorted order; second --write changes nothing"
else t_fail "tool ordering" "rc=$rc order=$order"$'\n'"$out"; fi

# 20i. symlink escape is refused
mk_fx "$tmp/fx i"; rm "$tmp/fx i/pixel-apps-setup.sh"; ln -s /etc/passwd "$tmp/fx i/pixel-apps-setup.sh"
fxrun "$tmp/fx i" --check
if [ $rc -eq 1 ] && case "$out" in *"symlink"*) true;; *) false;; esac; then
  t_ok "checksum tool: symlink artifact refused"
else t_fail "tool symlink" "rc=$rc"$'\n'"$out"; fi

# 20j. --check never mutates (even a stale manifest)
mk_fx "$tmp/fx j"; printf 'tamper\n' >> "$tmp/fx j/pixel-dev-setup.sh"
before="$(file_sha "$tmp/fx j/config/bootstrap-checksums.txt")"; fxrun "$tmp/fx j" --check
after="$(file_sha "$tmp/fx j/config/bootstrap-checksums.txt")"
if [ $rc -eq 1 ] && [ "$before" = "$after" ]; then
  t_ok "checksum tool: --check is non-mutating on a stale manifest"
else t_fail "tool check-mutate" "rc=$rc"; fi

# 20k. interrupted write simulation: embedded pattern unmatchable → --write dies
#      before touching the manifest; no partial state, no temp leftovers
mk_fx "$tmp/fx k"; sed -i -E '/pixel-apps-setup\.sh\).*printf/d' "$tmp/fx k/pixel-bootstrap.sh"
before="$(file_sha "$tmp/fx k/config/bootstrap-checksums.txt")"; fxrun "$tmp/fx k" --write
after="$(file_sha "$tmp/fx k/config/bootstrap-checksums.txt")"
if [ $rc -eq 1 ] && case "$out" in *"expected 1 line"*) true;; *) false;; esac \
   && [ "$before" = "$after" ] && [ "$(ck_leftovers "$tmp/fx k")" -eq 0 ]; then
  t_ok "checksum tool: failed --write leaves manifest byte-identical (no partial state)"
else t_fail "tool interrupted write" "rc=$rc"$'\n'"$out"; fi

# 20l. embedded/manifest mismatch is detected (single lockstep source of truth)
mk_fx "$tmp/fx l"
sed -i -E '/pixel-apps-setup\.sh\).*printf/ s/[0-9a-f]{64}/ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff/' "$tmp/fx l/pixel-bootstrap.sh"
fxrun "$tmp/fx l" --check
if [ $rc -eq 1 ] && case "$out" in *"EMBEDDED STALE: pixel-apps-setup.sh"*) true;; *) false;; esac; then
  t_ok "checksum tool: embedded/manifest mismatch detected"
else t_fail "tool embedded mismatch" "rc=$rc"$'\n'"$out"; fi

# 20m. usage contract: unknown argument and conflicting modes exit 2
bash "$CKTOOL" --bogus >/dev/null 2>&1; rc=$?
[ $rc -eq 2 ] && t_ok "checksum tool: unknown argument is a usage error (exit 2)" || t_fail "tool usage" "rc=$rc"
bash "$CKTOOL" --check --write >/dev/null 2>&1; rc=$?
[ $rc -eq 2 ] && t_ok "checksum tool: --check --write conflict is a usage error (exit 2)" || t_fail "tool conflict" "rc=$rc"

# 20n. clean-clone execution: the committed tool passes --check from a fresh clone
ckclone="$tmp/ck clone"
if git clone -q --local "$ROOT" "$ckclone" 2>/dev/null \
   && ( cd / && bash "$ckclone/scripts/update-bootstrap-checksums.sh" --check >/dev/null 2>&1 ); then
  t_ok "checksum tool: --check passes from a clean clone"
else t_fail "tool clean-clone" "clone or check failed"; fi

# --- 21. release-process governance (docs/BOOTSTRAP_RELEASE_PROCESS.md) -----------
RELDOC="$ROOT/docs/BOOTSTRAP_RELEASE_PROCESS.md"
rel_row="$(grep -E '^\|.*\| *current *\|' "$RELDOC" 2>/dev/null | head -1)"
rel_commit="$(printf '%s' "$rel_row" | grep -oE '[0-9a-f]{40}' | head -1)"
rel_digest="$(printf '%s' "$rel_row" | grep -oE '[0-9a-f]{64}' | head -1)"
if [ -f "$RELDOC" ] && [ -n "$rel_commit" ] && [ -n "$rel_digest" ] \
   && [ "$(blob_sha "$rel_commit")" = "$rel_digest" ]; then
  t_ok "release doc: 'current' pin-history row matches the pinned git object"
else
  t_fail "release doc pin history" "commit=$rel_commit digest=$rel_digest blob=$(blob_sha "$rel_commit")"
fi
if grep -q 'Rollback procedure' "$RELDOC" && grep -q 'operator-owned' "$RELDOC"; then
  t_ok "release doc: rollback path + operator-owned publishing documented"
else
  t_fail "release doc missing rollback/ownership sections"
fi

# --- 22. CI parity (workflow vs scripts/ci-local.sh, static) ----------------------
# Guards against silent drift between GitHub Actions and the local parity
# command. The essential gate commands must exist in BOTH places.
WF="$ROOT/.github/workflows/test.yml"
CIL="$ROOT/scripts/ci-local.sh"
if ! grep -q "$(printf '\t')" "$WF" && grep -q 'contents: read' "$WF"; then
  t_ok "workflow: valid-YAML hygiene (no tabs), least-privilege permissions"
else t_fail "workflow hygiene" "tabs or permissions regressed"; fi
for gate in 'git diff --check' 'bash scripts/update-bootstrap-checksums.sh --check' 'bash tests/run_tests.sh'; do
  if grep -qF "run: $gate" "$WF" && grep -qF "$gate" "$CIL"; then
    t_ok "CI parity: gate in workflow AND ci-local.sh: $gate"
  else
    t_fail "CI parity drift" "$gate missing in workflow or ci-local.sh"
  fi
done
if grep -qF "branches: [main, 'auto/*']" "$WF"; then
  t_ok "workflow triggers cover main + auto/* integration branches"
else t_fail "workflow triggers" "branch pattern changed"; fi
if grep -qE '\$\{\{ *secrets\.' "$WF" || grep -qE '\b(claude|codex)( |$)' "$WF"; then
  t_fail "workflow references a paid agent or a secret"
else
  t_ok "workflow invokes no paid agent and uses no secret context"
fi
# ci-local.sh itself: fail-fast, no mutation, runnable from anywhere (static shape)
if grep -q 'exit "$2"' "$CIL" && grep -q 'cd "$ROOT"' "$CIL"; then
  t_ok "ci-local.sh preserves failing step exit status and cds to repo root"
else t_fail "ci-local.sh shape" "fail-fast/root handling regressed"; fi

# --- summary ---------------------------------------------------------------------
echo
printf 'passed: %d   failed: %d   skipped: %d\n' "$PASS" "$FAIL" "$SKIP"
[ "$FAIL" -eq 0 ]
