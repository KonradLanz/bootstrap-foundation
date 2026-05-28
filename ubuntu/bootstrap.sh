#!/bin/sh
# ubuntu/bootstrap.sh
# Ubuntu / Debian / WSL2 Ubuntu Bootstrap
#
# STARTEN:
#   curl -fsSL https://raw.githubusercontent.com/KonradLanz/bootstrap-foundation/main/ubuntu/bootstrap.sh | sh

set -e
GITHUB_USER="${GITHUB_USER:-KonradLanz}"
REPO_BASE="$HOME/github"

# sudo-Wrapper: als root kein sudo noetig
if [ "$(id -u)" = "0" ]; then
    SUDO=""
else
    SUDO="sudo"
fi

echo ''
echo '================================================'
echo '  bootstrap-foundation: Ubuntu / Debian'
echo '================================================'
echo ''

# 1) apt update
echo '[1/3] apt update...'
$SUDO apt-get update -qq
echo '      OK'

# 2) git + curl
echo '[2/3] Installiere git + curl...'
$SUDO apt-get install -y git curl wget
echo '      OK'

# 3) Repos klonen
echo '[3/3] Repos klonen...'
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
echo '      OK'

echo ''
echo '================================================'
echo '  Ubuntu Bootstrap abgeschlossen!'
echo '================================================'
echo ''
echo "Repos: $REPO_BASE"
echo ''
