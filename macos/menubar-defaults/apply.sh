#!/usr/bin/env zsh
# menubar-defaults/apply.sh
# Idempotenter macOS Menüleiste-Defaults-Fix
# Behebt: BentoBox unterdrückt NSStatusItem-Slots → Notch-Flanken leer
#
# Idempotent: prüft aktuellen Zustand vor jedem write.
# Aufgerufen von: bootstrap.sh (optional), oder manuell.

set -euo pipefail
DOMAIN="com.apple.controlcenter"
SPACING_TARGET=6

print_status() { printf '[%s] %s\n' "$1" "$2" }

NEEDS_RESTART=0

apply_bool() {
  local domain="$1" key="$2" target="$3"
  local current
  current=$(defaults read "$domain" "$key" 2>/dev/null || echo "missing")
  if [[ "$current" == "$target" || ( "$target" == "1" && "$current" == "true" ) ]]; then
    print_status "--" "$key bereits korrekt ($current), übersprungen."
  else
    defaults write "$domain" "$key" -bool "$([ "$target" = '1' ] && echo true || echo false)"
    print_status ">>" "$key gesetzt → $target"
    NEEDS_RESTART=1
  fi
}

apply_int_global() {
  local key="$1" target="$2"
  local current
  current=$(defaults read -g "$key" 2>/dev/null || echo "missing")
  if [[ "$current" == "$target" ]]; then
    print_status "--" "$key bereits korrekt ($current), übersprungen."
  else
    defaults write -g "$key" -int "$target"
    print_status ">>" "$key gesetzt → $target"
    NEEDS_RESTART=1
  fi
}

print_status ">>" "=== menubar-defaults/apply.sh ==="

for i in 0 1 2 3; do
  apply_bool "$DOMAIN" "NSStatusItem Visible Item-$i" 1
done
apply_bool "$DOMAIN" "NSStatusItem Visible BentoBox"     1
apply_bool "$DOMAIN" "NSStatusItem VisibleCC BentoBox-0" 1
apply_bool "$DOMAIN" "NSStatusItem VisibleCC Battery"    1
apply_bool "$DOMAIN" "NSStatusItem VisibleCC Clock"      1
apply_bool "$DOMAIN" "NSStatusItem VisibleCC WiFi"       1
apply_int_global "NSStatusItemSpacing" "$SPACING_TARGET"

if [[ $NEEDS_RESTART -eq 1 ]]; then
  print_status ">>" "Änderungen erkannt → SystemUIServer neu starten..."
  killall SystemUIServer 2>/dev/null && print_status "OK" "SystemUIServer restartet." || true
else
  print_status "--" "Keine Änderungen nötig, SystemUIServer wird nicht neu gestartet."
fi

print_status "OK" "=== menubar-defaults/apply.sh abgeschlossen ==="
