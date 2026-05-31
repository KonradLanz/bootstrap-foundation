#!/usr/bin/env bash
# macos/02-gh-auth.sh
# ---------------------------------------------------------------------------
# GitHub CLI (gh) authentifizieren.
#
# Ablauf:
#   1. gh auth login  (Browser oder PAT - interaktiv)
#   2. git credential-helper auf gh setzen
#   3. git user.name + user.email abfragen (falls noch nicht gesetzt)
#
# Voraussetzung: brew install gh
# ---------------------------------------------------------------------------
set -euo pipefail

GITHUB_USER="${GITHUB_USER:-KonradLanz}"
GIT_BASE="${GIT_BASE:-$HOME/git}"

# Homebrew PATH sicherstellen (Apple Silicon)
if [[ -f /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

if ! command -v gh >/dev/null 2>&1; then
  echo 'gh nicht gefunden. Installiere via Homebrew...'
  brew install gh
fi

echo
echo '=== GitHub CLI Authentifizierung ==='

if gh auth status >/dev/null 2>&1; then
  echo 'gh ist bereits angemeldet:'
  gh auth status
  echo
  read -r -p 'Neu authentifizieren? [y/N] ' REDO
  [[ "$REDO" =~ ^[Yy]$ ]] || { echo 'Uebersprungen.'; exit 0; }
fi

echo
echo 'Authentifizierungsmethode waehlen:'
echo '  1) Browser (empfohlen fuer interaktive Nutzung)'
echo '  2) Personal Access Token (PAT) manuell eingeben'
read -r -p 'Auswahl [1]: ' AUTH_METHOD
AUTH_METHOD="${AUTH_METHOD:-1}"

case "$AUTH_METHOD" in
  2)
    echo
    echo 'PAT erzeugen unter:'
    echo '  https://github.com/settings/tokens/new'
    echo '  Benoetigt: repo, read:org, workflow'
    echo
    printf 'PAT einfuegen: '
    stty -echo 2>/dev/null || true
    read -r GH_TOKEN_INPUT
    stty echo 2>/dev/null || true
    printf '\n'
    printf '%s' "$GH_TOKEN_INPUT" | gh auth login --with-token
    GH_TOKEN_INPUT=""
    ;;
  *)
    gh auth login \
      --hostname github.com \
      --git-protocol https \
      --web
    ;;
esac

echo
echo '=== git credential helper auf gh setzen ==='
gh auth setup-git
echo '  git credential helper: OK'

echo
echo '=== git Identitaet pruefen ==='
CURR_NAME=$(git config --global user.name 2>/dev/null || true)
CURR_MAIL=$(git config --global user.email 2>/dev/null || true)

if [[ -z "$CURR_NAME" ]]; then
  read -r -p 'git user.name (z.B. Konrad Lanz): ' GIT_NAME
  git config --global user.name "$GIT_NAME"
else
  echo "  user.name:  ${CURR_NAME} (unveraendert)"
fi

if [[ -z "$CURR_MAIL" ]]; then
  read -r -p 'git user.email: ' GIT_MAIL
  git config --global user.email "$GIT_MAIL"
else
  echo "  user.email: ${CURR_MAIL} (unveraendert)"
fi

git config --global init.defaultBranch main
git config --global pull.rebase false
git config --global core.autocrlf input

echo
echo '=== Fertig ==='
gh auth status
echo
echo 'Naechster Schritt:'
echo "  bash ${GIT_BASE}/bootstrap-foundation/macos/03-gh-token-keepass.sh"
