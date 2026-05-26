#!/bin/sh
################################################################################
# qnap/gitea/bootstrap-gitea.sh
# Bootstrap Gitea as a Docker container on QNAP NAS.
#
# Usage:
#   sh qnap/gitea/bootstrap-gitea.sh [--dry-run] [--verbose] [DOMAIN] [ADMIN_PASS]
#   sh qnap/gitea/bootstrap-gitea.sh --help
#
# Compatible with BusyBox ash (no declare, no [[, no bash arrays).
# Follows bootstrap-foundation conventions.
################################################################################

set -e

# ── Locate repo root (script is at qnap/gitea/bootstrap-gitea.sh) ────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LIB_DIR="$REPO_ROOT/qnap/lib"

# ── Defaults ──────────────────────────────────────────────────────────────────
DRY_RUN=0
VERBOSE=0
ALWAYS_CONFIRM=0
GITEA_DOMAIN=""
GITEA_ADMIN_PASS=""
HTTP_PORT=3000
SSH_PORT=2222

# ── Parse arguments ───────────────────────────────────────────────────────────
while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        --verbose|-v)
            VERBOSE=1
            shift
            ;;
        --http-port)
            HTTP_PORT="$2"
            shift 2
            ;;
        --ssh-port)
            SSH_PORT="$2"
            shift 2
            ;;
        --help|-h)
            cat <<EOF
bootstrap-gitea.sh — Install Gitea via Docker on QNAP

Usage:
  $0 [OPTIONS] [DOMAIN] [ADMIN_PASS]

Options:
  --dry-run          Show what would be done; make no changes
  --verbose, -v      Print debug output
  --http-port PORT   HTTP port for Gitea  (default: 3000)
  --ssh-port  PORT   SSH port for Gitea   (default: 2222)
  --help, -h         Show this help

Positional:
  DOMAIN             Public domain or NAS IP (e.g. git.home.local)
  ADMIN_PASS         Gitea admin password    (prompted if omitted)

Examples:
  $0 --dry-run
  $0 --dry-run git.home.local secret123
  $0 git.home.local
  $0 --http-port 3080 --ssh-port 2223 git.home.local
EOF
            exit 0
            ;;
        -*)
            printf "Unknown option: %s\n" "$1" >&2
            exit 1
            ;;
        *)
            if [ -z "$GITEA_DOMAIN" ]; then
                GITEA_DOMAIN="$1"
            elif [ -z "$GITEA_ADMIN_PASS" ]; then
                GITEA_ADMIN_PASS="$1"
            fi
            shift
            ;;
    esac
done

# ── Source shared library ─────────────────────────────────────────────────────
if [ -f "$LIB_DIR/docker-service.sh" ]; then
    . "$LIB_DIR/docker-service.sh"
else
    printf "[ERROR] Cannot find %s/docker-service.sh\n" "$LIB_DIR" >&2
    exit 1
fi

# ── Banner ────────────────────────────────────────────────────────────────────
printf "\n"
printf "${BLUE}╔══════════════════════════════════════════════════════╗${NC}\n"
printf "${BLUE}║  Gitea Bootstrap — QNAP Docker Install               ║${NC}\n"
printf "${BLUE}╚══════════════════════════════════════════════════════╝${NC}\n"
[ "$DRY_RUN" -eq 1 ] && \
    printf "${YELLOW}  *** DRY-RUN mode — no changes will be made ***${NC}\n"
printf "\n"

# ── Step 1: System info ───────────────────────────────────────────────────────
log_info "[1/6] Collecting system information..."

HOSTNAME_VAL=$(hostname 2>/dev/null || printf "qnap-nas")
OS_NAME="QNAP NAS"
if [ -f /etc/os-release ]; then
    OS_NAME=$(grep "^PRETTY_NAME" /etc/os-release 2>/dev/null \
              | cut -d'=' -f2- | tr -d '"' || printf "QNAP NAS")
fi
CPU_CORES=0
if [ -f /proc/cpuinfo ]; then
    CPU_CORES=$(grep -c "^processor" /proc/cpuinfo || printf "0")
fi
RAM_KB=0
if [ -f /proc/meminfo ]; then
    RAM_KB=$(grep "MemTotal:" /proc/meminfo | awk '{print $2}')
fi
RAM_GB=$((RAM_KB / 1024 / 1024))

log_success "Host : $HOSTNAME_VAL"
log_success "OS   : $OS_NAME"
log_success "CPU  : $CPU_CORES cores | RAM: ${RAM_GB} GB"

# ── Step 2: Check requirements ────────────────────────────────────────────────
log_info "[2/6] Checking requirements..."

command -v docker >/dev/null 2>&1 || \
    log_error "Docker not found. Install QNAP Container Station first."
log_debug "docker: OK"

COMPOSE_CMD=""
if docker compose version >/dev/null 2>&1; then
    COMPOSE_CMD="docker compose"
    log_debug "docker compose plugin: OK"
elif command -v docker-compose >/dev/null 2>&1; then
    COMPOSE_CMD="docker-compose"
    log_debug "docker-compose standalone: OK"
else
    log_error "Neither 'docker compose' nor 'docker-compose' found."
fi

log_success "Requirements satisfied. Compose command: $COMPOSE_CMD"

# ── Step 3: Detect management IP ─────────────────────────────────────────────
log_info "[3/6] Detecting management IP..."
get_management_ip   # sets LOCAL_IP, QNAP_IFACE

if [ -z "$GITEA_DOMAIN" ]; then
    GITEA_DOMAIN="$LOCAL_IP"
    log_warn "No DOMAIN supplied; using IP: $GITEA_DOMAIN"
fi

ROOT_URL="http://${GITEA_DOMAIN}:${HTTP_PORT}"

# ── Step 4: Select persistent volume ─────────────────────────────────────────
log_info "[4/6] Selecting persistent volume..."
list_available_volumes
select_volume   # sets SELECTED_VOLUME

GITEA_BASE="$SELECTED_VOLUME/gitea"
DATA_DIR="$GITEA_BASE/data"
CONFIG_DIR="$GITEA_BASE/config"
DB_DIR="$GITEA_BASE/db"
COMPOSE_FILE="$GITEA_BASE/docker-compose.yml"

log_success "Gitea data will be stored at: $GITEA_BASE"
log_debug   "  data  : $DATA_DIR"
log_debug   "  config: $CONFIG_DIR"
log_debug   "  db    : $DB_DIR"

# ── Step 5: Create directories + docker-compose.yml ──────────────────────────
log_info "[5/6] Creating directories and docker-compose.yml..."

confirm_action "Create $GITEA_BASE/{data,config,db} and docker-compose.yml" || {
    log_warn "Installation aborted."
    exit 0
}

execute_cmd "mkdir -p $DATA_DIR"   "mkdir -p \"$DATA_DIR\""
execute_cmd "mkdir -p $CONFIG_DIR" "mkdir -p \"$CONFIG_DIR\""
execute_cmd "mkdir -p $DB_DIR"     "mkdir -p \"$DB_DIR\""

# Locate template (same directory as this script)
TPL_FILE="$SCRIPT_DIR/docker-compose.yml.tpl"
if [ ! -f "$TPL_FILE" ]; then
    log_error "Template not found: $TPL_FILE"
fi

# Substitute %%VAR%% placeholders via sed (ash-compatible)
COMPOSE_CONTENT=$(sed \
    -e "s|%%DATA_DIR%%|$DATA_DIR|g" \
    -e "s|%%CONFIG_DIR%%|$CONFIG_DIR|g" \
    -e "s|%%DB_DIR%%|$DB_DIR|g" \
    -e "s|%%HTTP_PORT%%|$HTTP_PORT|g" \
    -e "s|%%SSH_PORT%%|$SSH_PORT|g" \
    -e "s|%%DOMAIN%%|$GITEA_DOMAIN|g" \
    -e "s|%%ROOT_URL%%|$ROOT_URL|g" \
    "$TPL_FILE")

write_file "$COMPOSE_FILE" "$COMPOSE_CONTENT"
log_success "docker-compose.yml written: $COMPOSE_FILE"

# ── Step 6: Pull image + start + autorun hook ─────────────────────────────────
log_info "[6/6] Pulling Gitea image and starting container..."

confirm_action "Pull gitea/gitea:latest and start container" || {
    log_warn "Skipped container start. Run manually:"
    printf "  cd %s && %s up -d\n" "$GITEA_BASE" "$COMPOSE_CMD"
    exit 0
}

execute_cmd "docker pull gitea/gitea:latest" \
    "docker pull gitea/gitea:latest"

execute_cmd "Start Gitea container" \
    "cd \"$GITEA_BASE\" && $COMPOSE_CMD up -d"

# autorun.sh integration
add_autorun_hook "$GITEA_BASE" "# Gitea Docker service"

# Symlink to /opt/bin
if [ -d /opt/bin ] && [ ! -e /opt/bin/bootstrap-gitea.sh ]; then
    execute_cmd "Symlink to /opt/bin/bootstrap-gitea.sh" \
        "ln -s \"$0\" /opt/bin/bootstrap-gitea.sh"
    log_success "Symlinked: /opt/bin/bootstrap-gitea.sh"
fi

# ── Post-install summary ──────────────────────────────────────────────────────
printf "\n"
printf "${GREEN}╔══════════════════════════════════════════════════════╗${NC}\n"
printf "${GREEN}║  Gitea Installation Complete                         ║${NC}\n"
printf "${GREEN}╚══════════════════════════════════════════════════════╝${NC}\n"
printf "\n"
printf "  ${BLUE}Web UI${NC}       : http://%s:%s\n"       "$LOCAL_IP"      "$HTTP_PORT"
printf "  ${BLUE}SSH clone${NC}    : ssh://git@%s:%s\n"    "$LOCAL_IP"      "$SSH_PORT"
printf "  ${BLUE}Domain URL${NC}   : %s\n"                 "$ROOT_URL"
printf "  ${BLUE}Data path${NC}    : %s\n"                 "$GITEA_BASE"
printf "  ${BLUE}Compose file${NC} : %s\n"                 "$COMPOSE_FILE"
printf "\n"
printf "  ${YELLOW}First visit${NC}: open the Web UI above to complete setup.\n"
printf "  ${YELLOW}Admin user${NC} : created via browser wizard on first run.\n"
printf "\n"

if grep -qF "$GITEA_BASE" /etc/config/autorun.sh 2>/dev/null; then
    printf "  ${GREEN}autorun.sh${NC}: hook present — Gitea starts after every reboot.\n"
else
    printf "  ${YELLOW}autorun.sh${NC}: hook NOT found — add manually if needed:\n"
    printf "    cd \"%s\" && %s up -d\n" "$GITEA_BASE" "$COMPOSE_CMD"
fi
printf "\n"
