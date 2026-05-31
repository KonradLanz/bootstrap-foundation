#!/bin/sh
# macos/dotfiles-tracker/setup.sh  — idempotent
# Beliebig oft aufrufbar: ueberspringt bereits erledigte Schritte.
#
# Umgebungsvariablen (optional):
#   DOTFILES_TRACKER_DIR     Zielverzeichnis (default: ~/git/dotfiles-tracker)
#   DOTFILES_TRACKER_REMOTE  Remote-URL      (optional)

set -e

DOTFILES_TRACKER_DIR="${DOTFILES_TRACKER_DIR:-$HOME/git/dotfiles-tracker}"
DOTFILES_TRACKER_REMOTE="${DOTFILES_TRACKER_REMOTE:-}"

_ok()   { printf '  [OK]  %s\n' "$1"; }
_skip() { printf '  [--]  %s\n' "$1"; }
_run()  { printf '  [>>]  %s\n' "$1"; }

echo ''
echo '================================================'
echo '  dotfiles-tracker: Setup  (idempotent)'
echo '================================================'
echo ''

# 1) Verzeichnis
mkdir -p "${DOTFILES_TRACKER_DIR}"
_skip "Verzeichnis: ${DOTFILES_TRACKER_DIR}"

# 2) Git-Repo
if [ ! -d "${DOTFILES_TRACKER_DIR}/.git" ]; then
  git -C "${DOTFILES_TRACKER_DIR}" init
  _ok 'Git-Repo initialisiert'
else
  _skip 'Git-Repo bereits vorhanden'
fi

# 3) Remote (idempotent)
if [ -n "${DOTFILES_TRACKER_REMOTE}" ]; then
  if git -C "${DOTFILES_TRACKER_DIR}" remote get-url origin >/dev/null 2>&1; then
    CURR=$(git -C "${DOTFILES_TRACKER_DIR}" remote get-url origin)
    if [ "$CURR" = "${DOTFILES_TRACKER_REMOTE}" ]; then
      _skip "Remote bereits gesetzt: ${DOTFILES_TRACKER_REMOTE}"
    else
      git -C "${DOTFILES_TRACKER_DIR}" remote set-url origin "${DOTFILES_TRACKER_REMOTE}"
      _ok "Remote aktualisiert: ${DOTFILES_TRACKER_REMOTE}"
    fi
  else
    git -C "${DOTFILES_TRACKER_DIR}" remote add origin "${DOTFILES_TRACKER_REMOTE}"
    _ok "Remote hinzugefuegt: ${DOTFILES_TRACKER_REMOTE}"
  fi
else
  _skip 'Remote: keine DOTFILES_TRACKER_REMOTE gesetzt'
fi

# 4) Initiale Dotfiles erfassen — nur beim ersten Mal
if git -C "${DOTFILES_TRACKER_DIR}" rev-parse HEAD >/dev/null 2>&1; then
  _skip 'Snapshot bereits vorhanden (git log hat Commits)'
else
  _run 'Erfasse initiale Dotfiles...'
  DOTFILES=".zshrc .zprofile .bashrc .bash_profile .gitconfig .gitignore_global .vimrc .tmux.conf .ssh/config"
  COPIED=0
  for f in $DOTFILES; do
    SRC="$HOME/$f"
    DEST="${DOTFILES_TRACKER_DIR}/$f"
    if [ -f "$SRC" ]; then
      mkdir -p "$(dirname "$DEST")"
      cp "$SRC" "$DEST"
      _ok "Kopiert: $f"
      COPIED=$((COPIED + 1))
    fi
  done
  if [ "$COPIED" -gt 0 ]; then
    git -C "${DOTFILES_TRACKER_DIR}" add -A
    git -C "${DOTFILES_TRACKER_DIR}" commit -m "initial dotfiles snapshot [$(date '+%Y-%m-%d %H:%M')]"
    _ok "${COPIED} Dotfiles committed"
  else
    _skip 'Keine Dotfiles gefunden zum Committen'
  fi
fi

echo ''
echo '================================================'
echo '  dotfiles-tracker Setup abgeschlossen!'
echo '================================================'
echo ''
echo "Tracker-Repo: ${DOTFILES_TRACKER_DIR}"
echo ''
