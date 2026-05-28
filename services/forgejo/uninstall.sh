#!/bin/sh
# services/forgejo/uninstall.sh
# Forgejo vollstaendig deinstallieren (systemd, Binary, Konfig, Daten, User)
#
# ACHTUNG: --purge loescht auch Repositories und Datenbank!
#
# STARTEN (ohne Daten):
#   curl -fsSL https://raw.githubusercontent.com/KonradLanz/bootstrap-foundation/main/services/forgejo/uninstall.sh | sh
#
# STARTEN (mit Datenverlust / vollstaendig):
#   curl -fsSL ... | sh -s -- --purge

set -e

PURGE=0
for arg in "$@"; do
    [ "$arg" = "--purge" ] && PURGE=1
done

FORGEJO_USER="${FORGEJO_USER:-forgejo}"
FORGEJO_BIN="/usr/local/bin/forgejo"
FORGEJO_WORK="/var/lib/forgejo"
FORGEJO_CONF="/etc/forgejo"
FORGEJO_SERVICE="/etc/systemd/system/forgejo.service"

if [ "$(id -u)" = "0" ]; then SUDO=""; else SUDO="sudo"; fi

echo ''
echo '================================================'
echo '  Forgejo Uninstall'
if [ "$PURGE" = "1" ]; then
    echo '  MODUS: --purge (Daten werden geloescht!)'
else
    echo '  MODUS: soft (Daten bleiben erhalten)'
fi
echo '================================================'
echo ''

# 1) systemd Service stoppen und deaktivieren
echo '[1/5] systemd Service stoppen...'
if $SUDO systemctl is-active --quiet forgejo 2>/dev/null; then
    $SUDO systemctl stop forgejo
    echo '      forgejo.service gestoppt'
else
    echo '      forgejo.service war nicht aktiv'
fi
if $SUDO systemctl is-enabled --quiet forgejo 2>/dev/null; then
    $SUDO systemctl disable forgejo
    echo '      forgejo.service deaktiviert'
fi
if [ -f "$FORGEJO_SERVICE" ]; then
    $SUDO rm -f "$FORGEJO_SERVICE"
    $SUDO systemctl daemon-reload
    echo '      forgejo.service Datei entfernt'
fi
echo '      OK'

# 2) Binary entfernen
echo '[2/5] Binary entfernen...'
if [ -f "$FORGEJO_BIN" ]; then
    $SUDO rm -f "$FORGEJO_BIN"
    echo "      Entfernt: $FORGEJO_BIN"
else
    echo "      $FORGEJO_BIN nicht gefunden, OK"
fi
echo '      OK'

# 3) Konfiguration entfernen
echo '[3/5] Konfiguration entfernen...'
if [ -d "$FORGEJO_CONF" ]; then
    $SUDO rm -rf "$FORGEJO_CONF"
    echo "      Entfernt: $FORGEJO_CONF"
else
    echo "      $FORGEJO_CONF nicht gefunden, OK"
fi
echo '      OK'

# 4) Daten (nur mit --purge)
echo '[4/5] Daten...'
if [ "$PURGE" = "1" ]; then
    if [ -d "$FORGEJO_WORK" ]; then
        $SUDO rm -rf "$FORGEJO_WORK"
        echo "      PURGE: $FORGEJO_WORK geloescht (inkl. Repositories + DB)"
    else
        echo "      $FORGEJO_WORK nicht gefunden, OK"
    fi
else
    echo "      Daten behalten: $FORGEJO_WORK"
    echo "      (fuer vollstaendige Bereinigung: --purge)"
fi
echo '      OK'

# 5) Systembenutzer entfernen (nur mit --purge)
echo '[5/5] Systembenutzer...'
if [ "$PURGE" = "1" ]; then
    if id "$FORGEJO_USER" >/dev/null 2>&1; then
        $SUDO deluser --remove-home "$FORGEJO_USER" 2>/dev/null || \
            $SUDO userdel -r "$FORGEJO_USER" 2>/dev/null || true
        echo "      PURGE: Benutzer '$FORGEJO_USER' entfernt"
    else
        echo "      Benutzer '$FORGEJO_USER' nicht gefunden, OK"
    fi
else
    echo "      Benutzer '$FORGEJO_USER' behalten (kein --purge)"
fi
echo '      OK'

echo ''
echo '================================================'
echo '  Forgejo Uninstall abgeschlossen'
echo '================================================'
echo ''
if [ "$PURGE" = "0" ] && [ -d "$FORGEJO_WORK" ]; then
    echo "  Daten noch vorhanden: $FORGEJO_WORK"
    echo "  Zum vollstaendigen Loeschen: sh uninstall.sh --purge"
fi
echo '  Port 3000 freigegeben (Pruefe mit: ss -tlnp | grep 3000)'
echo ''
