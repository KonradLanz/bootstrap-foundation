#!/bin/sh
# services/gitea/uninstall.sh
# Gitea vollstaendig deinstallieren (systemd, Binary, Konfig, Daten, User)
#
# ACHTUNG: --purge loescht auch Repositories und Datenbank!
#
# STARTEN (ohne Daten):
#   curl -fsSL https://raw.githubusercontent.com/KonradLanz/bootstrap-foundation/main/services/gitea/uninstall.sh | sh
#
# STARTEN (mit Datenverlust / vollstaendig):
#   curl -fsSL ... | sh -s -- --purge

set -e

PURGE=0
for arg in "$@"; do
    [ "$arg" = "--purge" ] && PURGE=1
done

GITEA_USER="${GITEA_USER:-gitea}"
GITEA_BIN="/usr/local/bin/gitea"
GITEA_WORK="/var/lib/gitea"
GITEA_CONF="/etc/gitea"
GITEA_SERVICE="/etc/systemd/system/gitea.service"

if [ "$(id -u)" = "0" ]; then SUDO=""; else SUDO="sudo"; fi

echo ''
echo '================================================'
echo '  Gitea Uninstall'
if [ "$PURGE" = "1" ]; then
    echo '  MODUS: --purge (Daten werden geloescht!)'
else
    echo '  MODUS: soft (Daten bleiben erhalten)'
fi
echo '================================================'
echo ''

# 1) systemd Service stoppen und deaktivieren
echo '[1/5] systemd Service stoppen...'
if $SUDO systemctl is-active --quiet gitea 2>/dev/null; then
    $SUDO systemctl stop gitea
    echo '      gitea.service gestoppt'
else
    echo '      gitea.service war nicht aktiv'
fi
if $SUDO systemctl is-enabled --quiet gitea 2>/dev/null; then
    $SUDO systemctl disable gitea
    echo '      gitea.service deaktiviert'
fi
if [ -f "$GITEA_SERVICE" ]; then
    $SUDO rm -f "$GITEA_SERVICE"
    $SUDO systemctl daemon-reload
    echo '      gitea.service Datei entfernt'
fi
echo '      OK'

# 2) Binary entfernen
echo '[2/5] Binary entfernen...'
if [ -f "$GITEA_BIN" ]; then
    $SUDO rm -f "$GITEA_BIN"
    echo "      Entfernt: $GITEA_BIN"
else
    echo "      $GITEA_BIN nicht gefunden, OK"
fi
echo '      OK'

# 3) Konfiguration entfernen
echo '[3/5] Konfiguration entfernen...'
if [ -d "$GITEA_CONF" ]; then
    $SUDO rm -rf "$GITEA_CONF"
    echo "      Entfernt: $GITEA_CONF"
else
    echo "      $GITEA_CONF nicht gefunden, OK"
fi
echo '      OK'

# 4) Daten (nur mit --purge)
echo '[4/5] Daten...'
if [ "$PURGE" = "1" ]; then
    if [ -d "$GITEA_WORK" ]; then
        $SUDO rm -rf "$GITEA_WORK"
        echo "      PURGE: $GITEA_WORK geloescht (inkl. Repositories + DB)"
    else
        echo "      $GITEA_WORK nicht gefunden, OK"
    fi
else
    echo "      Daten behalten: $GITEA_WORK"
    echo "      (fuer vollstaendige Bereinigung: --purge)"
fi
echo '      OK'

# 5) Systembenutzer entfernen (nur mit --purge)
echo '[5/5] Systembenutzer...'
if [ "$PURGE" = "1" ]; then
    if id "$GITEA_USER" >/dev/null 2>&1; then
        $SUDO deluser --remove-home "$GITEA_USER" 2>/dev/null || \
            $SUDO userdel -r "$GITEA_USER" 2>/dev/null || true
        echo "      PURGE: Benutzer '$GITEA_USER' entfernt"
    else
        echo "      Benutzer '$GITEA_USER' nicht gefunden, OK"
    fi
else
    echo "      Benutzer '$GITEA_USER' behalten (kein --purge)"
fi
echo '      OK'

echo ''
echo '================================================'
echo '  Gitea Uninstall abgeschlossen'
echo '================================================'
echo ''
if [ "$PURGE" = "0" ] && [ -d "$GITEA_WORK" ]; then
    echo "  Daten noch vorhanden: $GITEA_WORK"
    echo "  Zum vollstaendigen Loeschen: sh uninstall.sh --purge"
fi
echo '  Port 3000 freigegeben (Pruefe mit: ss -tlnp | grep 3000)'
echo ''
