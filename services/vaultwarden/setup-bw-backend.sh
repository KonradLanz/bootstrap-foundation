#!/usr/bin/env zsh
# setup-bw-backend.sh
# Konfiguriert bw CLI und hängt Vaultwarden als Backend in
# lib/secret-backends.sh ein (nach keepassxc, vor plain).

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
LIB_DIR="${SCRIPT_DIR}/../../lib"
BACKENDS_SH="${LIB_DIR}/secret-backends.sh"

info()  { print -P "%F{green}✓ $*%f" }
warn()  { print -P "%F{yellow}⚠ $*%f" }

# ── bw CLI prüfen ────────────────────────────────────────────────────────────
if ! command -v bw >/dev/null 2>&1; then
  warn "bw nicht gefunden. Installieren:"
  print "  macOS:  brew install bitwarden-cli"
  print "  Linux:  npm install -g @bitwarden/cli"
  exit 1
fi

# ── bw login-Status prüfen ──────────────────────────────────────────────────
if ! bw status 2>/dev/null | grep -q '"status":"unlocked"'; then
  info "Bitte bei Vaultwarden anmelden:"
  bw login
  export BW_SESSION=$(bw unlock --raw)
fi

info "bw CLI verifiziert und unlocked."

# ── Eintrag lesen (Test) ─────────────────────────────────────────────────────
info "Beispiel: Eintrag lesen:"
print "  bw get password 'imap/greev.com'"
print "  bw get password 'imap/greev.com' | pbcopy   # direkt in Clipboard"

info "Bootstrap-Backend-Integration: TODO in lib/secret-backends.sh"
warn "sb_bitwarden Backend-Stub muss noch in $BACKENDS_SH eingetragen werden."
print ""
print "Prioritätsreihenfolge nach Integration:"
print "  keepassxc → bitwarden (vaultwarden) → gpg → plain"
