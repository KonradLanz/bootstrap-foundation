#!/bin/sh
################################################################################
# qnap/vaultwarden/bootstrap-vaultwarden.sh
# Bootstrap Vaultwarden as a Docker container on QNAP NAS.
#
# Vaultwarden is an unofficial Bitwarden-compatible server written in Rust.
# Credentials are managed via the Bitwarden CLI (bw) after setup.
#
# Usage:
#   sh qnap/vaultwarden/bootstrap-vaultwarden.sh [OPTIONS] [DOMAIN]
#
# Options:
#   --dry-run              Show what would be done; make no changes
#   --verbose, -v          Print debug output
#   --http-port PORT       HTTP port for Vaultwarden          (default: 8080)
#   --ws-port   PORT       WebSocket port                     (default: 3012)
#   --admin-token TOKEN    Hashed admin token (argon2id preferred)
#                          If omitted: generated via openssl rand -base64 48
#   --data-dir  PATH       Persistent data directory          (default: /share/vaultwarden)
#   --haproxy [IP]         TLS terminated at HAProxy/pfSense.
#                          Vaultwarden listens on http, DOMAIN uses https://.
#                          Binds port to 127.0.0.1 only.
#                          IP = trusted proxy IP (default: 192.168.1.2)
#   --rewrite-compose      Overwrite existing docker-compose.yml
#   --disable-signups      Disable new user registrations immediately (recommended after first user)
#
# Compatible with BusyBox ash (no declare, no [[, no bash arrays).
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LIB_DIR="$REPO_ROOT/qnap/lib"

# ── Defaults ──────────────────────────────────────────────────────────────────
DRY_RUN=0
VERBOSE=0
ALWAYS_CONFIRM=0
VW_DOMAIN=""
HTTP_PORT=8080
WS_PORT=3012
ADMIN_TOKEN=""
DATA_DIR="/share/vaultwarden"
USE_HAPROXY=0
HAPROXY_IP="192.168.1.2"
SHARED_NETWORK="nas-services"
REWRITE_COMPOSE=0
DISABLE_SIGNUPS=0

# ── Parse arguments ───────────────────────────────────────────────────────────
while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run)         DRY_RUN=1;  shift ;;
        --verbose|-v)      VERBOSE=1;  shift ;;
        --haproxy)
            USE_HAPROXY=1
            case "${2:-}" in
                -*|'') ;;
                *) HAPROXY_IP="$2"; shift ;;
            esac
            shift ;;
        --http-port)       HTTP_PORT="$2";      shift 2 ;;
        --ws-port)         WS_PORT="$2";        shift 2 ;;
        --admin-token)     ADMIN_TOKEN="$2";    shift 2 ;;
        --data-dir)        DATA_DIR="$2";       shift 2 ;;
        --rewrite-compose) REWRITE_COMPOSE=1;   shift ;;
        --disable-signups) DISABLE_SIGNUPS=1;   shift ;;
        --help|-h)
            cat <<EOF
bootstrap-vaultwarden.sh — Install Vaultwarden via Docker on QNAP

Usage:
  $0 [OPTIONS] [DOMAIN]

Options:
  --dry-run              Show what would be done; make no changes
  --verbose, -v          Print debug output
  --http-port PORT       HTTP port (default: 8080)
  --ws-port   PORT       WebSocket notifications port (default: 3012)
  --admin-token TOKEN    Admin token (generated if omitted)
  --data-dir  PATH       Data directory (default: /share/vaultwarden)
  --haproxy [IP]         TLS at HAProxy/pfSense (recommended). IP default: 192.168.1.2
  --rewrite-compose      Overwrite existing docker-compose.yml
  --disable-signups      Disable signups immediately (single-user setup)
  --help, -h             Show this help

Examples:
  $0 --dry-run
  $0 --haproxy vault.own.dedyn.io
  $0 --haproxy 192.168.1.2 --disable-signups vault.own.dedyn.io
  $0 --http-port 8080 --disable-signups
EOF
            exit 0
            ;;
        -*) printf "Unknown option: %s\n" "$1" >&2; exit 1 ;;
        *)
            [ -z "$VW_DOMAIN" ] && VW_DOMAIN="$1"
            shift ;;
    esac
done

# ── Source shared library ─────────────────────────────────────────────────────
[ -f "$LIB_DIR/docker-service.sh" ] || { printf "[ERROR] Cannot find %s/docker-service.sh\n" "$LIB_DIR" >&2; exit 1; }
. "$LIB_DIR/docker-service.sh"

# ── Derived values ────────────────────────────────────────────────────────────
COMPOSE_DIR="$DATA_DIR"
COMPOSE_FILE="$COMPOSE_DIR/docker-compose.yml"

# Build ROOT_URL
if [ -n "$VW_DOMAIN" ]; then
    if [ "$USE_HAPROXY" -eq 1 ]; then
        ROOT_URL="https://$VW_DOMAIN"
    else
        ROOT_URL="http://$VW_DOMAIN:$HTTP_PORT"
    fi
else
    # Will be replaced with detected IP in run_setup
    ROOT_URL=""
fi

# ── Generate admin token if not provided ─────────────────────────────────────
generate_admin_token() {
    if command -v openssl >/dev/null 2>&1; then
        openssl rand -base64 48
    else
        # Fallback: /dev/urandom
        head -c 36 /dev/urandom | base64 | tr -d '\n/'
    fi
}

# ── Build docker-compose.yml content ─────────────────────────────────────────
build_compose() {
    _root_url="$1"
    _token="$2"
    _signups="true"
    [ "$DISABLE_SIGNUPS" -eq 1 ] && _signups="false"

    _bind_addr=""
    [ "$USE_HAPROXY" -eq 1 ] && _bind_addr="127.0.0.1:"

    cat <<COMPOSE
services:
  vaultwarden:
    image: vaultwarden/server:latest
    container_name: vaultwarden
    restart: unless-stopped
    volumes:
      - ${DATA_DIR}/data:/data
    ports:
      - "${_bind_addr}${HTTP_PORT}:80"
      - "${_bind_addr}${WS_PORT}:3012"
    environment:
      DOMAIN: "${_root_url}"
      ADMIN_TOKEN: "${_token}"
      SIGNUPS_ALLOWED: "${_signups}"
      WEBSOCKET_ENABLED: "true"
      LOG_LEVEL: "warn"
      EXTENDED_LOGGING: "true"

networks:
  default:
    name: ${SHARED_NETWORK}
    external: true
COMPOSE
}

# ── Ensure shared Docker network exists ──────────────────────────────────────
ensure_network() {
    if ! docker network inspect "$SHARED_NETWORK" >/dev/null 2>&1; then
        log_info "Creating Docker network: $SHARED_NETWORK"
        execute_cmd "docker network create $SHARED_NETWORK" \
            docker network create "$SHARED_NETWORK"
    else
        log_debug "Network $SHARED_NETWORK already exists."
    fi
}

# ── Main setup ────────────────────────────────────────────────────────────────
run_setup() {
    log_info "=== Vaultwarden Bootstrap ==="
    log_info "Data dir  : $DATA_DIR"
    log_info "HTTP port : $HTTP_PORT"
    log_info "WS port   : $WS_PORT"
    log_info "HAProxy   : $USE_HAPROXY"
    [ -n "$VW_DOMAIN" ] && log_info "Domain    : $VW_DOMAIN"

    # ── Detect management IP if no domain given ────────────────────────────
    if [ -z "$ROOT_URL" ]; then
        get_management_ip   # sets LOCAL_IP
        ROOT_URL="http://$LOCAL_IP:$HTTP_PORT"
        log_info "No domain given — using ROOT_URL: $ROOT_URL"
    fi

    # ── Generate admin token ───────────────────────────────────────────────
    if [ -z "$ADMIN_TOKEN" ]; then
        log_info "Generating admin token..."
        ADMIN_TOKEN="$(generate_admin_token)"
        log_warn "ADMIN TOKEN (save this now — shown only once):"
        printf "\n  %s\n\n" "$ADMIN_TOKEN"
    fi

    # ── Create data directory ──────────────────────────────────────────────
    if [ ! -d "$DATA_DIR/data" ]; then
        log_info "Creating data directory: $DATA_DIR/data"
        execute_cmd "mkdir -p $DATA_DIR/data" \
            mkdir -p "$DATA_DIR/data"
    else
        log_debug "Data directory already exists: $DATA_DIR/data"
    fi

    # ── Ensure nas-services network ────────────────────────────────────────
    ensure_network

    # ── Write docker-compose.yml ───────────────────────────────────────────
    if [ -f "$COMPOSE_FILE" ] && [ "$REWRITE_COMPOSE" -eq 0 ]; then
        log_warn "docker-compose.yml already exists: $COMPOSE_FILE"
        log_warn "Use --rewrite-compose to overwrite."
    else
        log_info "Writing $COMPOSE_FILE"
        COMPOSE_CONTENT="$(build_compose "$ROOT_URL" "$ADMIN_TOKEN")"
        write_file "$COMPOSE_FILE" "$COMPOSE_CONTENT"
    fi

    # ── Start container ────────────────────────────────────────────────────
    log_info "Starting Vaultwarden container..."
    execute_cmd "docker compose up -d" \
        sh -c "cd '$COMPOSE_DIR' && docker compose up -d"

    log_success "Vaultwarden deployed."
    log_info "Next steps:"
    printf "  1. Open %s — create your account\n" "$ROOT_URL"
    printf "  2. Admin panel: %s/admin\n" "$ROOT_URL"
    printf "  3. Run setup-vaultwarden.sh --disable-signups to lock down registration\n"
    printf "  4. Configure reverse proxy TLS (HAProxy/pfSense or QNAP RP)\n"
    printf "\n"
    log_warn "Store the admin token securely before closing this terminal!"
}

run_setup
