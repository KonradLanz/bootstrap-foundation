#!/bin/sh
# services/gitea/bootstrap.sh
# Gitea Self-Hosted Git Forge Bootstrap (Ubuntu/Debian)
#
# Installiert Gitea als systemd-Service hinter einem Reverse Proxy (Caddy).
#
# VORAUSSETZUNG: Ubuntu/Debian-System, sudo-Rechte
#
# STARTEN:
#   curl -fsSL https://raw.githubusercontent.com/KonradLanz/bootstrap-foundation/main/services/gitea/bootstrap.sh | sh
#
# OPTIONALE VARIABLEN (Umgebungsvariablen vor dem Aufruf setzen):
#   GITEA_VERSION  - z.B. "1.23.7" (Standard: aktuell stable)
#   GITEA_DOMAIN   - z.B. "git.example.com" (Standard: localhost)
#   GITEA_PORT     - interner HTTP-Port (Standard: 3000)
#   GITEA_USER     - Systembenutzer fuer Gitea (Standard: gitea)

set -e

GITEA_VERSION="${GITEA_VERSION:-1.23.7}"
GITEA_DOMAIN="${GITEA_DOMAIN:-localhost}"
GITEA_PORT="${GITEA_PORT:-3000}"
GITEA_USER="${GITEA_USER:-gitea}"
GITEA_HOME="/home/$GITEA_USER"
GITEA_BIN="/usr/local/bin/gitea"
GITEA_WORK="/var/lib/gitea"
GITEA_CONF="/etc/gitea"
ARCH="$(uname -m)"

# sudo-Wrapper
if [ "$(id -u)" = "0" ]; then
    SUDO=""
else
    SUDO="sudo"
fi

# Architektur -> Gitea Asset-Name
case "$ARCH" in
    x86_64)  GITEA_ARCH="amd64" ;;
    aarch64) GITEA_ARCH="arm64" ;;
    armv7l)  GITEA_ARCH="armv6" ;;
    *) echo "[ERROR] Unbekannte Architektur: $ARCH"; exit 1 ;;
esac

GITEA_URL="https://dl.gitea.com/gitea/${GITEA_VERSION}/gitea-${GITEA_VERSION}-linux-${GITEA_ARCH}"

echo ''
echo '================================================'
echo '  bootstrap-foundation: Gitea Service'
echo '================================================'
echo "  Version : $GITEA_VERSION"
echo "  Domain  : $GITEA_DOMAIN"
echo "  Port    : $GITEA_PORT"
echo "  User    : $GITEA_USER"
echo '================================================'
echo ''

# 1) Basis-Pakete
echo '[1/6] Installiere Basis-Pakete...'
$SUDO apt-get update -qq
$SUDO apt-get install -y git curl wget sqlite3
echo '      OK'

# 2) Gitea-Systembenutzer anlegen
echo '[2/6] Systembenutzer anlegen...'
if ! id "$GITEA_USER" >/dev/null 2>&1; then
    $SUDO adduser \
        --system \
        --shell /bin/bash \
        --gecos 'Gitea' \
        --group \
        --disabled-password \
        --home "$GITEA_HOME" \
        "$GITEA_USER"
    echo "      Benutzer '$GITEA_USER' angelegt"
else
    echo "      Benutzer '$GITEA_USER' existiert bereits, OK"
fi

# 3) Gitea-Binary herunterladen
echo '[3/6] Lade Gitea Binary herunter...'
echo "      URL: $GITEA_URL"
if [ ! -f "$GITEA_BIN" ]; then
    $SUDO wget -q -O "$GITEA_BIN" "$GITEA_URL"
    $SUDO chmod +x "$GITEA_BIN"
    echo "      Installiert: $GITEA_BIN"
else
    INSTALLED_VERSION="$($GITEA_BIN --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo 'unbekannt')"
    echo "      Gitea $INSTALLED_VERSION bereits installiert, ueberspringe"
    echo "      (Zum Upgrade: GITEA_VERSION=X.Y.Z ./bootstrap.sh erneut ausfuehren)"
fi
echo '      OK'

# 4) Verzeichnisstruktur + app.ini
echo '[4/6] Verzeichnisse und Konfiguration...'
$SUDO mkdir -p "$GITEA_WORK" "$GITEA_CONF"
$SUDO chown -R "$GITEA_USER:$GITEA_USER" "$GITEA_WORK" "$GITEA_CONF"
$SUDO chmod 750 "$GITEA_CONF"

APP_INI="$GITEA_CONF/app.ini"
if [ ! -f "$APP_INI" ]; then
    $SUDO tee "$APP_INI" > /dev/null <<EOF
[DEFAULT]
RUN_USER = $GITEA_USER
RUN_MODE = prod

[server]
DOMAIN           = $GITEA_DOMAIN
HTTP_PORT        = $GITEA_PORT
ROOT_URL         = https://$GITEA_DOMAIN/
SSH_DOMAIN       = $GITEA_DOMAIN
LOCAL_ROOT_URL   = http://localhost:$GITEA_PORT/

[database]
DB_TYPE  = sqlite3
PATH     = $GITEA_WORK/gitea.db

[repository]
ROOT = $GITEA_WORK/repositories

[log]
ROOT_PATH = $GITEA_WORK/log
MODE      = file
LEVEL     = Warn

[security]
INSTALL_LOCK                   = false
SECRET_KEY                     =
INTERNAL_TOKEN                 =
PASSWORD_HASH_ALGO             = argon2
COOKIE_SECURE                  = true
COOKIE_SAMESITE                = lax
REVERSE_PROXY_LIMIT            = 1
REVERSE_PROXY_TRUSTED_PROXIES  = 127.0.0.1/32,::1/128

[session]
COOKIE_SECURE = true

[service]
DISABLE_REGISTRATION = false
REQUIRE_SIGNIN_VIEW  = false
EOF
    $SUDO chown "$GITEA_USER:$GITEA_USER" "$APP_INI"
    $SUDO chmod 640 "$APP_INI"
    echo "      app.ini erstellt: $APP_INI"
else
    echo "      app.ini existiert bereits, ueberspringe"
fi
echo '      OK'

# 5) systemd Service
echo '[5/6] systemd Service einrichten...'
$SUDO tee /etc/systemd/system/gitea.service > /dev/null <<EOF
[Unit]
Description=Gitea - Git with a cup of tea
After=network.target
Wants=network.target

[Service]
Type=simple
User=$GITEA_USER
Group=$GITEA_USER
WorkingDirectory=$GITEA_WORK
ExecStart=$GITEA_BIN web --config $GITEA_CONF/app.ini
Restart=on-failure
RestartSec=10
Environment=HOME=$GITEA_HOME USER=$GITEA_USER
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_BIND_SERVICE
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

$SUDO systemctl daemon-reload
$SUDO systemctl enable gitea
$SUDO systemctl start gitea
echo '      systemd: gitea.service aktiviert und gestartet'
echo '      OK'

# 6) Caddy als Reverse Proxy (optional)
echo '[6/6] Caddy Reverse Proxy...'
if [ "$GITEA_DOMAIN" = "localhost" ]; then
    echo '      GITEA_DOMAIN=localhost -> Caddy-Setup uebersprungen'
    echo "      Gitea laueft direkt auf http://localhost:$GITEA_PORT"
else
    if ! command -v caddy >/dev/null 2>&1; then
        echo '      Installiere Caddy...'
        $SUDO apt-get install -y debian-keyring debian-archive-keyring apt-transport-https
        curl -fsSL 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
            | $SUDO gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
        echo "deb [signed-by=/usr/share/keyrings/caddy-stable-archive-keyring.gpg] https://dl.cloudsmith.io/public/caddy/stable/deb/debian any-version main" \
            | $SUDO tee /etc/apt/sources.list.d/caddy-stable.list > /dev/null
        $SUDO apt-get update -qq
        $SUDO apt-get install -y caddy
    else
        echo '      Caddy bereits installiert'
    fi

    CADDYFILE="/etc/caddy/Caddyfile"
    if ! grep -q "$GITEA_DOMAIN" "$CADDYFILE" 2>/dev/null; then
        $SUDO tee -a "$CADDYFILE" > /dev/null <<EOF

$GITEA_DOMAIN {
    reverse_proxy localhost:$GITEA_PORT
}
EOF
        $SUDO systemctl reload caddy 2>/dev/null || $SUDO systemctl restart caddy
        echo "      Caddy: Block fuer $GITEA_DOMAIN hinzugefuegt"
    else
        echo "      Caddyfile hat bereits einen Block fuer $GITEA_DOMAIN, OK"
    fi
fi
echo '      OK'

echo ''
echo '================================================'
echo '  Gitea Bootstrap abgeschlossen!'
echo '================================================'
echo ''
if [ "$GITEA_DOMAIN" = "localhost" ]; then
    echo "  Gitea: http://localhost:$GITEA_PORT"
else
    echo "  Gitea: https://$GITEA_DOMAIN"
fi
echo ''
echo '  Naechste Schritte:'
echo '  1) Gitea Web-Setup aufrufen (Initial-Wizard)'
echo '  2) Admin-Account anlegen'
echo '  3) DISABLE_REGISTRATION = true setzen (optional)'
echo "  4) Logs: journalctl -u gitea -f"
echo ''
