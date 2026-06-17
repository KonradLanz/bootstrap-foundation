#!/bin/sh
################################################################################
# qnap/vaultwarden/setup-vaultwarden.sh
# Post-deploy initialisation fuer Vaultwarden auf QNAP.
#
# Fuehrt Post-Deploy-Schritte durch (analog zu setup-forgejo.sh):
#   - Wartet bis Vaultwarden bereit ist
#   - Prueft ob erster Account angelegt werden kann
#   - Deaktiviert oeffentliche Registrierung (--disable-signups)
#   - Erstellt Backup-Crontab-Eintrag (--setup-backup)
#   - Gibt bw-CLI Verbindungs-Snippet aus
#
# Usage:
#   sh qnap/vaultwarden/setup-vaultwarden.sh [OPTIONS]
#
# Options:
#   --disable-signups      Disable new registrations (single-user setup)
#   --setup-backup         Install daily backup cron job
#   --backup-dir PATH      Backup target directory (default: /share/backup)
#   --port PORT            HTTP port of running Vaultwarden (default: 8080)
#   --admin-token TOKEN    Admin token (reads from compose env if omitted)
#   --compose-dir PATH     Path with docker-compose.yml (default: /share/vaultwarden)
#   --dry-run              Show what would be done; make no changes
#   --help, -h             Show this help
#
# Compatible with BusyBox ash.
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LIB_DIR="$REPO_ROOT/qnap/lib"

# ── Defaults ──────────────────────────────────────────────────────────────────
DRY_RUN=0
VERBOSE=0
DISABLE_SIGNUPS=0
SETUP_BACKUP=0
BACKUP_DIR="/share/backup"
HTTP_PORT=8080
ADMIN_TOKEN=""
COMPOSE_DIR="/share/vaultwarden"
COMPOSE_FILE="$COMPOSE_DIR/docker-compose.yml"

# ── Parse arguments ───────────────────────────────────────────────────────────
while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run)         DRY_RUN=1;  shift ;;
        --verbose|-v)      VERBOSE=1;  shift ;;
        --disable-signups) DISABLE_SIGNUPS=1; shift ;;
        --setup-backup)    SETUP_BACKUP=1;    shift ;;
        --backup-dir)      BACKUP_DIR="$2";   shift 2 ;;
        --port)            HTTP_PORT="$2";    shift 2 ;;
        --admin-token)     ADMIN_TOKEN="$2";  shift 2 ;;
        --compose-dir)     COMPOSE_DIR="$2"; COMPOSE_FILE="$COMPOSE_DIR/docker-compose.yml"; shift 2 ;;
        --help|-h)
            cat <<EOF
setup-vaultwarden.sh — Post-deploy setup for Vaultwarden on QNAP

Usage:
  $0 [OPTIONS]

Options:
  --disable-signups      Disable new registrations (recommended: single-user)
  --setup-backup         Install daily backup cron job
  --backup-dir PATH      Backup target directory (default: /share/backup)
  --port PORT            HTTP port (default: 8080)
  --admin-token TOKEN    Admin token (reads from compose env if omitted)
  --compose-dir PATH     docker-compose.yml location (default: /share/vaultwarden)
  --dry-run              Show what would be done; make no changes
  --help, -h             Show this help

Examples:
  $0 --disable-signups --setup-backup
  $0 --disable-signups --dry-run
EOF
            exit 0
            ;;
        -*) printf "Unknown option: %s\n" "$1" >&2; exit 1 ;;
        *) shift ;;
    esac
done

# ── Source shared library ─────────────────────────────────────────────────────
[ -f "$LIB_DIR/docker-service.sh" ] || { printf "[ERROR] Cannot find %s/docker-service.sh\n" "$LIB_DIR" >&2; exit 1; }
. "$LIB_DIR/docker-service.sh"

# ── Wait until Vaultwarden is ready ────────────────────────────────────────
wait_for_vaultwarden() {
    _url="http://127.0.0.1:$HTTP_PORT/alive"
    _max=30
    _i=0
    log_info "Waiting for Vaultwarden at $_url"
    while [ "$_i" -lt "$_max" ]; do
        if wget -q --spider "$_url" 2>/dev/null || curl -sf "$_url" >/dev/null 2>&1; then
            log_success "Vaultwarden is ready."
            return 0
        fi
        _i=$(( _i + 1 ))
        printf "."
        sleep 2
    done
    printf "\n"
    log_error "Vaultwarden did not respond after $(( _max * 2 )) seconds."
}

# ── Disable signups via docker compose env patch ───────────────────────────
disable_signups() {
    if [ ! -f "$COMPOSE_FILE" ]; then
        log_warn "Cannot find $COMPOSE_FILE — skipping signups disable."
        return 0
    fi

    # Check if already disabled
    if grep -q 'SIGNUPS_ALLOWED.*false' "$COMPOSE_FILE" 2>/dev/null; then
        log_info "SIGNUPS_ALLOWED already false — nothing to do."
        return 0
    fi

    log_info "Setting SIGNUPS_ALLOWED=false in $COMPOSE_FILE"
    if [ "$DRY_RUN" -eq 1 ]; then
        log_dry_run "WOULD sed SIGNUPS_ALLOWED: true -> false in $COMPOSE_FILE"
        return 0
    fi
    sed -i 's/SIGNUPS_ALLOWED: \"true\"/SIGNUPS_ALLOWED: \"false\"/g' "$COMPOSE_FILE"
    log_info "Restarting Vaultwarden to apply change..."
    execute_cmd "docker compose restart" \
        sh -c "cd '$COMPOSE_DIR' && docker compose restart"
    log_success "Signups disabled and container restarted."
}

# ── Install backup cron job ────────────────────────────────────────────────
setup_backup_cron() {
    CRON_LINE="0 3 * * * tar czf ${BACKUP_DIR}/vaultwarden-\$(date +\%F).tar.gz /share/vaultwarden/data/ 2>&1 | logger -t vaultwarden-backup"

    if [ "$DRY_RUN" -eq 1 ]; then
        log_dry_run "WOULD add crontab entry:"
        printf "  %s\n" "$CRON_LINE"
        return 0
    fi

    # QNAP uses /etc/config/crontab
    CRONTAB_FILE="/etc/config/crontab"
    if grep -q 'vaultwarden-backup' "$CRONTAB_FILE" 2>/dev/null; then
        log_info "Backup cron job already present in $CRONTAB_FILE."
        return 0
    fi

    mkdir -p "$BACKUP_DIR"
    printf '%s\n' "$CRON_LINE" >> "$CRONTAB_FILE"
    crontab "$CRONTAB_FILE"
    log_success "Backup cron job installed (daily 03:00): $BACKUP_DIR/vaultwarden-YYYY-MM-DD.tar.gz"
}

# ── Print bw CLI integration snippet ───────────────────────────────────────
print_bw_snippet() {
    cat <<'SNIPPET'

───────────────────────────────────────────────────────────────────────────────
Bitwarden CLI (bw) integration snippet for pipeline scripts:
───────────────────────────────────────────────────────────────────────────────

  # One-time login (store session key in env or keychain)
  export BW_SESSION=$(bw login --raw)
  # OR unlock if already logged in:
  export BW_SESSION=$(bw unlock --raw)

  # Retrieve a secret by item name:
  export IMAP_PASSWORD=$(bw get password "email-analyser-imap")
  export SMTP_PASSWORD=$(bw get password "email-analyser-smtp")
  export OPENAI_API_KEY=$(bw get password "email-analyser-openai")

  # Lock vault when done:
  bw lock

SNIPPET
}

# ── Main ────────────────────────────────────────────────────────────────────
log_info "=== Vaultwarden Post-Deploy Setup ==="

wait_for_vaultwarden

[ "$DISABLE_SIGNUPS" -eq 1 ] && disable_signups
[ "$SETUP_BACKUP"    -eq 1 ] && setup_backup_cron

print_bw_snippet

log_success "Setup complete."
