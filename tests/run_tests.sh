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

# --- summary ---------------------------------------------------------------------
echo
printf 'passed: %d   failed: %d   skipped: %d\n' "$PASS" "$FAIL" "$SKIP"
[ "$FAIL" -eq 0 ]
