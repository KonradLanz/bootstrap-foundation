#!/bin/sh
# bootstrap.sh
# Zentraler Cold-Start-Einstieg fuer alle Plattformen
#
# STARTEN:
#   wget -qO- https://raw.githubusercontent.com/KonradLanz/bootstrap-foundation/main/bootstrap.sh | sh
#
# DANACH (wiederholbar, aus lokalem Repo):
#   cd /share/homes/admin/github/bootstrap-foundation && git pull && sh bootstrap.sh
#   cd ~/github/bootstrap-foundation && git pull && sh bootstrap.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd || echo '.')"

. "$SCRIPT_DIR/lib/detect-os.sh"
detect_os

echo ''
echo '================================================'
echo "  bootstrap-foundation: $OS"
echo '================================================'
echo ''

case "$OS" in
    qnap)   sh "$SCRIPT_DIR/qnap/bootstrap.sh"   ;;
    macos)  sh "$SCRIPT_DIR/macos/bootstrap.sh"  ;;
    ubuntu) sh "$SCRIPT_DIR/ubuntu/bootstrap.sh" ;;
    alpine) sh "$SCRIPT_DIR/alpine/bootstrap.sh" ;;
    *)
        echo "[FEHLER] Unbekanntes OS: $OS"
        echo "Manuell ausfuehren: sh <os>/bootstrap.sh"
        exit 1
        ;;
esac
