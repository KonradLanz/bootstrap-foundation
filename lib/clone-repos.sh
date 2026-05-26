#!/bin/sh
# lib/clone-repos.sh
# Repos klonen oder aktualisieren
# Source this file: . ./lib/clone-repos.sh

# GITHUB_USER muss gesetzt sein bevor dieses Script gesourced wird
GITHUB_USER="${GITHUB_USER:-KonradLanz}"
REPO_BASE="${REPO_BASE:-$HOME/github}"

clone_or_pull() {
    REPO="$1"
    DIR="$REPO_BASE/$REPO"
    mkdir -p "$REPO_BASE"
    if [ ! -d "$DIR" ]; then
        echo "  Klone $REPO..."
        git clone "https://github.com/$GITHUB_USER/$REPO.git" "$DIR"
    else
        echo "  Aktualisiere $REPO..."
        git -C "$DIR" pull
    fi
}

clone_foundation_repos() {
    clone_or_pull 'bootstrap-foundation'
    # ExecutionPolicy-Foundation nur auf Windows sinnvoll,
    # auf anderen Plattformen optional
    if [ "$OS" = 'macos' ] || [ "$OS" = 'ubuntu' ] || [ "$OS" = 'alpine' ]; then
        echo '  ExecutionPolicy-Foundation: Windows-only, uebersprungen'
    fi
}

clone_qnap_repos() {
    clone_or_pull 'qnap-config-keeper'
    clone_or_pull 'qnap-dotfiles'
}
