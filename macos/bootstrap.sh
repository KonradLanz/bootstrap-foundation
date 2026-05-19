#!/bin/sh
# macos/bootstrap.sh
# macOS Bootstrap - Homebrew + git + Foundation-Repos
#
# STARTEN:
#   curl -fsSL https://raw.githubusercontent.com/KonradLanz/bootstrap-foundation/main/macos/bootstrap.sh | sh

set -e
GITHUB_USER="${GITHUB_USER:-KonradLanz}"
REPO_BASE="$HOME/github"

echo ''
echo '================================================'
echo '  bootstrap-foundation: macOS'
echo '================================================'
echo ''

# OS-Detection lib
SCRIPT_DIR="$(dirname "$0")"
if [ -f "$SCRIPT_DIR/../lib/detect-os.sh" ]; then
    . "$SCRIPT_DIR/../lib/detect-os.sh"
fi
OS='macos'
PKG_MGR='brew'

# 1) Xcode CLT
echo '[1/4] Pruefe Xcode Command Line Tools...'
if ! xcode-select -p >/dev/null 2>&1; then
    echo '      Installiere Xcode CLT (Benutzerbestaetigung noetig)...'
    xcode-select --install
    echo '      Bitte Installation abwarten, dann Script neu starten.'
    exit 0
fi
echo '      Xcode CLT OK'

# 2) Homebrew
echo '[2/4] Pruefe Homebrew...'
if ! command -v brew >/dev/null 2>&1; then
    echo '      Installiere Homebrew...'
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    # Apple Silicon PATH
    if [ -f /opt/homebrew/bin/brew ]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
        echo 'eval "$($(brew --prefix)/bin/brew shellenv)"' >> "$HOME/.zprofile"
    fi
fi
echo '      Homebrew OK'

# 3) git
echo '[3/4] Pruefe git...'
if ! command -v git >/dev/null 2>&1; then
    brew install git
fi
echo '      git OK'

# 4) Foundation Repos klonen
echo '[4/4] Repos klonen...'
mkdir -p "$REPO_BASE"
for REPO in bootstrap-foundation; do
    DIR="$REPO_BASE/$REPO"
    if [ ! -d "$DIR" ]; then
        echo "      Klone $REPO..."
        git clone "https://github.com/$GITHUB_USER/$REPO.git" "$DIR"
    else
        echo "      Aktualisiere $REPO..."
        git -C "$DIR" pull
    fi
done
echo '      Repos OK'

echo ''
echo '================================================'
echo '  macOS Bootstrap abgeschlossen!'
echo '================================================'
echo ''
echo "Repos: $REPO_BASE"
echo ''
