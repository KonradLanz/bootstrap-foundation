#!/bin/sh
################################################################################
# qnap/gitea/bootstrap-gitea.sh
# Bootstrap Gitea as a Docker container on QNAP NAS.
#
# Usage:
#   sh qnap/gitea/bootstrap-gitea.sh [OPTIONS] [DOMAIN] [ADMIN_PASS]
#
# Options:
#   --dry-run              Show what would be done; make no changes
#   --verbose, -v          Print debug output
#   --http-port PORT       HTTP port for Gitea           (default: 3000)
#   --ssh-port  PORT       SSH port for Gitea            (default: 2222)
#   --image-tag TAG        Gitea image tag               (default: latest)
#   --postgres             Use shared PostgreSQL container (nas-postgres)
#   --tls                  Enable HTTPS using cert at SSL_CERT_DIR
#                          Do NOT combine with --haproxy.
#   --haproxy [IP]         TLS terminated at HAProxy/pfSense.
#                          Gitea listens on http, ROOT_URL uses https://.
#                          Binds port to 127.0.0.1 only.
#                          IP = trusted proxy IP (default: 192.168.1.2)
#   --ssl-dir PATH         Path to TLS certs            (default: /share/ssl/own.dedyn.io)
#   --rewrite-compose      Overwrite existing docker-compose.yml
#   --admin-user NAME      Gitea admin username          (default: gitea-admin)
#   --admin-email EMAIL    Gitea admin e-mail
#   --admin-pass PASS      Gitea admin password          (prompted if omitted)
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
GITEA_DOMAIN=""
HTTP_PORT=3000
SSH_PORT=2222
IMAGE_TAG="latest"
USE_POSTGRES=0
USE_TLS=0
USE_HAPROXY=0
HAPROXY_IP="192.168.1.2"
SSL_CERT_DIR="/share/ssl/own.dedyn.io"
SHARED_NETWORK="nas-services"
REWRITE_COMPOSE=0
ADMIN_USER="gitea-admin"
ADMIN_EMAIL=""
ADMIN_PASS=""

# ── Parse arguments ───────────────────────────────────────────────────────────
while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run)         DRY_RUN=1;  shift ;;
        --verbose|-v)      VERBOSE=1;  shift ;;
        --postgres)        USE_POSTGRES=1; shift ;;
        --tls)             USE_TLS=1;  shift ;;
        --haproxy)
            USE_HAPROXY=1
            # optional IP argument
            case "${2:-}" in
                -*|'') ;; # next arg is a flag or empty
                *)  HAPROXY_IP="$2"; shift ;;
            esac
            shift ;;
        --http-port)       HTTP_PORT="$2";      shift 2 ;;
        --ssh-port)        SSH_PORT="$2";       shift 2 ;;
        --image-tag)       IMAGE_TAG="$2";      shift 2 ;;
        --ssl-dir)         SSL_CERT_DIR="$2";   shift 2 ;;
        --rewrite-compose) REWRITE_COMPOSE=1;   shift ;;
        --admin-user)      ADMIN_USER="$2";     shift 2 ;;
        --admin-email)     ADMIN_EMAIL="$2";    shift 2 ;;
        --admin-pass)      ADMIN_PASS="$2";     shift 2 ;;
        --help|-h)
            cat <<EOF
bootstrap-gitea.sh — Install Gitea via Docker on QNAP

Usage:
  $0 [OPTIONS] [DOMAIN]

Options:
  --dry-run              Show what would be done; make no changes
  --verbose, -v          Print debug output
  --http-port PORT       HTTP port (default: 3000)
  --ssh-port PORT        SSH port  (default: 2222)
  --image-tag TAG        Gitea image tag (default: latest)
  --postgres             Use shared PostgreSQL (run bootstrap-postgres.sh first)
  --tls                  Enable HTTPS — Gitea handles TLS itself
  --haproxy [IP]         TLS at HAProxy/pfSense (recommended). IP default: 192.168.1.2
  --ssl-dir PATH         Path to TLS certs (default: /share/ssl/own.dedyn.io)
  --rewrite-compose      Overwrite existing docker-compose.yml
  --admin-user NAME      Admin username (default: gitea-admin)
  --admin-email EMAIL    Admin e-mail
  --admin-pass PASS      Admin password (prompted if omitted)
  --help, -h             Show this help

Examples:
  $0 --dry-run
  $0 --postgres --haproxy gitea.own.dedyn.io
  $0 --postgres --haproxy 192.168.1.2 --admin-user myadmin gitea.own.dedyn.io
  $0 --postgres --tls gitea.own.dedyn.io
EOF
            exit 0
            ;;
        -*) printf "Unknown option: %s\n" "$1" >&2; exit 1 ;;
        *)
            [ -z "$GITEA_DOMAIN" ] && GITEA_DOMAIN="$1"
            shift ;;
    esac
done

# ── Source shared library ─────────────────────────────────────────────────────
[ -f "$LIB_DIR/docker-service.sh" ] || { printf "[ERROR] Cannot find %s/docker-service.sh\n" "$LIB_DIR" >&2; exit 1; }
. "$LIB_DIR/docker-service.sh"

# ── Validate flag combinations ────────────────────────────────────────────────
if [ "$USE_TLS" -eq 1 ] && [ "$USE_HAPROXY" -eq 1 ]; then
    log_error "--tls and --haproxy are mutually exclusive. Use --haproxy when pfSense/HAProxy terminates TLS."
fi

# ── Banner ────────────────────────────────────────────────────────────────────
printf "\n"
printf "${BLUE}╔══════════════════════════════════════════════════════╗${NC}\n"
printf "${BLUE}║  Gitea Bootstrap — QNAP Docker Install               ║${NC}\n"
printf "${BLUE}╚══════════════════════════════════════════════════════╝${NC}\n"
[ "$DRY_RUN" -eq 1 ]       && printf "${YELLOW}  *** DRY-RUN mode — no changes will be made ***${NC}\n"
[ "$REWRITE_COMPOSE" -eq 1 ] && printf "${YELLOW}  *** --rewrite-compose: docker-compose.yml will be overwritten ***${NC}\n"
[ "$USE_HAPROXY" -eq 1 ]   && printf "${YELLOW}  *** HAProxy mode: TLS terminated at %s ***${NC}\n" "$HAPROXY_IP"
printf "\n"

# ── Step 1: System info ───────────────────────────────────────────────────────
log_info "[1/7] Collecting system information..."
HOSTNAME_VAL=$(hostname 2>/dev/null || printf "qnap-nas")
OS_NAME="QNAP NAS"
[ -f /etc/os-release ] && OS_NAME=$(grep "^PRETTY_NAME" /etc/os-release 2>/dev/null | cut -d'=' -f2- | tr -d '"')
CPU_CORES=0; [ -f /proc/cpuinfo ] && CPU_CORES=$(grep -c "^processor" /proc/cpuinfo)
RAM_KB=0;    [ -f /proc/meminfo ] && RAM_KB=$(grep "MemTotal:" /proc/meminfo | awk '{print $2}')
RAM_GB=$((RAM_KB / 1024 / 1024))
log_success "Host : $HOSTNAME_VAL"
log_success "OS   : $OS_NAME"
log_success "CPU  : $CPU_CORES cores | RAM: ${RAM_GB} GB"

# ── Step 2: Requirements ──────────────────────────────────────────────────────
log_info "[2/7] Checking requirements..."
command -v docker >/dev/null 2>&1 || log_error "Docker not found. Install QNAP Container Station first."

COMPOSE_CMD=""
if docker compose version >/dev/null 2>&1; then
    COMPOSE_CMD="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
    COMPOSE_CMD="docker-compose"
else
    log_error "Neither 'docker compose' nor 'docker-compose' found."
fi
log_success "Compose: $COMPOSE_CMD"

if [ "$USE_POSTGRES" -eq 1 ]; then
    docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^nas-postgres$" || \
        log_error "nas-postgres not running. Run bootstrap-postgres.sh first."
    log_success "nas-postgres: running"
fi

if [ "$USE_TLS" -eq 1 ]; then
    CERT_FILE="$SSL_CERT_DIR/own.dedyn.io.fullchain"
    KEY_FILE="$SSL_CERT_DIR/own.dedyn.io.key"
    if [ "$DRY_RUN" -ne 1 ]; then
        if [ ! -f "$CERT_FILE" ] || [ ! -f "$KEY_FILE" ]; then
            log_error "TLS certs not found at $SSL_CERT_DIR
  Expected: own.dedyn.io.fullchain  and  own.dedyn.io.key
  Fix:      Run pfsense/sync-certs-to-nas.sh to push certs from pfSense ACME.
  Tip:      Use --haproxy instead of --tls to terminate TLS at pfSense/HAProxy."
        fi
        log_success "TLS certs found: $SSL_CERT_DIR"
    else
        log_dry_run "Would verify TLS certs at $SSL_CERT_DIR"
    fi
fi

# ── Step 3: Management IP + URLs ─────────────────────────────────────────────
log_info "[3/7] Detecting management IP..."
get_management_ip

[ -z "$GITEA_DOMAIN" ] && { GITEA_DOMAIN="$LOCAL_IP"; log_warn "No DOMAIN supplied; using IP: $GITEA_DOMAIN"; }

if [ "$USE_TLS" -eq 1 ]; then
    PROTOCOL="https"
    ROOT_URL="https://${GITEA_DOMAIN}/"
elif [ "$USE_HAPROXY" -eq 1 ]; then
    PROTOCOL="http"
    ROOT_URL="https://${GITEA_DOMAIN}/"
else
    PROTOCOL="http"
    ROOT_URL="http://${GITEA_DOMAIN}:${HTTP_PORT}/"
fi

# ── Step 4: Admin password ────────────────────────────────────────────────────
if [ -z "$ADMIN_PASS" ]; then
    printf "\n${YELLOW}[INPUT]${NC} Gitea admin password for '%s': " "$ADMIN_USER"
    stty -echo 2>/dev/null || true
    read -r ADMIN_PASS
    stty echo 2>/dev/null || true
    printf "\n"
fi
[ -z "$ADMIN_PASS" ] && log_error "Admin password must not be empty."
[ -z "$ADMIN_EMAIL" ] && ADMIN_EMAIL="${ADMIN_USER}@${GITEA_DOMAIN}"

# ── Step 5: Select persistent volume ─────────────────────────────────────────
log_info "[4/7] Selecting persistent volume..."

GITEA_BASE=""
if [ -d /share/docs/gitea ] && [ -f /share/docs/gitea/docker-compose.yml ]; then
    if [ "$REWRITE_COMPOSE" -eq 1 ]; then
        log_warn "Existing installation at /share/docs/gitea — --rewrite-compose: compose will be regenerated."
    else
        log_warn "Existing installation detected at /share/docs/gitea — reusing volume."
        log_warn "To regenerate docker-compose.yml with new options, add --rewrite-compose"
    fi
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
log_success "Gitea data: $GITEA_BASE"

# ── Step 6: Generate docker-compose.yml ──────────────────────────────────────
log_info "[5/7] Creating directories and configuration..."

if [ -f "$COMPOSE_FILE" ] && [ "$REWRITE_COMPOSE" -eq 0 ]; then
    log_warn "docker-compose.yml exists — skipping (use --rewrite-compose to overwrite)"
else
    confirm_action "Write $COMPOSE_FILE  [DB: $([ "$USE_POSTGRES" -eq 1 ] && echo PostgreSQL || echo SQLite3)  TLS: $([ "$USE_TLS" -eq 1 ] && echo direct || { [ "$USE_HAPROXY" -eq 1 ] && echo haproxy || echo no; })  image: gitea/gitea:${IMAGE_TAG}]" || { log_warn "Aborted."; exit 0; }

    execute_cmd "mkdir -p $DATA_DIR"   "mkdir -p \"$DATA_DIR\""
    execute_cmd "mkdir -p $CONFIG_DIR" "mkdir -p \"$CONFIG_DIR\""

    # Database block
    if [ "$USE_POSTGRES" -eq 1 ]; then
        PG_ENV_FILE="$SELECTED_VOLUME/postgres/.env"
        PG_SUPERUSER="nasuser"
        PG_SUPERPASS=""
        if [ -f "$PG_ENV_FILE" ]; then
            PG_SUPERUSER=$(grep "^POSTGRES_USER="     "$PG_ENV_FILE" | cut -d'=' -f2-)
            PG_SUPERPASS=$(grep "^POSTGRES_PASSWORD=" "$PG_ENV_FILE" | cut -d'=' -f2-)
        fi
        if [ -z "$PG_SUPERPASS" ]; then
            printf "\n${YELLOW}[INPUT]${NC} PostgreSQL superuser password for '%s': " "$PG_SUPERUSER"
            stty -echo 2>/dev/null || true
            read -r PG_SUPERPASS
            stty echo 2>/dev/null || true
            printf "\n"
        fi

        # Dedicated DB user 'gitea' with password = ADMIN_PASS (changeable)
        DB_USER="gitea"
        DB_PASS="$ADMIN_PASS"
        DB_NAME="gitea"

        # Create db user + database via superuser
        execute_cmd "Create PostgreSQL user '${DB_USER}'" \
            "docker exec nas-postgres psql -U ${PG_SUPERUSER} -tc \"SELECT 1 FROM pg_roles WHERE rolname='${DB_USER}'\" | grep -q 1 || docker exec nas-postgres psql -U ${PG_SUPERUSER} -c \"CREATE USER ${DB_USER} WITH PASSWORD '${DB_PASS}';\""
        execute_cmd "Create database '${DB_NAME}' owned by '${DB_USER}'" \
            "docker exec nas-postgres psql -U ${PG_SUPERUSER} -tc \"SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'\" | grep -q 1 || docker exec nas-postgres psql -U ${PG_SUPERUSER} -c \"CREATE DATABASE ${DB_NAME} OWNER ${DB_USER} ENCODING 'UTF8' LC_COLLATE 'C' LC_CTYPE 'C' TEMPLATE template0;\""
        # PG15+: GRANT SCHEMA public -- ohne das schlaegt CREATE TABLE fehl
        execute_cmd "Grant schema public to '${DB_USER}'" \
            "docker exec nas-postgres psql -U ${PG_SUPERUSER} -c \"GRANT ALL ON SCHEMA public TO ${DB_USER};\" ${DB_NAME}"

        DB_ENV="      - GITEA__database__DB_TYPE=postgres
      - GITEA__database__HOST=nas-postgres:5432
      - GITEA__database__NAME=${DB_NAME}
      - GITEA__database__USER=${DB_USER}
      - GITEA__database__PASSWD=${DB_PASS}
      - GITEA__database__SSL_MODE=disable"
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

    # TLS / HAProxy block
    if [ "$USE_TLS" -eq 1 ]; then
        PROTO_ENV="      - GITEA__server__PROTOCOL=https
      - GITEA__server__CERT_FILE=/ssl/own.dedyn.io.fullchain
      - GITEA__server__KEY_FILE=/ssl/own.dedyn.io.key"
        TLS_VOLUME="      - ${SSL_CERT_DIR}:/ssl:ro"
        PORT_BIND="\"${HTTP_PORT}:3000\""
        PROXY_ENV=""
    elif [ "$USE_HAPROXY" -eq 1 ]; then
        NAS_IP=$(ip route get 1.1.1.1 2>/dev/null | awk '/src/{print $NF; exit}' || \
                 hostname -I 2>/dev/null | awk '{print $1}' || echo "0.0.0.0")
        log_info "HAProxy mode: bind auf NAS-IP ${NAS_IP}:${HTTP_PORT}"
        PROTO_ENV="      - GITEA__server__PROTOCOL=http"
        TLS_VOLUME=""
        PORT_BIND="\"${NAS_IP}:${HTTP_PORT}:3000\""
        PROXY_ENV="      - GITEA__security__REVERSE_PROXY_LIMIT=1
      - GITEA__security__REVERSE_PROXY_TRUSTED_PROXIES=${HAPROXY_IP}/32
      - GITEA__security__COOKIE_SECURE=true"
    else
        PROTO_ENV="      - GITEA__server__PROTOCOL=http"
        TLS_VOLUME=""
        PORT_BIND="\"${HTTP_PORT}:3000\""
        PROXY_ENV=""
    fi

    COMPOSE_CONTENT="# docker-compose.yml — Gitea on QNAP
# Generated by bootstrap-gitea.sh
# Regenerate: sh qnap/gitea/bootstrap-gitea.sh --rewrite-compose [OPTIONS] DOMAIN
# Image     : gitea/gitea:${IMAGE_TAG}
# Database  : $([ "$USE_POSTGRES" -eq 1 ] && echo "PostgreSQL (nas-postgres) user=gitea db=gitea" || echo "SQLite3")
# TLS mode  : $([ "$USE_TLS" -eq 1 ] && echo "direct (Gitea handles TLS)" || { [ "$USE_HAPROXY" -eq 1 ] && echo "haproxy (TLS at ${HAPROXY_IP})" || echo "none (HTTP only)"; })

services:
  gitea:
    image: gitea/gitea:${IMAGE_TAG}
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
${PROTO_ENV}
${PROXY_ENV}
      # Database
${DB_ENV}
      # Security — setup wizard disabled; admin user created via CLI below
      - GITEA__security__INSTALL_LOCK=true
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
      - ${PORT_BIND}
      - \"${SSH_PORT}:22\"
${NETWORK_SECTION}"

    write_file "$COMPOSE_FILE" "$COMPOSE_CONTENT"
    log_success "docker-compose.yml written: $COMPOSE_FILE"
fi

# ── Step 7: Pull + start + create admin user ──────────────────────────────────
log_info "[6/7] Pulling image and starting container..."

confirm_action "Pull gitea/gitea:${IMAGE_TAG} and start container" || { log_warn "Skipped."; exit 0; }

execute_cmd "docker pull gitea/gitea:${IMAGE_TAG}" \
    "docker pull gitea/gitea:${IMAGE_TAG}"

execute_cmd "Start Gitea container" \
    "cd \"$GITEA_BASE\" && $COMPOSE_CMD up -d"

# Wait for Gitea to be ready before creating admin user
log_info "[7/7] Waiting for Gitea to start..."
if [ "$DRY_RUN" -ne 1 ]; then
    _i=0
    while [ "$_i" -lt 30 ]; do
        if docker exec gitea /usr/local/bin/gitea --version >/dev/null 2>&1; then
            break
        fi
        sleep 2
        _i=$((_i + 1))
    done
    if [ "$_i" -ge 30 ]; then
        log_warn "Gitea did not become ready in 60s — skipping admin user creation."
        log_warn "Create manually: docker exec -u git gitea gitea admin user create --admin --username \"${ADMIN_USER}\" --email \"${ADMIN_EMAIL}\" --password \"<pass>\""
    else
        log_success "Gitea is ready."
        if docker exec -u git gitea \
            gitea admin user create \
                --admin \
                --username "$ADMIN_USER" \
                --email    "$ADMIN_EMAIL" \
                --password "$ADMIN_PASS" \
                --must-change-password=false 2>&1 | tee /tmp/gitea-admin-create.log | grep -q "successfully"; then
            log_success "Admin user '${ADMIN_USER}' created."
        else
            _out=$(cat /tmp/gitea-admin-create.log)
            if printf '%s' "$_out" | grep -qi "already exist"; then
                log_warn "Admin user '${ADMIN_USER}' already exists — skipping."
            else
                log_warn "Could not create admin user automatically."
                log_warn "Run manually: docker exec -u git gitea gitea admin user create --admin --username \"${ADMIN_USER}\" --email \"${ADMIN_EMAIL}\" --password \"<pass>\" --must-change-password=false"
            fi
        fi
    fi
else
    log_dry_run "Would create admin user '${ADMIN_USER}' via: docker exec -u git gitea gitea admin user create ..."
fi

add_autorun_hook "$GITEA_BASE" "# Gitea Docker service"

if [ -d /opt/bin ] && [ ! -e /opt/bin/bootstrap-gitea.sh ]; then
    execute_cmd "Symlink to /opt/bin/bootstrap-gitea.sh" \
        "ln -sf \"$0\" /opt/bin/bootstrap-gitea.sh"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
printf "\n"
printf "${GREEN}╔══════════════════════════════════════════════════════╗${NC}\n"
printf "${GREEN}║  Gitea Installation Complete                         ║${NC}\n"
printf "${GREEN}╚══════════════════════════════════════════════════════╝${NC}\n"
printf "\n"
printf "  ${BLUE}Web UI${NC}       : %s\n"                  "$ROOT_URL"
printf "  ${BLUE}SSH clone${NC}    : ssh://git@%s:%s\n"    "$GITEA_DOMAIN" "$SSH_PORT"
printf "  ${BLUE}Admin user${NC}   : %s  (%s)\n"           "$ADMIN_USER" "$ADMIN_EMAIL"
printf "  ${BLUE}Image${NC}        : gitea/gitea:%s\n"     "$IMAGE_TAG"
[ "$USE_POSTGRES" -eq 1 ] && printf "  ${BLUE}Database${NC}     : PostgreSQL — user=gitea db=gitea\n"
[ "$USE_TLS" -eq 1 ]      && printf "  ${BLUE}TLS${NC}          : direct (%s)\n" "$SSL_CERT_DIR"
[ "$USE_HAPROXY" -eq 1 ]  && printf "  ${BLUE}TLS${NC}          : via HAProxy at %s (port binds to 127.0.0.1)\n" "$HAPROXY_IP"
printf "  ${BLUE}Data path${NC}    : %s\n"                  "$GITEA_BASE"
printf "\n"
if grep -qF "$GITEA_BASE" /etc/config/autorun.sh 2>/dev/null; then
    printf "  ${GREEN}autorun.sh${NC}: hook present.\n"
else
    printf "  ${YELLOW}autorun.sh${NC}: hook NOT found — add manually:\n"
    printf "    cd \"%s\" && %s up -d\n" "$GITEA_BASE" "$COMPOSE_CMD"
fi
printf "\n"
