#!/usr/bin/env bash
# services/forgejo/02-configure-haproxy.sh
# ---------------------------------------------------------------------------
# Gibt eine HAProxy-Konfiguration aus (stdout) und schreibt die
# Forgejo app.ini fuer den Betrieb hinter pfSense/HAProxy.
#
# TLS-Terminierung: am HAProxy (pfSense)
# Forgejo laeuft intern per HTTP auf FORGEJO_HTTP_ADDR:FORGEJO_HTTP_PORT
#
# Aufruf:
#   sudo -u forgejo bash services/forgejo/02-configure-haproxy.sh \
#     <subdomain.domain.tld> <forgejo-interne-ip>
# ---------------------------------------------------------------------------
set -euo pipefail

DOMAIN="${1:?Usage: $0 <domain> <forgejo-internal-ip>}"
FORGEJO_HOST="${2:?Usage: $0 <domain> <forgejo-internal-ip>}"
FORGEJO_PORT="${3:-3000}"
FORGEJO_USER="${FORGEJO_USER:-forgejo}"
FORGEJO_CFG="/etc/forgejo/app.ini"
HTTP_ADDR="127.0.0.1"

# ---------------------------------------------------------------------------
# 1. app.ini schreiben (Hardening fuer pfSense/HAProxy-Betrieb)
# ---------------------------------------------------------------------------
if [[ $EUID -eq 0 ]] || sudo -u "${FORGEJO_USER}" test -w /etc/forgejo 2>/dev/null; then
  WRITE_CFG=1
else
  WRITE_CFG=0
fi

APP_INI_CONTENT=$(cat <<EOF
[server]
DOMAIN           = ${DOMAIN}
ROOT_URL         = https://${DOMAIN}/
HTTP_ADDR        = ${HTTP_ADDR}
HTTP_PORT        = ${FORGEJO_PORT}
SSH_DOMAIN       = ${DOMAIN}
START_SSH_SERVER = false
OFFLINE_MODE     = false
LOCAL_ROOT_URL   = http://localhost:${FORGEJO_PORT}/

[database]
DB_TYPE  = sqlite3
PATH     = /var/lib/${FORGEJO_USER}/forgejo.db

[repository]
ROOT = /var/lib/${FORGEJO_USER}/repositories

[log]
ROOT_PATH = /var/lib/${FORGEJO_USER}/log
MODE      = file
LEVEL     = Warn

[service]
DISABLE_REGISTRATION             = true
ALLOW_ONLY_EXTERNAL_REGISTRATION = false
SHOW_REGISTRATION_BUTTON         = false
REGISTER_EMAIL_CONFIRM           = false
ENABLE_NOTIFY_MAIL                = false

[security]
INSTALL_LOCK                   = true
COOKIE_SECURE                  = true
COOKIE_SAMESITE                = lax
REVERSE_PROXY_LIMIT            = 1
REVERSE_PROXY_TRUSTED_PROXIES  = 127.0.0.1/32,::1/128
PASSWORD_HASH_ALGO             = argon2

[session]
COOKIE_SECURE = true
EOF
)

if [[ $WRITE_CFG -eq 1 ]]; then
  if [[ -f "$FORGEJO_CFG" ]]; then
    cp -a "${FORGEJO_CFG}" "${FORGEJO_CFG}.bak.$(date +%F-%H%M%S)"
    echo "Backup: ${FORGEJO_CFG}.bak.*"
  fi
  if [[ $EUID -eq 0 ]]; then
    printf '%s\n' "$APP_INI_CONTENT" > "$FORGEJO_CFG"
    chown "${FORGEJO_USER}:${FORGEJO_USER}" "$FORGEJO_CFG"
    chmod 640 "$FORGEJO_CFG"
    echo "app.ini geschrieben: ${FORGEJO_CFG}"
  else
    sudo -u "${FORGEJO_USER}" bash -c "printf '%s\n' '$APP_INI_CONTENT' > '${FORGEJO_CFG}'"
    echo "app.ini geschrieben: ${FORGEJO_CFG}"
  fi
else
  echo "[WARN] Kein Schreibzugriff auf /etc/forgejo – app.ini NICHT geschrieben."
  echo "       Folgenden Inhalt manuell nach ${FORGEJO_CFG} kopieren:"
  echo "---"
  printf '%s\n' "$APP_INI_CONTENT"
  echo "---"
fi

# ---------------------------------------------------------------------------
# 2. HAProxy-Konfiguration ausgeben (fuer pfSense)
# ---------------------------------------------------------------------------

cat <<EOF

# ===========================================================================
# HAProxy-Konfiguration fuer pfSense (Referenz)
# ===========================================================================
# Diese Konfiguration wird in pfSense unter:
#   Services > HAProxy > Frontend / Backend
# eingetragen, NICHT in haproxy.cfg direkt.
# ===========================================================================

# --- Frontend (HTTPS, Port 443) ---
# Name:        forgejo-frontend
# Bindung:     <externe-IP>:443  oder  *:443
# Mode:        http
# SSL/TLS:     aktivieren, Zertifikat auswaehlen
# ACL:         hdr(host) -i ${DOMAIN}
# Backend:     forgejo-backend

# --- Backend ---
# Name:        forgejo-backend
# Mode:        http
# Balance:     roundrobin (single server)
# Server:
#   Name:    forgejo01
#   Adresse: ${FORGEJO_HOST}
#   Port:    ${FORGEJO_PORT}
#   Optionen: keine SSL, kein Verify (intern)

# --- X-Forwarded-For / X-Real-IP setzen ---
# In pfSense HAProxy unter:
#   Services > HAProxy > Backend > forgejo-backend > Advanced settings
# Option: "Pass through X-Forwarded-For" aktivieren
# Oder manuell in "Backend pass thru":
#   http-request set-header X-Real-IP %[src]
#   http-request set-header X-Forwarded-Proto https

# ===========================================================================
# app.ini Security-Hinweis:
# REVERSE_PROXY_TRUSTED_PROXIES = 127.0.0.1/32,::1/128
# -> Anpassen auf die interne IP des pfSense HAProxy, falls noetig.
#    Beispiel: 192.168.1.1/32
# ===========================================================================
EOF

echo
echo "=== HAProxy-Konfiguration ausgegeben ==="
echo "  Domain        : ${DOMAIN}"
echo "  Forgejo-Host  : ${FORGEJO_HOST}:${FORGEJO_PORT}"
echo "  app.ini       : ${FORGEJO_CFG}"
echo
echo "Naechster Schritt:"
echo "  pfSense: Frontend + Backend gemaess obiger Ausgabe einrichten"
echo "  Dann: bash services/forgejo/03-create-forgejo-users.sh"
