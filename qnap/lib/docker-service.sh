#!/bin/sh
################################################################################
# qnap/lib/docker-service.sh
# Shared helper functions for Docker-based service bootstraps on QNAP.
# Compatible with BusyBox ash (no declare, no [[, no bash arrays).
# Source this file from individual service bootstrap scripts:
#   . "$(dirname "$0")/../lib/docker-service.sh"
################################################################################

# ── Colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

log_info()    { printf "${BLUE}[INFO]${NC} %s\n" "$*"; }
log_success() { printf "${GREEN}[OK]${NC} %s\n" "$*"; }
log_warn()    { printf "${YELLOW}[WARN]${NC} %s\n" "$*"; }
log_error()   { printf "${RED}[ERROR]${NC} %s\n" "$*"; exit 1; }
log_debug()   { [ "$VERBOSE" -eq 1 ] && printf "${MAGENTA}[DEBUG]${NC} %s\n" "$*"; }
log_dry_run() { [ "$DRY_RUN"  -eq 1 ] && printf "${MAGENTA}[DRY-RUN]${NC} %s\n" "$*"; }

# ── Dry-run wrappers ──────────────────────────────────────────────────────────
execute_cmd() {
    # execute_cmd <description> <command string>
    _desc="$1"; shift; _cmd="$*"
    if [ "$DRY_RUN" -eq 1 ]; then
        log_dry_run "WOULD EXECUTE: $_desc"
        log_debug   "  \$ $_cmd"
        return 0
    fi
    log_debug "EXECUTE: $_desc"
    log_debug "  \$ $_cmd"
    eval "$_cmd"
}

write_file() {
    # write_file <path> <content>
    _path="$1"; _content="$2"
    if [ "$DRY_RUN" -eq 1 ]; then
        log_dry_run "WOULD WRITE: $_path"
        log_debug   "  size: $(printf '%s' "$_content" | wc -c) bytes"
        return 0
    fi
    log_debug "WRITE: $_path"
    printf '%s\n' "$_content" > "$_path"
}

# ── Confirmation prompt ───────────────────────────────────────────────────────
ALWAYS_CONFIRM=0

confirm_action() {
    # confirm_action <description>
    # Returns 0 to proceed, 1 to abort.
    _adesc="$1"
    if [ "$ALWAYS_CONFIRM" -eq 1 ]; then
        log_success "Auto-confirm: $_adesc"
        return 0
    fi
    printf "\n${YELLOW}ACTION: %s${NC}\n" "$_adesc"
    printf "${YELLOW}  [O]K  [A]BORT  [L]WAYS (always OK)${NC}\n"
    printf "${GREEN}Choice:${NC} "
    read -r _resp
    case "$_resp" in
        [Oo]*) return 0 ;;
        [Ll]*) ALWAYS_CONFIRM=1; return 0 ;;
        *)     log_warn "Aborted by user."; return 1 ;;
    esac
}

# ── Management IP detection ───────────────────────────────────────────────────
get_management_ip() {
    # Sets global LOCAL_IP and QNAP_IFACE.
    # Skips VPN ranges: 10.0.[3-9].x, 10.1x.x, 172.x.x
    LOCAL_IP=""
    QNAP_IFACE=""

    if command -v ip >/dev/null 2>&1; then
        log_debug "Probing via 'ip addr'"
        for _iface in qvs0 qvs1 qvs2 qvs3 eth0 eth1 eth2; do
            _ip=$(ip addr show "$_iface" 2>/dev/null \
                  | grep "inet " \
                  | grep -v "scope host\|scope link" \
                  | awk '{print $2}' | cut -d'/' -f1)
            if [ -n "$_ip" ]; then
                if ! printf '%s' "$_ip" | grep -qE \
                        '^10\.0\.[3-9]\.|^10\.1[0-9]\.|^172\.'; then
                    LOCAL_IP="$_ip"
                    QNAP_IFACE="$_iface"
                    log_success "IP: $LOCAL_IP (iface: $QNAP_IFACE)"
                    return 0
                fi
            fi
        done
    fi

    if [ -f /etc/config/network ]; then
        log_debug "Fallback: /etc/config/network"
        LOCAL_IP=$(grep -E "ipaddr" /etc/config/network 2>/dev/null \
                   | grep -E "192\.168|10\." \
                   | grep -v "10\.0\.[3-9]" \
                   | awk -F'=' '{print $2}' | head -1 \
                   | tr -d ' "')
        if [ -n "$LOCAL_IP" ]; then
            log_success "IP from config: $LOCAL_IP"
            return 0
        fi
    fi

    log_error "Could not determine management IP."
}

# ── Volume picker ─────────────────────────────────────────────────────────────
list_available_volumes() {
    # Print tree-format list of /share/ symlinks with disk usage.
    log_info "Available shares:"
    cd /share/ || return 1
    _shares=$(find . -maxdepth 1 -type l ! -name 'NFSv=*' \
              | sed 's|^\./||' | sort)
    [ -z "$_shares" ] && { log_warn "No shares found."; return 1; }

    _count=0
    _total=$(printf '%s\n' "$_shares" | wc -l)
    printf '%s\n' "$_shares" | while IFS= read -r _s; do
        _count=$((_count + 1))
        _tgt=$(readlink "$_s")
        if [ "$DRY_RUN" -eq 1 ]; then
            _usage="(--dry-run)"
        else
            _usage=$(df -h "/share/$_tgt" 2>/dev/null \
                     | tail -1 | awk '{print $5 " (" $3 "/" $2 ")"}')
        fi
        if [ "$_count" -lt "$_total" ]; then
            printf "  ├─ ${GREEN}%-20s${NC} -> %-35s | %s\n" \
                   "$_s" "$_tgt" "$_usage"
        else
            printf "  └─ ${GREEN}%-20s${NC} -> %-35s | %s\n" \
                   "$_s" "$_tgt" "$_usage"
        fi
    done
}

select_volume() {
    # Interactive share picker.
    # Sets global SELECTED_VOLUME to /share/<chosen>.
    SELECTED_VOLUME=""
    cd /share/ || log_error "Cannot access /share/"

    _shares=$(find . -maxdepth 1 -type l ! -name 'NFSv=*' \
              | sed 's|^\./||' | sort)
    [ -z "$_shares" ] && log_error "No shares found in /share/!"

    log_info "Select a share for persistent service data:"
    printf "\n"

    # Numbered list — ash compatible, no arrays
    _idx=0
    printf '%s\n' "$_shares" | while IFS= read -r _s; do
        _idx=$((_idx + 1))
        _tgt=$(readlink "$_s")
        printf "  ${GREEN}%d${NC}) %-20s (-> %s)\n" "$_idx" "$_s" "$_tgt"
    done

    _max=$(printf '%s\n' "$_shares" | wc -l)
    printf "\n${BLUE}[INFO]${NC} Enter share number [1-%d] (default: 1): " "$_max"
    read -r _choice

    case "$_choice" in
        ''|0) _choice=1 ;;
    esac

    if [ "$_choice" -lt 1 ] || [ "$_choice" -gt "$_max" ] 2>/dev/null; then
        log_warn "Invalid choice '$_choice', using 1."
        _choice=1
    fi

    # Resolve by line number — no arrays needed
    _chosen=$(printf '%s\n' "$_shares" | sed -n "${_choice}p")
    [ -z "$_chosen" ] && log_error "Could not resolve share choice."

    SELECTED_VOLUME="/share/$_chosen"
    log_success "Selected volume: $SELECTED_VOLUME"
}

# ── autorun.sh hook ───────────────────────────────────────────────────────────
add_autorun_hook() {
    # add_autorun_hook <service_dir> <hook_comment>
    # Appends 'cd <dir> && docker compose up -d' to /etc/config/autorun.sh
    # guarded by grep-check to prevent duplicates.
    _svc_dir="$1"
    _comment="${2:-# Auto-started service}"
    _autorun="/etc/config/autorun.sh"
    _hook="cd \"$_svc_dir\" && docker compose up -d"

    if grep -qF "$_svc_dir" "$_autorun" 2>/dev/null; then
        log_warn "autorun.sh already contains entry for $_svc_dir — skipping."
        return 0
    fi

    confirm_action "Add autorun hook for $_svc_dir" || return 1

    if [ "$DRY_RUN" -eq 1 ]; then
        log_dry_run "WOULD APPEND to $_autorun: $_comment / $_hook"
        return 0
    fi

    [ -f "$_autorun" ] || { printf '#!/bin/sh\n' > "$_autorun"; chmod +x "$_autorun"; }
    printf '\n%s\n%s\n' "$_comment" "$_hook" >> "$_autorun"
    log_success "autorun hook added to $_autorun"
}
