# Pixel Lab Kit

**Turn a Google Pixel 10 Pro into an autonomous AI development workstation.**
Termux + proot Ubuntu, the modern AI coding agents (Claude Code, Codex, Gemini,
Aider), one-tap home-screen launchers, and a backlog-driven agent that ships code
while you sleep.

> Userspace only. No root. Every script is idempotent and safe to re-run.

---

## 1. Quick start

**Prerequisite:** install **Termux** from **F-Droid** (or GitHub releases) — *not*
the Play Store build, which is unmaintained. Open Termux, then:

```bash
# one line — replace `B0LK13` with your GitHub username
curl -fsSL https://raw.githubusercontent.com/B0LK13/pixel-development/main/pixel-bootstrap.sh \
  | PIXEL_REPO_BASE=https://raw.githubusercontent.com/B0LK13/pixel-development/main bash
```

Prefer to clone?

```bash
pkg install -y git
git clone https://github.com/B0LK13/pixel-development && cd pixel-development
bash pixel-bootstrap.sh --open-store   # sets up one-tap shortcuts + Termux:Widget
```

Then, from the shortcuts (or the shell): run **Full Setup**, log in to the AI tools,
and start the autonomous loop. Full walkthrough in §5.

---

## 2. What's in the box

| File | Role |
|------|------|
| `pixel-bootstrap.sh` | Entry point. Fetches the setup scripts and creates one-tap **Termux:Widget** home-screen shortcuts. |
| `pixel-dev-setup.sh` | Layer 1 (Termux CLI toolbelt) + Layer 2 (proot **Ubuntu devbox** with Claude Code, Codex, Gemini, Aider, uv, Node 22). |
| `pixel-apps-setup.sh` | Daemons (sshd, Syncthing, optional Tailscale CLI), Nerd Font + extra-keys, boot autostart, and a tap-to-install checklist for the Android GUI apps bash can't install. |
| `pixel-autodev.sh` | Autonomous backlog runner — drives Claude Code headless over `BACKLOG.md`, one task per git branch, verified by the repo's own tests, committed only on green. |
| `KICKSTART.md` | The "go" prompt. Launches a supervised autonomous session that plans, works the backlog, and reports back in a `do_now / choose_path / unblock` block. |

---

## 3. Architecture — why two layers

```
Android (Pixel 10 Pro · aarch64)
└─ Termux  ............ bionic libc — fast native CLI toolbelt
   │  git · gh · ripgrep · fd · fzf · bat · eza · zoxide · nvim · tmux · lazygit · delta
   │  sshd · syncthing · starship · fonts · boot autostart
   └─ proot Ubuntu (devbox)  ... glibc — the AI stack lives here
         claude · codex · gemini · aider · uv · node 22
```

Claude Code, Codex, and Gemini ship **glibc** binaries; Termux uses **bionic**, so
those tools won't install/run natively there. The kit runs your everyday CLI tools
natively in Termux for speed, and isolates the AI agents in a clean glibc Ubuntu
rootfs. Enter it any time with `devbox`.

---

## 4. Requirements

- Google Pixel 10 Pro (or any aarch64 Android device).
- **Termux** from F-Droid; **Termux:Widget** and **Termux:Boot** (also F-Droid) for
  shortcuts and autostart — the apps checklist links them for you.
- A **Claude** plan (Pro / Max / Team / Console) for Claude Code; ChatGPT or an API
  key for Codex; a Google account for Gemini. Aider takes any provider key.
- ~2 GB free space and a data/Wi-Fi connection for the first install.

---

## 5. Full walkthrough

**5.1 Install Termux (F-Droid), open it.**

**5.2 Bootstrap.** Run the one-liner (§1) or `bash pixel-bootstrap.sh --open-store`.
Install **Termux:Widget**, then long-press home → Widgets → Termux:Widget → drag it
on. You now have tappable buttons: `1-Full-Setup … 6-SSH-Info`.

**5.3 Full setup.** Tap **1-Full-Setup** (or `bash pixel-dev-setup.sh && bash pixel-apps-setup.sh`).
This builds the toolbelt, the Ubuntu devbox, the AI stack, daemons, fonts, and the
app checklist. Re-runnable any time.

**5.4 Reload + storage.** Run `termux-reload-settings` (applies font + extra-keys).
Approve the storage popup if you want CLI access to Downloads/DCIM.

**5.5 Log in to the AI tools.** Enter the devbox and authenticate (interactive, once):

```bash
devbox
claude        # browser/device login (Claude Pro/Max/Team/Console)
codex login --device-auth
gemini        # Google sign-in
export ANTHROPIC_API_KEY=...   # or OPENAI_API_KEY=... for aider
```

**5.6 Go autonomous.** See §6.

---

## 6. Autonomous development

Two independent ways to work your backlog. Both live in the devbox and never push.

**6.1 Scripted (mechanical, deterministic):**

```bash
devbox
bash pixel-autodev.sh --dry-run              # show the plan, no agent calls
bash pixel-autodev.sh --max-tasks=3          # work 3 tasks
```

**6.2 Operator prompt (plans, reviews, reports):**

```bash
devbox && cd ~/pixel-lab
claude -p "$(cat KICKSTART.md)" --permission-mode dontAsk \
  --max-turns 60 --max-budget-usd 6
```

**Backlog format** (`~/pixel-lab/BACKLOG.md`, auto-seeded on first run):

```markdown
- [ ] [local-launchpad] Add a .pixel-lab.json to fix `stack: unknown`
- [ ] [pixel-common] Export a helper to read+validate .pixel-lab.json, with a test
```

Open items are `- [ ]`; a leading `[repo]` routes the task to that subfolder. The
runner cuts an `auto/<slug>` branch per task, runs the repo's tests, commits
`feat(auto): …` **only on green**, and flips the line to `- [x]`. Failures keep a
`wip(auto)` branch for review and leave the task open.

**Charter.** Both paths obey `PIXEL_AGENT.md` (auto-seeded): smallest verified slice,
one task = one change, the `.pixel-lab.json` metadata convention, privacy-first, and
"the runner owns git — the agent never commits or pushes."

---

## 7. Guardrails

- Per-task **git branch** + reset-on-failure; **never auto-pushes** (use `--push` to opt in).
- `--permission-mode dontAsk` with a scoped tool **allow**-list and a **deny**-list
  (`git push`, `git reset`, `rm -rf`, `sudo`, `WebFetch`).
- `--max-turns` and `--max-budget-usd` caps + a per-task timeout on every agent call.
- Refuses to run on a dirty tree; refuses if the agent resolves to the Termux binary
  (the PATH-leak guard).
- Runs inside the proot container — no access to the host Android system.

---

## 8. Command reference

```
pixel-bootstrap.sh   [--open-store] [--repo-base=URL]
pixel-dev-setup.sh   [--minimal] [--no-ai] [--yes]
pixel-apps-setup.sh  [--open-stores] [--with-tailscale-cli] [--ssh-port=N] [--no-font] [--yes]
pixel-autodev.sh     [--workspace=DIR] [--backlog=FILE] [--max-tasks=N] [--max-turns=N]
                     [--budget=USD] [--timeout=SECONDS] [--model=sonnet|opus]
                     [--agent=claude|codex] [--yolo] [--push] [--dry-run] [--yes]
```

Every script supports `--help`.

---

## 9. Privacy

Aligned to a privacy-first posture: no telemetry, no third-party calls beyond package
installs and the AI providers you log into, and nothing leaves the device unencrypted.
High-sensitivity work stays in the local container. Review diffs on `auto/*` branches
before merging.

---

## 10. Repo layout

```
pixel-development/
├─ pixel-bootstrap.sh
├─ pixel-dev-setup.sh
├─ pixel-apps-setup.sh
├─ pixel-autodev.sh
├─ tests/run_tests.sh   ← verification gate (syntax, shellcheck, dry-run behaviour)
├─ .pixel-lab.json      ← stack metadata the autodev runner reads for the test command
├─ KICKSTART.md
├─ README.md
├─ LICENSE
└─ .gitignore
```

Keep the scripts at the repo **root** so the `curl | bash` raw URLs resolve.
Run the suite yourself with `bash tests/run_tests.sh` — the autodev runner picks
the same command up from `.pixel-lab.json` when it works tasks in this repo.

---

## 11. License

MIT — see [LICENSE](LICENSE).

*Built for the pixel-lab fleet · The Black Agency / NullPoint Intelligence.*
