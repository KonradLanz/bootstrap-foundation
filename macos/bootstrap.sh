#!/bin/sh
# macos/bootstrap.sh
# macOS Bootstrap - Homebrew + git + gh + Foundation-Repos
#
# STARTEN (frisches MacBook, kein git vorhanden):
#   curl -fsSL https://raw.githubusercontent.com/KonradLanz/bootstrap-foundation/main/macos/bootstrap.sh | sh
#
# Umgebungsvariablen (optional):
#   GITHUB_USER   GitHub-Username       (default: KonradLanz)
#   GIT_BASE      lokales Repo-Verzeichnis (default: ~/git)

set -e

GITHUB_USER="${GITHUB_USER:-KonradLanz}"
GIT_BASE="${GIT_BASE:-$HOME/git}"

echo ''
echo '================================================'
echo '  bootstrap-foundation: macOS'
echo '================================================'
echo ''

# 1) Xcode CLT
echo '[1/5] Pruefe Xcode Command Line Tools...'
if ! xcode-select -p >/dev/null 2>&1; then
  echo '      Installiere Xcode CLT (Benutzerbestaetigung noetig)...'
  xcode-select --install
  echo '      Bitte Installation abwarten, dann Script neu starten.'
  exit 0
fi
echo '      Xcode CLT OK'

# 2) Homebrew
echo '[2/5] Pruefe Homebrew...'
if ! command -v brew >/dev/null 2>&1; then
  echo '      Installiere Homebrew...'
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  if [ -f /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
    grep -qxF 'eval "$($(brew --prefix)/bin/brew shellenv)"' "$HOME/.zprofile" 2>/dev/null \
      || echo 'eval "$($(brew --prefix)/bin/brew shellenv)"' >> "$HOME/.zprofile"
  fi
fi
echo '      Homebrew OK'

# 3) git + gh
echo '[3/5] Pruefe git und gh...'
brew list git >/dev/null 2>&1 || brew install git
brew list gh   >/dev/null 2>&1 || brew install gh
echo '      git + gh OK'

# 4) Foundation Repos klonen
echo '[4/5] Repos klonen nach ${GIT_BASE}...'
mkdir -p "${GIT_BASE}"
for REPO in bootstrap-foundation; do
  DIR="${GIT_BASE}/${REPO}"
  if [ ! -d "$DIR" ]; then
    echo "      Klone ${REPO}..."
    git clone "https://github.com/${GITHUB_USER}/${REPO}.git" "$DIR"
  else
    echo "      Aktualisiere ${REPO}..."
    git -C "$DIR" pull
  fi
done
echo '      Repos OK'

# 5) gh + Token
echo '[5/5] GitHub CLI einrichten...'
if ! gh auth status >/dev/null 2>&1; then
  echo '      Starte gh auth login...'
  bash "${GIT_BASE}/bootstrap-foundation/macos/02-gh-auth.sh" || true
else
  echo '      gh bereits authentifiziert.'
fi

echo ''
echo '================================================'
echo '  macOS Bootstrap abgeschlossen!'
echo '================================================'
echo ''
echo "Repos: ${GIT_BASE}"
echo ''
echo 'Naechste Schritte:'
echo "  bash ${GIT_BASE}/bootstrap-foundation/macos/02-gh-auth.sh"
echo "  bash ${GIT_BASE}/bootstrap-foundation/macos/03-gh-token-keepass.sh"
echo "  bash ${GIT_BASE}/bootstrap-foundation/macos/04-ssh-key-github.sh"
echo ''
