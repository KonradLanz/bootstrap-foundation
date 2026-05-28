#!/bin/sh
################################################################################
# qnap/gitea/uninstall-gitea.sh
# Stoppt und entfernt den Gitea-Docker-Container auf QNAP.
#
# Daten werden NIEMALS automatisch geloescht.
# --purge-data muss explizit uebergeben werden, mit interaktiver Rueckfrage
# (Default: N = Daten behalten).
#
# Usage:
#   sh qnap/gitea/uninstall-gitea.sh [OPTIONS]
#
# Options:
#   --dry-run        Zeigt was getan wuerden; keine Aenderungen
#   --purge-data     Erlaubt Loeschen der Datendirektory (interaktive Bestaetigung)
#   --base-dir PATH  Pfad zum Gitea-Datenverzeichnis (default: auto-detect)
#   --help, -h       Diese Hilfe
#
# Compatible with BusyBox ash (no declare, no [[, no bash arrays).
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LIB_DIR="$REPO_ROOT/qnap/lib"

# ── Defaults ──────────────────────────────────────────────────────────────────
DRY_RUN=0
PURGE_DATA=0
GITEA_BASE=""
AUTORUN_FILE="/etc/config/autorun.sh"

# ── Parse arguments ───────────────────────────────────────────────────────────
while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run)    DRY_RUN=1; shift ;;
        --purge-data) PURGE_DATA=1; shift ;;
        --base-dir)   GITEA_BASE="$2"; shift 2 ;;
        --help|-h)
            cat <<EOF
uninstall-gitea.sh — Entfernt Gitea Docker-Container auf QNAP

Usage:
  $0 [OPTIONS]

Options:
  --dry-run        Nur anzeigen, keine Aenderungen
  --purge-data     Daten loeschen erlauben (interaktive Bestaetigung, default: N)
  --base-dir PATH  Gitea-Datenpfad (default: auto-detect)
  --help, -h       Diese Hilfe

Daten werden NIEMALS automatisch geloescht.
Ohne --purge-data werden Daten immer behalten.
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
    RED=''; GREEN=''; YELLOW=''; BLUE=''; NC=''
    log_info()    { printf "  [INFO]  %s\n" "$1"; }
    log_success() { printf "  [OK]    %s\n" "$1"; }
    log_warn()    { printf "  [WARN]  %s\n" "$1"; }
    log_error()   { printf "  [ERROR] %s\n" "$1" >&2; exit 1; }
fi

execute_cmd() {
    DESC="$1"; CMD="$2"
    if [ "$DRY_RUN" -eq 1 ]; then
        printf "  [DRY]   %s\n" "$DESC"
        return 0
    fi
    eval "$CMD" || { log_warn "Fehlgeschlagen: $DESC"; return 1; }
}

# ── Banner ─────────────────────────────────────────────────────────────────────
printf "\n"
printf "${RED}╔══════════════════════════════════════════════════════╗${NC}\n"
printf "${RED}║  Gitea Uninstall — QNAP Docker                       ║${NC}\n"
printf "${RED}╚══════════════════════════════════════════════════════╝${NC}\n"
[ "$DRY_RUN" -eq 1 ] && printf "${YELLOW}  *** DRY-RUN — keine Aenderungen ***${NC}\n"
printf "\n"

# ── Step 1: Gitea-Basisverzeichnis finden ──────────────────────────────────────
log_info "[1/4] Suche Gitea-Datenverzeichnis..."

if [ -n "$GITEA_BASE" ]; then
    if [ ! -d "$GITEA_BASE" ]; then
        log_error "Verzeichnis nicht gefunden: $GITEA_BASE"
    fi
else
    if [ -d /share/docs/gitea ] && [ -f /share/docs/gitea/docker-compose.yml ]; then
        GITEA_BASE="/share/docs/gitea"
    else
        if docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^gitea$'; then
            DETECTED="$(docker inspect gitea \
                --format '{{range .Mounts}}{{if eq .Destination "/data"}}{{.Source}}{{end}}{{end}}' \
                2>/dev/null | head -1)"
            if [ -n "$DETECTED" ]; then
                GITEA_BASE="$(dirname "$DETECTED")"
            fi
        fi
    fi
fi

if [ -z "$GITEA_BASE" ]; then
    log_warn "Kein Gitea-Datenverzeichnis gefunden — nur Container wird gestoppt."
else
    log_success "Gitea-Daten: $GITEA_BASE"
fi

# ── Step 2: Container stoppen + entfernen ─────────────────────────────────────
log_info "[2/4] Stoppe und entferne Gitea-Container..."

if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q '^gitea$'; then
    if [ -n "$GITEA_BASE" ] && [ -f "$GITEA_BASE/docker-compose.yml" ]; then
        execute_cmd "docker compose down (gitea)" \
            "cd \"$GITEA_BASE\" && docker compose down 2>/dev/null || docker-compose down 2>/dev/null"
    else
        execute_cmd "docker stop gitea" "docker stop gitea"
        execute_cmd "docker rm gitea"   "docker rm gitea"
    fi
    log_success "Container gestoppt und entfernt"
else
    log_warn "Kein laufender/vorhandener Container 'gitea' gefunden"
fi

if docker images 'gitea/gitea' --format '{{.Repository}}' 2>/dev/null | grep -q 'gitea'; then
    log_info "  Docker-Image vorhanden: gitea/gitea"
    log_info "  Zum Entfernen: docker rmi gitea/gitea:latest"
fi

# ── Step 3: autorun.sh-Hook entfernen ─────────────────────────────────────────
log_info "[3/4] Entferne autorun.sh-Hook..."

if [ -f "$AUTORUN_FILE" ]; then
    if grep -qF "gitea" "$AUTORUN_FILE" 2>/dev/null; then
        if [ "$DRY_RUN" -eq 1 ]; then
            printf "  [DRY]   Wuerde Gitea-Zeilen aus %s entfernen:\n" "$AUTORUN_FILE"
            grep -n "gitea" "$AUTORUN_FILE" | sed 's/^/          /'
        else
            cp "$AUTORUN_FILE" "${AUTORUN_FILE}.bak.$(date +%Y%m%d%H%M%S)"
            sed -i '/# Gitea Docker service/{N;d}' "$AUTORUN_FILE" 2>/dev/null || \
            sed -i '/gitea/d' "$AUTORUN_FILE"
            log_success "autorun.sh bereinigt (Backup erstellt)"
        fi
    else
        log_warn "Kein Gitea-Hook in $AUTORUN_FILE gefunden"
    fi
else
    log_warn "$AUTORUN_FILE nicht vorhanden"
fi

if [ -L /opt/bin/bootstrap-gitea.sh ]; then
    execute_cmd "Entferne /opt/bin/bootstrap-gitea.sh" "rm /opt/bin/bootstrap-gitea.sh"
fi

# ── Step 4: Datenverwaltung ────────────────────────────────────────────────────
log_info "[4/4] Datenverwaltung..."

if [ -z "$GITEA_BASE" ] || [ ! -d "$GITEA_BASE" ]; then
    log_warn "Kein Datenverzeichnis gefunden — nichts zu tun"
elif [ "$PURGE_DATA" -eq 0 ]; then
    printf "\n"
    printf "  ${GREEN}Daten wurden behalten:${NC} %s\n" "$GITEA_BASE"
    printf "  Zum Loeschen: %s --purge-data\n" "$0"
else
    printf "\n"
    printf "  ${RED}WARNUNG: Daten loeschen ist unwiderruflich!${NC}\n"
    printf "  Verzeichnis : %s\n" "$GITEA_BASE"
    printf "  Groesse     : %s\n" "$(du -sh "$GITEA_BASE" 2>/dev/null | cut -f1 || echo '?')"
    printf "\n"
    printf "  Wirklich loeschen? [j/N] "
    read -r CONFIRM
    case "$CONFIRM" in
        j|J|ja|Ja|JA|yes|YES|y|Y)
            if [ "$DRY_RUN" -eq 1 ]; then
                printf "  [DRY]   Wuerde loeschen: %s\n" "$GITEA_BASE"
            else
                rm -rf "$GITEA_BASE"
                log_success "Daten geloescht: $GITEA_BASE"
            fi
            ;;
        *)
            log_warn "Loeschen abgebrochen — Daten behalten: $GITEA_BASE"
            ;;
    esac
fi

# ── Zusammenfassung ────────────────────────────────────────────────────────────
printf "\n"
printf "${GREEN}╔══════════════════════════════════════════════════════╗${NC}\n"
printf "${GREEN}║  Gitea Uninstall abgeschlossen                       ║${NC}\n"
printf "${GREEN}╚══════════════════════════════════════════════════════╝${NC}\n"
printf "\n"
printf "  Container  : gestoppt und entfernt\n"
printf "  autorun.sh : bereinigt\n"
if [ -n "$GITEA_BASE" ] && [ -d "$GITEA_BASE" ]; then
    printf "  Daten      : ${YELLOW}behalten${NC} -> %s\n" "$GITEA_BASE"
else
    printf "  Daten      : entfernt oder nicht vorhanden\n"
fi
printf "\n"
