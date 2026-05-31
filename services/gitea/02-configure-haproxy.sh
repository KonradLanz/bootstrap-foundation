#!/usr/bin/env bash
# services/gitea/02-configure-haproxy.sh
# ---------------------------------------------------------------------------
# Gibt eine HAProxy-Konfiguration aus (stdout) und schreibt die
# Gitea app.ini fuer den Betrieb hinter pfSense/HAProxy.
#
# TLS-Terminierung: am HAProxy (pfSense)
# Gitea laeuft intern per HTTP auf GITEA_HTTP_ADDR:GITEA_HTTP_PORT
# Subdomain-Beispiel: git.example.lan
#
# Aufruf:
#   sudo -u gitea bash services/gitea/02-configure-haproxy.sh \
#     <subdomain.domain.tld> <gitea-interne-ip>
# ---------------------------------------------------------------------------
set -euo pipefail

DOMAIN="${1:?Usage: $0 <domain> <gitea-internal-ip>}"
GITEA_HOST="${2:?Usage: $0 <domain> <gitea-internal-ip>}"
GITEA_PORT="${3:-3000}"
GITEA_USER="${GITEA_USER:-gitea}"
GITEA_CFG="/etc/gitea/app.ini"
HTTP_ADDR="127.0.0.1"

# ---------------------------------------------------------------------------
# 1. app.ini schreiben
# ---------------------------------------------------------------------------
if [[ $EUID -eq 0 ]] || sudo -u "${GITEA_USER}" test -w /etc/gitea 2>/dev/null; then
  WRITE_CFG=1
else
  WRITE_CFG=0
fi

APP_INI_CONTENT=$(cat <<EOF
[server]
DOMAIN           = ${DOMAIN}
ROOT_URL         = https://${DOMAIN}/
HTTP_ADDR        = ${HTTP_ADDR}
HTTP_PORT        = ${GITEA_PORT}
SSH_DOMAIN       = ${DOMAIN}
START_SSH_SERVER = false
OFFLINE_MODE     = false

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

[session]
COOKIE_SECURE = true
EOF
)

if [[ $WRITE_CFG -eq 1 ]]; then
  if [[ -f "$GITEA_CFG" ]]; then
    cp -a "${GITEA_CFG}" "${GITEA_CFG}.bak.$(date +%F-%H%M%S)"
    echo "Backup: ${GITEA_CFG}.bak.*"
  fi
  if [[ $EUID -eq 0 ]]; then
    printf '%s\n' "$APP_INI_CONTENT" > "$GITEA_CFG"
    chown "${GITEA_USER}:${GITEA_USER}" "$GITEA_CFG"
    chmod 640 "$GITEA_CFG"
    echo "app.ini geschrieben: ${GITEA_CFG}"
  else
    sudo -u "${GITEA_USER}" bash -c "printf '%s\n' '$APP_INI_CONTENT' > '${GITEA_CFG}'"
    echo "app.ini geschrieben: ${GITEA_CFG}"
  fi
else
  echo "[WARN] Kein Schreibzugriff auf /etc/gitea – app.ini NICHT geschrieben."
  echo "       Folgenden Inhalt manuell nach ${GITEA_CFG} kopieren:"
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
# Name:        gitea-frontend
# Bindung:     <externe-IP>:443  oder  *:443
# Mode:        http
# SSL/TLS:     aktivieren, Zertifikat auswaehlen (Let's Encrypt oder intern)
# ACL:         hdr(host) -i ${DOMAIN}
# Backend:     gitea-backend

# --- Backend ---
# Name:        gitea-backend
# Mode:        http
# Balance:     roundrobin (single server – nur einer noetig)
# Server:
#   Name:    gitea01
#   Adresse: ${GITEA_HOST}
#   Port:    ${GITEA_PORT}
#   Optionen: keine SSL, kein Verify (intern)

# --- Reqset / Forwardfor (im Backend oder globalen Optionen) ---
# option forwardfor
# http-request set-header X-Forwarded-Proto https
# http-request set-header X-Real-IP %[src]

# --- HTTP-to-HTTPS Redirect (separates Frontend Port 80) ---
# Name:        gitea-frontend-http
# Bindung:     *:80
# ACL:         hdr(host) -i ${DOMAIN}
# Action:      http-request redirect scheme https

# ===========================================================================
# Firewall-Regel (pfSense)
# ===========================================================================
# - Port 3000 des Gitea-Hosts NUR fuer die HAProxy-Quell-IP freigeben.
# - Alle anderen Verbindungen auf Port 3000 blockieren.
# Beispiel (pf-Syntax, zur Information):
#   pass in quick on <internal_if> proto tcp \
#     from <pfsense-lan-ip> to ${GITEA_HOST} port ${GITEA_PORT}
#   block in quick on <internal_if> proto tcp to ${GITEA_HOST} port ${GITEA_PORT}

# ===========================================================================
EOF

echo
echo "=== Naechste Schritte ==="
echo "  3. Gitea neu starten:"
echo "       systemctl restart gitea"
echo "  4. HAProxy in pfSense gemaess obiger Referenz konfigurieren."
echo "  5. DNS-Eintrag fuer ${DOMAIN} auf HAProxy-IP setzen."
echo "  6. User anlegen:"
echo "       bash services/gitea/03-create-gitea-users.sh"
