#!/usr/bin/env zsh
# setup-recovery-qr.sh
# Generiert einen QR-Code der als Deep-Link auf die Vaultwarden
# Admin-Recovery-Seite zeigt, eingeschränkt auf lokale IPs.
#
# Sicherheitsmodell:
#   - QR-Code zeigt auf https://vault.own.dedyn.io/recover
#     (oder http://192.168.x.x:8080/recover für LAN-only)
#   - Der URL enthält KEIN Passwort / Token
#   - Zugriff auf /admin erfordert ADMIN_TOKEN (serverseitig)
#   - WireGuard stellt sicher dass nur bekannte Geräte die IP erreichen
#   - QR-Code kann ausgedruckt werden: nur im Heimnetz nutzbar

set -euo pipefail

# ── Konfiguration ────────────────────────────────────────────────────────────
# Passe VW_RECOVERY_URL an deine lokale IP oder Subdomain an:
VW_RECOVERY_URL="${VAULTWARDEN_RECOVERY_URL:-http://192.168.1.1:8080/admin}"
VW_LABEL="${VAULTWARDEN_LABEL:-Vaultwarden Recovery}"
OUTPUT_PNG="/tmp/vaultwarden-recovery-qr.png"

info()  { print -P "%F{green}✓ $*%f" }
warn()  { print -P "%F{yellow}⚠ $*%f" }
error() { print -P "%F{red}❌ $*%f"; exit 1 }

# ── qrencode prüfen ──────────────────────────────────────────────────────────
if ! command -v qrencode >/dev/null 2>&1; then
  error "qrencode nicht gefunden. Installieren: brew install qrencode"
fi

# ── QR im Terminal anzeigen (ANSI Unicode) ───────────────────────────────────
print ""
info "Recovery URL: $VW_RECOVERY_URL"
print ""
echo "$VW_RECOVERY_URL" | qrencode -t ANSIUTF8 -l H
print ""

# ── QR als PNG speichern ─────────────────────────────────────────────────────
echo "$VW_RECOVERY_URL" | qrencode \
  -t PNG \
  -s 8 \
  -l H \
  -o "$OUTPUT_PNG"

info "QR-Code gespeichert: $OUTPUT_PNG"
print ""
warn "SICHERHEITSHINWEIS:"
print "  • Dieser QR-Code zeigt auf dein lokales Netzwerk."
print "  • Ausdrucken: sicher — ohne VPN / WireGuard nicht erreichbar."
print "  • NIEMALS in Cloud speichern oder per E-Mail senden."
print "  • Nach dem Ausdrucken löschen:"
print "      rm $OUTPUT_PNG"
print ""

# ── Drucken (macOS) ──────────────────────────────────────────────────────────
if [[ "$(uname)" == "Darwin" ]]; then
  print "Jetzt drucken? [y/N]"
  read -r REPLY
  if [[ "$REPLY" =~ ^[Yy]$ ]]; then
    # lp oder Preview zum Drucken verwenden
    if command -v lp >/dev/null 2>&1; then
      lp "$OUTPUT_PNG"
      info "Druckauftrag gesendet."
    else
      open "$OUTPUT_PNG"  # öffnet in Preview → manuell drucken
      info "In Preview geöffnet — bitte manuell drucken (Cmd+P)."
    fi
    print ""
    warn "Nach dem Drucken unbedingt löschen:"
    print "  rm $OUTPUT_PNG"
  else
    info "Nicht gedruckt. Datei liegt unter: $OUTPUT_PNG"
    warn "Bitte nach Verwendung löschen: rm $OUTPUT_PNG"
  fi
fi

# QNAP-Hinweis
if [[ "$(uname -m)" == "x86_64" ]] && [[ -d /share ]]; then
  print ""
  warn "QNAP erkannt: 'lp' ist möglicherweise nicht verfügbar."
  print "  PNG übertragen und am Mac drucken:"
  print "    scp qnap:$OUTPUT_PNG /tmp/ && open /tmp/vaultwarden-recovery-qr.png"
fi
