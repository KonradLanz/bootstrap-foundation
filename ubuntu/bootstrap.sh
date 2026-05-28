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
echo '[1/4] apt update...'
$SUDO apt-get update -qq
echo '      OK'

# 2) git + curl + wget
echo '[2/4] Installiere git + curl + wget...'
$SUDO apt-get install -y git curl wget
echo '      OK'

# 3) GitHub CLI (gh)
echo '[3/4] Installiere gh (GitHub CLI)...'
if ! command -v gh >/dev/null 2>&1; then
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        | $SUDO dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
    $SUDO chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        | $SUDO tee /etc/apt/sources.list.d/github-cli.list > /dev/null
    $SUDO apt-get update -qq
    $SUDO apt-get install -y gh
else
    echo '      gh bereits installiert, ueberspringe'
fi
echo '      OK'

# 4) Repos klonen
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
echo '      OK'

echo ''
echo '================================================'
echo '  Ubuntu Bootstrap abgeschlossen!'
echo '================================================'
echo ''
echo "Repos: $REPO_BASE"
echo 'Naechster Schritt: gh auth login'
echo ''
