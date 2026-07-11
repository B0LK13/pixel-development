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

# --- summary ------------------------------------------------------------------
echo
printf 'passed: %d   failed: %d   skipped: %d\n' "$PASS" "$FAIL" "$SKIP"
[ "$FAIL" -eq 0 ]
