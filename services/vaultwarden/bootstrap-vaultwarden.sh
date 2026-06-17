#!/usr/bin/env zsh
# bootstrap-vaultwarden.sh
# Startet Vaultwarden auf QNAP (wenn erreichbar per WireGuard)
# oder lokal als Docker-Fallback.
# Idempotent: zweimaliger Aufruf ist sicher.

set -euo pipefail

VW_REMOTE_URL="${VAULTWARDEN_URL:-https://vault.own.dedyn.io}"
VW_LOCAL_URL="http://localhost:8080"
VW_LOCAL_PORT="${VAULTWARDEN_LOCAL_PORT:-8080}"
DATA_DIR="${VAULTWARDEN_DATA:-$HOME/.local/share/vaultwarden}"

# ── Farben ──────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()  { print -P "%F{green}✓ $*%f" }
warn()  { print -P "%F{yellow}⚠ $*%f" }
error() { print -P "%F{red}❌ $*%f"; exit 1 }

# ── Schritt 1: Ist Remote-Server (QNAP via WireGuard) erreichbar? ───────────
if curl -sf --max-time 3 "$VW_REMOTE_URL/alive" >/dev/null 2>&1; then
  info "Vaultwarden Remote-Server erreichbar: $VW_REMOTE_URL"
  info "Nutze Remote-Instanz. Kein lokaler Container nötig."
  bw config server "$VW_REMOTE_URL" 2>/dev/null && info "bw CLI konfiguriert auf $VW_REMOTE_URL"
  exit 0
fi

warn "Remote-Server nicht erreichbar ($VW_REMOTE_URL)"
warn "Starte lokalen Vaultwarden-Container als Fallback..."

# ── Schritt 2: Docker prüfen ────────────────────────────────────────────────
if ! command -v docker >/dev/null 2>&1; then
  error "Docker nicht gefunden. Bitte Docker Desktop installieren: https://www.docker.com/products/docker-desktop/"
fi

if ! docker info >/dev/null 2>&1; then
  error "Docker läuft nicht. Bitte Docker Desktop starten."
fi

# ── Schritt 3: Container starten (idempotent) ───────────────────────────────
mkdir -p "$DATA_DIR"

if docker ps --format '{{.Names}}' | grep -q '^vaultwarden$'; then
  info "Vaultwarden-Container läuft bereits auf $VW_LOCAL_URL"
else
  if docker ps -a --format '{{.Names}}' | grep -q '^vaultwarden$'; then
    info "Container existiert (gestoppt) — starte neu..."
    docker start vaultwarden
  else
    info "Erstelle neuen Vaultwarden-Container..."
    docker run -d \
      --name vaultwarden \
      --restart unless-stopped \
      -v "$DATA_DIR":/data \
      -p "127.0.0.1:${VW_LOCAL_PORT}:80" \
      -e SIGNUPS_ALLOWED=false \
      -e INVITATIONS_ALLOWED=true \
      -e ADMIN_TOKEN="$(openssl rand -base64 48)" \
      -e LOG_LEVEL=warn \
      vaultwarden/server:latest

    info "Container gestartet."
    warn "ADMIN_TOKEN wurde zufällig generiert."
    warn "Setze einen festen Token in .env.local: VAULTWARDEN_ADMIN_TOKEN=..."
  fi
  sleep 2
  info "Vaultwarden verfügbar: $VW_LOCAL_URL"
  info "Admin-Panel: ${VW_LOCAL_URL}/admin"
fi

# ── Schritt 4: bw CLI konfigurieren ─────────────────────────────────────────
if command -v bw >/dev/null 2>&1; then
  bw config server "$VW_LOCAL_URL"
  info "bw CLI konfiguriert auf $VW_LOCAL_URL"
else
  warn "Bitwarden CLI (bw) nicht gefunden. Installieren mit: brew install bitwarden-cli"
fi

info "Bootstrap abgeschlossen. Nächster Schritt:"
print "  1. Konto anlegen: open $VW_LOCAL_URL"
print "  2. bw login"
print "  3. bash services/vaultwarden/setup-bw-backend.sh"
