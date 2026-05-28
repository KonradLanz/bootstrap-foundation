#!/bin/sh
################################################################################
# qnap/forgejo/uninstall-forgejo.sh
# Stoppt und entfernt den Forgejo-Docker-Container auf QNAP.
#
# Daten werden NIEMALS automatisch geloescht.
# --purge-data muss explizit uebergeben werden, mit interaktiver Rueckfrage
# (Default: N = Daten behalten).
#
# Usage:
#   sh qnap/forgejo/uninstall-forgejo.sh [OPTIONS]
#
# Options:
#   --dry-run        Zeigt was getan wuerden; keine Aenderungen
#   --purge-data     Erlaubt Loeschen der Datendirektory (interaktive Bestaetigung)
#   --base-dir PATH  Pfad zum Forgejo-Datenverzeichnis (default: auto-detect)
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
FORGEJO_BASE=""
AUTORUN_FILE="/etc/config/autorun.sh"

# ── Parse arguments ───────────────────────────────────────────────────────────
while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run)    DRY_RUN=1; shift ;;
        --purge-data) PURGE_DATA=1; shift ;;
        --base-dir)   FORGEJO_BASE="$2"; shift 2 ;;
        --help|-h)
            cat <<EOF
uninstall-forgejo.sh — Entfernt Forgejo Docker-Container auf QNAP

Usage:
  $0 [OPTIONS]

Options:
  --dry-run        Nur anzeigen, keine Aenderungen
  --purge-data     Daten loeschen erlauben (interaktive Bestaetigung, default: N)
  --base-dir PATH  Forgejo-Datenpfad (default: auto-detect)
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
    # Minimale Farb-/Log-Definitionen falls lib fehlt
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
printf "${RED}║  Forgejo Uninstall — QNAP Docker                     ║${NC}\n"
printf "${RED}╚══════════════════════════════════════════════════════╝${NC}\n"
[ "$DRY_RUN" -eq 1 ] && printf "${YELLOW}  *** DRY-RUN — keine Aenderungen ***${NC}\n"
printf "\n"

# ── Step 1: Forgejo-Basisverzeichnis finden ────────────────────────────────────
log_info "[1/4] Suche Forgejo-Datenverzeichnis..."

if [ -n "$FORGEJO_BASE" ]; then
    # Manuell uebergeben
    if [ ! -d "$FORGEJO_BASE" ]; then
        log_error "Verzeichnis nicht gefunden: $FORGEJO_BASE"
    fi
else
    # Auto-detect: erstmal Standard-Pfad, dann laufenden Container fragen
    if [ -d /share/docs/forgejo ] && [ -f /share/docs/forgejo/docker-compose.yml ]; then
        FORGEJO_BASE="/share/docs/forgejo"
    else
        # Container laeuft: Mount-Pfad auslesen
        if docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^forgejo$'; then
            DETECTED="$(docker inspect forgejo \
                --format '{{range .Mounts}}{{if eq .Destination "/data"}}{{.Source}}{{end}}{{end}}' \
                2>/dev/null | head -1)"
            if [ -n "$DETECTED" ]; then
                # DETECTED ist z.B. /share/docs/forgejo/data -> parent
                FORGEJO_BASE="$(dirname "$DETECTED")"
            fi
        fi
    fi
fi

if [ -z "$FORGEJO_BASE" ]; then
    log_warn "Kein Forgejo-Datenverzeichnis gefunden — nur Container wird gestoppt."
else
    log_success "Forgejo-Daten: $FORGEJO_BASE"
fi

# ── Step 2: Container stoppen + entfernen ─────────────────────────────────────
log_info "[2/4] Stoppe und entferne Forgejo-Container..."

if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q '^forgejo$'; then
    if [ -n "$FORGEJO_BASE" ] && [ -f "$FORGEJO_BASE/docker-compose.yml" ]; then
        execute_cmd "docker compose down (forgejo)" \
            "cd \"$FORGEJO_BASE\" && docker compose down 2>/dev/null || docker-compose down 2>/dev/null"
    else
        execute_cmd "docker stop forgejo" "docker stop forgejo"
        execute_cmd "docker rm forgejo"   "docker rm forgejo"
    fi
    log_success "Container gestoppt und entfernt"
else
    log_warn "Kein laufender/vorhandener Container 'forgejo' gefunden"
fi

# Image optional entfernen (wird nicht gemacht ohne explizite Nachfrage)
if docker images 'codeberg.org/forgejo/forgejo' --format '{{.Repository}}' 2>/dev/null | grep -q 'forgejo'; then
    log_info "  Docker-Image vorhanden: codeberg.org/forgejo/forgejo"
    log_info "  Zum Entfernen: docker rmi codeberg.org/forgejo/forgejo:latest"
fi

# ── Step 3: autorun.sh-Hook entfernen ─────────────────────────────────────────
log_info "[3/4] Entferne autorun.sh-Hook..."

if [ -f "$AUTORUN_FILE" ]; then
    if grep -qF "forgejo" "$AUTORUN_FILE" 2>/dev/null; then
        if [ "$DRY_RUN" -eq 1 ]; then
            printf "  [DRY]   Wuerde Forgejo-Zeilen aus %s entfernen:\n" "$AUTORUN_FILE"
            grep -n "forgejo" "$AUTORUN_FILE" | sed 's/^/          /'
        else
            # Backup vor Aenderung
            cp "$AUTORUN_FILE" "${AUTORUN_FILE}.bak.$(date +%Y%m%d%H%M%S)"
            # Entferne Kommentarzeile + compose-Zeile (2 zusammenhaengende Zeilen)
            sed -i '/# Forgejo Docker service/{N;d}' "$AUTORUN_FILE" 2>/dev/null || \
            sed -i '/forgejo/d' "$AUTORUN_FILE"
            log_success "autorun.sh bereinigt (Backup erstellt)"
        fi
    else
        log_warn "Kein Forgejo-Hook in $AUTORUN_FILE gefunden"
    fi
else
    log_warn "$AUTORUN_FILE nicht vorhanden"
fi

# /opt/bin Symlink entfernen
if [ -L /opt/bin/bootstrap-forgejo.sh ]; then
    execute_cmd "Entferne /opt/bin/bootstrap-forgejo.sh" "rm /opt/bin/bootstrap-forgejo.sh"
fi

# ── Step 4: Datenverwaltung ────────────────────────────────────────────────────
log_info "[4/4] Datenverwaltung..."

if [ -z "$FORGEJO_BASE" ] || [ ! -d "$FORGEJO_BASE" ]; then
    log_warn "Kein Datenverzeichnis gefunden — nichts zu tun"
elif [ "$PURGE_DATA" -eq 0 ]; then
    printf "\n"
    printf "  ${GREEN}Daten wurden behalten:${NC} %s\n" "$FORGEJO_BASE"
    printf "  Zum Loeschen: %s --purge-data\n" "$0"
else
    printf "\n"
    printf "  ${RED}WARNUNG: Daten loeschen ist unwiderruflich!${NC}\n"
    printf "  Verzeichnis : %s\n" "$FORGEJO_BASE"
    printf "  Groesse     : %s\n" "$(du -sh "$FORGEJO_BASE" 2>/dev/null | cut -f1 || echo '?')"
    printf "\n"
    printf "  Wirklich loeschen? [j/N] "
    read -r CONFIRM
    case "$CONFIRM" in
        j|J|ja|Ja|JA|yes|YES|y|Y)
            if [ "$DRY_RUN" -eq 1 ]; then
                printf "  [DRY]   Wuerde loeschen: %s\n" "$FORGEJO_BASE"
            else
                rm -rf "$FORGEJO_BASE"
                log_success "Daten geloescht: $FORGEJO_BASE"
            fi
            ;;
        *)
            log_warn "Loeschen abgebrochen — Daten behalten: $FORGEJO_BASE"
            ;;
    esac
fi

# ── Zusammenfassung ────────────────────────────────────────────────────────────
printf "\n"
printf "${GREEN}╔══════════════════════════════════════════════════════╗${NC}\n"
printf "${GREEN}║  Forgejo Uninstall abgeschlossen                     ║${NC}\n"
printf "${GREEN}╚══════════════════════════════════════════════════════╝${NC}\n"
printf "\n"
printf "  Container  : gestoppt und entfernt\n"
printf "  autorun.sh : bereinigt\n"
if [ -n "$FORGEJO_BASE" ] && [ -d "$FORGEJO_BASE" ]; then
    printf "  Daten      : ${YELLOW}behalten${NC} -> %s\n" "$FORGEJO_BASE"
else
    printf "  Daten      : entfernt oder nicht vorhanden\n"
fi
printf "\n"
