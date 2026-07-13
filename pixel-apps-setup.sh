#!/data/data/com.termux/files/usr/bin/bash
###############################################################################
#  pixel-apps-setup.sh                                                        #
#  Companion-app layer for the Pixel 10 Pro AI dev workstation.               #
#                                                                             #
#  WHAT BASH CAN DO  → install/configure Termux CLI + daemon components       #
#                      (sshd, Syncthing, Tailscale CLI), Nerd Font, styling,  #
#                      and Termux:Boot autostart.                             #
#  WHAT BASH CANNOT DO → install Android GUI APKs (Obsidian, GitHub Mobile,   #
#                      KeePassDX, Tailscale app…). Those need F-Droid/Play.    #
#                      So this script ALSO writes a tap-to-install checklist   #
#                      and can open the essential store pages for you.        #
#                                                                             #
#  Pairs with: pixel-dev-setup.sh (the dev/AI toolchain).                     #
#  Usage: bash pixel-apps-setup.sh [--open-stores] [--with-tailscale-cli]     #
#                                  [--ssh-port=N] [--no-font] [--yes] [-h]    #
###############################################################################
set -uo pipefail

# ---------------------------------------------------------------------------
# 0. Config / flags / logging
# ---------------------------------------------------------------------------
SCRIPT_VERSION="1.0.0"
LOG_FILE="${HOME}/pixel-apps-setup.log"
OPEN_STORES=0; TS_CLI=0; NO_FONT=0; SSH_PORT=8022
FAILED=()

for arg in "$@"; do
  case "$arg" in
    --open-stores)        OPEN_STORES=1 ;;
    --with-tailscale-cli) TS_CLI=1 ;;
    --no-font)            NO_FONT=1 ;;
    --yes|-y)             : ;;  # accepted for CLI parity with pixel-dev-setup.sh (no prompts here)
    --ssh-port=*)         SSH_PORT="${arg#*=}" ;;
    --help|-h) sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown flag: $arg (try --help)"; exit 2 ;;
  esac
done

# Validate --ssh-port before any side effect (log file, preflight): it must be
# an integer in 1–65535. Leading zeros are tolerated and canonicalised
# (08022 → 8022), the same convention as pixel-autodev.sh's --timeout.
bad_port(){ echo "pixel-apps-setup: --ssh-port must be an integer between 1 and 65535 (got '$1')" >&2; exit 2; }
case "$SSH_PORT" in
  ''|*[!0-9]*) bad_port "$SSH_PORT" ;;
esac
SSH_PORT="${SSH_PORT#"${SSH_PORT%%[!0]*}"}"   # strip leading zeros (pure string op — no arithmetic)
[ -n "$SSH_PORT" ] || SSH_PORT=0              # "0"/"000…" collapses to 0, rejected below
if [ "${#SSH_PORT}" -gt 5 ] || [ "$SSH_PORT" -lt 1 ] || [ "$SSH_PORT" -gt 65535 ]; then
  bad_port "$SSH_PORT"
fi

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_R=$'\033[0m'; C_B=$'\033[1m'; C_DIM=$'\033[2m'
  RED=$'\033[38;5;203m'; BLU=$'\033[38;5;39m'; GRN=$'\033[38;5;42m'; YLW=$'\033[38;5;221m'
else C_R=; C_B=; C_DIM=; RED=; BLU=; GRN=; YLW=; fi

_log(){ printf '%s %s\n' "$(date '+%H:%M:%S')" "$*" >>"$LOG_FILE" 2>/dev/null; }
step(){ printf '\n%s%s▌ %s%s\n' "$C_B" "$BLU" "$*" "$C_R"; _log "STEP $*"; }
info(){ printf '  %s•%s %s\n' "$BLU" "$C_R" "$*"; _log "INFO $*"; }
ok(){   printf '  %s✔%s %s\n' "$GRN" "$C_R" "$*"; _log "OK   $*"; }
warn(){ printf '  %s▲%s %s\n' "$YLW" "$C_R" "$*" >&2; _log "WARN $*"; }
die(){  printf '\n%s✖ %s%s\n' "$RED" "$*" "$C_R" >&2; _log "FATAL $*"; exit 1; }
have(){ command -v "$1" >/dev/null 2>&1; }
trap 'warn "Step failed near line $LINENO (rc=$?) — continuing; see $LOG_FILE"' ERR

: > "$LOG_FILE" 2>/dev/null || true

banner(){
cat <<EOF
${C_B}${RED}
  ┌────────────────────────────────────────────────┐
  │   PIXEL // APPS  —  companion layer              │
  │   daemons · fonts · autostart · app checklist    │
  └────────────────────────────────────────────────┘${C_R}
  ${C_DIM}v${SCRIPT_VERSION}  ·  log: ${LOG_FILE}${C_R}
EOF
}

# Resilient single-package installer
pkg_one(){
  local p="$1"
  pkg list-installed 2>/dev/null | grep -q "^$p/" && { ok "pkg: $p (present)"; return 0; }
  if pkg install -y "$p" >>"$LOG_FILE" 2>&1; then ok "pkg: $p"
  else warn "pkg failed: $p (skipped)"; FAILED+=("pkg:$p"); fi
}

open_url(){
  if have termux-open-url; then termux-open-url "$1" >/dev/null 2>&1
  elif have am; then am start -a android.intent.action.VIEW -d "$1" >/dev/null 2>&1
  else return 1; fi
}

# ---------------------------------------------------------------------------
# 1. Preflight
# ---------------------------------------------------------------------------
preflight(){
  step "1. Preflight"
  [ -n "${PREFIX:-}" ] && have pkg || die "Run inside Termux (F-Droid build). Install Termux, open it, re-run."
  ok "Termux detected ($(uname -m))"
  yes | pkg update >>"$LOG_FILE" 2>&1 || warn "pkg update had warnings"
}

# ---------------------------------------------------------------------------
# 2. CLI + daemon packages (the installable half of the app list)
# ---------------------------------------------------------------------------
packages(){
  step "2. CLI / daemon packages"
  pkg_one termux-api          # backs the Termux:API app (clipboard, notifications, sensors)
  pkg_one termux-services     # runit service manager for sshd/syncthing
  pkg_one openssh             # sshd — reach the phone over the mesh
  pkg_one syncthing           # P2P no-cloud sync (phone <-> Proxmox <-> desktop)
  pkg_one rsync
  pkg_one ncurses-utils
  [ "$TS_CLI" = 1 ] && pkg_one tailscale  # optional Termux-side Tailscale CLI
}

# ---------------------------------------------------------------------------
# 3. SSH server
# ---------------------------------------------------------------------------
ssh_server(){
  step "3. SSH server (port ${SSH_PORT})"
  mkdir -p "$HOME/.ssh"; chmod 700 "$HOME/.ssh"
  touch "$HOME/.ssh/authorized_keys"; chmod 600 "$HOME/.ssh/authorized_keys"
  # Termux sshd default port is 8022; override if requested.
  if [ "$SSH_PORT" != "8022" ]; then
    if grep -q '^Port ' "$PREFIX/etc/ssh/sshd_config" 2>/dev/null; then
      sed -i "s/^Port .*/Port ${SSH_PORT}/" "$PREFIX/etc/ssh/sshd_config"
    else
      echo "Port ${SSH_PORT}" >> "$PREFIX/etc/ssh/sshd_config"
    fi
  fi
  have sshd && { sshd; ok "sshd started on ${SSH_PORT}"; } || warn "sshd not available"
  info "Add your laptop key:  echo 'ssh-ed25519 AAAA... you' >> ~/.ssh/authorized_keys"
  info "Then from laptop:     ssh -p ${SSH_PORT} \$(whoami)@<phone-ip>"
}

# ---------------------------------------------------------------------------
# 4. Tailscale CLI (optional) + Syncthing
# ---------------------------------------------------------------------------
mesh_and_sync(){
  step "4. Mesh + sync daemons"
  if [ "$TS_CLI" = 1 ] && have tailscaled; then
    mkdir -p "$PREFIX/var/run/tailscale"
    pgrep -f tailscaled >/dev/null 2>&1 || \
      (tailscaled --tun=userspace-networking \
        --socket="$PREFIX/var/run/tailscale/tailscaled.sock" >>"$LOG_FILE" 2>&1 &)
    ok "tailscaled (userspace) started — run: tailscale up   (then open the auth URL)"
  else
    info "Tailscale CLI skipped — the Tailscale Android app is the recommended way to join the mesh."
  fi
  if have syncthing; then
    ok "Syncthing installed — web UI at http://127.0.0.1:8384 once running (see autostart)"
  fi
}

# ---------------------------------------------------------------------------
# 5. Nerd Font + extra-keys + styling
# ---------------------------------------------------------------------------
styling(){
  step "5. Font + extra-keys"
  mkdir -p "$HOME/.termux"
  if [ "$NO_FONT" = 0 ] && [ ! -f "$HOME/.termux/font.ttf" ]; then
    info "Fetching JetBrainsMono Nerd Font (uses mobile data ~30MB)…"
    local tmp="$PREFIX/tmp/jbmono.zip"
    if curl -fsSL -o "$tmp" \
        https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip >>"$LOG_FILE" 2>&1; then
      local ttf
      ttf="$(unzip -Z1 "$tmp" 2>/dev/null | grep -m1 'NerdFontMono-Regular.ttf')"
      [ -z "$ttf" ] && ttf="$(unzip -Z1 "$tmp" 2>/dev/null | grep -m1 'Regular.ttf')"
      if [ -n "$ttf" ] && unzip -o -j "$tmp" "$ttf" -d "$PREFIX/tmp" >>"$LOG_FILE" 2>&1; then
        cp "$PREFIX/tmp/$(basename "$ttf")" "$HOME/.termux/font.ttf" && ok "Nerd Font installed"
      else warn "Could not extract font (skipped)"; fi
      rm -f "$tmp"
    else warn "Font download failed (skipped) — run with --no-font to silence"; fi
  else
    ok "Font step skipped"
  fi

  local PROP="$HOME/.termux/termux.properties"
  if ! grep -q 'extra-keys' "$PROP" 2>/dev/null; then
    cat >> "$PROP" <<'PROPEOF'
extra-keys = [['ESC','/','|','HOME','UP','END','PGUP','DEL'], \
              ['TAB','CTRL','ALT','LEFT','DOWN','RIGHT','PGDN','BKSP']]
PROPEOF
    ok "extra-keys row configured (Esc/Ctrl/Alt/arrows for nvim & tmux)"
  else
    ok "extra-keys already configured"
  fi
  have termux-reload-settings && termux-reload-settings || true
}

# ---------------------------------------------------------------------------
# 6. Termux:Boot autostart scripts
# ---------------------------------------------------------------------------
autostart(){
  step "6. Boot autostart"
  local BOOT="$HOME/.termux/boot"; mkdir -p "$BOOT"
  cat > "$BOOT/10-wakelock-sshd.sh" <<EOF
#!${PREFIX}/bin/sh
termux-wake-lock
sshd
EOF
  cat > "$BOOT/20-syncthing.sh" <<EOF
#!${PREFIX}/bin/sh
syncthing -no-browser >/dev/null 2>&1 &
EOF
  if [ "$TS_CLI" = 1 ]; then
    cat > "$BOOT/15-tailscaled.sh" <<EOF
#!${PREFIX}/bin/sh
tailscaled --tun=userspace-networking --socket=${PREFIX}/var/run/tailscale/tailscaled.sock >/dev/null 2>&1 &
EOF
  fi
  chmod +x "$BOOT"/*.sh
  ok "Boot scripts written to ~/.termux/boot/"
  info "These fire only if the ${C_B}Termux:Boot${C_R} app is installed (see checklist)."
}

# ---------------------------------------------------------------------------
# 7. GUI app checklist (the half bash can't install) + optional store launch
# ---------------------------------------------------------------------------
# rows: Label|source|id-or-query    source = fdroid | play | playsearch
APPS=(
  # --- Necessary Termux add-ons (install from SAME source as Termux) ---
  "Termux:API|fdroid|com.termux.api"
  "Termux:Boot|fdroid|com.termux.boot"
  "Termux:Styling|fdroid|com.termux.styling"
  # --- Recommended ---
  "Tailscale|play|com.tailscale.ipn"
  "Obsidian|play|md.obsidian"
  "GitHub|play|com.github.android"
  "KeePassDX|fdroid|com.kunzisoft.keepass.libre"
  "Syncthing (app)|fdroid|com.nutomic.syncthingandroid"
  "Acode editor|play|com.foxdebug.acode"
  "Termius (SSH)|play|com.server.auditor.ssh.client"
  "Cloudflare WARP|play|com.cloudflare.onedotonedotonedotone"
  # --- Useful / bridges ---
  "KDE Connect|fdroid|org.kde.kdeconnect_tp"
  "Material Files|fdroid|me.zhanghai.android.files"
  "Bitwarden|play|com.x8bit.bitwarden"
  "Claude|play|com.anthropic.claude"
  "ChatGPT|play|com.openai.chatgpt"
  "Gemini|play|com.google.android.apps.bard"
  "Outlook|play|com.microsoft.office.outlook"
  "Google Drive|play|com.google.android.apps.docs"
  "Canva|play|com.canva.editor"
  "Fing|play|com.overlook.android.fing"
  "Hostinger|playsearch|Hostinger hPanel"
)

app_link(){ # source id -> url
  case "$1" in
    fdroid)     printf 'https://f-droid.org/packages/%s/' "$2" ;;
    play)       printf 'https://play.google.com/store/apps/details?id=%s' "$2" ;;
    playsearch) printf 'https://play.google.com/store/search?q=%s&c=apps' "${2// /%20}" ;;
  esac
}

checklist(){
  step "7. GUI app checklist"
  local out="$HOME/pixel-apps-checklist.md"
  [ -d "$HOME/storage/shared" ] && out="$HOME/storage/shared/pixel-apps-checklist.md"
  {
    echo "# Pixel 10 Pro — Android App Checklist"
    echo "_Generated $(date '+%Y-%m-%d %H:%M'). Tap a link to install._"
    echo
    echo "> Install Termux & every \`Termux:*\` add-on from **F-Droid**, never the Play Store build."
    echo
    local row label src id
    for row in "${APPS[@]}"; do
      IFS='|' read -r label src id <<<"$row"
      echo "- [ ] **${label}** — [install]($(app_link "$src" "$id")) \`($src)\`"
    done
  } > "$out" 2>/dev/null && ok "Checklist saved: $out" || warn "Could not write checklist file"

  printf '\n  %sTap-to-install list:%s\n' "$C_B" "$C_R"
  local row label src id
  for row in "${APPS[@]}"; do
    IFS='|' read -r label src id <<<"$row"
    printf '   %s▸%s %-18s %s%s%s\n' "$BLU" "$C_R" "$label" "$C_DIM" "$(app_link "$src" "$id")" "$C_R"
  done

  if [ "$OPEN_STORES" = 1 ]; then
    info "Opening the essential Termux add-on pages (approve installs in F-Droid)…"
    for id in com.termux.api com.termux.boot com.termux.styling; do
      open_url "https://f-droid.org/packages/$id/" || warn "couldn't open $id"
      sleep 2
    done
  else
    info "Re-run with --open-stores to auto-open the essential add-on pages."
  fi
}

# ---------------------------------------------------------------------------
summary(){
  step "8. Summary"
  [ "${#FAILED[@]}" -gt 0 ] && warn "Skipped: ${FAILED[*]}"
  cat <<EOF

${C_B}Reload Termux now:${C_R}  termux-reload-settings   ${C_DIM}# applies font + extra-keys${C_R}
${C_B}Start a service by hand:${C_R}
  sshd                         ${C_DIM}# ssh server on ${SSH_PORT}${C_R}
  syncthing -no-browser &      ${C_DIM}# then open http://127.0.0.1:8384${C_R}

${C_B}Autostart on boot${C_R} needs the Termux:Boot app (top of the checklist).
${C_B}Mesh:${C_R} use the Tailscale Android app to join; the Pixel then appears to your fleet.
EOF
  printf '\n%s%s✔ Companion layer ready.%s\n' "$C_B" "$GRN" "$C_R"
}

main(){
  banner; preflight; packages; ssh_server; mesh_and_sync; styling; autostart; checklist; summary
}
main "$@"
