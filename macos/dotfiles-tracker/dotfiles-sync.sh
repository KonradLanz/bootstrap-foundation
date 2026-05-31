#!/bin/sh
# macos/dotfiles-tracker/dotfiles-sync.sh
# Kopiert aktuellen Stand der /etc/hosts und anderer nicht-symgelinkte
# Dateien ins Repo und committet Aenderungen.
# Home-Dateien sind Symlinks -> werden automatisch gesehen.
#
# Ausfuehren:
#   bash ~/git/bootstrap-foundation/macos/dotfiles-tracker/dotfiles-sync.sh
#   bash ~/git/bootstrap-foundation/macos/dotfiles-tracker/dotfiles-sync.sh "Kommentar"
#
# Umgebungsvariablen (optional):
#   DOTFILES_DIR   Verzeichnis mit dem dotfiles-Repo  (default: ~/git/dotfiles)

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/git/dotfiles}"
MSG="${1:-sync [$(date '+%Y-%m-%d %H:%M')]}"

if [ ! -d "${DOTFILES_DIR}/.git" ]; then
  echo "[dotfiles-sync] Kein Git-Repo unter ${DOTFILES_DIR}"
  echo "Bitte erst setup.sh ausfuehren."
  exit 1
fi

# Nicht-symgelinkte Dateien aktualisieren (z.B. /etc/hosts)
NON_SYMLINK_FILES="
/etc/hosts|etc/hosts
"

echo "$NON_SYMLINK_FILES" | while IFS='|' read -r src dst; do
  [ -z "$src" ] && continue
  [ ! -f "$src" ] && continue
  dst_path="${DOTFILES_DIR}/${dst}"
  mkdir -p "$(dirname "$dst_path")"
  cp "$src" "$dst_path"
done

# Commit wenn Aenderungen vorhanden
if git -C "${DOTFILES_DIR}" diff --quiet HEAD 2>/dev/null \
   && [ -z "$(git -C "${DOTFILES_DIR}" ls-files --others --exclude-standard)" ]; then
  echo '[dotfiles-sync] Keine Aenderungen.'
  exit 0
fi

git -C "${DOTFILES_DIR}" add -A
git -C "${DOTFILES_DIR}" commit -m "${MSG}"
echo "[dotfiles-sync] Commit: ${MSG}"
