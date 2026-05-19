#!/bin/sh
# alpine/bootstrap.sh
# Alpine Linux / WSL2 Alpine Bootstrap
#
# STARTEN:
#   wget -qO- https://raw.githubusercontent.com/KonradLanz/bootstrap-foundation/main/alpine/bootstrap.sh | sh
#   # oder:
#   curl -fsSL https://raw.githubusercontent.com/KonradLanz/bootstrap-foundation/main/alpine/bootstrap.sh | sh

set -e
GITHUB_USER="${GITHUB_USER:-KonradLanz}"
REPO_BASE="$HOME/github"

echo ''
echo '================================================'
echo '  bootstrap-foundation: Alpine Linux'
echo '================================================'
echo ''

# 1) apk update
echo '[1/3] apk update...'
apk update --no-cache
echo '      OK'

# 2) git + curl
echo '[2/3] Installiere git + curl...'
apk add --no-cache git curl wget
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
echo '  Alpine Bootstrap abgeschlossen!'
echo '================================================'
echo ''
echo "Repos: $REPO_BASE"
echo ''
