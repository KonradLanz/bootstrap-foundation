#!/bin/sh
# macos/brew-tracker/brew-hook.sh
# Brew-Wrapper: automatisch nach jedem install/uninstall/upgrade
# ein git-Commit im brew-tracker-Verzeichnis.
#
# Einrichten (einmalig):
#   source ~/git/bootstrap-foundation/macos/brew-tracker/brew-hook.sh
#   # oder in .zshrc eintragen:
#   echo 'source ~/git/bootstrap-foundation/macos/brew-tracker/brew-hook.sh' >> ~/.zshrc
#
# Umgebungsvariablen (optional):
#   BREW_TRACKER_DIR   Verzeichnis mit Brewfile + Git-Repo  (default: ~/git/brew-tracker)

BREW_TRACKER_DIR="${BREW_TRACKER_DIR:-$HOME/git/brew-tracker}"

brew() {
  command brew "$@"
  local exit_code=$?

  case "$1" in
    install|uninstall|remove|reinstall|upgrade|tap|untap|pin|unpin)
      _brew_tracker_commit "$1 $2"
      ;;
  esac

  return $exit_code
}

_brew_tracker_commit() {
  local action="$1"

  # Sicherstellen dass Verzeichnis + Git-Repo existiert
  if [ ! -d "${BREW_TRACKER_DIR}/.git" ]; then
    echo "[brew-tracker] Kein Git-Repo unter ${BREW_TRACKER_DIR} - bitte erst setup.sh ausfuehren."
    return
  fi

  # Brewfile aktualisieren
  command brew bundle dump --force --file="${BREW_TRACKER_DIR}/Brewfile" 2>/dev/null

  # Aenderungen commiten (nur wenn etwas geaendert hat)
  if git -C "${BREW_TRACKER_DIR}" diff --quiet HEAD 2>/dev/null && \
     git -C "${BREW_TRACKER_DIR}" diff --cached --quiet 2>/dev/null; then
    # Untracked files pruefen
    if [ -z "$(git -C "${BREW_TRACKER_DIR}" ls-files --others --exclude-standard)" ]; then
      return
    fi
  fi

  git -C "${BREW_TRACKER_DIR}" add -A
  git -C "${BREW_TRACKER_DIR}" commit -m "brew ${action} [$(date '+%Y-%m-%d %H:%M')]"
  echo "[brew-tracker] Commit: brew ${action}"
}
