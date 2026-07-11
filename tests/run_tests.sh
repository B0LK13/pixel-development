#!/usr/bin/env bash
###############################################################################
#  tests/run_tests.sh — verification gate for the pixel-development kit.      #
#                                                                             #
#  Pure bash, no dependencies. Uses shellcheck / git when available.          #
#  Covers: bash -n syntax · shellcheck (warning+) · --help/flag contract ·    #
#  .pixel-lab.json validity · pixel-autodev.sh dry-run behaviour (seeding,    #
#  backlog parsing, slug branches) with a fake `claude` on PATH.              #
#                                                                             #
#  Usage: bash tests/run_tests.sh        (exit 0 = all green)                 #
###############################################################################
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PASS=0; FAIL=0; SKIP=0
t_ok(){   PASS=$((PASS+1)); printf '  ok    %s\n' "$1"; }
t_fail(){ FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | head -20 | sed 's/^/        /'; }
t_skip(){ SKIP=$((SKIP+1)); printf '  skip  %s\n' "$1"; }

SCRIPTS=(pixel-bootstrap.sh pixel-dev-setup.sh pixel-apps-setup.sh pixel-autodev.sh)

echo "== pixel-development test suite =="

# --- 1. Syntax --------------------------------------------------------------
for s in "${SCRIPTS[@]}"; do
  if err="$(bash -n "$s" 2>&1)"; then t_ok "syntax: $s"; else t_fail "syntax: $s" "$err"; fi
done

# --- 2. Shellcheck (severity warning and up) --------------------------------
if command -v shellcheck >/dev/null 2>&1; then
  for s in "${SCRIPTS[@]}"; do
    if out="$(shellcheck -S warning "$s" 2>&1)"; then t_ok "shellcheck: $s"; else t_fail "shellcheck: $s" "$out"; fi
  done
else
  t_skip "shellcheck not installed — lint gate skipped (pkg install shellcheck)"
fi

# --- 3. --help / unknown-flag contract --------------------------------------
for s in "${SCRIPTS[@]}"; do
  out="$(bash "$s" --help 2>&1)"; rc=$?
  if [ $rc -eq 0 ] && [ -n "$out" ]; then t_ok "--help exits 0 with usage: $s"; else t_fail "--help: $s" "rc=$rc"; fi
  bash "$s" --definitely-not-a-flag >/dev/null 2>&1; rc=$?
  if [ $rc -eq 2 ]; then t_ok "unknown flag exits 2: $s"; else t_fail "unknown flag: $s" "rc=$rc (want 2)"; fi
done

# --- 4. .pixel-lab.json validity --------------------------------------------
if command -v jq >/dev/null 2>&1; then
  if jq -e '.name and .stack and .test' .pixel-lab.json >/dev/null 2>&1; then
    t_ok ".pixel-lab.json declares name/stack/test"
  else
    t_fail ".pixel-lab.json missing name/stack/test"
  fi
else
  t_skip "jq not installed — .pixel-lab.json check skipped"
fi

# --- 5. pixel-autodev.sh functional (dry-run, fake agent) --------------------
tmp="$(mktemp -d)"
cleanup(){ [ -n "${tmp:-}" ] && [ -d "$tmp" ] && rm -rf "$tmp"; }
trap cleanup EXIT

mkdir -p "$tmp/bin"
cat > "$tmp/bin/claude" <<'EOF'
#!/usr/bin/env bash
# fake agent: preflight only needs `command -v claude` to resolve outside Termux
exit 0
EOF
chmod +x "$tmp/bin/claude"
APATH="$tmp/bin:$PATH"

# 5a. dry-run: parses an open task, would cut a slug branch, leaves backlog alone
# (a real workspace has BACKLOG.md + PIXEL_AGENT.md committed, so the tree is clean)
ws="$tmp/ws1"; mkdir -p "$ws"; git -C "$ws" init -q 2>/dev/null
printf -- '- [ ] Add a .pixel-lab.json to fix stack detection\n' > "$ws/BACKLOG.md"
printf '# test charter\n' > "$ws/PIXEL_AGENT.md"
printf '.autodev/\n' > "$ws/.gitignore"   # runner writes run-logs here; ignore like this repo does
git -C "$ws" add -A && git -C "$ws" -c user.name=t -c user.email=t@t commit -qm init
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

# --- 6. --timeout contract ------------------------------------------------------
# mk_ws <dir>: fixture git workspace with a clean tree (repo-local identity,
# committed charter + .gitignore). Caller then writes BACKLOG.md and commits.
mk_ws(){
  local d="$1"; mkdir -p "$d"; git -C "$d" init -q 2>/dev/null
  git -C "$d" config user.name t; git -C "$d" config user.email t@t
  printf '# test charter\n' > "$d/PIXEL_AGENT.md"
  printf '.autodev/\n' > "$d/.gitignore"
  git -C "$d" add -A && git -C "$d" commit -qm init >/dev/null
}
# preflight also needs a `codex` binary to resolve (CI images may lack one)
cat > "$tmp/bin/codex" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$tmp/bin/codex"

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
cat > "$tmp/bin/fake-claude" <<'EOF'
#!/usr/bin/env bash
echo fake-change > agent-made-change.txt
echo "fake claude: made one change"
exit 0
EOF
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
cat > "$tmp/bin/slow-agent" <<'EOF'
#!/usr/bin/env bash
sleep 30
exit 0
EOF
chmod +x "$tmp/bin/slow-agent"
ws8="$tmp/ws8"; mk_ws "$ws8"
printf -- '- [ ] Probe claude timeout path\n' > "$ws8/BACKLOG.md"
git -C "$ws8" add -A && git -C "$ws8" commit -qm task >/dev/null
out="$(env PATH="$APATH" CLAUDE_BIN="$tmp/bin/slow-agent" bash "$ROOT/pixel-autodev.sh" --workspace="$ws8" --timeout=1 2>&1)"; rc=$?
if [ $rc -eq 0 ] && case "$out" in *"timed out after 1s"*) true;; *) false;; esac \
   && [ -z "$(git -C "$ws8" branch --list 'auto/*')" ] \
   && grep -q '^- \[ \] Probe claude timeout path' "$ws8/BACKLOG.md"; then
  t_ok "claude backend: 1s timeout kills stub, branch reverted, task stays open"
else
  t_fail "claude timeout path" "rc=$rc"$'\n'"$out"
fi
ws9="$tmp/ws9"; mk_ws "$ws9"
printf -- '- [ ] Probe codex timeout path\n' > "$ws9/BACKLOG.md"
git -C "$ws9" add -A && git -C "$ws9" commit -qm task >/dev/null
out="$(env PATH="$APATH" CODEX_BIN="$tmp/bin/slow-agent" bash "$ROOT/pixel-autodev.sh" --workspace="$ws9" --agent=codex --timeout=1 2>&1)"; rc=$?
if [ $rc -eq 0 ] && case "$out" in *"timed out after 1s"*) true;; *) false;; esac \
   && [ -z "$(git -C "$ws9" branch --list 'auto/*')" ] \
   && grep -q '^- \[ \] Probe codex timeout path' "$ws9/BACKLOG.md"; then
  t_ok "codex backend: 1s timeout kills stub, branch reverted, task stays open"
else
  t_fail "codex timeout path" "rc=$rc"$'\n'"$out"
fi

# --- summary ------------------------------------------------------------------
echo
printf 'passed: %d   failed: %d   skipped: %d\n' "$PASS" "$FAIL" "$SKIP"
[ "$FAIL" -eq 0 ]
