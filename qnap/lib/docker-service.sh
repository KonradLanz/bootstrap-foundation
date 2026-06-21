#!/bin/sh
################################################################################
# qnap/lib/docker-service.sh
# Shared helper functions for Docker-based service bootstraps on QNAP.
# Compatible with BusyBox ash (no declare, no [[, no bash arrays).
# Source this file from individual service bootstrap scripts:
#   . "$(dirname "$0")/../lib/docker-service.sh"
#
# ash set -e gotchas fixed here:
#   1. 'cmd | while' subshell: replaced with tempfile + redirect
#   2. '[ cond ] && cmd' in functions: exits 1 when cond false under set -e
#      Fix: every log function ends with explicit 'return 0'
################################################################################

# ── Colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Every log function MUST return 0 explicitly.
# '[ cond ] && cmd' exits 1 when cond is false — fatal under set -e.
log_info()    { printf "${BLUE}[INFO]${NC} %s\n" "$*"; return 0; }
log_success() { printf "${GREEN}[OK]${NC} %s\n" "$*"; return 0; }
log_warn()    { printf "${YELLOW}[WARN]${NC} %s\n" "$*"; return 0; }
log_error()   { printf "${RED}[ERROR]${NC} %s\n" "$*" >&2; exit 1; }
log_debug() {
    if [ "$VERBOSE" -eq 1 ]; then
        printf "${MAGENTA}[DEBUG]${NC} %s\n" "$*"
    fi
    return 0
}
log_dry_run() {
    if [ "$DRY_RUN" -eq 1 ]; then
        printf "${MAGENTA}[DRY-RUN]${NC} %s\n" "$*"
    fi
    return 0
}

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
    # Callers using set -e must guard: confirm_action "..." || { ...; exit 0; }
    _adesc="$1"
    if [ "$ALWAYS_CONFIRM" -eq 1 ]; then
        log_success "Auto-confirm: $_adesc"
        return 0
    fi
    printf "\n${YELLOW}ACTION: %s${NC}\n" "$_adesc"
    printf "${YELLOW}  [O]K  [A]BORT  [L]WAYS (always OK)${NC}\n"
    printf "${GREEN}Choice:${NC} "
    read -r _resp < /dev/tty
    case "$_resp" in
        [Oo]*) return 0 ;;
        [Ll]*) ALWAYS_CONFIRM=1; return 0 ;;
        *)     log_warn "Aborted by user."; return 1 ;;
    esac
}

# ── Management IP detection ───────────────────────────────────────────────────
# Collects ALL candidate IPs across all interfaces.
# - Exactly one candidate  → auto-select (no prompt)
# - More than one          → numbered list, user picks
# Override: set QNAP_IP=<ip> before sourcing to skip detection entirely.

get_management_ip() {
    # Sets globals: LOCAL_IP, QNAP_IFACE
    LOCAL_IP=""
    QNAP_IFACE=""

    # ── honour explicit override ──────────────────────────────────────────────
    if [ -n "${QNAP_IP:-}" ]; then
        LOCAL_IP="$QNAP_IP"
        QNAP_IFACE="(override)"
        log_success "IP: $LOCAL_IP (from QNAP_IP env)"
        return 0
    fi

    # ── collect candidates into tempfile  (iface<TAB>ip) ─────────────────────
    _ip_tmp=$(mktemp /tmp/mgmt_ips.XXXXXX)

    # VPN / container ranges to skip
    _skip_re='^10\.0\.[3-9]\.|^10\.1[0-9]\.|^172\.'

    if command -v ip >/dev/null 2>&1; then
        log_debug "Probing via 'ip addr'"
        # Collect all interfaces — NOT a fixed list — via tempfile to avoid
        # ash pipe-subshell trap ('cmd | while' runs in a subshell in ash).
        _if_tmp=$(mktemp /tmp/mgmt_ifaces.XXXXXX)
        ip addr show 2>/dev/null \
          | awk '/^[0-9]+:/{iface=$2; sub(/:$/,"",iface)}
                 /inet /{print iface, $2}' > "$_if_tmp"
        while read -r _iface _cidr; do
            _ip=$(printf '%s' "$_cidr" | cut -d'/' -f1)
            # skip loopback and link-local
            printf '%s' "$_ip" | grep -qE '^127\.|^169\.254\.' && continue
            # skip VPN/container ranges
            printf '%s' "$_ip" | grep -qE "$_skip_re" && continue
            printf '%s\t%s\n' "$_iface" "$_ip" >> "$_ip_tmp"
        done < "$_if_tmp"
        rm -f "$_if_tmp"
    fi

    # Fallback: scan known QNAP iface names when 'ip' is absent / yields nothing
    if [ ! -s "$_ip_tmp" ] && command -v ifconfig >/dev/null 2>&1; then
        log_debug "Fallback: ifconfig"
        for _if in qvs0 qvs1 qvs2 qvs3 eth0 eth1 eth2 eth3; do
            _ip=$(ifconfig "$_if" 2>/dev/null \
                  | grep 'inet addr:' | awk -F: '{print $2}' | awk '{print $1}')
            [ -z "$_ip" ] && \
            _ip=$(ifconfig "$_if" 2>/dev/null \
                  | grep 'inet ' | awk '{print $2}' | sed 's/addr://')
            [ -z "$_ip" ] && continue
            printf '%s' "$_ip" | grep -qE '^127\.|^169\.254\.' && continue
            printf '%s' "$_ip" | grep -qE "$_skip_re"           && continue
            printf '%s\t%s\n' "$_if" "$_ip" >> "$_ip_tmp"
        done
    fi

    # Config-file fallback
    if [ ! -s "$_ip_tmp" ] && [ -f /etc/config/network ]; then
        log_debug "Fallback: /etc/config/network"
        _cf_tmp=$(mktemp /tmp/mgmt_cf.XXXXXX)
        grep -E "ipaddr" /etc/config/network 2>/dev/null \
          | grep -E "192\.168|10\." \
          | grep -v "10\.0\.[3-9]" \
          | awk -F'=' '{print $2}' | tr -d ' "' > "$_cf_tmp"
        while read -r _ip; do
            [ -n "$_ip" ] && printf 'config\t%s\n' "$_ip" >> "$_ip_tmp"
        done < "$_cf_tmp"
        rm -f "$_cf_tmp"
    fi

    if [ ! -s "$_ip_tmp" ]; then
        rm -f "$_ip_tmp"
        log_error "Could not determine management IP. Set QNAP_IP=<ip> to override."
    fi

    _count=$(wc -l < "$_ip_tmp")

    # ── single candidate — use automatically ─────────────────────────────────
    if [ "$_count" -eq 1 ]; then
        QNAP_IFACE=$(awk -F'\t' '{print $1}' "$_ip_tmp")
        LOCAL_IP=$(awk   -F'\t' '{print $2}' "$_ip_tmp")
        rm -f "$_ip_tmp"
        log_success "IP: $LOCAL_IP (iface: $QNAP_IFACE)"
        return 0
    fi

    # ── multiple candidates — prompt user ─────────────────────────────────────
    printf "\n${YELLOW}[INPUT]${NC} Multiple network interfaces found. Select management IP:\n\n"
    _idx=0
    while IFS='	' read -r _if _ip; do
        _idx=$((_idx + 1))
        printf "  ${GREEN}%d)${NC} %-12s %s\n" "$_idx" "$_if" "$_ip"
    done < "$_ip_tmp"
    printf "\n${BLUE}[INFO]${NC} Enter number [1-%d] (default: 1): " "$_count"
    read -r _choice < /dev/tty
    case "$_choice" in ''|0) _choice=1 ;; esac
    if ! expr "$_choice" : '^[0-9][0-9]*$' >/dev/null 2>&1 \
        || [ "$_choice" -lt 1 ] || [ "$_choice" -gt "$_count" ]; then
        log_warn "Invalid choice '$_choice', using 1."
        _choice=1
    fi
    _chosen_line=$(sed -n "${_choice}p" "$_ip_tmp")
    rm -f "$_ip_tmp"
    QNAP_IFACE=$(printf '%s' "$_chosen_line" | awk -F'	' '{print $1}')
    LOCAL_IP=$(printf   '%s' "$_chosen_line" | awk -F'	' '{print $2}')
    log_success "IP: $LOCAL_IP (iface: $QNAP_IFACE)"
    return 0
}

# ── Volume picker ─────────────────────────────────────────────────────────────
# ash pipe-subshell fix: write share list to tempfile, read with redirection.
# 'cmd | while' creates a subshell in ash — variables set inside never escape.
# 'while ... done < file' runs in the current shell — variables propagate.

_shares_tmpfile() {
    _tf=$(mktemp /tmp/shares.XXXXXX)
    find /share/ -maxdepth 1 -type l ! -name 'NFSv=*' \
        | sed 's|^/share/||' | sort > "$_tf"
    printf '%s' "$_tf"
}

list_available_volumes() {
    log_info "Available shares:"
    _tf=$(_shares_tmpfile)
    [ -s "$_tf" ] || { rm -f "$_tf"; log_warn "No shares found."; return 1; }

    _count=0
    _total=$(wc -l < "$_tf")
    while IFS= read -r _s; do
        _count=$((_count + 1))
        _tgt=$(readlink "/share/$_s" 2>/dev/null || printf "?")
        if [ "$DRY_RUN" -eq 1 ]; then
            _usage="(--dry-run)"
        else
            _usage=$(df -h "/share/$_s" 2>/dev/null \
                     | tail -1 | awk '{print $5 " (" $3 "/" $2 ")"}')
        fi
        if [ "$_count" -lt "$_total" ]; then
            printf "  ├─ ${GREEN}%-20s${NC} -> %-35s | %s\n" "$_s" "$_tgt" "$_usage"
        else
            printf "  └─ ${GREEN}%-20s${NC} -> %-35s | %s\n" "$_s" "$_tgt" "$_usage"
        fi
    done < "$_tf"
    rm -f "$_tf"
    return 0
}

select_volume() {
    # Sets global SELECTED_VOLUME to /share/<chosen>.
    # Uses tempfile redirect — NOT pipe — so assignment reaches parent shell.
    SELECTED_VOLUME=""

    _tf=$(_shares_tmpfile)
    [ -s "$_tf" ] || { rm -f "$_tf"; log_error "No shares found in /share/!"; }

    _max=$(wc -l < "$_tf")
    log_info "Select a share for persistent service data:"
    printf "\n"

    _idx=0
    while IFS= read -r _s; do
        _idx=$((_idx + 1))
        _tgt=$(readlink "/share/$_s" 2>/dev/null || printf "?")
        printf "  ${GREEN}%d${NC}) %-20s (-> %s)\n" "$_idx" "$_s" "$_tgt"
    done < "$_tf"

    printf "\n${BLUE}[INFO]${NC} Enter share number [1-%d] (default: 1): " "$_max"
    read -r _choice < /dev/tty

    case "$_choice" in
        ''|0) _choice=1 ;;
    esac

    if ! expr "$_choice" : '^[0-9][0-9]*$' >/dev/null 2>&1 \
        || [ "$_choice" -lt 1 ] || [ "$_choice" -gt "$_max" ]; then
        log_warn "Invalid choice '$_choice', using 1."
        _choice=1
    fi

    _chosen=$(sed -n "${_choice}p" "$_tf")
    rm -f "$_tf"

    [ -z "$_chosen" ] && log_error "Could not resolve share choice."

    SELECTED_VOLUME="/share/$_chosen"
    log_success "Selected volume: $SELECTED_VOLUME"
    return 0
}

# ── autorun.sh hook ───────────────────────────────────────────────────────────
add_autorun_hook() {
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
        log_dry_run "WOULD APPEND to $_autorun: $_comment"
        log_dry_run "WOULD APPEND: $_hook"
        return 0
    fi

    [ -f "$_autorun" ] || { printf '#!/bin/sh\n' > "$_autorun"; chmod +x "$_autorun"; }
    printf '\n%s\n%s\n' "$_comment" "$_hook" >> "$_autorun"
    log_success "autorun hook added to $_autorun"
    return 0
}
