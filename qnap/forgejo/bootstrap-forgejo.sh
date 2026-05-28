#!/bin/sh
################################################################################
# qnap/forgejo/bootstrap-forgejo.sh
# Bootstrap Forgejo as a Docker container on QNAP NAS.
#
# Forgejo is a community-governed Free Software fork of Gitea.
# Drop-in alternative to qnap/gitea/bootstrap-gitea.sh.
#
# Usage:
#   sh qnap/forgejo/bootstrap-forgejo.sh [OPTIONS] [DOMAIN] [ADMIN_PASS]
#
# Options:
#   --dry-run           Show what would be done; make no changes
#   --verbose, -v       Print debug output
#   --http-port PORT    HTTP port for Forgejo     (default: 3000)
#   --ssh-port  PORT    SSH port for Forgejo      (default: 2222)
#   --postgres          Use shared PostgreSQL container (nas-postgres)
#   --tls               Enable HTTPS using cert at SSL_CERT_DIR
#   --ssl-dir PATH      Path to TLS certs        (default: /share/ssl/own.dedyn.io)
#
# Compatible with BusyBox ash (no declare, no [[, no bash arrays).
################################################################################

# ── Locate repo root ──────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LIB_DIR="$REPO_ROOT/qnap/lib"

# ── Defaults ──────────────────────────────────────────────────────────────────
DRY_RUN=0
VERBOSE=0
ALWAYS_CONFIRM=0
FORGEJO_DOMAIN=""
FORGEJO_ADMIN_PASS=""
HTTP_PORT=3000
SSH_PORT=2222
USE_POSTGRES=0
USE_TLS=0
SSL_CERT_DIR="/share/ssl/own.dedyn.io"
SHARED_NETWORK="nas-services"

# ── Parse arguments ───────────────────────────────────────────────────────────
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
bootstrap-forgejo.sh — Install Forgejo via Docker on QNAP

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
  DOMAIN              Public domain or NAS IP (e.g. forgejo.own.dedyn.io)
  ADMIN_PASS          Admin password (prompted if omitted)

Examples:
  $0 --dry-run
  $0 192.168.0.215
  $0 --postgres --tls forgejo.own.dedyn.io
  $0 --postgres --tls --ssl-dir /share/ssl/own.dedyn.io forgejo.own.dedyn.io
EOF
            exit 0
            ;;
        -*)
            printf "Unknown option: %s\n" "$1" >&2; exit 1 ;;
        *)
            if [ -z "$FORGEJO_DOMAIN" ]; then
                FORGEJO_DOMAIN="$1"
            elif [ -z "$FORGEJO_ADMIN_PASS" ]; then
                FORGEJO_ADMIN_PASS="$1"
            fi
            shift ;;
    esac
done

# ── Source shared library ──────────────────────────────────────────────────────
if [ -f "$LIB_DIR/docker-service.sh" ]; then
    . "$LIB_DIR/docker-service.sh"
else
    printf "[ERROR] Cannot find %s/docker-service.sh\n" "$LIB_DIR" >&2
    exit 1
fi

# ── Banner ─────────────────────────────────────────────────────────────────────
printf "\n"
printf "${BLUE}╔══════════════════════════════════════════════════════╗${NC}\n"
printf "${BLUE}║  Forgejo Bootstrap — QNAP Docker Install             ║${NC}\n"
printf "${BLUE}╚══════════════════════════════════════════════════════╝${NC}\n"
[ "$DRY_RUN" -eq 1 ] && \
    printf "${YELLOW}  *** DRY-RUN mode — no changes will be made ***${NC}\n"
printf "\n"

# ── Step 1: System info ────────────────────────────────────────────────────────
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

# ── Step 2: Requirements ───────────────────────────────────────────────────────
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

# ── Step 3: Detect management IP ──────────────────────────────────────────────
log_info "[3/6] Detecting management IP..."
get_management_ip

[ -z "$FORGEJO_DOMAIN" ] && {
    FORGEJO_DOMAIN="$LOCAL_IP"
    log_warn "No DOMAIN supplied; using IP: $FORGEJO_DOMAIN"
}

if [ "$USE_TLS" -eq 1 ]; then
    PROTOCOL="https"
    ROOT_URL="https://${FORGEJO_DOMAIN}"
else
    PROTOCOL="http"
    ROOT_URL="http://${FORGEJO_DOMAIN}:${HTTP_PORT}"
fi

# ── Step 4: Select persistent volume ──────────────────────────────────────────
log_info "[4/6] Selecting persistent volume..."

FORGEJO_BASE=""
if [ -d /share/docs/forgejo ] && [ -f /share/docs/forgejo/docker-compose.yml ]; then
    log_warn "Existing installation detected at /share/docs/forgejo — reusing volume."
    FORGEJO_BASE="/share/docs/forgejo"
    SELECTED_VOLUME="/share/docs"
else
    list_available_volumes
    select_volume
    FORGEJO_BASE="$SELECTED_VOLUME/forgejo"
fi

DATA_DIR="$FORGEJO_BASE/data"
CONFIG_DIR="$FORGEJO_BASE/config"
COMPOSE_FILE="$FORGEJO_BASE/docker-compose.yml"

log_success "Forgejo data will be stored at: $FORGEJO_BASE"
log_debug   "  data  : $DATA_DIR"
log_debug   "  config: $CONFIG_DIR"

# ── Step 5: Create directories + generate compose ─────────────────────────────
log_info "[5/6] Creating directories and configuration..."

confirm_action "Create $FORGEJO_BASE/{data,config} and docker-compose.yml" || {
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
    DB_ENV="      - FORGEJO__database__DB_TYPE=postgres
      - FORGEJO__database__HOST=nas-postgres:5432
      - FORGEJO__database__NAME=forgejo
      - FORGEJO__database__USER=${PG_USER}
      - FORGEJO__database__PASSWD=${PG_PASS}
      - FORGEJO__database__SSL_MODE=disable"
    CREATE_DB_CMD="docker exec nas-postgres psql -U ${PG_USER} -tc \"SELECT 1 FROM pg_database WHERE datname='forgejo'\" | grep -q 1 || docker exec nas-postgres psql -U ${PG_USER} -c \"CREATE DATABASE forgejo ENCODING 'UTF8' LC_COLLATE 'C' LC_CTYPE 'C' TEMPLATE template0;\""
    execute_cmd "Create forgejo database in PostgreSQL" "$CREATE_DB_CMD"
    NETWORK_SECTION="    networks:
      - ${SHARED_NETWORK}

networks:
  ${SHARED_NETWORK}:
    external: true"
else
    DB_ENV="      - FORGEJO__database__DB_TYPE=sqlite3
      - FORGEJO__database__PATH=/data/forgejo.db"
    NETWORK_SECTION=""
fi

# Build TLS env block
# Note: Forgejo uses the same FORGEJO__ env prefix as Gitea uses GITEA__
if [ "$USE_TLS" -eq 1 ]; then
    TLS_ENV="      - FORGEJO__server__PROTOCOL=https
      - FORGEJO__server__CERT_FILE=/ssl/own.dedyn.io.fullchain
      - FORGEJO__server__KEY_FILE=/ssl/own.dedyn.io.key"
    TLS_VOLUME="      - ${SSL_CERT_DIR}:/ssl:ro"
else
    TLS_ENV="      - FORGEJO__server__PROTOCOL=http"
    TLS_VOLUME=""
fi

COMPOSE_CONTENT="# docker-compose.yml — Forgejo on QNAP
# Generated by bootstrap-forgejo.sh — regenerate: sh qnap/forgejo/bootstrap-forgejo.sh [OPTIONS]

services:
  forgejo:
    image: codeberg.org/forgejo/forgejo:latest
    container_name: forgejo
    restart: unless-stopped
    environment:
      # Server
      - FORGEJO__server__DOMAIN=${FORGEJO_DOMAIN}
      - FORGEJO__server__ROOT_URL=${ROOT_URL}
      - FORGEJO__server__HTTP_PORT=3000
      - FORGEJO__server__SSH_DOMAIN=${FORGEJO_DOMAIN}
      - FORGEJO__server__SSH_PORT=${SSH_PORT}
      - FORGEJO__server__OFFLINE_MODE=true
${TLS_ENV}
      # Database
${DB_ENV}
      # Security
      - FORGEJO__security__INSTALL_LOCK=false
      # Log
      - FORGEJO__log__LEVEL=Info
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

# ── Step 6: Pull + start + autorun ────────────────────────────────────────────
log_info "[6/6] Pulling Forgejo image and starting container..."

confirm_action "Pull codeberg.org/forgejo/forgejo:latest and start container" || {
    log_warn "Skipped. Run manually: cd $FORGEJO_BASE && $COMPOSE_CMD up -d"
    exit 0
}

execute_cmd "docker pull codeberg.org/forgejo/forgejo:latest" \
    "docker pull codeberg.org/forgejo/forgejo:latest"

execute_cmd "Start Forgejo container" \
    "cd \"$FORGEJO_BASE\" && $COMPOSE_CMD up -d"

add_autorun_hook "$FORGEJO_BASE" "# Forgejo Docker service"

if [ -d /opt/bin ] && [ ! -e /opt/bin/bootstrap-forgejo.sh ]; then
    execute_cmd "Symlink to /opt/bin/bootstrap-forgejo.sh" \
        "ln -sf \"$0\" /opt/bin/bootstrap-forgejo.sh"
    log_success "Symlinked: /opt/bin/bootstrap-forgejo.sh"
fi

# ── Post-install summary ───────────────────────────────────────────────────────
printf "\n"
printf "${GREEN}╔══════════════════════════════════════════════════════╗${NC}\n"
printf "${GREEN}║  Forgejo Installation Complete                       ║${NC}\n"
printf "${GREEN}╚══════════════════════════════════════════════════════╝${NC}\n"
printf "\n"
if [ "$USE_TLS" -eq 1 ]; then
    printf "  ${BLUE}Web UI${NC}       : https://%s\n"          "$FORGEJO_DOMAIN"
else
    printf "  ${BLUE}Web UI${NC}       : http://%s:%s\n"        "$LOCAL_IP" "$HTTP_PORT"
fi
printf "  ${BLUE}SSH clone${NC}    : ssh://git@%s:%s\n"    "$FORGEJO_DOMAIN" "$SSH_PORT"
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
printf "  ${BLUE}Data path${NC}    : %s\n"                  "$FORGEJO_BASE"
printf "  ${BLUE}Compose file${NC} : %s\n"                  "$COMPOSE_FILE"
printf "\n"
printf "  ${YELLOW}First visit${NC}: open the Web UI to complete the setup wizard.\n"
printf "  ${YELLOW}Admin user${NC} : created via browser wizard on first run.\n"
printf "\n"
if grep -qF "$FORGEJO_BASE" /etc/config/autorun.sh 2>/dev/null; then
    printf "  ${GREEN}autorun.sh${NC}: hook present — Forgejo starts after every reboot.\n"
else
    printf "  ${YELLOW}autorun.sh${NC}: hook NOT found — add manually:\n"
    printf "    cd \"%s\" && %s up -d\n" "$FORGEJO_BASE" "$COMPOSE_CMD"
fi
printf "\n"
