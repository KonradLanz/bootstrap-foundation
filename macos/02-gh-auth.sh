#!/usr/bin/env bash
# macos/02-gh-auth.sh  — idempotent
# GitHub CLI (gh) authentifizieren.
# Beliebig oft aufrufbar: laeuft durch ohne Aenderungen wenn schon OK.
set -euo pipefail

GITHUB_USER="${GITHUB_USER:-KonradLanz}"
GIT_BASE="${GIT_BASE:-$HOME/git}"

_ok()   { printf '  [OK]  %s\n' "$1"; }
_skip() { printf '  [--]  %s\n' "$1"; }
_run()  { printf '  [>>]  %s\n' "$1"; }

[[ -f /opt/homebrew/bin/brew ]] && eval "$(/opt/homebrew/bin/brew shellenv)"

if ! command -v gh >/dev/null 2>&1; then
  _run 'gh nicht gefunden — installiere via Homebrew...'
  brew install gh
fi

echo
echo '=== GitHub CLI Authentifizierung (idempotent) ==='

if gh auth status >/dev/null 2>&1; then
  _skip 'gh bereits angemeldet:'
  gh auth status
  echo
  read -r -p '  Neu authentifizieren? [y/N] ' REDO
  [[ "$REDO" =~ ^[Yy]$ ]] || { echo '  Uebersprungen.'; STEP_AUTH=0; }
fi

if [[ "${STEP_AUTH:-1}" == "1" ]]; then
  echo
  echo '  Authentifizierungsmethode:'
  echo '    1) Browser (empfohlen)'
  echo '    2) Personal Access Token (PAT)'
  read -r -p '  Auswahl [1]: ' AUTH_METHOD
  AUTH_METHOD="${AUTH_METHOD:-1}"
  case "$AUTH_METHOD" in
    2)
      echo
      printf '  PAT einfuegen (https://github.com/settings/tokens/new  Scopes: repo read:org workflow): '
      stty -echo 2>/dev/null || true
      read -r GH_TOKEN_INPUT
      stty echo 2>/dev/null || true
      printf '\n'
      printf '%s' "$GH_TOKEN_INPUT" | gh auth login --with-token
      GH_TOKEN_INPUT=""
      ;;
    *)
      gh auth login --hostname github.com --git-protocol https --web
      ;;
  esac
  _ok 'gh angemeldet'
fi

# gh als git credential helper setzen (idempotent)
echo
echo '=== git credential helper ==='
if git config --global credential.helper 2>/dev/null | grep -q 'gh auth git-credential'; then
  _skip 'credential helper bereits gesetzt'
else
  gh auth setup-git
  _ok 'credential helper: gh auth git-credential'
fi

# git Identitaet
echo
echo '=== git Identitaet ==='
CURR_NAME=$(git config --global user.name 2>/dev/null || true)
CURR_MAIL=$(git config --global user.email 2>/dev/null || true)

if [[ -n "$CURR_NAME" ]]; then
  _skip "user.name:  ${CURR_NAME}"
else
  read -r -p '  git user.name: ' GIT_NAME
  git config --global user.name "$GIT_NAME"
  _ok "user.name: ${GIT_NAME}"
fi

if [[ -n "$CURR_MAIL" ]]; then
  _skip "user.email: ${CURR_MAIL}"
else
  read -r -p '  git user.email: ' GIT_MAIL
  git config --global user.email "$GIT_MAIL"
  _ok "user.email: ${GIT_MAIL}"
fi

# git defaults (idempotent — git config ueberschreibt harmlos)
git config --global init.defaultBranch main
git config --global pull.rebase false
git config --global core.autocrlf input
_skip 'git defaults gesetzt (init.defaultBranch=main, pull.rebase=false, core.autocrlf=input)'

echo
echo '=== Fertig ==='
gh auth status
echo
echo 'Naechster Schritt:'
echo "  bash ${GIT_BASE}/bootstrap-foundation/macos/03-gh-token-keepass.sh"
