#!/bin/sh
# macos/brew-tracker/brew-history-import.sh
# Legt rückwirkende Git-Commits im brew-tracker-Repo an,
# basierend auf den Filesystem-Timestamps im Homebrew Cellar.
#
# Ausfuehren (einmalig, nach setup.sh):
#   bash ~/git/bootstrap-foundation/macos/brew-tracker/brew-history-import.sh
#
# Umgebungsvariablen (optional):
#   BREW_TRACKER_DIR   Verzeichnis mit dem tracker-Repo  (default: ~/git/brew-tracker)
#   CELLAR_DIR         Homebrew Cellar-Pfad               (default: /opt/homebrew/Cellar)

set -e

BREW_TRACKER_DIR="${BREW_TRACKER_DIR:-$HOME/git/brew-tracker}"
CELLAR_DIR="${CELLAR_DIR:-/opt/homebrew/Cellar}"

if [ ! -d "${BREW_TRACKER_DIR}/.git" ]; then
  echo "[brew-history-import] Kein Git-Repo unter ${BREW_TRACKER_DIR}"
  echo "Bitte erst setup.sh ausfuehren."
  exit 1
fi

echo ''
echo '================================================'
echo '  brew-history-import: Historische Commits'
echo '================================================'
echo ''
echo "Lese Cellar-Daten aus: ${CELLAR_DIR}"
echo ''

# Alle manuell installierten Pakete (keine Abhaengigkeiten) mit Datum einlesen
# Sortiert nach Datum -> Commits in chronologischer Reihenfolge
TMPFILE=$(mktemp)

for pkg in $(brew leaves 2>/dev/null); do
  cellar_path="${CELLAR_DIR}/${pkg}"
  if [ -d "${cellar_path}" ]; then
    date=$(stat -f '%Sm' -t '%Y-%m-%d' "${cellar_path}" 2>/dev/null || echo "0000-00-00")
    echo "${date} ${pkg}"
  fi
done | sort > "${TMPFILE}"

echo 'Gefundene Pakete (chronologisch):'
cat "${TMPFILE}"
echo ''

# Pakete nach Datum gruppieren und je Datum einen Commit anlegen
PREV_DATE=""
PKGS_FOR_DATE=""

commit_group() {
  local date="$1"
  local pkgs="$2"
  [ -z "$pkgs" ] && return

  local iso_date="${date}T12:00:00"
  echo "  Commit [${date}]: ${pkgs}"

  GIT_AUTHOR_DATE="${iso_date}" \
  GIT_COMMITTER_DATE="${iso_date}" \
    git -C "${BREW_TRACKER_DIR}" commit --allow-empty \
      -m "historical: ${pkgs} [${date}]"
}

while IFS= read -r line; do
  date=$(echo "$line" | cut -d' ' -f1)
  pkg=$(echo "$line"  | cut -d' ' -f2)

  if [ "$date" = "$PREV_DATE" ]; then
    PKGS_FOR_DATE="${PKGS_FOR_DATE} ${pkg}"
  else
    commit_group "$PREV_DATE" "$PKGS_FOR_DATE"
    PREV_DATE="$date"
    PKGS_FOR_DATE="$pkg"
  fi
done < "${TMPFILE}"

# Letzten Block commiten
commit_group "$PREV_DATE" "$PKGS_FOR_DATE"

rm -f "${TMPFILE}"

echo ''
echo '================================================'
echo '  Import abgeschlossen!'
echo '================================================'
echo ''
echo 'Verlauf ansehen:'
echo "  git -C ${BREW_TRACKER_DIR} log --oneline"
echo ''
