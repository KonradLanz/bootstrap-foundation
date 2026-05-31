#!/bin/sh
# macos/bootstrap.sh
# macOS Bootstrap - idempotent, beliebig oft aufrufbar.
#
# STARTEN (frisches MacBook, kein git vorhanden):
#   curl -fsSL https://raw.githubusercontent.com/KonradLanz/bootstrap-foundation/main/macos/bootstrap.sh | sh
#
# Umgebungsvariablen (optional):
#   GITHUB_USER   GitHub-Username          (default: KonradLanz)
#   GIT_BASE      lokales Repo-Verzeichnis (default: ~/git)

set -e

GITHUB_USER="${GITHUB_USER:-KonradLanz}"
GIT_BASE="${GIT_BASE:-$HOME/git}"

_ok()   { printf '  [OK]  %s\n' "$1"; }
_skip() { printf '  [--]  %s\n' "$1"; }
_run()  { printf '  [>>]  %s\n' "$1"; }

echo ''
echo '================================================'
echo '  bootstrap-foundation: macOS  (idempotent)'
echo '================================================'
echo ''

# --- Homebrew PATH sicherstellen (Apple Silicon) ---
if [ -f /opt/homebrew/bin/brew ]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

# 1) Xcode CLT
printf '[1/6] Xcode Command Line Tools... '
if xcode-select -p >/dev/null 2>&1; then
  _skip 'bereits installiert'
else
  echo ''
  _run 'Installiere Xcode CLT (Benutzerbestaetigung noetig)...'
  xcode-select --install
  echo '      Bitte Installation abwarten, dann Script neu starten.'
  exit 0
fi

# 2) Homebrew
printf '[2/6] Homebrew... '
if command -v brew >/dev/null 2>&1; then
  _skip 'bereits installiert'
else
  echo ''
  _run 'Installiere Homebrew...'
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  if [ -f /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
    grep -qxF 'eval "$($(brew --prefix)/bin/brew shellenv)"' "$HOME/.zprofile" 2>/dev/null \
      || echo 'eval "$($(brew --prefix)/bin/brew shellenv)"' >> "$HOME/.zprofile"
  fi
  _ok 'Homebrew installiert'
fi

# 3) git + gh
printf '[3/6] git + gh... '
NEED_INSTALL=0
brew list git >/dev/null 2>&1 || { brew install git; NEED_INSTALL=1; }
brew list gh   >/dev/null 2>&1 || { brew install gh;  NEED_INSTALL=1; }
if [ "$NEED_INSTALL" -eq 0 ]; then
  _skip 'git + gh bereits installiert'
else
  _ok 'git + gh installiert'
fi

# 4) keepassxc (fuer Token-Verwaltung)
printf '[4/6] keepassxc... '
if brew list --cask keepassxc >/dev/null 2>&1; then
  _skip 'keepassxc bereits installiert'
else
  brew install --cask keepassxc
  _ok 'keepassxc installiert'
fi

# 5) Foundation Repo klonen / aktualisieren
printf '[5/6] bootstrap-foundation Repo... '
mkdir -p "${GIT_BASE}"
DIR="${GIT_BASE}/bootstrap-foundation"
if [ ! -d "${DIR}/.git" ]; then
  echo ''
  _run "Klone bootstrap-foundation nach ${DIR}..."
  git clone "https://github.com/${GITHUB_USER}/bootstrap-foundation.git" "${DIR}"
  _ok 'Repo geklont'
else
  git -C "${DIR}" pull --ff-only 2>/dev/null && _skip 'Repo aktuell' || _ok 'Repo aktualisiert'
fi

# 6) Tracker starten (idempotent - setup.sh prueft selbst ob schon initialisiert)
printf '[6/6] Tracker einrichten... '
echo ''

BT_DIR="${GIT_BASE}/brew-tracker"
DT_DIR="${GIT_BASE}/dotfiles-tracker"

if [ -d "${BT_DIR}/.git" ]; then
  _skip 'brew-tracker bereits eingerichtet'
else
  _run 'brew-tracker Setup...'
  bash "${DIR}/macos/brew-tracker/setup.sh"
fi

if [ -d "${DT_DIR}/.git" ]; then
  _skip 'dotfiles-tracker bereits eingerichtet'
else
  _run 'dotfiles-tracker Setup...'
  bash "${DIR}/macos/dotfiles-tracker/setup.sh"
fi

# brew-hook in .zshrc einmalig eintragen
HOOK_LINE="source \"${DIR}/macos/brew-tracker/brew-hook.sh\""
if grep -qF 'brew-tracker/brew-hook.sh' "$HOME/.zshrc" 2>/dev/null; then
  _skip 'brew-hook bereits in .zshrc'
else
  echo "${HOOK_LINE}" >> "$HOME/.zshrc"
  _ok 'brew-hook in .zshrc eingetragen'
fi

echo ''
echo '================================================'
echo '  macOS Bootstrap abgeschlossen!'
echo '================================================'
echo ''
echo "Repos:   ${GIT_BASE}"
echo ''
echo 'Naechste Schritte:'
echo "  bash ${DIR}/macos/02-gh-auth.sh          # gh anmelden"
echo "  bash ${DIR}/macos/03-gh-token-keepass.sh # PAT in KeePass"
echo "  bash ${DIR}/macos/04-ssh-key-github.sh   # SSH-Key"
echo ''
