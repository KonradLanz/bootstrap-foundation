#!/bin/sh
################################################################################
# qnap/port-status.sh
# Zeigt Status aller QNAP-Docker-Services und Port-Belegung.
# Speziell fuer parallelen Betrieb von Gitea + Forgejo.
#
# Usage:
#   sh qnap/port-status.sh [--verbose]
#
# Compatible with BusyBox ash.
################################################################################

VERBOSE=0
[ "$1" = "--verbose" ] || [ "$1" = "-v" ] && VERBOSE=1

# Farben (ANSI, funktioniert in QNAP-Shell)
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

printf "\n"
printf "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}\n"
printf "${CYAN}║  QNAP Docker Service + Port Status                           ║${NC}\n"
printf "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}\n"
printf "\n"

# ── Docker verfuegbar? ─────────────────────────────────────────────────────────
if ! command -v docker >/dev/null 2>&1; then
    printf "  ${RED}[ERROR]${NC} Docker nicht gefunden. Container Station installieren.\n\n"
    exit 1
fi

# ── Hilfsfunktion: Port-Inhaber ermitteln ──────────────────────────────────────
port_holder() {
    PORT="$1"
    # Welcher Docker-Container haelt diesen Port?
    HOLDER="$(docker ps --format '{{.Names}} {{.Ports}}' 2>/dev/null \
        | grep ":${PORT}->" | awk '{print $1}' | head -1)"
    if [ -n "$HOLDER" ]; then
        printf "docker:%s" "$HOLDER"
        return
    fi
    # Kein Docker -> netstat/ss
    if command -v netstat >/dev/null 2>&1; then
        LINE="$(netstat -tlnp 2>/dev/null | grep ":${PORT} ")"
        [ -n "$LINE" ] && { printf "%s" "$(echo $LINE | awk '{print $7}')"; return; }
    elif command -v ss >/dev/null 2>&1; then
        LINE="$(ss -tlnp 2>/dev/null | grep ":${PORT} ")"
        [ -n "$LINE" ] && { printf "%s" "$(echo $LINE | grep -o 'users:([^)]*)' | head -1)"; return; }
    fi
    printf "frei"
}

# ── Sektion 1: Laufende Docker-Container ───────────────────────────────────────
printf "${BLUE}[ Docker Container ]${NC}\n"
printf "  %-20s %-12s %-30s %s\n" "NAME" "STATUS" "IMAGE" "PORTS"
printf "  %s\n" "$(printf '─%.0s' $(seq 1 80))"

if docker ps -a --format '{{.Names}}|{{.Status}}|{{.Image}}|{{.Ports}}' 2>/dev/null | grep -q '|'; then
    docker ps -a --format '{{.Names}}|{{.Status}}|{{.Image}}|{{.Ports}}' 2>/dev/null \
    | while IFS='|' read -r NAME STATUS IMAGE PORTS; do
        # Status-Farbe
        case "$STATUS" in
            Up*)   SCOLOR="$GREEN" ;;
            Exited*) SCOLOR="$RED" ;;
            *)     SCOLOR="$YELLOW" ;;
        esac
        # Image kuerzen
        SHORT_IMAGE="$(echo "$IMAGE" | sed 's|.*/||' | cut -c1-28)"
        # Ports kuerzen
        SHORT_PORTS="$(echo "$PORTS" | sed 's/0\.0\.0\.0://g' | sed 's/, /,/g' | cut -c1-40)"
        printf "  %-20s ${SCOLOR}%-12s${NC} %-30s %s\n" \
            "$NAME" "$(echo $STATUS | cut -c1-10)" "$SHORT_IMAGE" "$SHORT_PORTS"
    done
else
    printf "  (keine Container vorhanden)\n"
fi
printf "\n"

# ── Sektion 2: Port-Belegung ───────────────────────────────────────────────────
printf "${BLUE}[ Port-Belegung ]${NC}\n"
printf "  %-8s %-10s %s\n" "PORT" "PROTO" "INHABER"
printf "  %s\n" "$(printf '─%.0s' $(seq 1 50))"

for PORT in 80 443 3000 3001 2222 2223 5432 5433; do
    HOLDER="$(port_holder $PORT)"
    if [ "$HOLDER" = "frei" ]; then
        printf "  %-8s %-10s ${GREEN}frei${NC}\n" ":$PORT" "TCP"
    else
        printf "  %-8s %-10s ${YELLOW}%s${NC}\n" ":$PORT" "TCP" "$HOLDER"
    fi
done
printf "\n"

# ── Sektion 3: Gitea vs. Forgejo Direktvergleich ──────────────────────────────
printf "${BLUE}[ Gitea vs. Forgejo ]${NC}\n"
printf "  %-12s %-10s %-8s %-8s %s\n" "SERVICE" "STATUS" "HTTP" "SSH" "DATEN"
printf "  %s\n" "$(printf '─%.0s' $(seq 1 65))"

for SVC in gitea forgejo; do
    # Container-Status
    RAW_STATUS="$(docker inspect "$SVC" --format '{{.State.Status}}' 2>/dev/null || echo 'nicht installiert')"
    case "$RAW_STATUS" in
        running) STEXT="${GREEN}running${NC}" ;;
        exited)  STEXT="${RED}exited${NC}" ;;
        "nicht installiert") STEXT="${YELLOW}--${NC}" ;;
        *) STEXT="$RAW_STATUS" ;;
    esac

    # Ports aus docker inspect
    HTTP_PORT=""
    SSH_PORT=""
    if docker inspect "$SVC" >/dev/null 2>&1; then
        HTTP_PORT="$(docker inspect "$SVC" \
            --format '{{range $p,$b := .NetworkSettings.Ports}}{{if $b}}{{$p}}={{index $b 0 "HostPort"}} {{end}}{{end}}' \
            2>/dev/null | tr ' ' '\n' | grep '3000\|8080\|80/' | grep -o '[0-9]*$' | head -1)"
        SSH_PORT="$(docker inspect "$SVC" \
            --format '{{range $p,$b := .NetworkSettings.Ports}}{{if $b}}{{$p}}={{index $b 0 "HostPort"}} {{end}}{{end}}' \
            2>/dev/null | tr ' ' '\n' | grep '22/' | grep -o '[0-9]*$' | head -1)"
    fi
    [ -z "$HTTP_PORT" ] && HTTP_PORT="-"
    [ -z "$SSH_PORT"  ] && SSH_PORT="-"

    # Datenpfad
    DATA_PATH="-"
    for CANDIDATE in /share/docs/$SVC /share/CACHEDEV1_DATA/$SVC /share/CACHEDEV2_DATA/$SVC; do
        [ -d "$CANDIDATE" ] && { DATA_PATH="$CANDIDATE"; break; }
    done
    SHORT_DATA="$(echo $DATA_PATH | sed 's|/share/||')"

    printf "  %-12s %-10b %-8s %-8s %s\n" \
        "$SVC" "$STEXT" "$HTTP_PORT" "$SSH_PORT" "$SHORT_DATA"
done
printf "\n"

# ── Sektion 4: autorun.sh ─────────────────────────────────────────────────────
printf "${BLUE}[ autorun.sh Hooks ]${NC}\n"
if [ -f /etc/config/autorun.sh ]; then
    # Zeige nur relevante nicht-auskommentierte Zeilen
    grep -v '^#' /etc/config/autorun.sh | grep -v '^$' | while read -r LINE; do
        printf "  %s\n" "$LINE"
    done
    printf "\n"
    printf "  ${GREEN}Aktive Hooks:${NC} $(grep -vc '^#\|^$' /etc/config/autorun.sh 2>/dev/null || echo 0)\n"
else
    printf "  /etc/config/autorun.sh nicht vorhanden\n"
fi
printf "\n"

# ── Sektion 5: Empfehlung paralleler Betrieb ──────────────────────────────────
GITEA_UP=0
FORGEJO_UP=0
docker inspect gitea    --format '{{.State.Status}}' 2>/dev/null | grep -q running && GITEA_UP=1
docker inspect forgejo  --format '{{.State.Status}}' 2>/dev/null | grep -q running && FORGEJO_UP=1

if [ "$GITEA_UP" -eq 1 ] && [ "$FORGEJO_UP" -eq 1 ]; then
    printf "${GREEN}[ Parallelbetrieb aktiv ]${NC}\n"
    printf "  Gitea   und Forgejo laufen gleichzeitig.\n"
    printf "  Vergleiche, dann deinstalliere den Verlierer:\n"
    printf "\n"
    printf "  Gitea entfernen   : sh qnap/gitea/uninstall-gitea.sh\n"
    printf "  Forgejo entfernen : sh qnap/forgejo/uninstall-forgejo.sh\n"
    printf "  (Daten bleiben erhalten bis --purge-data explizit uebergeben wird)\n"
elif [ "$GITEA_UP" -eq 1 ] && [ "$FORGEJO_UP" -eq 0 ]; then
    printf "${YELLOW}[ Nur Gitea aktiv ]${NC}\n"
    printf "  Forgejo starten : sh qnap/forgejo/bootstrap-forgejo.sh --http-port 3001 --ssh-port 2223\n"
elif [ "$GITEA_UP" -eq 0 ] && [ "$FORGEJO_UP" -eq 1 ]; then
    printf "${YELLOW}[ Nur Forgejo aktiv ]${NC}\n"
    printf "  Gitea starten   : sh qnap/gitea/bootstrap-gitea.sh --http-port 3001 --ssh-port 2223\n"
else
    printf "${YELLOW}[ Kein Service aktiv ]${NC}\n"
    printf "  Forgejo starten : sh qnap/forgejo/bootstrap-forgejo.sh\n"
    printf "  Gitea starten   : sh qnap/gitea/bootstrap-gitea.sh\n"
fi
printf "\n"
printf "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}\n"
printf "\n"
