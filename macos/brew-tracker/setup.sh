#!/bin/sh
# macos/brew-tracker/setup.sh
# Erstellt das lokale brew-tracker Git-Repo und legt den Anfangs-Brewfile-Snapshot an.
#
# Ausfuehren (einmalig auf jedem Mac):
#   bash ~/git/bootstrap-foundation/macos/brew-tracker/setup.sh
#
# Umgebungsvariablen (optional):
#   BREW_TRACKER_DIR   Zielverzeichnis fuer das tracker-Repo  (default: ~/git/brew-tracker)
#   BREW_TRACKER_REMOTE  optionale Remote-URL (z.B. git@github.com:KonradLanz/brew-tracker.git)

set -e

BREW_TRACKER_DIR="${BREW_TRACKER_DIR:-$HOME/git/brew-tracker}"
BREW_TRACKER_REMOTE="${BREW_TRACKER_REMOTE:-}"

echo ''
echo '================================================'
echo '  brew-tracker: Setup'
echo '================================================'
echo ''

# 1) Verzeichnis anlegen
echo '[1/4] Verzeichnis anlegen...'
mkdir -p "${BREW_TRACKER_DIR}"

# 2) Git-Repo initialisieren
echo '[2/4] Git-Repo initialisieren...'
if [ ! -d "${BREW_TRACKER_DIR}/.git" ]; then
  git -C "${BREW_TRACKER_DIR}" init
  echo "      Init: ${BREW_TRACKER_DIR}"
else
  echo '      Git-Repo existiert bereits.'
fi

# 3) Remote konfigurieren (optional)
if [ -n "${BREW_TRACKER_REMOTE}" ]; then
  echo '[3/4] Remote konfigurieren...'
  if git -C "${BREW_TRACKER_DIR}" remote get-url origin >/dev/null 2>&1; then
    git -C "${BREW_TRACKER_DIR}" remote set-url origin "${BREW_TRACKER_REMOTE}"
    echo "      Remote aktualisiert: ${BREW_TRACKER_REMOTE}"
  else
    git -C "${BREW_TRACKER_DIR}" remote add origin "${BREW_TRACKER_REMOTE}"
    echo "      Remote hinzugefuegt: ${BREW_TRACKER_REMOTE}"
  fi
else
  echo '[3/4] Remote konfigurieren... (uebersprungen, keine BREW_TRACKER_REMOTE gesetzt)'
fi

# 4) Ersten Brewfile-Snapshot erstellen
echo '[4/4] Aktuellen Homebrew-Zustand snapshotten...'
brew bundle dump --force --file="${BREW_TRACKER_DIR}/Brewfile"
echo "      Brewfile erstellt: $(wc -l < "${BREW_TRACKER_DIR}/Brewfile" | tr -d ' ') Zeilen"

git -C "${BREW_TRACKER_DIR}" add -A
git -C "${BREW_TRACKER_DIR}" commit -m "initial snapshot [$(date '+%Y-%m-%d %H:%M')]"

echo ''
echo '================================================'
echo '  brew-tracker Setup abgeschlossen!'
echo '================================================'
echo ''
echo "Tracker-Repo:   ${BREW_TRACKER_DIR}"
echo ''
echo 'Hook aktivieren - einmalig in .zshrc eintragen:'
echo '  echo '\''source ~/git/bootstrap-foundation/macos/brew-tracker/brew-hook.sh'\'' >> ~/.zshrc'
echo '  source ~/.zshrc'
echo ''
if [ -n "${BREW_TRACKER_REMOTE}" ]; then
  echo 'Aenderungen pushen:'
  echo "  git -C ${BREW_TRACKER_DIR} push -u origin main"
  echo ''
fi
echo 'Verlauf ansehen:'
echo "  git -C ${BREW_TRACKER_DIR} log --oneline"
echo "  bash ~/git/bootstrap-foundation/macos/brew-tracker/brew-diff.sh"
echo ''
