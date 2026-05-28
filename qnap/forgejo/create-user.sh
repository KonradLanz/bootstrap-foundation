#!/bin/sh
################################################################################
# qnap/forgejo/create-user.sh
# Benutzer in Forgejo per CLI anlegen, aendern oder loeschen.
# Verwendet 'forgejo admin user' Befehle im laufenden Container.
#
# Usage:
#   sh qnap/forgejo/create-user.sh [COMMAND] [OPTIONS]
#
# Commands:
#   create   Neuen User anlegen         (default wenn kein Command)
#   delete   User loeschen
#   list     Alle User auflisten
#   passwd   Passwort aendern
#   promote  User zum Admin befoerdern
#   demote   Admin-Rechte entziehen
#
# Options (create):
#   --username NAME    Benutzername (Pflicht)
#   --password PASS    Passwort     (interaktiv wenn nicht angegeben)
#   --email EMAIL      E-Mail       (default: NAME@localhost)
#   --admin            Als Admin anlegen
#   --must-change      Passwort bei erstem Login aendern muessen
#   --source-id ID     Auth-Source fuer LDAP/OAuth (default: 0 = local)
#
# Options (delete):
#   --username NAME    Zu loeschender Benutzername (Pflicht)
#   --purge            Repos und Daten des Users mitloeschen
#
# Options (passwd):
#   --username NAME    Benutzername (Pflicht)
#   --password PASS    Neues Passwort (interaktiv wenn nicht angegeben)
#
# Global Options:
#   --container NAME   Docker-Containername (default: forgejo)
#   --dry-run          Nur anzeigen, keine Aenderungen
#   --help, -h         Diese Hilfe
#
# Compatible with BusyBox ash.
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LIB_DIR="$REPO_ROOT/qnap/lib"

# ── Defaults ──────────────────────────────────────────────────────────────────
DRY_RUN=0
CONTAINER="forgejo"
COMMAND="create"
USERNAME=""
PASSWORD=""
EMAIL=""
IS_ADMIN=0
MUST_CHANGE=0
PURGE=0
SOURCE_ID=0

# ── Parse command ──────────────────────────────────────────────────────────────
case "$1" in
    create|delete|list|passwd|promote|demote) COMMAND="$1"; shift ;;
esac

while [ $# -gt 0 ]; do
    case "$1" in
        --username)   USERNAME="$2";   shift 2 ;;
        --password)   PASSWORD="$2";   shift 2 ;;
        --email)      EMAIL="$2";      shift 2 ;;
        --admin)      IS_ADMIN=1;      shift ;;
        --must-change) MUST_CHANGE=1;  shift ;;
        --purge)      PURGE=1;         shift ;;
        --source-id)  SOURCE_ID="$2"; shift 2 ;;
        --container)  CONTAINER="$2"; shift 2 ;;
        --dry-run)    DRY_RUN=1;       shift ;;
        --help|-h)
            cat <<EOF
create-user.sh — Forgejo User-Verwaltung per CLI

Usage:
  $0 [COMMAND] [OPTIONS]

Commands:
  create   Neuen User anlegen (default)
  delete   User loeschen
  list     Alle User anzeigen
  passwd   Passwort aendern
  promote  Zum Admin befoerdern
  demote   Admin-Rechte entziehen

Options (create):
  --username NAME    Benutzername (Pflicht)
  --password PASS    Passwort (interaktiv wenn weggelassen)
  --email EMAIL      E-Mail (default: NAME@localhost)
  --admin            Als Admin anlegen
  --must-change      Passwort bei erstem Login aendern
  --source-id ID     Auth-Source-ID (default: 0 = lokal)

Options (delete):
  --username NAME    Benutzername (Pflicht)
  --purge            Repos und Daten des Users ebenfalls loeschen

Global:
  --container NAME   Docker-Containername (default: forgejo)
  --dry-run          Nur anzeigen

Beispiele:
  $0 create --username konrad --email k@example.com --admin
  $0 create --username bob --must-change
  $0 list
  $0 passwd --username konrad
  $0 promote --username bob
  $0 delete --username bob --purge
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

# ── Container-Check ────────────────────────────────────────────────────────────
docker inspect "$CONTAINER" --format '{{.State.Status}}' 2>/dev/null | grep -q running || \
    log_error "Container '$CONTAINER' laeuft nicht."

# ── Hilfsfunktion: CLI ausfuehren ───────────────────────────────────────────────────
run_cli() {
    # run_cli <beschreibung> <forgejo-cli-argumente>
    _desc="$1"; shift
    if [ "$DRY_RUN" -eq 1 ]; then
        printf "  [DRY]   docker exec -u git %s forgejo %s\n" "$CONTAINER" "$*"
        return 0
    fi
    OUTPUT=$(docker exec -u git "$CONTAINER" forgejo $@ 2>&1)
    EXIT=$?
    if [ $EXIT -eq 0 ]; then
        log_success "$_desc"
        [ -n "$OUTPUT" ] && printf "  %s\n" "$OUTPUT"
    else
        log_warn "$_desc fehlgeschlagen: $OUTPUT"
        return 1
    fi
}

# ── Commands ─────────────────────────────────────────────────────────────────────
case "$COMMAND" in

    # ───── create ────────────────────────────────────────────────────────────────
    create)
        [ -z "$USERNAME" ] && log_error "--username ist Pflicht"
        [ -z "$EMAIL" ]    && EMAIL="${USERNAME}@localhost"

        if [ -z "$PASSWORD" ]; then
            printf "${YELLOW}[INPUT]${NC} Passwort fuer '%s': " "$USERNAME"
            stty -echo 2>/dev/null || true
            read -r PASSWORD
            stty echo 2>/dev/null || true
            printf "\n"
            [ -z "$PASSWORD" ] && log_error "Passwort darf nicht leer sein."
        fi

        CLI_ARGS="admin user create \
            --username '$USERNAME' \
            --password '$PASSWORD' \
            --email '$EMAIL' \
            --must-change-password=$([ $MUST_CHANGE -eq 1 ] && echo true || echo false)"

        [ $IS_ADMIN -eq 1 ] && CLI_ARGS="$CLI_ARGS --admin"
        [ "$SOURCE_ID" != "0" ] && CLI_ARGS="$CLI_ARGS --source-id $SOURCE_ID"

        printf "\n"
        log_info "Lege User an: $USERNAME ($EMAIL)$([ $IS_ADMIN -eq 1 ] && echo ' [ADMIN]')"
        if [ "$DRY_RUN" -eq 1 ]; then
            printf "  [DRY]   docker exec -u git %s forgejo %s\n" "$CONTAINER" "$CLI_ARGS"
        else
            OUTPUT=$(docker exec -u git "$CONTAINER" sh -c "forgejo $CLI_ARGS" 2>&1)
            EXIT=$?
            if [ $EXIT -eq 0 ]; then
                log_success "User '$USERNAME' angelegt"
            elif printf '%s' "$OUTPUT" | grep -qi "already exists\|duplicate"; then
                log_warn "User '$USERNAME' existiert bereits"
            else
                log_warn "Fehler: $OUTPUT"
            fi
        fi
        ;;

    # ───── delete ────────────────────────────────────────────────────────────────
    delete)
        [ -z "$USERNAME" ] && log_error "--username ist Pflicht"
        printf "\n"
        printf "  ${RED}WARNUNG:${NC} User '%s' loeschen!" "$USERNAME"
        [ $PURGE -eq 1 ] && printf " (inkl. Repos und Daten)"
        printf "\n"
        printf "  Bestaetigen? [j/N] "
        read -r CONFIRM
        case "$CONFIRM" in
            j|J|ja|Ja|yes|YES|y|Y)
                PURGE_FLAG=""; [ $PURGE -eq 1 ] && PURGE_FLAG="--purge"
                run_cli "User '$USERNAME' geloescht" \
                    admin user delete --username "$USERNAME" $PURGE_FLAG
                ;;
            *) log_warn "Abgebrochen" ;;
        esac
        ;;

    # ───── list ──────────────────────────────────────────────────────────────────
    list)
        printf "\n${BLUE}[ Forgejo Users in Container: $CONTAINER ]${NC}\n"
        docker exec -u git "$CONTAINER" forgejo admin user list 2>&1
        ;;

    # ───── passwd ───────────────────────────────────────────────────────────────
    passwd)
        [ -z "$USERNAME" ] && log_error "--username ist Pflicht"
        if [ -z "$PASSWORD" ]; then
            printf "${YELLOW}[INPUT]${NC} Neues Passwort fuer '%s': " "$USERNAME"
            stty -echo 2>/dev/null || true
            read -r PASSWORD
            stty echo 2>/dev/null || true
            printf "\n"
        fi
        run_cli "Passwort fuer '$USERNAME' geaendert" \
            admin user change-password --username "$USERNAME" --password "$PASSWORD"
        ;;

    # ───── promote ──────────────────────────────────────────────────────────────
    promote)
        [ -z "$USERNAME" ] && log_error "--username ist Pflicht"
        run_cli "'$USERNAME' zum Admin befoerdert" \
            admin user generate-access-token --username "$USERNAME" 2>/dev/null || \
        run_cli "'$USERNAME' zum Admin befoerdert" \
            admin user edit --username "$USERNAME" --admin=true
        ;;

    # ───── demote ───────────────────────────────────────────────────────────────
    demote)
        [ -z "$USERNAME" ] && log_error "--username ist Pflicht"
        run_cli "'$USERNAME' Admin-Rechte entzogen" \
            admin user edit --username "$USERNAME" --admin=false
        ;;

esac

printf "\n"
