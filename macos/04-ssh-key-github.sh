#!/usr/bin/env bash
# macos/04-ssh-key-github.sh  — idempotent
# Ed25519 SSH-Key erzeugen und bei GitHub registrieren.
# Beliebig oft aufrufbar: ueberspringt bereits erledigte Schritte.
set -euo pipefail

GITHUB_USER="${GITHUB_USER:-KonradLanz}"
GIT_BASE="${GIT_BASE:-$HOME/git}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519}"
SSH_KEY_TITLE="${SSH_KEY_TITLE:-$(hostname -s)-$(date +%Y%m%d)}"

_ok()   { printf '  [OK]  %s\n' "$1"; }
_skip() { printf '  [--]  %s\n' "$1"; }
_run()  { printf '  [>>]  %s\n' "$1"; }

[[ -f /opt/homebrew/bin/brew ]] && eval "$(/opt/homebrew/bin/brew shellenv)"

if ! command -v gh >/dev/null 2>&1; then
  echo 'gh nicht gefunden — bitte 02-gh-auth.sh ausfuehren.'; exit 1
fi
if ! gh auth status >/dev/null 2>&1; then
  echo 'gh nicht angemeldet — bitte 02-gh-auth.sh ausfuehren.'; exit 1
fi

mkdir -p ~/.ssh
chmod 700 ~/.ssh

echo
echo '=== SSH-Key fuer GitHub (idempotent) ==='

# Key erzeugen
if [[ -f "${SSH_KEY}" ]]; then
  _skip "SSH-Key vorhanden: ${SSH_KEY}"
  read -r -p '  Neuen Key erzeugen (ersetzt bestehenden)? [y/N] ' REGEN
  SKIP_KEYGEN=1
  [[ "$REGEN" =~ ^[Yy]$ ]] && SKIP_KEYGEN=0
else
  SKIP_KEYGEN=0
fi

if [[ "$SKIP_KEYGEN" == "0" ]]; then
  printf '  Passphrase fuer SSH-Key (leer = kein Passwort): '
  stty -echo 2>/dev/null || true
  read -r SSH_PASSPHRASE
  stty echo 2>/dev/null || true
  printf '\n'
  ssh-keygen -t ed25519 -C "${GITHUB_USER}@github" -f "${SSH_KEY}" -N "${SSH_PASSPHRASE}"
  SSH_PASSPHRASE=""
  _ok "Key erzeugt: ${SSH_KEY}"
fi

# ssh-agent + macOS Keychain
echo
echo '=== ssh-agent ==='
eval "$(ssh-agent -s)" >/dev/null
if ssh-add -l 2>/dev/null | grep -qF "${SSH_KEY}"; then
  _skip 'Key bereits im ssh-agent'
else
  ssh-add --apple-use-keychain "${SSH_KEY}" 2>/dev/null \
    || ssh-add "${SSH_KEY}" 2>/dev/null \
    || echo '  [WARN] ssh-add fehlgeschlagen — Key manuell hinzufuegen.'
  _ok 'Key zum ssh-agent hinzugefuegt'
fi

# ~/.ssh/config
echo
echo '=== ~/.ssh/config ==='
SSH_CONFIG="$HOME/.ssh/config"
if grep -q 'Host github.com' "${SSH_CONFIG}" 2>/dev/null; then
  _skip 'github.com Eintrag vorhanden'
else
  cat >> "${SSH_CONFIG}" <<EOF

# GitHub — bootstrap-foundation
Host github.com
  HostName github.com
  User git
  IdentityFile ${SSH_KEY}
  AddKeysToAgent yes
  UseKeychain yes
EOF
  chmod 600 "${SSH_CONFIG}"
  _ok 'github.com Eintrag hinzugefuegt'
fi

# Key bei GitHub registrieren
echo
echo '=== Public Key bei GitHub registrieren ==='
PUB_KEY="${SSH_KEY}.pub"
PUB_CONTENT=$(cat "$PUB_KEY")

if gh ssh-key list 2>/dev/null | grep -qF "$(echo "$PUB_CONTENT" | awk '{print $2}')"; then
  _skip 'Key bereits bei GitHub registriert'
else
  gh ssh-key add "${PUB_KEY}" --title "${SSH_KEY_TITLE}"
  _ok "Key registriert: ${SSH_KEY_TITLE}"
fi

# Remote umstellen (idempotent)
echo
echo '=== Remote auf SSH umstellen ==='
REPO_DIR="${GIT_BASE}/bootstrap-foundation"
if [[ -d "${REPO_DIR}/.git" ]]; then
  CURR_REMOTE=$(git -C "${REPO_DIR}" remote get-url origin 2>/dev/null || true)
  SSH_REMOTE="git@github.com:${GITHUB_USER}/bootstrap-foundation.git"
  if [[ "$CURR_REMOTE" == "$SSH_REMOTE" ]]; then
    _skip "Remote bereits SSH: ${SSH_REMOTE}"
  else
    git -C "${REPO_DIR}" remote set-url origin "${SSH_REMOTE}"
    _ok "Remote auf SSH umgestellt: ${SSH_REMOTE}"
  fi
fi

# Verbindungstest
echo
echo '=== Verbindungstest ==='
if ssh -o BatchMode=yes -o ConnectTimeout=5 -T git@github.com 2>&1 | grep -q 'successfully authenticated'; then
  _ok 'SSH-Verbindung zu github.com'
else
  echo '  [INFO] Teste manuell: ssh -T git@github.com'
fi

echo
echo '=== Fertig ==='
echo "  SSH-Key    : ${SSH_KEY}"
echo "  GitHub-User: ${GITHUB_USER}"
