#!/bin/sh
################################################################################
# qnap/forgejo/bootstrap-forgejo.sh
# Bootstrap Forgejo as a Docker container on QNAP NAS.
#
# Forgejo is a community-governed Free Software fork of Gitea.
# Drop-in alternative to qnap/gitea/bootstrap-gitea.sh.
#
# Usage:
#   sh qnap/forgejo/bootstrap-forgejo.sh [OPTIONS] [DOMAIN]
#
# Options:
#   --dry-run              Show what would be done; make no changes
#   --verbose, -v          Print debug output
#   --http-port PORT       HTTP port for Forgejo          (default: 3000)
#   --ssh-port  PORT       SSH port for Forgejo           (default: 2222)
#   --image-tag TAG        Forgejo image tag              (default: 10)
#   --postgres             Use shared PostgreSQL container (nas-postgres)
#   --tls                  Enable HTTPS — Forgejo handles TLS itself.
#                          Do NOT combine with --haproxy.
#   --haproxy [IP]         TLS terminated at HAProxy/pfSense.
#                          Forgejo listens on http, ROOT_URL uses https://.
#                          Binds port to 127.0.0.1 only.
#                          IP = trusted proxy IP (default: 192.168.1.2)
#   --ssl-dir PATH         Path to TLS certs             (default: /share/ssl/own.dedyn.io)
#   --rewrite-compose      Overwrite existing docker-compose.yml
#   --admin-user NAME      Forgejo admin username         (default: forgejo-admin)
#   --admin-email EMAIL    Forgejo admin e-mail
#   --admin-pass PASS      Forgejo admin password         (prompted if omitted)
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
FORGEJO_DOMAIN=""
HTTP_PORT=3000
SSH_PORT=2222
IMAGE_TAG="10"
USE_POSTGRES=0
USE_TLS=0
USE_HAPROXY=0
HAPROXY_IP="192.168.1.2"
SSL_CERT_DIR="/share/ssl/own.dedyn.io"
SHARED_NETWORK="nas-services"
REWRITE_COMPOSE=0
ADMIN_USER="forgejo-admin"
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
            case "${2:-}" in
                -*|'') ;;
                *) HAPROXY_IP="$2"; shift ;;
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
bootstrap-forgejo.sh — Install Forgejo via Docker on QNAP

Usage:
  $0 [OPTIONS] [DOMAIN]

Options:
  --dry-run              Show what would be done; make no changes
  --verbose, -v          Print debug output
  --http-port PORT       HTTP port (default: 3000)
  --ssh-port PORT        SSH port  (default: 2222)
  --image-tag TAG        Forgejo image tag on Codeberg (default: 10)
  --postgres             Use shared PostgreSQL (run bootstrap-postgres.sh first)
  --tls                  Enable HTTPS — Forgejo handles TLS itself
  --haproxy [IP]         TLS at HAProxy/pfSense (recommended). IP default: 192.168.1.2
  --ssl-dir PATH         Path to TLS certs (default: /share/ssl/own.dedyn.io)
  --rewrite-compose      Overwrite existing docker-compose.yml
  --admin-user NAME      Admin username (default: forgejo-admin)
  --admin-email EMAIL    Admin e-mail
  --admin-pass PASS      Admin password (prompted if omitted)
  --help, -h             Show this help

Examples:
  $0 --dry-run
  $0 --postgres --haproxy forgejo.own.dedyn.io
  $0 --postgres --haproxy 192.168.1.2 --admin-user myadmin forgejo.own.dedyn.io
  $0 --postgres --tls forgejo.own.dedyn.io
EOF
            exit 0
            ;;
        -*) printf "Unknown option: %s\n" "$1" >&2; exit 1 ;;
        *)
            [ -z "$FORGEJO_DOMAIN" ] && FORGEJO_DOMAIN="$1"
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
printf "${BLUE}║  Forgejo Bootstrap — QNAP Docker Install             ║${NC}\n"
printf "${BLUE}╚══════════════════════════════════════════════════════╝${NC}\n"
[ "$DRY_RUN" -eq 1 ]        && printf "${YELLOW}  *** DRY-RUN mode — no changes will be made ***${NC}\n"
[ "$REWRITE_COMPOSE" -eq 1 ] && printf "${YELLOW}  *** --rewrite-compose: docker-compose.yml will be overwritten ***${NC}\n"
[ "$USE_HAPROXY" -eq 1 ]    && printf "${YELLOW}  *** HAProxy mode: TLS terminated at %s ***${NC}\n" "$HAPROXY_IP"
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

[ -z "$FORGEJO_DOMAIN" ] && { FORGEJO_DOMAIN="$LOCAL_IP"; log_warn "No DOMAIN supplied; using IP: $FORGEJO_DOMAIN"; }

if [ "$USE_TLS" -eq 1 ]; then
    PROTOCOL="https"
    ROOT_URL="https://${FORGEJO_DOMAIN}/"
elif [ "$USE_HAPROXY" -eq 1 ]; then
    PROTOCOL="http"
    ROOT_URL="https://${FORGEJO_DOMAIN}/"
else
    PROTOCOL="http"
    ROOT_URL="http://${FORGEJO_DOMAIN}:${HTTP_PORT}/"
fi

# ── Step 4: Admin password ────────────────────────────────────────────────────
if [ -z "$ADMIN_PASS" ]; then
    printf "\n${YELLOW}[INPUT]${NC} Forgejo admin password for '%s': " "$ADMIN_USER"
    stty -echo 2>/dev/null || true
    read -r ADMIN_PASS
    stty echo 2>/dev/null || true
    printf "\n"
fi
[ -z "$ADMIN_PASS" ] && log_error "Admin password must not be empty."
[ -z "$ADMIN_EMAIL" ] && ADMIN_EMAIL="${ADMIN_USER}@${FORGEJO_DOMAIN}"

# ── Step 5: Select persistent volume ─────────────────────────────────────────
log_info "[4/7] Selecting persistent volume..."

FORGEJO_BASE=""
if [ -d /share/docs/forgejo ] && [ -f /share/docs/forgejo/docker-compose.yml ]; then
    if [ "$REWRITE_COMPOSE" -eq 1 ]; then
        log_warn "Existing installation at /share/docs/forgejo — --rewrite-compose: compose will be regenerated."
    else
        log_warn "Existing installation detected at /share/docs/forgejo — reusing volume."
        log_warn "To regenerate docker-compose.yml with new options, add --rewrite-compose"
    fi
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
log_success "Forgejo data: $FORGEJO_BASE"

# ── Step 6: Generate docker-compose.yml ──────────────────────────────────────
log_info "[5/7] Creating directories and configuration..."

if [ -f "$COMPOSE_FILE" ] && [ "$REWRITE_COMPOSE" -eq 0 ]; then
    log_warn "docker-compose.yml exists — skipping (use --rewrite-compose to overwrite)"
else
    confirm_action "Write $COMPOSE_FILE  [DB: $([ "$USE_POSTGRES" -eq 1 ] && echo PostgreSQL || echo SQLite3)  TLS: $([ "$USE_TLS" -eq 1 ] && echo direct || { [ "$USE_HAPROXY" -eq 1 ] && echo haproxy || echo no; })  image: codeberg.org/forgejo/forgejo:${IMAGE_TAG}]" || { log_warn "Aborted."; exit 0; }

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

        # Dedicated DB user 'forgejo'
        DB_USER="forgejo"
        DB_PASS="$ADMIN_PASS"
        DB_NAME="forgejo"

        execute_cmd "Create PostgreSQL user '${DB_USER}'" \
            "docker exec nas-postgres psql -U ${PG_SUPERUSER} -tc \"SELECT 1 FROM pg_roles WHERE rolname='${DB_USER}'\" | grep -q 1 || docker exec nas-postgres psql -U ${PG_SUPERUSER} -c \"CREATE USER ${DB_USER} WITH PASSWORD '${DB_PASS}';\""
        execute_cmd "Create database '${DB_NAME}' owned by '${DB_USER}'" \
            "docker exec nas-postgres psql -U ${PG_SUPERUSER} -tc \"SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'\" | grep -q 1 || docker exec nas-postgres psql -U ${PG_SUPERUSER} -c \"CREATE DATABASE ${DB_NAME} OWNER ${DB_USER} ENCODING 'UTF8' LC_COLLATE 'C' LC_CTYPE 'C' TEMPLATE template0;\""

        DB_ENV="      - FORGEJO__database__DB_TYPE=postgres
      - FORGEJO__database__HOST=nas-postgres:5432
      - FORGEJO__database__NAME=${DB_NAME}
      - FORGEJO__database__USER=${DB_USER}
      - FORGEJO__database__PASSWD=${DB_PASS}
      - FORGEJO__database__SSL_MODE=disable"
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

    # TLS / HAProxy block
    if [ "$USE_TLS" -eq 1 ]; then
        PROTO_ENV="      - FORGEJO__server__PROTOCOL=https
      - FORGEJO__server__CERT_FILE=/ssl/own.dedyn.io.fullchain
      - FORGEJO__server__KEY_FILE=/ssl/own.dedyn.io.key"
        TLS_VOLUME="      - ${SSL_CERT_DIR}:/ssl:ro"
        PORT_BIND="\"${HTTP_PORT}:3000\""
        PROXY_ENV=""
    elif [ "$USE_HAPROXY" -eq 1 ]; then
        PROTO_ENV="      - FORGEJO__server__PROTOCOL=http"
        TLS_VOLUME=""
        PORT_BIND="\"127.0.0.1:${HTTP_PORT}:3000\""
        PROXY_ENV="      - FORGEJO__security__REVERSE_PROXY_LIMIT=1
      - FORGEJO__security__REVERSE_PROXY_TRUSTED_PROXIES=${HAPROXY_IP}/32
      - FORGEJO__security__COOKIE_SECURE=true"
    else
        PROTO_ENV="      - FORGEJO__server__PROTOCOL=http"
        TLS_VOLUME=""
        PORT_BIND="\"${HTTP_PORT}:3000\""
        PROXY_ENV=""
    fi

    COMPOSE_CONTENT="# docker-compose.yml — Forgejo on QNAP
# Generated by bootstrap-forgejo.sh
# Regenerate: sh qnap/forgejo/bootstrap-forgejo.sh --rewrite-compose [OPTIONS] DOMAIN
# Image     : codeberg.org/forgejo/forgejo:${IMAGE_TAG}
# Database  : $([ "$USE_POSTGRES" -eq 1 ] && echo "PostgreSQL (nas-postgres) user=forgejo db=forgejo" || echo "SQLite3")
# TLS mode  : $([ "$USE_TLS" -eq 1 ] && echo "direct (Forgejo handles TLS)" || { [ "$USE_HAPROXY" -eq 1 ] && echo "haproxy (TLS at ${HAPROXY_IP})" || echo "none (HTTP only)"; })

services:
  forgejo:
    image: codeberg.org/forgejo/forgejo:${IMAGE_TAG}
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
${PROTO_ENV}
${PROXY_ENV}
      # Database
${DB_ENV}
      # Security — setup wizard disabled; admin user created via CLI below
      - FORGEJO__security__INSTALL_LOCK=true
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
      - ${PORT_BIND}
      - \"${SSH_PORT}:22\"
${NETWORK_SECTION}"

    write_file "$COMPOSE_FILE" "$COMPOSE_CONTENT"
    log_success "docker-compose.yml written: $COMPOSE_FILE"
fi

# ── Step 7: Pull + start + create admin user ──────────────────────────────────
log_info "[6/7] Pulling image and starting container..."

confirm_action "Pull codeberg.org/forgejo/forgejo:${IMAGE_TAG} and start container" || { log_warn "Skipped."; exit 0; }

execute_cmd "docker pull codeberg.org/forgejo/forgejo:${IMAGE_TAG}" \
    "docker pull codeberg.org/forgejo/forgejo:${IMAGE_TAG}"

execute_cmd "Start Forgejo container" \
    "cd \"$FORGEJO_BASE\" && $COMPOSE_CMD up -d"

# Wait for Forgejo to be ready
log_info "[7/7] Waiting for Forgejo to start..."
if [ "$DRY_RUN" -ne 1 ]; then
    _i=0
    while [ "$_i" -lt 30 ]; do
        if docker exec forgejo /usr/local/bin/forgejo --version >/dev/null 2>&1; then
            break
        fi
        sleep 2
        _i=$((_i + 1))
    done
    if [ "$_i" -ge 30 ]; then
        log_warn "Forgejo did not become ready in 60s — skipping admin user creation."
        log_warn "Create manually: docker exec -u git forgejo forgejo admin user create --admin --username \"${ADMIN_USER}\" --email \"${ADMIN_EMAIL}\" --password \"<pass>\""
    else
        log_success "Forgejo is ready."
        if docker exec -u git forgejo \
            forgejo admin user create \
                --admin \
                --username "$ADMIN_USER" \
                --email    "$ADMIN_EMAIL" \
                --password "$ADMIN_PASS" \
                --must-change-password=false 2>&1 | tee /tmp/forgejo-admin-create.log | grep -q "successfully"; then
            log_success "Admin user '${ADMIN_USER}' created."
        else
            _out=$(cat /tmp/forgejo-admin-create.log)
            if printf '%s' "$_out" | grep -qi "already exist"; then
                log_warn "Admin user '${ADMIN_USER}' already exists — skipping."
            else
                log_warn "Could not create admin user automatically."
                log_warn "Run manually: docker exec -u git forgejo forgejo admin user create --admin --username \"${ADMIN_USER}\" --email \"${ADMIN_EMAIL}\" --password \"<pass>\" --must-change-password=false"
            fi
        fi
    fi
else
    log_dry_run "Would create admin user '${ADMIN_USER}' via: docker exec -u git forgejo forgejo admin user create ..."
fi

add_autorun_hook "$FORGEJO_BASE" "# Forgejo Docker service"

if [ -d /opt/bin ] && [ ! -e /opt/bin/bootstrap-forgejo.sh ]; then
    execute_cmd "Symlink to /opt/bin/bootstrap-forgejo.sh" \
        "ln -sf \"$0\" /opt/bin/bootstrap-forgejo.sh"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
printf "\n"
printf "${GREEN}╔══════════════════════════════════════════════════════╗${NC}\n"
printf "${GREEN}║  Forgejo Installation Complete                       ║${NC}\n"
printf "${GREEN}╚══════════════════════════════════════════════════════╝${NC}\n"
printf "\n"
printf "  ${BLUE}Web UI${NC}       : %s\n"                  "$ROOT_URL"
printf "  ${BLUE}SSH clone${NC}    : ssh://git@%s:%s\n"    "$FORGEJO_DOMAIN" "$SSH_PORT"
printf "  ${BLUE}Admin user${NC}   : %s  (%s)\n"           "$ADMIN_USER" "$ADMIN_EMAIL"
printf "  ${BLUE}Image${NC}        : codeberg.org/forgejo/forgejo:%s\n" "$IMAGE_TAG"
[ "$USE_POSTGRES" -eq 1 ] && printf "  ${BLUE}Database${NC}     : PostgreSQL — user=forgejo db=forgejo\n"
[ "$USE_TLS" -eq 1 ]      && printf "  ${BLUE}TLS${NC}          : direct (%s)\n" "$SSL_CERT_DIR"
[ "$USE_HAPROXY" -eq 1 ]  && printf "  ${BLUE}TLS${NC}          : via HAProxy at %s (port binds to 127.0.0.1)\n" "$HAPROXY_IP"
printf "  ${BLUE}Data path${NC}    : %s\n"                  "$FORGEJO_BASE"
printf "\n"
if grep -qF "$FORGEJO_BASE" /etc/config/autorun.sh 2>/dev/null; then
    printf "  ${GREEN}autorun.sh${NC}: hook present.\n"
else
    printf "  ${YELLOW}autorun.sh${NC}: hook NOT found — add manually:\n"
    printf "    cd \"%s\" && %s up -d\n" "$FORGEJO_BASE" "$COMPOSE_CMD"
fi
printf "\n"
