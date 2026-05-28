#!/bin/sh
# services/port-check.sh
# Prueft Port-Belegung fuer Gitea und Forgejo (verhindert Port 3000 Konflikte)
#
# Zeigt: welcher Prozess haelt welchen Port, Status beider Services.
#
# STARTEN:
#   sh services/port-check.sh
#   # oder remote:
#   curl -fsSL https://raw.githubusercontent.com/KonradLanz/bootstrap-foundation/main/services/port-check.sh | sh

GITEA_PORT="${GITEA_PORT:-3000}"
FORGEJO_PORT="${FORGEJO_PORT:-3000}"

if [ "$(id -u)" = "0" ]; then SUDO=""; else SUDO="sudo"; fi

echo ''
echo '================================================'
echo '  Service Port-Check: Gitea vs. Forgejo'
echo '================================================'
echo ''

# --- systemd Status ---
echo '[ systemd Services ]'
for SVC in gitea forgejo; do
    if systemctl list-unit-files "${SVC}.service" 2>/dev/null | grep -q "${SVC}.service"; then
        STATUS="$(systemctl is-active $SVC 2>/dev/null || echo 'unknown')"
        ENABLED="$(systemctl is-enabled $SVC 2>/dev/null || echo 'unknown')"
        printf '  %-10s active=%-10s enabled=%s\n' "$SVC" "$STATUS" "$ENABLED"
    else
        printf '  %-10s nicht installiert\n' "$SVC"
    fi
done
echo ''

# --- Port-Belegung ---
echo '[ Port-Belegung ]'
if command -v ss >/dev/null 2>&1; then
    # ss bevorzugt (modernes Linux)
    for PORT in 3000 2222 22 80 443; do
        LINE="$($SUDO ss -tlnp "sport = :$PORT" 2>/dev/null | tail -n +2)"
        if [ -n "$LINE" ]; then
            PROC="$(echo "$LINE" | grep -oP 'users:\(\("\K[^"]+' || echo '?')"
            printf '  Port %-5s BELEGT   -> %s\n' "$PORT" "$PROC"
        else
            printf '  Port %-5s frei\n' "$PORT"
        fi
    done
elif command -v netstat >/dev/null 2>&1; then
    # Fallback: netstat
    for PORT in 3000 2222 22 80 443; do
        LINE="$(netstat -tlnp 2>/dev/null | grep ":$PORT ")"
        if [ -n "$LINE" ]; then
            printf '  Port %-5s BELEGT   -> %s\n' "$PORT" "$(echo $LINE | awk '{print $7}')"
        else
            printf '  Port %-5s frei\n' "$PORT"
        fi
    done
else
    echo '  [WARN] weder ss noch netstat verfuegbar'
    echo '  Installiere mit: sudo apt-get install -y iproute2'
fi
echo ''

# --- Konflikterkennung ---
echo '[ Konflikterkennung ]'
GITEA_ACTIVE=0
FORGEJO_ACTIVE=0
systemctl is-active --quiet gitea 2>/dev/null && GITEA_ACTIVE=1
systemctl is-active --quiet forgejo 2>/dev/null && FORGEJO_ACTIVE=1

if [ "$GITEA_ACTIVE" = "1" ] && [ "$FORGEJO_ACTIVE" = "1" ]; then
    if [ "$GITEA_PORT" = "$FORGEJO_PORT" ]; then
        echo "  KONFLIKT: Beide Services laufen auf Port $GITEA_PORT!"
        echo ''
        echo '  Loesungen:'
        echo '  A) Gitea deinstallieren:'
        echo '       curl -fsSL https://raw.githubusercontent.com/KonradLanz/bootstrap-foundation/main/services/gitea/uninstall.sh | sh'
        echo '  B) Forgejo auf anderen Port setzen:'
        echo '       sudo sed -i "s/HTTP_PORT.*= 3000/HTTP_PORT = 3001/" /etc/forgejo/app.ini'
        echo '       sudo systemctl restart forgejo'
        echo '  C) Gitea auf anderen Port setzen:'
        echo '       sudo sed -i "s/HTTP_PORT.*= 3000/HTTP_PORT = 3001/" /etc/gitea/app.ini'
        echo '       sudo systemctl restart gitea'
    else
        echo "  OK: Gitea laeuft auf Port $GITEA_PORT, Forgejo auf Port $FORGEJO_PORT - kein Konflikt"
    fi
elif [ "$GITEA_ACTIVE" = "1" ] && [ "$FORGEJO_ACTIVE" = "0" ]; then
    echo "  OK: Nur Gitea aktiv (Port $GITEA_PORT), Forgejo nicht aktiv"
elif [ "$GITEA_ACTIVE" = "0" ] && [ "$FORGEJO_ACTIVE" = "1" ]; then
    echo "  OK: Nur Forgejo aktiv (Port $FORGEJO_PORT), Gitea nicht aktiv"
else
    echo '  OK: Weder Gitea noch Forgejo aktiv'
fi
echo ''

# --- app.ini Ports ---
echo '[ Konfigurierte Ports (app.ini) ]'
for SVC in gitea forgejo; do
    INI="/etc/$SVC/app.ini"
    if [ -f "$INI" ]; then
        PORT_VAL="$(grep 'HTTP_PORT' "$INI" 2>/dev/null | tr -d ' ' | cut -d= -f2 || echo 'nicht gesetzt')"
        printf '  %-10s HTTP_PORT = %s  (%s)\n' "$SVC" "$PORT_VAL" "$INI"
    else
        printf '  %-10s app.ini nicht vorhanden (%s)\n' "$SVC" "$INI"
    fi
done
echo ''
echo '================================================'
echo '  Port-Check abgeschlossen'
echo '================================================'
echo ''
