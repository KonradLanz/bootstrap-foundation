#!/bin/sh
# macos/dotfiles-tracker/dotfiles-diff.sh
# Zeigt was sich in den Dotfiles seit dem letzten Commit geaendert hat.
#
# Ausfuehren:
#   bash ~/git/bootstrap-foundation/macos/dotfiles-tracker/dotfiles-diff.sh
#   bash ~/git/bootstrap-foundation/macos/dotfiles-tracker/dotfiles-diff.sh <commit-hash>
#
# Umgebungsvariablen (optional):
#   DOTFILES_DIR   Verzeichnis mit dem dotfiles-Repo  (default: ~/git/dotfiles)

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/git/dotfiles}"
REF="${1:-HEAD~1}"

if [ ! -d "${DOTFILES_DIR}/.git" ]; then
  echo "[dotfiles-diff] Kein Git-Repo unter ${DOTFILES_DIR}"
  exit 1
fi

COMMIT_COUNT=$(git -C "${DOTFILES_DIR}" rev-list --count HEAD 2>/dev/null || echo 0)
if [ "$COMMIT_COUNT" -lt 2 ]; then
  echo '[dotfiles-diff] Noch keine Aenderungen seit dem ersten Snapshot.'
  exit 0
fi

echo ''
echo '================================================'
echo "  dotfiles-diff: Aenderungen seit ${REF}"
echo '================================================'
echo ''
git -C "${DOTFILES_DIR}" diff "${REF}" HEAD
echo ''
echo 'Verlauf:'
git -C "${DOTFILES_DIR}" log --oneline
echo ''
