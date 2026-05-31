#!/bin/sh
# lib/input-cache.sh
#
# Enter-Once Cache ("DurchEntern") helper for POSIX shells.
#
# Supported sensitivity backends:
#   plain      - plain text file (non-sensitive convenience values)
#   gpg        - symmetric AES-256 encryption via GnuPG
#   keepassxc  - read/write via keepassxc-cli into a .kdbx database
#
# The keepassxc backend requires:
#   - keepassxc-cli in PATH (or KEEPASSXC_CLI env var pointing to the binary)
#   - KL_KEEPASS_DB  pointing to the .kdbx file
#   - KL_KEEPASS_PASS OR KL_KEEPASS_KEYFILE for database unlock
#     (if neither is set the user is prompted once per session)
#
# All cached values are local and git-ignored. Never committed.
#
# This file is designed to be sourced from other scripts.

set -eu

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
: "${XDG_CACHE_HOME:=$HOME/.cache}"
KL_INPUT_CACHE_ROOT="$XDG_CACHE_HOME/kl-input-cache"

# KeePassXC defaults (override via env)
: "${KEEPASSXC_CLI:=keepassxc-cli}"
: "${KL_KEEPASS_DB:=${HOME}/KeePassLatest.kdbx}"
: "${KL_KEEPASS_GROUP:=bootstrap-foundation}"

# Session-level KeePass master password (populated once per shell session)
KL_KEEPASS_PASS_SESSION=""

# ---------------------------------------------------------------------------
# Internal: repo ID
# ---------------------------------------------------------------------------
kl_repo_id() {
    if command -v git >/dev/null 2>&1; then
        top=$(git rev-parse --show-toplevel 2>/dev/null || printf '')
    else
        top=
    fi
    if [ -n "$top" ]; then
        printf '%s' "$top" | sha1sum | awk '{print $1}'
    else
        pwd | sha1sum | awk '{print $1}'
    fi
}

kl_cache_dir() {
    repo_id="$(kl_repo_id)"
    dir="$KL_INPUT_CACHE_ROOT/$repo_id"
    mkdir -p "$dir"
    printf '%s\n' "$dir"
}

# ---------------------------------------------------------------------------
# Internal: KeePassXC helpers
# ---------------------------------------------------------------------------

# Unlock prompt (once per session, cached in KL_KEEPASS_PASS_SESSION)
_kl_keepass_unlock() {
    if [ -n "${KL_KEEPASS_PASS:-}" ]; then
        KL_KEEPASS_PASS_SESSION="$KL_KEEPASS_PASS"
        return 0
    fi
    if [ -z "$KL_KEEPASS_PASS_SESSION" ]; then
        printf 'KeePass master password for %s: ' "$KL_KEEPASS_DB" >&2
        stty -echo 2>/dev/null || true
        read -r KL_KEEPASS_PASS_SESSION || KL_KEEPASS_PASS_SESSION=""
        stty echo 2>/dev/null || true
        printf '\n' >&2
    fi
}

# keepassxc-cli wrapper that pipes the master password via stdin
_kl_kp_cli() {
    _kl_keepass_unlock
    printf '%s\n' "$KL_KEEPASS_PASS_SESSION" \
        | "$KEEPASSXC_CLI" "$@" --no-password 2>/dev/null
}

# Check if keepassxc-cli is usable and DB exists
_kl_keepassxc_available() {
    command -v "$KEEPASSXC_CLI" >/dev/null 2>&1 || return 1
    [ -f "$KL_KEEPASS_DB" ] || return 1
    return 0
}

# Entry path inside the .kdbx: group/key
_kl_kp_entry() {
    key="$1"
    printf '%s/%s' "$KL_KEEPASS_GROUP" "$key"
}

# Read password from KeePass entry (returns empty string if not found)
kl_keepass_read() {
    key="$1"
    _kl_keepass_unlock
    entry="$(_kl_kp_entry "$key")"
    result=$(printf '%s\n' "$KL_KEEPASS_PASS_SESSION" \
        | "$KEEPASSXC_CLI" show -a password --no-password "$KL_KEEPASS_DB" "$entry" 2>/dev/null || true)
    printf '%s' "$result"
}

# Write (add or edit) password into KeePass
kl_keepass_write() {
    key="$1"
    value="$2"
    username="${3:-bootstrap}"
    _kl_keepass_unlock
    entry="$(_kl_kp_entry "$key")"
    # Try edit first, then add
    if printf '%s\n' "$KL_KEEPASS_PASS_SESSION" \
        | "$KEEPASSXC_CLI" locate --no-password "$KL_KEEPASS_DB" "$entry" >/dev/null 2>&1; then
        printf '%s\n' "$KL_KEEPASS_PASS_SESSION" \
            | "$KEEPASSXC_CLI" edit \
                --no-password \
                --username "$username" \
                --password "$value" \
                "$KL_KEEPASS_DB" "$entry" >/dev/null 2>&1
    else
        printf '%s\n' "$KL_KEEPASS_PASS_SESSION" \
            | "$KEEPASSXC_CLI" add \
                --no-password \
                --username "$username" \
                --password "$value" \
                "$KL_KEEPASS_DB" "$entry" >/dev/null 2>&1
    fi
}

# ---------------------------------------------------------------------------
# Internal: plain / gpg load-write
# ---------------------------------------------------------------------------
kl_load_from_file() {
    file="$1"
    sensitivity="$2"
    if [ "$sensitivity" = "gpg" ]; then
        printf '%s' "$(gpg --batch --quiet --decrypt "$file")"
    else
        cat "$file"
    fi
}

kl_write_to_file() {
    file="$1"
    value="$2"
    sensitivity="$3"
    if [ "$sensitivity" = "gpg" ]; then
        printf '%s' "$value" | gpg --batch --yes --symmetric --cipher-algo AES256 -o "$file"
    else
        printf '%s\n' "$value" >"$file"
    fi
}

# ---------------------------------------------------------------------------
# Unassisted wait
# ---------------------------------------------------------------------------
kl_unassisted_wait() {
    what="$1"
    delay="$2"
    if ! [ -t 0 ]; then
        return 0
    fi
    if [ -z "${BASH_VERSION:-}" ]; then
        sleep "$delay"
        return 0
    fi
    printf 'Using %s in %s seconds. Press SPACE for +30s… ' "$what" "$delay" >&2
    # shellcheck disable=SC2162
    if read -r -t "$delay" -n 1 key 2>/dev/null; then
        case "$key" in
            " ") printf '\nExtending wait by 30 seconds…\n' >&2; sleep 30 ;;
            *)   printf '\n' >&2 ;;
        esac
    else
        printf '\n' >&2
    fi
}

# ---------------------------------------------------------------------------
# Main: kl_read_cached
# ---------------------------------------------------------------------------
# Usage: kl_read_cached VAR KEY PROMPT DEFAULT SENSITIVITY
#
# SENSITIVITY: plain | gpg | keepassxc
#   keepassxc: reads from KeePass first; falls back to interactive prompt
#              and writes the entered value back into KeePass.

kl_read_cached() {
    var_name="$1"
    key="$2"
    prompt="$3"
    default_value="${4-}"
    sensitivity="${5-gpg}"

    run_mode="${KL_RUN_MODE:-auto}"
    if [ "$run_mode" = "auto" ]; then
        if [ -t 0 ]; then run_mode="interactive"; else run_mode="unassisted"; fi
    fi

    # -----------------------------------------------------------------------
    # keepassxc backend
    # -----------------------------------------------------------------------
    if [ "$sensitivity" = "keepassxc" ]; then
        if _kl_keepassxc_available; then
            cached_val="$(kl_keepass_read "$key" 2>/dev/null || true)"
            if [ -n "$cached_val" ]; then
                if [ "$run_mode" = "interactive" ]; then
                    printf '%s [Enter = reuse from KeePass]\n> ' "$prompt" >&2
                    read -r input || input=""
                    if [ -z "$input" ]; then
                        eval "$var_name=\"$cached_val\""
                        return 0
                    fi
                    kl_keepass_write "$key" "$input"
                    eval "$var_name=\"$input\""
                    return 0
                else
                    printf 'KeePass: reusing "%s"\n' "$key" >&2
                    eval "$var_name=\"$cached_val\""
                    return 0
                fi
            fi
            # Not in KeePass yet – fall through to interactive prompt, then store
            printf '%s [will be saved to KeePass]\n> ' "$prompt" >&2
            read -r input || input=""
            value="${input:-$default_value}"
            if [ -n "$value" ]; then
                kl_keepass_write "$key" "$value"
            fi
            eval "$var_name=\"$value\""
            return 0
        else
            printf '[KeePassXC not available – falling back to gpg]\n' >&2
            sensitivity="gpg"
        fi
    fi

    # -----------------------------------------------------------------------
    # gpg / plain backend (original logic)
    # -----------------------------------------------------------------------
    dir="$(kl_cache_dir)"
    case "$sensitivity" in
        gpg)   file="$dir/$key.gpg" ;;
        plain) file="$dir/$key.txt" ;;
        *)     file="$dir/$key" ;;
    esac

    value=""

    if [ -f "$file" ]; then
        if [ "$run_mode" = "interactive" ]; then
            printf '%s [Enter = reuse cached]\n> ' "$prompt" >&2
            read -r input || input=""
            if [ -z "$input" ]; then
                value="$(kl_load_from_file "$file" "$sensitivity")"
            else
                value="$input"
                kl_write_to_file "$file" "$value" "$sensitivity"
            fi
        else
            printf '%s\n' "$prompt" >&2
            kl_unassisted_wait "cached value for $key" 2
            value="$(kl_load_from_file "$file" "$sensitivity")"
        fi
    else
        if [ "$run_mode" = "interactive" ]; then
            if [ -n "$default_value" ]; then
                printf '%s [default: %s]\n> ' "$prompt" "$default_value" >&2
            else
                printf '%s\n> ' "$prompt" >&2
            fi
            read -r input || input=""
            value="${input:-$default_value}"
            if [ -n "$value" ]; then
                kl_write_to_file "$file" "$value" "$sensitivity"
            fi
        else
            if [ -n "$default_value" ]; then
                printf '%s\n[no cache, using default "%s"]\n' "$prompt" "$default_value" >&2
                kl_unassisted_wait "default for $key" 3
                value="$default_value"
                kl_write_to_file "$file" "$value" "$sensitivity"
            else
                printf '%s\n[no cache and no default for "%s" – waiting for input]\n> ' "$prompt" "$key" >&2
                read -r input || input=""
                value="$input"
                if [ -n "$value" ]; then
                    kl_write_to_file "$file" "$value" "$sensitivity"
                fi
            fi
        fi
    fi

    eval "$var_name=\"$value\""
}

# ---------------------------------------------------------------------------
# Optional: purge cache for current repo
# ---------------------------------------------------------------------------
kl_purge_cache_for_repo() {
    dir="$(kl_cache_dir)"
    printf 'Delete all cached inputs for this repository in "%s"? [y/N] ' "$dir" >&2
    read -r answer || answer=""
    case "$answer" in
        y|Y) rm -rf -- "$dir"; printf 'Cache deleted.\n' >&2 ;;
        *)   printf 'Keeping cache.\n' >&2 ;;
    esac
}
