#!/bin/sh
################################################################################
# qnap/forgejo/setup-forgejo.sh
# Post-Install Autokonfiguration fuer Forgejo auf QNAP.
#
# Fuehrt den Initial-Setup via Forgejo-API durch (ersetzt den Web-Wizard):
#   - Wartet bis Forgejo bereit ist
#   - Konfiguriert App-Name, Domain, Datenbank via POST /api/v1/...
#   - Legt Admin-Account an (via Forgejo-CLI im Container)
#   - Setzt INSTALL_LOCK=true
#   - Deaktiviert oeffentliche Registrierung (optional)
#
# Usage:
#   sh qnap/forgejo/setup-forgejo.sh [OPTIONS]
#
# Options:
#   --admin-user NAME     Admin-Benutzername         (default: admin)
#   --admin-pass PASS     Admin-Passwort             (prompted if omitted)
#   --admin-email EMAIL   Admin-E-Mail               (default: admin@localhost)
#   --app-name NAME       Anzeigename der Instanz     (default: Forgejo)
#   --domain DOMAIN       Domain oder IP             (default: aus docker inspect)
#   --port PORT           HTTP-Port                  (default: 3000)
#   --disable-register    Oeffentliche Registrierung deaktivieren
#   --dry-run             Nur anzeigen, keine Aenderungen
#   --help, -h            Diese Hilfe
#
# Voraussetzung: Forgejo-Container laeuft (docker ps | grep forgejo)
# Compatible with BusyBox ash.
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LIB_DIR="$REPO_ROOT/qnap/lib"

# ── Defaults ──────────────────────────────────────────────────────────────────
DRY_RUN=0
ADMIN_USER="admin"
ADMIN_PASS=""
ADMIN_EMAIL="admin@localhost"
APP_NAME="Forgejo"
DOMAIN=""
HTTP_PORT="3000"
DISABLE_REGISTER=0
CONTAINER="forgejo"

# ── Parse arguments ───────────────────────────────────────────────────────────
while [ $# -gt 0 ]; do
    case "$1" in
        --admin-user)      ADMIN_USER="$2";   shift 2 ;;
        --admin-pass)      ADMIN_PASS="$2";   shift 2 ;;
        --admin-email)     ADMIN_EMAIL="$2";  shift 2 ;;
        --app-name)        APP_NAME="$2";     shift 2 ;;
        --domain)          DOMAIN="$2";       shift 2 ;;
        --port)            HTTP_PORT="$2";    shift 2 ;;
        --disable-register) DISABLE_REGISTER=1; shift ;;
        --dry-run)         DRY_RUN=1;         shift ;;
        --help|-h)
            cat <<EOF
setup-forgejo.sh — Post-Install Autokonfiguration fuer Forgejo

Usage:
  $0 [OPTIONS]

Options:
  --admin-user NAME     Admin-Benutzername         (default: admin)
  --admin-pass PASS     Admin-Passwort             (interaktiv wenn nicht angegeben)
  --admin-email EMAIL   Admin-E-Mail               (default: admin@localhost)
  --app-name NAME       Instanzname                (default: Forgejo)
  --domain DOMAIN       Domain oder IP             (default: auto-detect)
  --port PORT           HTTP-Port                  (default: 3000)
  --disable-register    Oeffentliche Registrierung sperren
  --dry-run             Nur anzeigen
  --help, -h            Diese Hilfe

Beispiele:
  $0 --admin-user konrad --admin-email k@example.com
  $0 --admin-user admin --disable-register
  $0 --domain forgejo.own.dedyn.io --app-name "Mein Forge"
EOF
            exit 0
            ;;
        *) printf "Unbekannte Option: %s\n" "$1" >&2; exit 1 ;;
    esac
done

# ── Source shared library ──────────────────────────────────────────────────────
if [ -f "$LIB_DIR/docker-service.sh" ]; then
    . "$LIB_DIR/docker-service.sh"
else
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
    BLUE='\033[1;36m'; NC='\033[0m'
    log_info()    { printf "${BLUE}[INFO]${NC} %s\n" "$*"; }
    log_success() { printf "${GREEN}[OK]${NC} %s\n" "$*"; }
    log_warn()    { printf "${YELLOW}[WARN]${NC} %s\n" "$*"; }
    log_error()   { printf "${RED}[ERROR]${NC} %s\n" "$*" >&2; exit 1; }
fi

# ── Banner ─────────────────────────────────────────────────────────────────────
printf "\n"
printf "${BLUE}╔══════════════════════════════════════════════════════╗${NC}\n"
printf "${BLUE}║  Forgejo Setup — Post-Install Autokonfig              ║${NC}\n"
printf "${BLUE}╚══════════════════════════════════════════════════════╝${NC}\n"
[ "$DRY_RUN" -eq 1 ] && printf "${YELLOW}  *** DRY-RUN — keine Aenderungen ***${NC}\n"
printf "\n"

# ── Passwort abfragen wenn nicht gesetzt ─────────────────────────────────────
if [ -z "$ADMIN_PASS" ]; then
    printf "${YELLOW}[INPUT]${NC} Admin-Passwort fuer '%s': " "$ADMIN_USER"
    stty -echo 2>/dev/null || true
    read -r ADMIN_PASS
    stty echo 2>/dev/null || true
    printf "\n"
    [ -z "$ADMIN_PASS" ] && log_error "Passwort darf nicht leer sein."
fi

# ── Step 1: Container pruefen ──────────────────────────────────────────────────
log_info "[1/5] Pruefe Container..."
docker inspect "$CONTAINER" --format '{{.State.Status}}' 2>/dev/null | grep -q running || \
    log_error "Container '$CONTAINER' laeuft nicht. Zuerst bootstrap-forgejo.sh ausfuehren."
log_success "Container '$CONTAINER' laeuft"

# Domain auto-detect wenn nicht gesetzt
if [ -z "$DOMAIN" ]; then
    DOMAIN="$(docker inspect forgejo \
        --format '{{range $p,$b := .NetworkSettings.Ports}}{{if $b}}{{index $b 0 "HostIp"}}{{end}}{{end}}' \
        2>/dev/null | grep -v '^0\.0\.0\.0$\|^$' | head -1)"
    [ -z "$DOMAIN" ] && DOMAIN="localhost"
    log_warn "--domain nicht angegeben, verwende: $DOMAIN"
fi

FORGEJO_URL="http://localhost:${HTTP_PORT}"
log_success "Forgejo URL (intern): $FORGEJOURL"

# ── Step 2: Warten bis Forgejo bereit ──────────────────────────────────────────
log_info "[2/5] Warte auf Forgejo HTTP..."
MAX_WAIT=60
WAIT=0
while [ $WAIT -lt $MAX_WAIT ]; do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
        "http://localhost:${HTTP_PORT}" 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "303" ]; then
        log_success "Forgejo antwortet (HTTP $HTTP_CODE) nach ${WAIT}s"
        break
    fi
    WAIT=$((WAIT + 3))
    printf "  ... warte %ds (HTTP %s)\n" "$WAIT" "$HTTP_CODE"
    sleep 3
done
[ $WAIT -ge $MAX_WAIT ] && log_error "Forgejo antwortet nach ${MAX_WAIT}s nicht. Container-Logs: docker logs $CONTAINER"

# ── Step 3: Admin-User per Forgejo CLI anlegen ─────────────────────────────────
log_info "[3/5] Lege Admin-User per CLI an..."
# Forgejo CLI laeuft direkt im Container via 'forgejo admin user create'
CLI_CMD="docker exec -u git $CONTAINER \
    forgejo admin user create \
    --username '$ADMIN_USER' \
    --password '$ADMIN_PASS' \
    --email '$ADMIN_EMAIL' \
    --admin \
    --must-change-password=false"

if [ "$DRY_RUN" -eq 1 ]; then
    printf "  [DRY]   Wuerde ausfuehren:\n"
    printf "          docker exec -u git forgejo forgejo admin user create \\\n"
    printf "            --username '%s' --email '%s' --admin\n" "$ADMIN_USER" "$ADMIN_EMAIL"
else
    OUTPUT=$(eval "$CLI_CMD" 2>&1)
    EXIT_CODE=$?
    if [ $EXIT_CODE -eq 0 ]; then
        log_success "Admin-User '$ADMIN_USER' angelegt"
    else
        # Bereits vorhanden ist kein Fehler
        if printf '%s' "$OUTPUT" | grep -qi "already exists\|bereits\|duplicate"; then
            log_warn "User '$ADMIN_USER' existiert bereits — uebersprungen"
        else
            log_warn "CLI-Fehler: $OUTPUT"
            log_warn "Fallback: User kann im Web-Wizard angelegt werden"
        fi
    fi
fi

# ── Step 4: app.ini via CLI setzen (INSTALL_LOCK + optional Registrierung sperren) ──────
# Forgejo CLI: forgejo admin user / forgejo admin app-ini
log_info "[4/5] Setze app.ini Werte (INSTALL_LOCK, optional DISABLE_REGISTRATION)..."

# INSTALL_LOCK via forgejo CLI im Container
SET_LOCK_CMD="docker exec -u git $CONTAINER \
    forgejo admin app-ini set --section security --key INSTALL_LOCK --value true"

if [ "$DRY_RUN" -eq 1 ]; then
    printf "  [DRY]   forgejo admin app-ini set security.INSTALL_LOCK=true\n"
else
    OUTPUT=$(eval "$SET_LOCK_CMD" 2>&1)
    if [ $? -eq 0 ]; then
        log_success "INSTALL_LOCK=true gesetzt"
    else
        # Neuere Forgejo-Versionen: app-ini Befehl ggf. anders
        log_warn "app-ini CLI fehlgeschlagen: $OUTPUT"
        log_warn "Alternativ: docker exec -u git forgejo forgejo admin app-ini set ..."
        # Direktes Schreiben in app.ini als Fallback
        APP_INI_HOST="$(docker inspect forgejo \
            --format '{{range .Mounts}}{{if eq .Destination "/etc/gitea"}}{{.Source}}{{end}}{{end}}' \
            2>/dev/null)/app.ini"
        if [ -f "$APP_INI_HOST" ]; then
            sed -i 's/^INSTALL_LOCK.*= false/INSTALL_LOCK       = true/' "$APP_INI_HOST" 2>/dev/null || true
            grep -q 'INSTALL_LOCK' "$APP_INI_HOST" || \
                printf '\n[security]\nINSTALL_LOCK = true\n' >> "$APP_INI_HOST"
            log_success "INSTALL_LOCK=true direkt in app.ini gesetzt: $APP_INI_HOST"
        fi
    fi
fi

if [ "$DISABLE_REGISTER" -eq 1 ]; then
    DIS_CMD="docker exec -u git $CONTAINER \
        forgejo admin app-ini set --section service --key DISABLE_REGISTRATION --value true"
    if [ "$DRY_RUN" -eq 1 ]; then
        printf "  [DRY]   forgejo admin app-ini set service.DISABLE_REGISTRATION=true\n"
    else
        OUTPUT=$(eval "$DIS_CMD" 2>&1)
        if [ $? -eq 0 ]; then
            log_success "DISABLE_REGISTRATION=true gesetzt"
        else
            log_warn "Fallback: direkt in app.ini schreiben..."
            APP_INI_HOST="$(docker inspect forgejo \
                --format '{{range .Mounts}}{{if eq .Destination "/etc/gitea"}}{{.Source}}{{end}}{{end}}' \
                2>/dev/null)/app.ini"
            [ -f "$APP_INI_HOST" ] && \
                sed -i 's/^DISABLE_REGISTRATION.*/DISABLE_REGISTRATION = true/' "$APP_INI_HOST"
            log_success "DISABLE_REGISTRATION=true in app.ini gesetzt"
        fi
    fi
fi

# ── Step 5: Container neu starten damit app.ini greift ───────────────────────────
log_info "[5/5] Starte Container neu (app.ini-Aenderungen aktivieren)..."
if [ "$DRY_RUN" -eq 1 ]; then
    printf "  [DRY]   docker restart forgejo\n"
else
    docker restart "$CONTAINER" >/dev/null 2>&1
    sleep 3
    STATUS=$(docker inspect "$CONTAINER" --format '{{.State.Status}}' 2>/dev/null)
    if [ "$STATUS" = "running" ]; then
        log_success "Container neu gestartet und laeuft"
    else
        log_warn "Container-Status nach Restart: $STATUS"
    fi
fi

# ── Zusammenfassung ────────────────────────────────────────────────────────────
printf "\n"
printf "${GREEN}╔══════════════════════════════════════════════════════╗${NC}\n"
printf "${GREEN}║  Forgejo Setup abgeschlossen                         ║${NC}\n"
printf "${GREEN}╚══════════════════════════════════════════════════════╝${NC}\n"
printf "\n"
printf "  Admin-User  : %s\n" "$ADMIN_USER"
printf "  Admin-Email : %s\n" "$ADMIN_EMAIL"
printf "  Web UI      : http://%s:%s\n" "$DOMAIN" "$HTTP_PORT"
printf "  INSTALL_LOCK: true\n"
[ "$DISABLE_REGISTER" -eq 1 ] && printf "  Registrierung: deaktiviert\n"
printf "\n"
printf "  Naechste Schritte:\n"
printf "  1) Weiteren User anlegen: sh qnap/forgejo/create-user.sh --username <name>\n"
printf "  2) SSH-Key in Forgejo Web UI hinterlegen\n"
printf "  3) HAProxy-Backend auf Port %s zeigen lassen\n" "$HTTP_PORT"
printf "\n"
