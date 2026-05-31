#!/bin/sh
# macos/brew-tracker/brew-diff.sh
# Zeigt was sich seit dem letzten Commit (oder seit einem bestimmten Commit) geaendert hat.
#
# Ausfuehren:
#   bash ~/git/bootstrap-foundation/macos/brew-tracker/brew-diff.sh
#   bash ~/git/bootstrap-foundation/macos/brew-tracker/brew-diff.sh <commit-hash>
#
# Umgebungsvariablen (optional):
#   BREW_TRACKER_DIR   Verzeichnis mit dem tracker-Repo  (default: ~/git/brew-tracker)

BREW_TRACKER_DIR="${BREW_TRACKER_DIR:-$HOME/git/brew-tracker}"
REF="${1:-HEAD~1}"

if [ ! -d "${BREW_TRACKER_DIR}/.git" ]; then
  echo "[brew-diff] Kein Git-Repo unter ${BREW_TRACKER_DIR}"
  echo "Bitte erst setup.sh ausfuehren."
  exit 1
}

COMMIT_COUNT=$(git -C "${BREW_TRACKER_DIR}" rev-list --count HEAD 2>/dev/null || echo 0)
if [ "$COMMIT_COUNT" -lt 2 ]; then
  echo '[brew-diff] Noch keine Aenderungen seit dem ersten Snapshot.'
  echo ''
  echo 'Aktueller Zustand:'
  cat "${BREW_TRACKER_DIR}/Brewfile"
  exit 0
fi

echo ''
echo '================================================'
echo "  brew-diff: Aenderungen seit ${REF}"
echo '================================================'
echo ''

# Installierte Pakete (neu hinzugekommen)
echo '++ Installiert:'
git -C "${BREW_TRACKER_DIR}" diff "${REF}" HEAD -- Brewfile \
  | grep '^+' | grep -v '^+++' | grep -v '^+#' \
  | sed 's/^+/  + /' || echo '  (keine)'

echo ''

# Deinstallierte Pakete (entfernt)
echo '-- Deinstalliert:'
git -C "${BREW_TRACKER_DIR}" diff "${REF}" HEAD -- Brewfile \
  | grep '^-' | grep -v '^---' | grep -v '^-#' \
  | sed 's/^-/  - /' || echo '  (keine)'

echo ''
echo 'Vollstaendiger Verlauf:'
git -C "${BREW_TRACKER_DIR}" log --oneline
echo ''
