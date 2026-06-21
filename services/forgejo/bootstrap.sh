#!/bin/sh
# services/forgejo/bootstrap.sh
# Forgejo Self-Hosted Git Forge Bootstrap (Ubuntu/Debian)
#
# Installiert Forgejo als systemd-Service hinter einem Reverse Proxy (Caddy).
# Forgejo ist ein community-gesteuerter Free-Software-Fork von Gitea.
#
# VORAUSSETZUNG: Ubuntu/Debian-System, sudo-Rechte
#
# STARTEN:
#   curl -fsSL https://raw.githubusercontent.com/KonradLanz/bootstrap-foundation/main/services/forgejo/bootstrap.sh | sh
#
# OPTIONALE VARIABLEN (Umgebungsvariablen vor dem Aufruf setzen):
#   FORGEJO_VERSION  - z.B. "9.0.3" (Standard: aktuell stable)
#   FORGEJO_DOMAIN   - z.B. "git.example.com" (Standard: localhost)
#   FORGEJO_PORT     - interner HTTP-Port (Standard: 3000)
#   FORGEJO_USER     - Systembenutzer fuer Forgejo (Standard: forgejo)

set -e

FORGEJO_VERSION="${FORGEJO_VERSION:-9.0.3}"
FORGEJO_DOMAIN="${FORGEJO_DOMAIN:-localhost}"
FORGEJO_PORT="${FORGEJO_PORT:-3000}"
FORGEJO_USER="${FORGEJO_USER:-forgejo}"
FORGEJO_HOME="/home/$FORGEJO_USER"
FORGEJO_BIN="/usr/local/bin/forgejo"
FORGEJO_WORK="/var/lib/forgejo"
FORGEJO_CONF="/etc/forgejo"
ARCH="$(uname -m)"

# sudo-Wrapper
if [ "$(id -u)" = "0" ]; then
    SUDO=""
else
    SUDO="sudo"
fi

# Architektur -> Forgejo Asset-Name
case "$ARCH" in
    x86_64)  FORGEJO_ARCH="amd64" ;;
    aarch64) FORGEJO_ARCH="arm64" ;;
    armv7l)  FORGEJO_ARCH="armv6" ;;
    *) echo "[ERROR] Unbekannte Architektur: $ARCH"; exit 1 ;;
esac

FORGEJO_URL="https://codeberg.org/forgejo/forgejo/releases/download/v${FORGEJO_VERSION}/forgejo-${FORGEJO_VERSION}-linux-${FORGEJO_ARCH}"

echo ''
echo '================================================'
echo '  bootstrap-foundation: Forgejo Service'
echo '================================================'
echo "  Version : $FORGEJO_VERSION"
echo "  Domain  : $FORGEJO_DOMAIN"
echo "  Port    : $FORGEJO_PORT"
echo "  User    : $FORGEJO_USER"
echo '================================================'
echo ''

# 1) Basis-Pakete
echo '[1/6] Installiere Basis-Pakete...'
$SUDO apt-get update -qq
$SUDO apt-get install -y git curl wget sqlite3
echo '      OK'

# 2) Forgejo-Systembenutzer anlegen
echo '[2/6] Systembenutzer anlegen...'
if ! id "$FORGEJO_USER" >/dev/null 2>&1; then
    $SUDO adduser \
        --system \
        --shell /bin/bash \
        --gecos 'Forgejo' \
        --group \
        --disabled-password \
        --home "$FORGEJO_HOME" \
        "$FORGEJO_USER"
    echo "      Benutzer '$FORGEJO_USER' angelegt"
else
    echo "      Benutzer '$FORGEJO_USER' existiert bereits, OK"
fi

# 3) Forgejo-Binary herunterladen
echo '[3/6] Lade Forgejo Binary herunter...'
echo "      URL: $FORGEJO_URL"
if [ ! -f "$FORGEJO_BIN" ]; then
    $SUDO wget -q -O "$FORGEJO_BIN" "$FORGEJO_URL"
    $SUDO chmod +x "$FORGEJO_BIN"
    echo "      Installiert: $FORGEJO_BIN"
else
    INSTALLED_VERSION="$($FORGEJO_BIN --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo 'unbekannt')"
    echo "      Forgejo $INSTALLED_VERSION bereits installiert, ueberspringe"
    echo "      (Zum Upgrade: FORGEJO_VERSION=X.Y.Z ./bootstrap.sh erneut ausfuehren)"
fi
echo '      OK'

# 4) Verzeichnisstruktur + app.ini
echo '[4/6] Verzeichnisse und Konfiguration...'
$SUDO mkdir -p "$FORGEJO_WORK" "$FORGEJO_CONF"
$SUDO chown -R "$FORGEJO_USER:$FORGEJO_USER" "$FORGEJO_WORK" "$FORGEJO_CONF"
$SUDO chmod 750 "$FORGEJO_CONF"

# app.ini nur anlegen wenn noch nicht vorhanden
APP_INI="$FORGEJO_CONF/app.ini"
if [ ! -f "$APP_INI" ]; then
    $SUDO tee "$APP_INI" > /dev/null <<EOF
[DEFAULT]
RUN_USER = $FORGEJO_USER
RUN_MODE = prod

[server]
DOMAIN           = $FORGEJO_DOMAIN
HTTP_PORT        = $FORGEJO_PORT
ROOT_URL         = https://$FORGEJO_DOMAIN/
SSH_DOMAIN       = $FORGEJO_DOMAIN
LOCAL_ROOT_URL   = http://localhost:$FORGEJO_PORT/

[database]
DB_TYPE  = sqlite3
PATH     = $FORGEJO_WORK/forgejo.db

[repository]
ROOT = $FORGEJO_WORK/repositories

[log]
ROOT_PATH = $FORGEJO_WORK/log
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

[openid]
ENABLE_OPENID_SIGNIN = true
EOF
    $SUDO chown "$FORGEJO_USER:$FORGEJO_USER" "$APP_INI"
    $SUDO chmod 640 "$APP_INI"
    echo "      app.ini erstellt: $APP_INI"
else
    echo "      app.ini existiert bereits, ueberspringe"
fi
echo '      OK'

# 5) systemd Service
echo '[5/6] systemd Service einrichten...'
$SUDO tee /etc/systemd/system/forgejo.service > /dev/null <<EOF
[Unit]
Description=Forgejo - Beyond coding. We forge.
After=network.target
Wants=network.target

[Service]
Type=simple
User=$FORGEJO_USER
Group=$FORGEJO_USER
WorkingDirectory=$FORGEJO_WORK
ExecStart=$FORGEJO_BIN web --config $FORGEJO_CONF/app.ini
Restart=on-failure
RestartSec=10
Environment=HOME=$FORGEJO_HOME USER=$FORGEJO_USER
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_BIND_SERVICE
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

$SUDO systemctl daemon-reload
$SUDO systemctl enable forgejo
$SUDO systemctl start forgejo
echo '      systemd: forgejo.service aktiviert und gestartet'
echo '      OK'

# 6) Caddy als Reverse Proxy (optional)
echo '[6/6] Caddy Reverse Proxy...'
if [ "$FORGEJO_DOMAIN" = "localhost" ]; then
    echo '      FORGEJO_DOMAIN=localhost -> Caddy-Setup uebersprungen'
    echo '      Forgejo laueft direkt auf http://localhost:$FORGEJO_PORT'
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
    # Nur schreiben wenn noch kein Forgejo-Block vorhanden
    if ! grep -q "$FORGEJO_DOMAIN" "$CADDYFILE" 2>/dev/null; then
        $SUDO tee -a "$CADDYFILE" > /dev/null <<EOF

$FORGEJO_DOMAIN {
    reverse_proxy localhost:$FORGEJO_PORT
}
EOF
        $SUDO systemctl reload caddy 2>/dev/null || $SUDO systemctl restart caddy
        echo "      Caddy: Block fuer $FORGEJO_DOMAIN hinzugefuegt"
    else
        echo "      Caddyfile hat bereits einen Block fuer $FORGEJO_DOMAIN, OK"
    fi
fi
echo '      OK'

echo ''
echo '================================================'
echo '  Forgejo Bootstrap abgeschlossen!'
echo '================================================'
echo ''
if [ "$FORGEJO_DOMAIN" = "localhost" ]; then
    echo "  Forgejo: http://localhost:$FORGEJO_PORT"
else
    echo "  Forgejo: https://$FORGEJO_DOMAIN"
fi
echo ''
echo '  Naechste Schritte:'
echo '  1) Forgejo Web-Setup aufrufen (Initial-Wizard)'
echo '  2) Admin-Account anlegen'
echo '  3) DISABLE_REGISTRATION = true setzen (optional)'
echo "  4) Logs: journalctl -u forgejo -f"
echo ''
