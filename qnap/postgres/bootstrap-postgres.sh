#!/bin/sh
################################################################################
# qnap/postgres/bootstrap-postgres.sh
# Bootstrap a shared PostgreSQL container on QNAP NAS.
#
# Usage:
#   sh qnap/postgres/bootstrap-postgres.sh [--dry-run] [--verbose] [POSTGRES_PASS]
#
# Creates a standalone PostgreSQL stack that other services (Gitea, Paperless)
# connect to via the shared Docker network "nas-services".
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
POSTGRES_PASS=""
POSTGRES_PORT=5432
POSTGRES_USER="nasuser"
SHARED_NETWORK="nas-services"

# ── Parse arguments ─────────────────────────────────────────────────────────────────
while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run)      DRY_RUN=1;  shift ;;
        --verbose|-v)   VERBOSE=1;  shift ;;
        --port)         POSTGRES_PORT="$2"; shift 2 ;;
        --user)         POSTGRES_USER="$2"; shift 2 ;;
        --help|-h)
            cat <<EOF
bootstrap-postgres.sh — Install shared PostgreSQL via Docker on QNAP

Usage:
  $0 [OPTIONS] [POSTGRES_PASS]

Options:
  --dry-run          Show what would be done; make no changes
  --verbose, -v      Print debug output
  --port PORT        Host port for PostgreSQL (default: 5432)
  --user USER        PostgreSQL superuser name (default: nasuser)
  --help, -h         Show this help

Positional:
  POSTGRES_PASS      Superuser password (prompted if omitted)

Network:
  Creates shared Docker network "$SHARED_NETWORK".
  Other services reference it as an external network in their compose files.
EOF
            exit 0
            ;;
        -*)
            printf "Unknown option: %s\n" "$1" >&2; exit 1 ;;
        *)
            [ -z "$POSTGRES_PASS" ] && POSTGRES_PASS="$1"
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
printf "${BLUE}║  PostgreSQL Bootstrap — QNAP Docker Install          ║${NC}\n"
printf "${BLUE}╚══════════════════════════════════════════════════════╝${NC}\n"
[ "$DRY_RUN" -eq 1 ] && \
    printf "${YELLOW}  *** DRY-RUN mode — no changes will be made ***${NC}\n"
printf "\n"

# ── Step 1: System info ───────────────────────────────────────────────────────────────────
log_info "[1/5] Collecting system information..."
HOSTNAME_VAL=$(hostname 2>/dev/null || printf "qnap-nas")
OS_NAME="QNAP NAS"
[ -f /etc/os-release ] && \
    OS_NAME=$(grep "^PRETTY_NAME" /etc/os-release 2>/dev/null \
              | cut -d'=' -f2- | tr -d '"')
log_success "Host : $HOSTNAME_VAL"
log_success "OS   : $OS_NAME"

# ── Step 2: Requirements ────────────────────────────────────────────────────────────────────
log_info "[2/5] Checking requirements..."
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

# ── Step 3: Password ─────────────────────────────────────────────────────────────────────────────
if [ -z "$POSTGRES_PASS" ]; then
    printf "\n${YELLOW}[INPUT]${NC} PostgreSQL superuser password: "
    stty -echo 2>/dev/null || true
    read -r POSTGRES_PASS
    stty echo 2>/dev/null || true
    printf "\n"
fi
[ -z "$POSTGRES_PASS" ] && log_error "PostgreSQL password must not be empty."

# ── Step 4: Select persistent volume ─────────────────────────────────────────────────────
log_info "[3/5] Selecting persistent volume..."
list_available_volumes
select_volume   # sets SELECTED_VOLUME

PG_BASE="$SELECTED_VOLUME/postgres"
PG_DATA="$PG_BASE/data"
PG_COMPOSE="$PG_BASE/docker-compose.yml"
PG_ENV="$PG_BASE/.env"

log_success "PostgreSQL data will be stored at: $PG_BASE"
log_debug   "  data: $PG_DATA"

# ── Step 5: Create dirs + .env + docker-compose.yml + shared network ───────────────
log_info "[4/5] Creating PostgreSQL stack..."

confirm_action "Create $PG_BASE and docker-compose.yml" || {
    log_warn "Installation aborted."
    exit 0
}

execute_cmd "mkdir -p $PG_DATA" "mkdir -p \"$PG_DATA\""

ENV_CONTENT="POSTGRES_USER=${POSTGRES_USER}
POSTGRES_PASSWORD=${POSTGRES_PASS}
POSTGRES_PORT=${POSTGRES_PORT}"

write_file "$PG_ENV" "$ENV_CONTENT"
if [ "$DRY_RUN" -ne 1 ]; then
    chmod 600 "$PG_ENV"
fi
log_success ".env written: $PG_ENV (mode 600)"

COMPOSE_CONTENT="# PostgreSQL shared stack — managed by bootstrap-postgres.sh
# Connect other services via external network: ${SHARED_NETWORK}
# Credentials are in .env (not committed to git)

services:
  postgres:
    image: postgres:16-alpine
    container_name: nas-postgres
    restart: unless-stopped
    env_file: .env
    environment:
      - POSTGRES_INITDB_ARGS=--encoding=UTF8 --lc-collate=C --lc-ctype=C
    volumes:
      - ${PG_DATA}:/var/lib/postgresql/data
      - /etc/timezone:/etc/timezone:ro
      - /etc/localtime:/etc/localtime:ro
    ports:
      - \"127.0.0.1:${POSTGRES_PORT}:5432\"
    networks:
      - ${SHARED_NETWORK}
    healthcheck:
      test: [\"CMD-SHELL\", \"pg_isready -U \${POSTGRES_USER}\"]
      interval: 10s
      timeout: 5s
      retries: 5

networks:
  ${SHARED_NETWORK}:
    name: ${SHARED_NETWORK}
    driver: bridge"

write_file "$PG_COMPOSE" "$COMPOSE_CONTENT"
log_success "docker-compose.yml written: $PG_COMPOSE"

# ── Step 5: Pull + start + autorun ────────────────────────────────────────────────────────────
log_info "[5/5] Pulling PostgreSQL image and starting container..."

confirm_action "Pull postgres:16-alpine and start container" || {
    log_warn "Skipped. Run manually: cd $PG_BASE && $COMPOSE_CMD up -d"
    exit 0
}

execute_cmd "docker pull postgres:16-alpine" \
    "docker pull postgres:16-alpine"

execute_cmd "Start PostgreSQL container" \
    "cd \"$PG_BASE\" && $COMPOSE_CMD up -d"

add_autorun_hook "$PG_BASE" "# PostgreSQL shared Docker service"

# ── Post-install summary ───────────────────────────────────────────────────────────────────
printf "\n"
printf "${GREEN}╔══════════════════════════════════════════════════════╗${NC}\n"
printf "${GREEN}║  PostgreSQL Installation Complete                    ║${NC}\n"
printf "${GREEN}╚══════════════════════════════════════════════════════╝${NC}\n"
printf "\n"
printf "  ${BLUE}Container${NC}    : nas-postgres\n"
printf "  ${BLUE}Network${NC}      : %s\n"      "$SHARED_NETWORK"
printf "  ${BLUE}Port${NC}         : 127.0.0.1:%s (localhost only)\n" "$POSTGRES_PORT"
printf "  ${BLUE}User${NC}         : %s\n"      "$POSTGRES_USER"
printf "  ${BLUE}Data path${NC}    : %s\n"      "$PG_DATA"
printf "  ${BLUE}Credentials${NC}  : %s\n"      "$PG_ENV"
printf "  ${BLUE}Compose file${NC} : %s\n"      "$PG_COMPOSE"
printf "\n"
printf "  ${YELLOW}Next steps:${NC}\n"
printf "    - Run bootstrap-gitea.sh --postgres to connect Gitea\n"
printf "    - Databases for each service are created automatically on first start\n"
printf "\n"
if grep -qF "$PG_BASE" /etc/config/autorun.sh 2>/dev/null; then
    printf "  ${GREEN}autorun.sh${NC}: hook present — PostgreSQL starts after every reboot.\n"
else
    printf "  ${YELLOW}autorun.sh${NC}: hook NOT found — add manually:\n"
    printf "    cd \"%s\" && %s up -d\n" "$PG_BASE" "$COMPOSE_CMD"
fi
printf "\n"
