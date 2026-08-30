#!/bin/sh
# bootstrap-foundation/android/bootstrap.sh
# Termux bootstrap for Android — part of bootstrap-foundation
# Run AFTER manually installing Termux from F-Droid.
#
# One-liner:
#   curl -fsSL https://raw.githubusercontent.com/KonradLanz/bootstrap-foundation/main/android/bootstrap.sh | sh
#
# Optional env vars:
#   KL_GITHUB_USER     GitHub username (default: KonradLanz)
#   KL_FORGEJO_HOST    Internal Forgejo host (e.g. forgejo.own.dedyn.io)
#   KL_FORGEJO_PORT    SSH port for Forgejo (default: 2222)
#   KL_GIT_EMAIL       Git author email
#   KL_GIT_NAME        Git author name
#   KL_SKIP_ACODE      Set to 1 to skip Acode install hint
#   KL_RUN_MODE        unassisted | interactive | auto (default: auto)

set -e

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
GITHUB_USER="${KL_GITHUB_USER:-KonradLanz}"
FORGEJO_HOST="${KL_FORGEJO_HOST:-}"
FORGEJO_PORT="${KL_FORGEJO_PORT:-2222}"
GIT_EMAIL="${KL_GIT_EMAIL:-}"
GIT_NAME="${KL_GIT_NAME:-Konrad}"
RUN_MODE="${KL_RUN_MODE:-auto}"

_tty() { [ "$RUN_MODE" = 'interactive' ] || { [ "$RUN_MODE" = 'auto' ] && [ -t 0 ]; }; }

_ask() {
  # _ask VAR PROMPT DEFAULT
  _var="$1"; _prompt="$2"; _default="$3"
  if _tty; then
    printf '%s [%s]: ' "$_prompt" "$_default"
    read -r _input
    eval "$_var=\"${_input:-$_default}\""
  else
    eval "$_var=\"$_default\""
  fi
}

_info()  { printf '\033[1;34m=> %s\033[0m\n' "$*"; }
_ok()    { printf '\033[1;32m   ok: %s\033[0m\n' "$*"; }
_warn()  { printf '\033[1;33m   !! %s\033[0m\n' "$*"; }
_step()  { printf '\n\033[1;36m--- %s ---\033[0m\n' "$*"; }

# ---------------------------------------------------------------------------
# 1. Storage permission
# ---------------------------------------------------------------------------
_step '1/7 Storage access'
if [ ! -d "$HOME/storage" ]; then
  _info 'Requesting storage access...'
  termux-setup-storage || _warn 'termux-setup-storage failed — run manually if needed'
else
  _ok 'Storage already set up'
fi

# ---------------------------------------------------------------------------
# 2. Package update
# ---------------------------------------------------------------------------
_step '2/7 Package update'
_info 'pkg update && upgrade'
pkg update -y && pkg upgrade -y

# ---------------------------------------------------------------------------
# 3. Base packages
# ---------------------------------------------------------------------------
_step '3/7 Base packages'
BASE_PKGS="git openssh curl wget python nodejs vim termux-api"
_info "Installing: $BASE_PKGS"
# shellcheck disable=SC2086
pkg install -y $BASE_PKGS

# ---------------------------------------------------------------------------
# 4. Shell helpers
# ---------------------------------------------------------------------------
_step '4/7 Shell helpers'
if ! grep -q 'alias g=' "$HOME/.bashrc" 2>/dev/null; then
  cat >> "$HOME/.bashrc" << 'BASHRC'

# --- bootstrap-foundation android helpers ---
alias g='git'
alias gs='git status'
alias gl='git log --oneline -10'
alias gp='git push'
alias gpl='git pull'
alias ga='git add -A'
alias gc='git commit -m'

_kl_commit_push() {
  msg="${*:-update}"
  git add -A && git commit -m "$msg" && git push
}
alias gcp='_kl_commit_push'
# Usage: gcp "feat: my message"  =>  add + commit + push in one command
BASHRC
  _ok 'Shell aliases written to ~/.bashrc'
else
  _ok 'Shell aliases already present'
fi

# ---------------------------------------------------------------------------
# 5. SSH key setup
# ---------------------------------------------------------------------------
_step '5/7 SSH key'
SSH_KEY="$HOME/.ssh/id_ed25519"
if [ ! -f "$SSH_KEY" ]; then
  _info 'Generating ed25519 SSH key...'
  mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
  _ask GIT_EMAIL 'Git email' "${GIT_EMAIL:-phone@koni}"
  ssh-keygen -t ed25519 -C "$GIT_EMAIL" -f "$SSH_KEY" -N ''
  _ok "Key created: $SSH_KEY"
else
  _ok "SSH key already exists: $SSH_KEY"
fi

printf '\n\033[1;33mYour public key (add to GitHub + Forgejo):\033[0m\n'
cat "${SSH_KEY}.pub"
printf '\n'

# ---------------------------------------------------------------------------
# 6. Git global config
# ---------------------------------------------------------------------------
_step '6/7 Git config'
_ask GIT_NAME  'Git author name'  "$GIT_NAME"
_ask GIT_EMAIL 'Git author email' "${GIT_EMAIL:-${GIT_NAME}@koni}"
git config --global user.name  "$GIT_NAME"
git config --global user.email "$GIT_EMAIL"
git config --global init.defaultBranch main
git config --global pull.rebase false
_ok "git config: $GIT_NAME <$GIT_EMAIL>"

# GitHub SSH config
mkdir -p "$HOME/.ssh"
if ! grep -q 'Host github.com' "$HOME/.ssh/config" 2>/dev/null; then
  cat >> "$HOME/.ssh/config" << EOF

Host github.com
  HostName github.com
  User git
  IdentityFile $SSH_KEY
  StrictHostKeyChecking accept-new
EOF
  chmod 600 "$HOME/.ssh/config"
  _ok 'github.com SSH entry added'
fi

# Optional: Forgejo SSH config
if [ -n "$FORGEJO_HOST" ]; then
  if ! grep -q "Host forgejo-home" "$HOME/.ssh/config" 2>/dev/null; then
    cat >> "$HOME/.ssh/config" << EOF

Host forgejo-home
  HostName $FORGEJO_HOST
  Port $FORGEJO_PORT
  User git
  IdentityFile $SSH_KEY
  StrictHostKeyChecking accept-new
EOF
    _ok "forgejo-home SSH entry added ($FORGEJO_HOST:$FORGEJO_PORT)"
  else
    _ok 'forgejo-home SSH entry already present'
  fi
fi

# ---------------------------------------------------------------------------
# 7. Clone bootstrap repos
# ---------------------------------------------------------------------------
_step '7/7 Clone bootstrap-foundation'
PROJECTS="$HOME/projects"
mkdir -p "$PROJECTS"

_clone_or_pull() {
  _repo_url="$1"; _dir="$2"
  if [ -d "$_dir/.git" ]; then
    _info "Updating $_dir"
    git -C "$_dir" pull --ff-only || _warn "pull failed — check manually"
  else
    _info "Cloning $_repo_url"
    git clone "$_repo_url" "$_dir"
  fi
}

_clone_or_pull "git@github.com:${GITHUB_USER}/bootstrap-foundation.git" \
  "$PROJECTS/bootstrap-foundation"

# bw-minimal is useful on mobile too
if [ -n "$GITHUB_USER" ]; then
  _clone_or_pull "git@github.com:${GITHUB_USER}/bw-minimal.git" \
    "$PROJECTS/bw-minimal" 2>/dev/null || \
    _warn 'bw-minimal clone skipped (repo not accessible or not needed)'
fi

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
printf '\n\033[1;32m=== Android/Termux bootstrap complete ===\033[0m\n'
if [ "${KL_SKIP_ACODE:-0}" != '1' ]; then
  printf '\n\033[1;33mNext steps:\033[0m\n'
  printf '  1. Install Acode from Play Store (or F-Droid)\n'
  printf '  2. In Acode: Settings > Terminal > enable Termux integration\n'
  printf '  3. Add your public key to GitHub: https://github.com/settings/keys\n'
  if [ -n "$FORGEJO_HOST" ]; then
    printf '  4. Add your public key to Forgejo: https://%s/-/user/settings/keys\n' "$FORGEJO_HOST"
  fi
  printf '  5. Test: ssh -T git@github.com\n'
fi
printf '\n  Quick alias: gcp "your message"  =>  git add -A + commit + push\n'
printf '\n'
