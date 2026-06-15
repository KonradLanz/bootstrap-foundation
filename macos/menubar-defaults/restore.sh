#!/usr/bin/env zsh
# menubar-defaults/restore.sh
# Rollback: NSStatusItemSpacing auf macOS-Standard zurücksetzen
# Verwendung: falls BentoBox nach apply.sh weiterhin Konflikte verursacht

set -euo pipefail
print_status() { printf '[%s] %s\n' "$1" "$2" }

print_status ">>" "NSStatusItemSpacing auf macOS-Standard (12) zurücksetzen..."
defaults delete -g NSStatusItemSpacing 2>/dev/null && print_status "OK" "NSStatusItemSpacing gelöscht (System-Default 12 aktiv)." || print_status "--" "NSStatusItemSpacing war nicht gesetzt."

print_status ">>" "SystemUIServer neu starten..."
killall SystemUIServer 2>/dev/null && print_status "OK" "SystemUIServer restartet." || true
