#!/bin/sh
################################################################################
# qnap/gitea/bootstrap-gitea.sh
# Bootstrap Gitea as a Docker container on QNAP NAS.
#
# Usage:
#   sh qnap/gitea/bootstrap-gitea.sh [OPTIONS] [DOMAIN] [ADMIN_PASS]
#
# Options:
#   --dry-run           Show what would be done; make no changes
#   --verbose, -v       Print debug output
#   --http-port PORT    HTTP port for Gitea      (default: 3000)
#   --ssh-port  PORT    SSH port for Gitea       (default: 2222)
#   --postgres          Use shared PostgreSQL container (nas-postgres)
#   --tls               Enable HTTPS using cert at SSL_CERT_DIR
#   --ssl-dir PATH      Path to TLS certs        (default: /share/ssl/own.dedyn.io)
#
# Compatible with BusyBox ash (no declare, no [[, no bash arrays).
################################################################################

# ── Locate repo root ─────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LIB_DIR="$REPO_ROOT/qnap/lib"

# ── Defaults ──────────────────────────────────────────────────────────────────────────────
DRY_RUN=0
VERBOSE=0
ALWAYS_CONFIRM=0
GITEA_DOMAIN=""
GITEA_ADMIN_PASS=""
HTTP_PORT=3000
SSH_PORT=2222
USE_POSTGRES=0
USE_TLS=0
SSL_CERT_DIR="/share/ssl/own.dedyn.io"
SHARED_NETWORK="nas-services"

# ── Parse arguments ─────────────────────────────────────────────────────────────────
while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run)      DRY_RUN=1;  shift ;;
        --verbose|-v)   VERBOSE=1;  shift ;;
        --postgres)     USE_POSTGRES=1; shift ;;
        --tls)          USE_TLS=1;  shift ;;
        --http-port)    HTTP_PORT="$2";    shift 2 ;;
        --ssh-port)     SSH_PORT="$2";     shift 2 ;;
        --ssl-dir)      SSL_CERT_DIR="$2"; shift 2 ;;
        --help|-h)
            cat <<EOF
bootstrap-gitea.sh — Install Gitea via Docker on QNAP

Usage:
  $0 [OPTIONS] [DOMAIN] [ADMIN_PASS]

Options:
  --dry-run           Show what would be done; make no changes
  --verbose, -v       Print debug output
  --http-port PORT    HTTP port (default: 3000)
  --ssh-port PORT     SSH port  (default: 2222)
  --postgres          Use shared PostgreSQL (requires bootstrap-postgres.sh run first)
  --tls               Enable HTTPS with cert from --ssl-dir
  --ssl-dir PATH      Path containing own.dedyn.io.fullchain + own.dedyn.io.key
                      (default: /share/ssl/own.dedyn.io)
  --help, -h          Show this help

Positional:
  DOMAIN              Public domain or NAS IP (e.g. gitea.own.dedyn.io)
  ADMIN_PASS          Admin password (prompted if omitted)

Examples:
  $0 --dry-run
  $0 192.168.0.215
  $0 --postgres --tls gitea.own.dedyn.io
  $0 --postgres --tls --ssl-dir /share/ssl/own.dedyn.io gitea.own.dedyn.io
EOF
            exit 0
            ;;
        -*)
            printf "Unknown option: %s\n" "$1" >&2; exit 1 ;;
        *)
            if [ -z "$GITEA_DOMAIN" ]; then
                GITEA_DOMAIN="$1"
            elif [ -z "$GITEA_ADMIN_PASS" ]; then
                GITEA_ADMIN_PASS="$1"
            fi
            shift ;;
    esac
done

# ── Source shared library ────────────────────────────────────────────────────────────────
if [ -f "$LIB_DIR/docker-service.sh" ]; then
    . "$LIB_DIR/docker-service.sh"
else
    printf "[ERROR] Cannot find %s/docker-service.sh\n" "$LIB_DIR" >&2
    exit 1
fi

# ── Banner ──────────────────────────────────────────────────────────────────────────────
printf "\n"
printf "${BLUE}╔══════════════════════════════════════════════════════╗${NC}\n"
printf "${BLUE}║  Gitea Bootstrap — QNAP Docker Install               ║${NC}\n"
printf "${BLUE}╚══════════════════════════════════════════════════════╝${NC}\n"
[ "$DRY_RUN" -eq 1 ] && \
    printf "${YELLOW}  *** DRY-RUN mode — no changes will be made ***${NC}\n"
printf "\n"

# ── Step 1: System info ───────────────────────────────────────────────────────────────────
log_info "[1/6] Collecting system information..."
HOSTNAME_VAL=$(hostname 2>/dev/null || printf "qnap-nas")
OS_NAME="QNAP NAS"
[ -f /etc/os-release ] && \
    OS_NAME=$(grep "^PRETTY_NAME" /etc/os-release 2>/dev/null \
              | cut -d'=' -f2- | tr -d '"')
CPU_CORES=0
[ -f /proc/cpuinfo ] && CPU_CORES=$(grep -c "^processor" /proc/cpuinfo)
RAM_KB=0
[ -f /proc/meminfo ] && RAM_KB=$(grep "MemTotal:" /proc/meminfo | awk '{print $2}')
RAM_GB=$((RAM_KB / 1024 / 1024))
log_success "Host : $HOSTNAME_VAL"
log_success "OS   : $OS_NAME"
log_success "CPU  : $CPU_CORES cores | RAM: ${RAM_GB} GB"

# ── Step 2: Requirements ────────────────────────────────────────────────────────────────────
log_info "[2/6] Checking requirements..."
command -v docker >/dev/null 2>&1 || \
    log_error "Docker not found. Install QNAP Container Station first."

COMPOSE_CMD=""
if docker compose version >/dev/null 2>&1; then
    COMPOSE_CMD="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
    COMPOSE_CMD="docker-compose"
else
    log_error "Neither 'docker compose' nor 'docker-compose' found."
fi
log_success "Requirements satisfied. Compose command: $COMPOSE_CMD"

if [ "$USE_POSTGRES" -eq 1 ]; then
    if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^nas-postgres$"; then
        log_error "nas-postgres container not running. Run bootstrap-postgres.sh first."
    fi
    log_success "nas-postgres: running"
fi

if [ "$USE_TLS" -eq 1 ]; then
    CERT_FILE="$SSL_CERT_DIR/own.dedyn.io.fullchain"
    KEY_FILE="$SSL_CERT_DIR/own.dedyn.io.key"
    if [ "$DRY_RUN" -ne 1 ]; then
        [ -f "$CERT_FILE" ] || log_error "TLS cert not found: $CERT_FILE"
        [ -f "$KEY_FILE"  ] || log_error "TLS key not found:  $KEY_FILE"
        log_success "TLS certs found: $SSL_CERT_DIR"
    else
        log_dry_run "Would verify TLS certs at $SSL_CERT_DIR"
    fi
fi

# ── Step 3: Detect management IP ─────────────────────────────────────────────────────
log_info "[3/6] Detecting management IP..."
get_management_ip

[ -z "$GITEA_DOMAIN" ] && {
    GITEA_DOMAIN="$LOCAL_IP"
    log_warn "No DOMAIN supplied; using IP: $GITEA_DOMAIN"
}

if [ "$USE_TLS" -eq 1 ]; then
    PROTOCOL="https"
    ROOT_URL="https://${GITEA_DOMAIN}"
else
    PROTOCOL="http"
    ROOT_URL="http://${GITEA_DOMAIN}:${HTTP_PORT}"
fi

# ── Step 4: Select persistent volume ─────────────────────────────────────────────────────
log_info "[4/6] Selecting persistent volume..."

GITEA_BASE=""
if [ -d /share/docs/gitea ] && [ -f /share/docs/gitea/docker-compose.yml ]; then
    log_warn "Existing installation detected at /share/docs/gitea — reusing volume."
    GITEA_BASE="/share/docs/gitea"
    SELECTED_VOLUME="/share/docs"
else
    list_available_volumes
    select_volume
    GITEA_BASE="$SELECTED_VOLUME/gitea"
fi

DATA_DIR="$GITEA_BASE/data"
CONFIG_DIR="$GITEA_BASE/config"
COMPOSE_FILE="$GITEA_BASE/docker-compose.yml"

log_success "Gitea data will be stored at: $GITEA_BASE"
log_debug   "  data  : $DATA_DIR"
log_debug   "  config: $CONFIG_DIR"

# ── Step 5: Create directories + generate compose ──────────────────────────────────────
log_info "[5/6] Creating directories and configuration..."

confirm_action "Create $GITEA_BASE/{data,config} and docker-compose.yml" || {
    log_warn "Installation aborted."
    exit 0
}

execute_cmd "mkdir -p $DATA_DIR"   "mkdir -p \"$DATA_DIR\""
execute_cmd "mkdir -p $CONFIG_DIR" "mkdir -p \"$CONFIG_DIR\""

# Build database env block
if [ "$USE_POSTGRES" -eq 1 ]; then
    PG_ENV_FILE="$SELECTED_VOLUME/postgres/.env"
    PG_USER="nasuser"
    PG_PASS=""
    if [ -f "$PG_ENV_FILE" ]; then
        PG_USER=$(grep "^POSTGRES_USER=" "$PG_ENV_FILE" | cut -d'=' -f2-)
        PG_PASS=$(grep "^POSTGRES_PASSWORD=" "$PG_ENV_FILE" | cut -d'=' -f2-)
    fi
    if [ -z "$PG_PASS" ]; then
        printf "\n${YELLOW}[INPUT]${NC} PostgreSQL password for user '%s': " "$PG_USER"
        stty -echo 2>/dev/null || true
        read -r PG_PASS
        stty echo 2>/dev/null || true
        printf "\n"
    fi
    DB_ENV="      - GITEA__database__DB_TYPE=postgres
      - GITEA__database__HOST=nas-postgres:5432
      - GITEA__database__NAME=gitea
      - GITEA__database__USER=${PG_USER}
      - GITEA__database__PASSWD=${PG_PASS}
      - GITEA__database__SSL_MODE=disable"
    CREATE_DB_CMD="docker exec nas-postgres psql -U ${PG_USER} -tc \"SELECT 1 FROM pg_database WHERE datname='gitea'\" | grep -q 1 || docker exec nas-postgres psql -U ${PG_USER} -c \"CREATE DATABASE gitea ENCODING 'UTF8' LC_COLLATE 'C' LC_CTYPE 'C' TEMPLATE template0;\""
    execute_cmd "Create gitea database in PostgreSQL" "$CREATE_DB_CMD"
    NETWORK_SECTION="    networks:
      - ${SHARED_NETWORK}

networks:
  ${SHARED_NETWORK}:
    external: true"
else
    DB_ENV="      - GITEA__database__DB_TYPE=sqlite3
      - GITEA__database__PATH=/data/gitea.db"
    NETWORK_SECTION=""
fi

# Build TLS env block
if [ "$USE_TLS" -eq 1 ]; then
    TLS_ENV="      - GITEA__server__PROTOCOL=https
      - GITEA__server__CERT_FILE=/ssl/own.dedyn.io.fullchain
      - GITEA__server__KEY_FILE=/ssl/own.dedyn.io.key"
    TLS_VOLUME="      - ${SSL_CERT_DIR}:/ssl:ro"
else
    TLS_ENV="      - GITEA__server__PROTOCOL=http"
    TLS_VOLUME=""
fi

COMPOSE_CONTENT="# docker-compose.yml — Gitea on QNAP
# Generated by bootstrap-gitea.sh — regenerate: sh qnap/gitea/bootstrap-gitea.sh [OPTIONS]

services:
  gitea:
    image: gitea/gitea:latest
    container_name: gitea
    restart: unless-stopped
    environment:
      # Server
      - GITEA__server__DOMAIN=${GITEA_DOMAIN}
      - GITEA__server__ROOT_URL=${ROOT_URL}
      - GITEA__server__HTTP_PORT=3000
      - GITEA__server__SSH_DOMAIN=${GITEA_DOMAIN}
      - GITEA__server__SSH_PORT=${SSH_PORT}
      - GITEA__server__OFFLINE_MODE=true
${TLS_ENV}
      # Database
${DB_ENV}
      # Security
      - GITEA__security__INSTALL_LOCK=false
      # Log
      - GITEA__log__LEVEL=Info
      # User mapping
      - USER_UID=1000
      - USER_GID=1000
    volumes:
      - ${DATA_DIR}:/data
      - ${CONFIG_DIR}:/etc/gitea
      - /etc/timezone:/etc/timezone:ro
      - /etc/localtime:/etc/localtime:ro
${TLS_VOLUME}
    ports:
      - \"${HTTP_PORT}:3000\"
      - \"${SSH_PORT}:22\"
${NETWORK_SECTION}"

write_file "$COMPOSE_FILE" "$COMPOSE_CONTENT"
log_success "docker-compose.yml written: $COMPOSE_FILE"

# ── Step 6: Pull + start + autorun ───────────────────────────────────────────────────────────
log_info "[6/6] Pulling Gitea image and starting container..."

confirm_action "Pull gitea/gitea:latest and start container" || {
    log_warn "Skipped. Run manually: cd $GITEA_BASE && $COMPOSE_CMD up -d"
    exit 0
}

execute_cmd "docker pull gitea/gitea:latest" \
    "docker pull gitea/gitea:latest"

execute_cmd "Start Gitea container" \
    "cd \"$GITEA_BASE\" && $COMPOSE_CMD up -d"

add_autorun_hook "$GITEA_BASE" "# Gitea Docker service"

if [ -d /opt/bin ] && [ ! -e /opt/bin/bootstrap-gitea.sh ]; then
    execute_cmd "Symlink to /opt/bin/bootstrap-gitea.sh" \
        "ln -sf \"$0\" /opt/bin/bootstrap-gitea.sh"
    log_success "Symlinked: /opt/bin/bootstrap-gitea.sh"
fi

# ── Post-install summary ───────────────────────────────────────────────────────────────────
printf "\n"
printf "${GREEN}╔══════════════════════════════════════════════════════╗${NC}\n"
printf "${GREEN}║  Gitea Installation Complete                         ║${NC}\n"
printf "${GREEN}╚══════════════════════════════════════════════════════╝${NC}\n"
printf "\n"
if [ "$USE_TLS" -eq 1 ]; then
    printf "  ${BLUE}Web UI${NC}       : https://%s\n"          "$GITEA_DOMAIN"
else
    printf "  ${BLUE}Web UI${NC}       : http://%s:%s\n"        "$LOCAL_IP" "$HTTP_PORT"
fi
printf "  ${BLUE}SSH clone${NC}    : ssh://git@%s:%s\n"    "$GITEA_DOMAIN" "$SSH_PORT"
if [ "$USE_POSTGRES" -eq 1 ]; then
    printf "  ${BLUE}Database${NC}     : PostgreSQL (nas-postgres)\n"
else
    printf "  ${BLUE}Database${NC}     : SQLite3\n"
fi
if [ "$USE_TLS" -eq 1 ]; then
    printf "  ${BLUE}TLS${NC}          : enabled (%s)\n" "$SSL_CERT_DIR"
else
    printf "  ${BLUE}TLS${NC}          : disabled\n"
fi
printf "  ${BLUE}Data path${NC}    : %s\n"                  "$GITEA_BASE"
printf "  ${BLUE}Compose file${NC} : %s\n"                  "$COMPOSE_FILE"
printf "\n"
printf "  ${YELLOW}First visit${NC}: open the Web UI to complete the setup wizard.\n"
printf "  ${YELLOW}Admin user${NC} : created via browser wizard on first run.\n"
printf "\n"
if grep -qF "$GITEA_BASE" /etc/config/autorun.sh 2>/dev/null; then
    printf "  ${GREEN}autorun.sh${NC}: hook present — Gitea starts after every reboot.\n"
else
    printf "  ${YELLOW}autorun.sh${NC}: hook NOT found — add manually:\n"
    printf "    cd \"%s\" && %s up -d\n" "$GITEA_BASE" "$COMPOSE_CMD"
fi
printf "\n"
