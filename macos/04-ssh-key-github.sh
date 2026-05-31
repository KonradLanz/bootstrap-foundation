#!/usr/bin/env bash
# macos/04-ssh-key-github.sh
# ---------------------------------------------------------------------------
# Ed25519 SSH-Key erzeugen und bei GitHub registrieren.
#
# Ablauf:
#   1. Pruefe ob ~/.ssh/id_ed25519 existiert, erzeuge falls nicht
#   2. Trage Key in ~/.ssh/config ein (Host github.com)
#   3. Registriere Public Key via gh ssh-key add
#
# Voraussetzung: gh auth status muss OK sein (02-gh-auth.sh ausfuehren)
# ---------------------------------------------------------------------------
set -euo pipefail

GITHUB_USER="${GITHUB_USER:-KonradLanz}"
GIT_BASE="${GIT_BASE:-$HOME/git}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519}"
SSH_KEY_TITLE="${SSH_KEY_TITLE:-$(hostname -s)-$(date +%Y%m%d)}"

# Homebrew PATH
[[ -f /opt/homebrew/bin/brew ]] && eval "$(/opt/homebrew/bin/brew shellenv)"

if ! command -v gh >/dev/null 2>&1; then
  echo 'gh nicht gefunden. Bitte 02-gh-auth.sh ausfuehren.'; exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  echo 'gh nicht angemeldet. Bitte 02-gh-auth.sh ausfuehren.'; exit 1
fi

mkdir -p ~/.ssh
chmod 700 ~/.ssh

echo
echo '=== SSH-Key fuer GitHub ==='

if [[ -f "${SSH_KEY}" ]]; then
  echo "  Vorhandener Key: ${SSH_KEY}"
  read -r -p '  Neuen Key erzeugen und alten ersetzen? [y/N] ' REGEN
  [[ "$REGEN" =~ ^[Yy]$ ]] || { echo '  Uebersprungen.'; SKIP_KEYGEN=1; }
fi

if [[ "${SKIP_KEYGEN:-0}" != "1" ]]; then
  printf '  Passphrase fuer SSH-Key (leer = kein Passwort): '
  stty -echo 2>/dev/null || true
  read -r SSH_PASSPHRASE
  stty echo 2>/dev/null || true
  printf '\n'

  ssh-keygen -t ed25519 -C "${GITHUB_USER}@github" \
    -f "${SSH_KEY}" \
    -N "${SSH_PASSPHRASE}"
  SSH_PASSPHRASE=""
  echo "  Key erzeugt: ${SSH_KEY}"
fi

# ssh-agent + Keychain (macOS)
echo
echo '=== ssh-agent + macOS Keychain ==='
eval "$(ssh-agent -s)"
ssh-add --apple-use-keychain "${SSH_KEY}" 2>/dev/null \
  || ssh-add "${SSH_KEY}" 2>/dev/null \
  || echo '[WARN] ssh-add fehlgeschlagen - Key manuell hinzufuegen.'

# ~/.ssh/config
SSH_CONFIG="$HOME/.ssh/config"
if ! grep -q 'Host github.com' "${SSH_CONFIG}" 2>/dev/null; then
  cat >> "${SSH_CONFIG}" <<EOF

# GitHub - bootstrap-foundation
Host github.com
  HostName github.com
  User git
  IdentityFile ${SSH_KEY}
  AddKeysToAgent yes
  UseKeychain yes
EOF
  chmod 600 "${SSH_CONFIG}"
  echo '  ~/.ssh/config: github.com Eintrag hinzugefuegt.'
else
  echo '  ~/.ssh/config: github.com Eintrag vorhanden (unveraendert).'
fi

# Key bei GitHub registrieren
echo
echo '=== Public Key bei GitHub registrieren ==='
PUB_KEY="${SSH_KEY}.pub"

if gh ssh-key list 2>/dev/null | grep -qF "$(cat "$PUB_KEY")"; then
  echo '  Key bereits bei GitHub registriert.'
else
  gh ssh-key add "${PUB_KEY}" --title "${SSH_KEY_TITLE}"
  echo "  Key registriert als: ${SSH_KEY_TITLE}"
fi

# Verbindungstest
echo
echo '=== Verbindungstest ==='
if ssh -T git@github.com 2>&1 | grep -q 'successfully authenticated'; then
  echo '  SSH-Verbindung zu github.com: OK'
else
  echo '  [INFO] ssh -T git@github.com'
  ssh -T git@github.com 2>&1 || true
fi

echo
echo '=== Fertig ==='
echo "  SSH-Key    : ${SSH_KEY}"
echo "  GitHub-User: ${GITHUB_USER}"
echo
echo 'Repos mit SSH klonen:'
printf '  git clone git@github.com:%s/bootstrap-foundation.git ~/git/bootstrap-foundation\n' "${GITHUB_USER}"
echo
echo 'Bestehende Repos auf SSH umstellen:'
printf '  git -C ~/git/bootstrap-foundation remote set-url origin git@github.com:%s/bootstrap-foundation.git\n' "${GITHUB_USER}"
