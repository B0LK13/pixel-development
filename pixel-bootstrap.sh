#!/data/data/com.termux/files/usr/bin/bash
###############################################################################
#  pixel-bootstrap.sh — one-tap installer for the Pixel 10 Pro dev kit        #
#                                                                             #
#  "One tap" on Android = Termux:Widget. This script drops launcher scripts   #
#  into ~/.shortcuts/ so the Termux:Widget app turns them into home-screen    #
#  buttons. It also finds (or downloads) the two setup scripts so the very    #
#  first run is a single paste.                                               #
#                                                                             #
#  First-run one-liner (if you host the scripts):                             #
#    curl -fsSL <BASE>/pixel-bootstrap.sh | PIXEL_REPO_BASE=<BASE> bash       #
#  Or save all three .sh files together and run:  bash pixel-bootstrap.sh     #
#                                                                             #
#  Usage: bash pixel-bootstrap.sh [--open-store] [--repo-base=URL] [-h]       #
###############################################################################
set -uo pipefail

REPO_BASE="${PIXEL_REPO_BASE:-https://raw.githubusercontent.com/B0LK13/pixel-development/main}"
DEST="$HOME/.local/share/pixel"
SHORTCUTS="$HOME/.shortcuts"
SETUP_SCRIPTS="pixel-dev-setup.sh pixel-apps-setup.sh"
OPEN_STORE=0

for arg in "$@"; do
  case "$arg" in
    --open-store)   OPEN_STORE=1 ;;
    --repo-base=*)  REPO_BASE="${arg#*=}" ;;
    --help|-h) sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown flag: $arg (try --help)"; exit 2 ;;
  esac
done

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_R=$'\033[0m'; C_B=$'\033[1m'; C_DIM=$'\033[2m'
  RED=$'\033[38;5;203m'; BLU=$'\033[38;5;39m'; GRN=$'\033[38;5;42m'; YLW=$'\033[38;5;221m'
else C_R=; C_B=; C_DIM=; RED=; BLU=; GRN=; YLW=; fi
step(){ printf '\n%s%s▌ %s%s\n' "$C_B" "$BLU" "$*" "$C_R"; }
info(){ printf '  %s•%s %s\n' "$BLU" "$C_R" "$*"; }
ok(){   printf '  %s✔%s %s\n' "$GRN" "$C_R" "$*"; }
warn(){ printf '  %s▲%s %s\n' "$YLW" "$C_R" "$*" >&2; }
die(){  printf '\n%s✖ %s%s\n' "$RED" "$*" "$C_R" >&2; exit 1; }
have(){ command -v "$1" >/dev/null 2>&1; }

# ---------------------------------------------------------------------------
# 1. Preflight
# ---------------------------------------------------------------------------
[ -n "${PREFIX:-}" ] && have pkg || die "Run inside Termux (F-Droid build)."
step "1. Preparing directories"
mkdir -p "$DEST" "$SHORTCUTS" "$SHORTCUTS/tasks"
ok "$DEST  +  $SHORTCUTS"

# ---------------------------------------------------------------------------
# 2. Locate or download the two setup scripts
# ---------------------------------------------------------------------------
step "2. Resolving setup scripts"
SEARCH_DIRS=("$DEST" "$HOME" "$PWD" "$HOME/storage/shared/Download" "$HOME/downloads" "$HOME/storage/downloads")
for s in $SETUP_SCRIPTS; do
  if [ -f "$DEST/$s" ]; then ok "$s (cached)"; continue; fi
  found=""
  for d in "${SEARCH_DIRS[@]}"; do
    [ -f "$d/$s" ] && { found="$d/$s"; break; }
  done
  if [ -n "$found" ]; then
    cp "$found" "$DEST/$s" && ok "$s (copied from ${found%/*})"
  elif curl -fsSL -o "$DEST/$s" "$REPO_BASE/$s" 2>/dev/null; then
    ok "$s (downloaded)"
  else
    warn "$s not found locally and download failed."
    info "Put it next to this script, or set --repo-base=<URL where it's hosted>."
  fi
  chmod +x "$DEST/$s" 2>/dev/null || true
done

# ---------------------------------------------------------------------------
# 3. Build the home-screen shortcuts
# ---------------------------------------------------------------------------
step "3. Creating one-tap shortcuts (~/.shortcuts/)"

# mkshortcut <filename>  — body comes from stdin; Termux shebang auto-prepended
mkshortcut(){
  local name="$1"
  { echo "#!$PREFIX/bin/bash"; cat; } > "$SHORTCUTS/$name"
  chmod +x "$SHORTCUTS/$name"
  ok "shortcut: $name"
}

mkshortcut "1-Full-Setup" <<EOF
# Full deploy: dev/AI toolchain, then companion-app layer
set -e
echo "=== FULL SETUP ==="
bash "$DEST/pixel-dev-setup.sh"
bash "$DEST/pixel-apps-setup.sh"
echo; echo "Done. Press enter to close."; read _
EOF

mkshortcut "2-Dev-Setup" <<EOF
# Toolchain + AI devbox only
bash "$DEST/pixel-dev-setup.sh"
echo; echo "Press enter to close."; read _
EOF

mkshortcut "3-Apps-Setup" <<EOF
# Daemons, fonts, autostart + app checklist
bash "$DEST/pixel-apps-setup.sh"
echo; echo "Press enter to close."; read _
EOF

mkshortcut "4-Enter-Devbox" <<'EOF'
# Drop straight into the Ubuntu AI layer
exec proot-distro login ubuntu --shared-tmp
EOF

mkshortcut "5-Update-AI" <<'EOF'
# Update Claude Code / Codex / Gemini / Aider with a leak-proof PATH
proot-distro login ubuntu -- bash -lc '
  export PATH=/root/.npm-global/bin:/root/.local/bin:/usr/local/bin:/usr/bin:/bin
  hash -r
  echo "node: $(command -v node)"
  npm install -g @openai/codex@latest @google/gemini-cli@latest 2>/dev/null || true
  curl -fsSL https://claude.ai/install.sh | bash 2>/dev/null || true
  command -v uv >/dev/null && uv tool upgrade aider-chat 2>/dev/null || true
  echo; claude --version 2>/dev/null; codex --version 2>/dev/null; gemini --version 2>/dev/null
'
echo; echo "Press enter to close."; read _
EOF

mkshortcut "6-SSH-Info" <<'EOF'
# Start sshd and show how to connect
sshd 2>/dev/null
echo "Phone IP(s):"; (ifconfig 2>/dev/null || ip addr) | grep -Eo 'inet [0-9.]+' | awk '{print "  "$2}'
echo "Port: 8022"
echo "Public key:"; cat "$HOME/.ssh/id_ed25519.pub" 2>/dev/null || echo "  (none — run Dev-Setup first)"
echo; echo "Press enter to close."; read _
EOF

# Silent background task (runs without opening a terminal) — start daemons
mkshortcut "tasks/start-daemons" <<'EOF'
termux-wake-lock
sshd 2>/dev/null
syncthing -no-browser >/dev/null 2>&1 &
EOF

# ---------------------------------------------------------------------------
# 4. Termux:Widget app
# ---------------------------------------------------------------------------
step "4. Termux:Widget app"
if [ "$OPEN_STORE" = 1 ]; then
  url="https://f-droid.org/packages/com.termux.widget/"
  if have termux-open-url; then termux-open-url "$url"
  elif have am; then am start -a android.intent.action.VIEW -d "$url" >/dev/null 2>&1; fi
  ok "Opened Termux:Widget on F-Droid — install it, then add the widget to your home screen."
else
  info "Install the ${C_B}Termux:Widget${C_R} app from F-Droid (com.termux.widget) — re-run with --open-store to open it."
fi

# ---------------------------------------------------------------------------
step "5. Summary"
cat <<EOF

${C_B}You now have these one-tap shortcuts:${C_R}
  ${BLU}1-Full-Setup${C_R}    full deploy (toolchain + AI + apps)
  ${BLU}2-Dev-Setup${C_R}     toolchain + AI devbox
  ${BLU}3-Apps-Setup${C_R}    daemons + fonts + app checklist
  ${BLU}4-Enter-Devbox${C_R}  jump into the Ubuntu AI layer
  ${BLU}5-Update-AI${C_R}     update Claude/Codex/Gemini/Aider (PATH-safe)
  ${BLU}6-SSH-Info${C_R}      start sshd + show IP/key

${C_B}Make them tappable:${C_R}
  1. Install ${C_B}Termux:Widget${C_R} from F-Droid.
  2. Long-press home screen → Widgets → Termux:Widget → drag to home.
  3. Tap any entry to run it.

${C_DIM}Shortcuts live in ~/.shortcuts/ — edit any file to tweak what a tap does.${C_R}
EOF
printf '\n%s%s✔ One-tap layer ready.%s\n' "$C_B" "$GRN" "$C_R"
