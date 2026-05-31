#!/bin/sh
# macos/brew-tracker/setup.sh  — idempotent
# Beliebig oft aufrufbar: ueberspringt bereits erledigte Schritte.
#
# Umgebungsvariablen (optional):
#   BREW_TRACKER_DIR     Zielverzeichnis (default: ~/git/brew-tracker)
#   BREW_TRACKER_REMOTE  Remote-URL      (optional)

set -e

BREW_TRACKER_DIR="${BREW_TRACKER_DIR:-$HOME/git/brew-tracker}"
BREW_TRACKER_REMOTE="${BREW_TRACKER_REMOTE:-}"

_ok()   { printf '  [OK]  %s\n' "$1"; }
_skip() { printf '  [--]  %s\n' "$1"; }
_run()  { printf '  [>>]  %s\n' "$1"; }

# Homebrew PATH (Apple Silicon)
[ -f /opt/homebrew/bin/brew ] && eval "$(/opt/homebrew/bin/brew shellenv)"

echo ''
echo '================================================'
echo '  brew-tracker: Setup  (idempotent)'
echo '================================================'
echo ''

# 1) Verzeichnis
mkdir -p "${BREW_TRACKER_DIR}"
_skip "Verzeichnis: ${BREW_TRACKER_DIR}"

# 2) Git-Repo
if [ ! -d "${BREW_TRACKER_DIR}/.git" ]; then
  git -C "${BREW_TRACKER_DIR}" init
  _ok 'Git-Repo initialisiert'
else
  _skip 'Git-Repo bereits vorhanden'
fi

# 3) Remote (idempotent)
if [ -n "${BREW_TRACKER_REMOTE}" ]; then
  if git -C "${BREW_TRACKER_DIR}" remote get-url origin >/dev/null 2>&1; then
    CURR=$(git -C "${BREW_TRACKER_DIR}" remote get-url origin)
    if [ "$CURR" = "${BREW_TRACKER_REMOTE}" ]; then
      _skip "Remote bereits gesetzt: ${BREW_TRACKER_REMOTE}"
    else
      git -C "${BREW_TRACKER_DIR}" remote set-url origin "${BREW_TRACKER_REMOTE}"
      _ok "Remote aktualisiert: ${BREW_TRACKER_REMOTE}"
    fi
  else
    git -C "${BREW_TRACKER_DIR}" remote add origin "${BREW_TRACKER_REMOTE}"
    _ok "Remote hinzugefuegt: ${BREW_TRACKER_REMOTE}"
  fi
else
  _skip 'Remote: keine BREW_TRACKER_REMOTE gesetzt'
fi

# 4) Ersten Snapshot — nur wenn noch kein Commit vorhanden
if git -C "${BREW_TRACKER_DIR}" rev-parse HEAD >/dev/null 2>&1; then
  _skip 'Snapshot bereits vorhanden (git log hat Commits)'
else
  _run 'Erstelle initialen Brewfile-Snapshot...'
  brew bundle dump --force --file="${BREW_TRACKER_DIR}/Brewfile"
  LINES=$(wc -l < "${BREW_TRACKER_DIR}/Brewfile" | tr -d ' ')
  git -C "${BREW_TRACKER_DIR}" add -A
  git -C "${BREW_TRACKER_DIR}" commit -m "initial snapshot [$(date '+%Y-%m-%d %H:%M')]"
  _ok "Snapshot erstellt: ${LINES} Zeilen in Brewfile"
fi

echo ''
echo '================================================'
echo '  brew-tracker Setup abgeschlossen!'
echo '================================================'
echo ''
echo "Tracker-Repo: ${BREW_TRACKER_DIR}"
echo ''
echo 'Hook aktivieren (einmalig, falls noch nicht in .zshrc):'
BASE="${GIT_BASE:-$HOME/git}"
echo "  grep -qF 'brew-hook.sh' ~/.zshrc || echo 'source \"${BASE}/bootstrap-foundation/macos/brew-tracker/brew-hook.sh\"' >> ~/.zshrc"
echo ''
