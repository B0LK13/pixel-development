#!/usr/bin/env bash
###############################################################################
#  pixel-dev-setup.sh                                                         #
#  Turn a Google Pixel 10 Pro (Termux) into a serious AI dev workstation.     #
#                                                                             #
#  Architecture:                                                              #
#    Layer 1  Termux (aarch64 / bionic) ......... fast native CLI toolbelt    #
#    Layer 2  proot Ubuntu (aarch64 / glibc) .... AI agents + Node/Python     #
#                                                                             #
#  Why two layers? Claude Code / Codex / Gemini ship glibc binaries; Termux   #
#  uses bionic libc, so the AI stack lives in a clean Ubuntu rootfs while the  #
#  snappy everyday tools (git, ripgrep, fzf, nvim, gh) run natively in Termux.#
#                                                                             #
#  Safe by design: userspace only, no root, fully re-runnable (idempotent).   #
#  Usage:   bash pixel-dev-setup.sh [--minimal] [--no-ai] [--yes] [--help]    #
###############################################################################
set -uo pipefail

# ---------------------------------------------------------------------------
# 0. Config, flags, logging
# ---------------------------------------------------------------------------
SCRIPT_VERSION="1.0.0"
LOG_FILE="${HOME}/pixel-dev-setup.log"
DISTRO="ubuntu"
DO_AI=1; MINIMAL=0; ASSUME_YES=0
FAILED=(); INSTALLED=()

for arg in "$@"; do
  case "$arg" in
    --minimal) MINIMAL=1 ;;
    --no-ai)   DO_AI=0 ;;
    --yes|-y)  ASSUME_YES=1 ;;
    --help|-h)
      sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) echo "Unknown flag: $arg (try --help)"; exit 2 ;;
  esac
done

# Colors (graphite/red/electric-blue) with NO_COLOR support
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_R=$'\033[0m'; C_B=$'\033[1m'; C_DIM=$'\033[2m'
  RED=$'\033[38;5;203m'; BLU=$'\033[38;5;39m'; GRN=$'\033[38;5;42m'; YLW=$'\033[38;5;221m'
else
  C_R=; C_B=; C_DIM=; RED=; BLU=; GRN=; YLW=
fi

_ts(){ date '+%H:%M:%S'; }
_log(){ printf '%s %s\n' "$(_ts)" "$*" >>"$LOG_FILE"; }
step(){ printf '\n%s%s▌ %s%s\n' "$C_B" "$BLU" "$*" "$C_R"; _log "STEP $*"; }
info(){ printf '  %s•%s %s\n' "$BLU" "$C_R" "$*"; _log "INFO $*"; }
ok(){   printf '  %s✔%s %s\n' "$GRN" "$C_R" "$*"; _log "OK   $*"; INSTALLED+=("$*"); }
warn(){ printf '  %s▲%s %s\n' "$YLW" "$C_R" "$*" >&2; _log "WARN $*"; }
die(){  printf '\n%s✖ %s%s\n' "$RED" "$*" "$C_R" >&2; _log "FATAL $*"; exit 1; }
have(){ command -v "$1" >/dev/null 2>&1; }

trap 'warn "Step failed near line $LINENO (rc=$?) — continuing; see $LOG_FILE"' ERR

banner(){
cat <<EOF
${C_B}${RED}
  ┌────────────────────────────────────────────────┐
  │   PIXEL // DEV  —  field deployment kit          │
  │   Pixel 10 Pro  ·  Termux + proot Ubuntu         │
  └────────────────────────────────────────────────┘${C_R}
  ${C_DIM}v${SCRIPT_VERSION}  ·  log: ${LOG_FILE}${C_R}
EOF
}

# ---------------------------------------------------------------------------
# 1. Preflight checks
# ---------------------------------------------------------------------------
preflight(){
  step "1. Preflight"
  : > "$LOG_FILE" 2>/dev/null || LOG_FILE="$PREFIX/tmp/pixel-dev-setup.log"
  if [ -z "${PREFIX:-}" ] || ! have pkg; then
    die "This must run inside Termux. Install Termux from F-Droid (NOT the Play Store build), open it, then re-run."
  fi
  local arch; arch="$(uname -m)"
  if [ "$arch" != "aarch64" ]; then
    warn "Detected arch '$arch' (expected aarch64). Continuing, but the AI layer assumes 64-bit ARM."
  else
    ok "Termux on aarch64 confirmed"
  fi
  info "Mode: $([ "$MINIMAL" = 1 ] && echo minimal || echo full)  ·  AI layer: $([ "$DO_AI" = 1 ] && echo on || echo off)"
}

# Resilient installer: try each pkg individually, never abort the whole run
pkg_install(){
  local p
  for p in "$@"; do
    if pkg list-installed 2>/dev/null | grep -q "^$p/"; then
      continue
    fi
    if pkg install -y "$p" >>"$LOG_FILE" 2>&1; then
      ok "pkg: $p"
    else
      warn "pkg failed: $p (skipped — name may differ in your repo)"
      FAILED+=("pkg:$p")
    fi
  done
}

# ---------------------------------------------------------------------------
# 2. Termux base: storage + system update
# ---------------------------------------------------------------------------
termux_base(){
  step "2. Termux base"
  info "Requesting storage access (approve the Android popup if it appears)…"
  termux-setup-storage >/dev/null 2>&1 || warn "storage grant skipped/denied — you can re-run later"
  info "Updating package index…"
  yes | pkg update >>"$LOG_FILE" 2>&1 || warn "pkg update had warnings"
  pkg upgrade -y >>"$LOG_FILE" 2>&1 || warn "pkg upgrade had warnings"
  ok "System updated"
}

# ---------------------------------------------------------------------------
# 3. Native Termux toolbelt (popular GitHub CLIs)
# ---------------------------------------------------------------------------
termux_tools(){
  step "3. Native CLI toolbelt"
  pkg_install \
    git gh openssh curl wget rsync proot-distro tar unzip \
    ripgrep fd fzf bat eza zoxide jq tree ncdu htop \
    neovim tmux lazygit git-delta \
    python nodejs-lts clang make pkg-config \
    starship termux-api termux-tools man
  info "Toolbelt: git/gh/ssh · ripgrep/fd/fzf/bat/eza/zoxide · nvim/tmux/lazygit/delta · python/node"
}

# ---------------------------------------------------------------------------
# 4. SSH key + git identity
# ---------------------------------------------------------------------------
ssh_and_git(){
  step "4. SSH key & git identity"
  if [ ! -f "$HOME/.ssh/id_ed25519" ]; then
    ssh-keygen -t ed25519 -N "" -f "$HOME/.ssh/id_ed25519" -C "pixel-$(date +%Y%m%d)" >>"$LOG_FILE" 2>&1 \
      && ok "ED25519 keypair generated (~/.ssh/id_ed25519.pub)" || warn "ssh-keygen failed"
  else
    ok "SSH key already exists"
  fi

  if ! git config --global user.name >/dev/null 2>&1; then
    if [ "$ASSUME_YES" = 1 ] || [ ! -t 0 ]; then
      git config --global user.name "B0LK13"
      info "git user.name defaulted to 'B0LK13' — change with: git config --global user.name \"You\""
    else
      printf '  %s?%s git user.name: ' "$BLU" "$C_R"; read -r gname
      printf '  %s?%s git user.email: ' "$BLU" "$C_R"; read -r gmail
      git config --global user.name "${gname:-B0LK13}"
      [ -n "${gmail:-}" ] && git config --global user.email "$gmail"
    fi
  fi
  git config --global init.defaultBranch main
  have delta && git config --global core.pager delta 2>/dev/null || true
  ok "git configured (defaultBranch=main$(have delta && echo ', delta pager' || true))"
}

# ---------------------------------------------------------------------------
# 5. Shell experience (starship, aliases, fzf/zoxide)
# ---------------------------------------------------------------------------
shell_setup(){
  step "5. Shell experience"
  local RC="$HOME/.bashrc"
  if ! grep -q 'PIXEL-DEV SHELL' "$RC" 2>/dev/null; then
    cat >> "$RC" <<'RCEOF'

# --- PIXEL-DEV SHELL ---
export EDITOR=nvim
alias ll='eza -lah --git --group-directories-first 2>/dev/null || ls -lah'
alias ls='eza --group-directories-first 2>/dev/null || ls'
alias cat='bat --paging=never 2>/dev/null || cat'
alias gs='git status'
alias gl='git log --oneline --graph --decorate -20'
alias lg='lazygit'
alias v='nvim'
# devbox: drop into the AI Ubuntu layer
alias devbox='proot-distro login ubuntu --shared-tmp'
command -v starship >/dev/null 2>&1 && eval "$(starship init bash)"
command -v zoxide  >/dev/null 2>&1 && eval "$(zoxide init bash)"
[ -f "$PREFIX/share/fzf/key-bindings.bash" ] && source "$PREFIX/share/fzf/key-bindings.bash"
# --- /PIXEL-DEV SHELL ---
RCEOF
    ok "$HOME/.bashrc enhanced (starship prompt, aliases, fzf, zoxide, devbox)"
  else
    ok "Shell config already present"
  fi
}

# ---------------------------------------------------------------------------
# 6. proot Ubuntu "devbox" + AI stack
# ---------------------------------------------------------------------------
devbox_setup(){
  [ "$DO_AI" = 0 ] && { info "Skipping AI layer (--no-ai)"; return 0; }
  [ "$MINIMAL" = 1 ] && { info "Skipping AI layer (--minimal)"; return 0; }
  step "6. Ubuntu devbox + AI agents"

  if ! have proot-distro; then warn "proot-distro missing — cannot build AI layer"; return 0; fi

  local ROOTFS="$PREFIX/var/lib/proot-distro/installed-rootfs/$DISTRO"
  if [ ! -d "$ROOTFS" ]; then
    info "Installing Ubuntu rootfs (one-time, ~150MB download)…"
    proot-distro install "$DISTRO" >>"$LOG_FILE" 2>&1 \
      && ok "Ubuntu rootfs installed" || { warn "Ubuntu install failed — see $LOG_FILE"; return 0; }
  else
    ok "Ubuntu rootfs already installed"
  fi

  # Drop the provisioning script into the rootfs and execute it inside Ubuntu.
  info "Provisioning AI stack inside Ubuntu (Claude Code · Codex · Gemini · Aider · uv · Node 22)…"
  mkdir -p "$ROOTFS/root"
  cat > "$ROOTFS/root/provision-devbox.sh" <<'INNER'
#!/usr/bin/env bash
set -uo pipefail
C_R=$'\033[0m'; C_GRN=$'\033[38;5;42m'; C_BLU=$'\033[38;5;39m'; C_YLW=$'\033[38;5;221m'; C_DIM=$'\033[2m'
[ -n "${NO_COLOR:-}" ] && { C_R=; C_GRN=; C_BLU=; C_YLW=; C_DIM=; }
log(){ printf '%s[devbox]%s %s\n' "$C_BLU" "$C_R" "$*"; }
ok(){  printf '%s[devbox]%s %s\n' "$C_GRN" "$C_R" "$*"; }
warn(){ printf '%s[devbox]%s %s\n' "$C_YLW" "$C_R" "$*" >&2; }
have(){ command -v "$1" >/dev/null 2>&1; }
export DEBIAN_FRONTEND=noninteractive
export PATH="/root/.local/bin:/root/.npm-global/bin:$PATH"

log "Updating apt + base toolchain…"
apt-get update -y -qq || warn "apt update hiccup (continuing)"
apt-get install -y -qq --no-install-recommends \
  build-essential git curl wget ca-certificates gnupg openssh-client \
  ripgrep fd-find python3 python3-pip python3-venv pipx unzip jq less nano \
  || warn "some base packages failed (continuing)"
have fdfind && ln -sf "$(command -v fdfind)" /root/.local/bin/fd 2>/dev/null || true

if ! have node || [ "$(node -v 2>/dev/null | sed 's/v//;s/\..*//')" -lt 20 ] 2>/dev/null; then
  log "Installing Node.js 22 LTS…"
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash - >/dev/null 2>&1 \
    && apt-get install -y -qq nodejs && ok "Node $(node -v)" \
    || warn "Node install failed — npm tools will be skipped"
else
  ok "Node present ($(node -v))"
fi
npm config set prefix /root/.npm-global >/dev/null 2>&1 || true

if ! have uv; then
  log "Installing uv…"
  curl -LsSf https://astral.sh/uv/install.sh | sh >/dev/null 2>&1 && ok "uv installed" || warn "uv failed"
fi

if ! have claude; then
  log "Installing Claude Code (native glibc arm64)…"
  curl -fsSL https://claude.ai/install.sh | bash >/dev/null 2>&1 \
    && ok "Claude Code installed" || warn "Claude Code failed — retry: curl -fsSL https://claude.ai/install.sh | bash"
else ok "Claude Code present"; fi

if have npm && ! have codex; then
  log "Installing OpenAI Codex CLI…"
  npm install -g @openai/codex >/dev/null 2>&1 && ok "Codex installed" || warn "Codex failed"
fi

# Gemini CLI: free/Google One users are being migrated to "Antigravity CLI" in 2026.
if have npm && ! have gemini; then
  log "Installing Gemini CLI…"
  npm install -g @google/gemini-cli >/dev/null 2>&1 && ok "Gemini CLI installed" || warn "Gemini CLI failed"
fi

if have uv && ! have aider; then
  log "Installing Aider…"
  uv tool install --quiet aider-chat >/dev/null 2>&1 && ok "Aider installed" || warn "Aider failed"
fi

RC=/root/.bashrc
grep -q 'PIXEL-DEVBOX PATH' "$RC" 2>/dev/null || cat >> "$RC" <<'RCEOF'

# --- PIXEL-DEVBOX PATH ---
export PATH="$HOME/.local/bin:$HOME/.npm-global/bin:$PATH"
export EDITOR=nano
alias ll='ls -lah --color=auto'
echo "devbox online — claude | codex | gemini | aider | uv | node $(node -v 2>/dev/null)"
# --- /PIXEL-DEVBOX PATH ---
RCEOF
ok "Provisioning complete."
INNER

  if proot-distro login "$DISTRO" -- bash /root/provision-devbox.sh; then
    ok "AI stack provisioned inside Ubuntu devbox"
  else
    warn "Devbox provisioning returned errors — open it with 'devbox' and re-run /root/provision-devbox.sh"
  fi
}

# ---------------------------------------------------------------------------
# 7. Summary + next steps
# ---------------------------------------------------------------------------
summary(){
  step "7. Summary"
  printf '  %s%d components reported success.%s\n' "$GRN" "${#INSTALLED[@]}" "$C_R"
  if [ "${#FAILED[@]}" -gt 0 ]; then
    printf '  %s%d items skipped/failed:%s %s\n' "$YLW" "${#FAILED[@]}" "$C_R" "${FAILED[*]}"
  fi
  cat <<EOF

${C_B}Activate this session:${C_R}  source ~/.bashrc
${C_B}Enter the AI devbox:${C_R}    devbox        ${C_DIM}# proot Ubuntu w/ Claude Code, Codex, Gemini, Aider${C_R}

${C_B}First-time logins (interactive, run inside ${C_DIM}devbox${C_R}${C_B}):${C_R}
  ${BLU}claude${C_R}   → browser/code login  (needs Claude Pro/Max/Team/Console)
  ${BLU}codex${C_R}    → 'Sign in with ChatGPT' or:  codex login --device-auth
  ${BLU}gemini${C_R}   → Google sign-in        (free tier may route to Antigravity CLI)
  ${BLU}aider${C_R}    → export ANTHROPIC_API_KEY=...  or  OPENAI_API_KEY=...

${C_B}Add your SSH key to GitHub:${C_R}
  cat ~/.ssh/id_ed25519.pub        ${C_DIM}# then: gh auth login${C_R}
EOF
}

# ---------------------------------------------------------------------------
main(){
  banner
  preflight
  termux_base
  termux_tools
  ssh_and_git
  shell_setup
  devbox_setup
  summary
  printf '\n%s%s✔ Deployment complete.%s\n' "$C_B" "$GRN" "$C_R"
}
main "$@"
