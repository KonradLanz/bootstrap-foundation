#!/bin/sh
# lib/input-cache.sh
#
# Enter-Once Cache ("DurchEntern") helper for POSIX shells.
#
# Caches interactive inputs per git repository so you only type them once
# and can keep pressing Enter afterwards ("WeiterEntern").
#
# Credential storage is delegated to lib/secret-backends.sh which provides
# keepassxc, gpg, and plain backends. Source secret-backends.sh before
# sourcing this file, or set KL_BOOTSTRAP_ROOT so this file can find it.
#
# Sensitivity values for kl_read_cached:
#   plain      - plain text (URLs, usernames, non-sensitive) -- input VISIBLE
#   gpg        - symmetric AES-256 via GnuPG                -- input HIDDEN (read -s)
#   keepassxc  - keepassxc-cli against a .kdbx database     -- input HIDDEN (read -s)
#   auto       - auto-detect via sb_detect_backend (default) -- HIDDEN if backend != plain
#
# IMPORTANT: Any sensitivity != plain triggers silent input (read -s / stty -echo).
# This covers passwords, tokens, API keys -- anything that must not appear in terminal.
#
# This file is designed to be sourced from other scripts.

set -eu

# ---------------------------------------------------------------------------
# _kl_read_input VAR SENSITIVITY PROMPT
#
# Central read helper -- ALWAYS silent (read -s) for non-plain sensitivity.
# Covers: passwords, tokens, API keys, passphrases.
# Plain text (URLs, usernames): read -r (visible).
# ---------------------------------------------------------------------------
_kl_read_input() {
    _kl_var="$1"
    _kl_sens="$2"
    _kl_prompt="$3"
    _kl_input=""

    if [ "$_kl_sens" = "plain" ]; then
        # Visible input -- safe for non-sensitive data
        printf '%s' "$_kl_prompt" >&2
        read -r _kl_input || _kl_input=""
    else
        # Silent input -- passwords, tokens, API keys
        # Use read -s if available (bash/zsh), fallback to stty -echo for POSIX sh
        printf '%s' "$_kl_prompt" >&2
        if ( read -rs _kl_test_silent 2>/dev/null </dev/null ); then
            read -rs _kl_input 2>/dev/null || _kl_input=""
        else
            # POSIX sh fallback: stty -echo
            _kl_old_stty="$(stty -g 2>/dev/null || true)"
            stty -echo 2>/dev/null || true
            read -r _kl_input || _kl_input=""
            stty "$_kl_old_stty" 2>/dev/null || true
        fi
        printf '\n' >&2  # Newline after silent input
    fi

    eval "$_kl_var=\"$_kl_input\""
}

# ---------------------------------------------------------------------------
# Locate and source secret-backends.sh
# ---------------------------------------------------------------------------
_kl_find_bootstrap_root() {
    if [ -n "${KL_BOOTSTRAP_ROOT:-}" ]; then
        printf '%s' "$KL_BOOTSTRAP_ROOT"
        return
    fi
    # Try relative to this file's directory (lib/../ = repo root)
    _self_dir="$(cd "$(dirname "${0:-lib/input-cache.sh}")" 2>/dev/null && pwd || echo '')"
    for candidate in \
        "${_self_dir}/.." \
        "$HOME/github/bootstrap-foundation" \
        "$HOME/repos/bootstrap-foundation" \
        "$(pwd)";
    do
        if [ -f "${candidate}/lib/secret-backends.sh" ]; then
            printf '%s' "$candidate"
            return
        fi
    done
    printf ''
}

if [ -z "${_KL_SECRET_BACKENDS_LOADED:-}" ]; then
    _kl_root="$(_kl_find_bootstrap_root)"
    if [ -n "$_kl_root" ] && [ -f "${_kl_root}/lib/secret-backends.sh" ]; then
        # shellcheck source=/dev/null
        . "${_kl_root}/lib/secret-backends.sh"
        _KL_SECRET_BACKENDS_LOADED=1
    else
        # Graceful degradation: no backends, plain-only mode
        _KL_SECRET_BACKENDS_LOADED=0
        sb_detect_backend() { printf 'plain'; }
        sb_read()  { cat "$2" 2>/dev/null || true; }
        sb_write() { printf '%s\n' "$3" > "$2"; }
    fi
export _KL_SECRET_BACKENDS_LOADED
fi

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
: "${XDG_CACHE_HOME:=$HOME/.cache}"
KL_INPUT_CACHE_ROOT="$XDG_CACHE_HOME/kl-input-cache"

# ---------------------------------------------------------------------------
# Internal: per-repo cache directory
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
# Unassisted wait (optional TTY grace period)
# ---------------------------------------------------------------------------
kl_unassisted_wait() {
    what="$1"
    delay="$2"
    if ! [ -t 0 ]; then return 0; fi
    if [ -z "${BASH_VERSION:-}" ]; then sleep "$delay"; return 0; fi
    printf 'Using %s in %s seconds. Press SPACE for +30s... ' "$what" "$delay" >&2
    # shellcheck disable=SC2162
    if read -r -t "$delay" -n 1 key 2>/dev/null; then
        case "$key" in
            " ") printf '\nExtending wait by 30 seconds...\n' >&2; sleep 30 ;;
            *)   printf '\n' >&2 ;;
        esac
    else
        printf '\n' >&2
    fi
}

# ---------------------------------------------------------------------------
# kl_read_cached VAR KEY PROMPT DEFAULT SENSITIVITY
#
# VAR         - shell variable name to assign
# KEY         - logical cache key
# PROMPT      - human-readable prompt
# DEFAULT     - default value ("" = no sensible default)
# SENSITIVITY - plain | gpg | keepassxc | auto
# ---------------------------------------------------------------------------
kl_read_cached() {
    var_name="$1"
    key="$2"
    prompt="$3"
    default_value="${4-}"
    sensitivity="${5:-auto}"

    # Resolve 'auto' to actual backend
    if [ "$sensitivity" = "auto" ]; then
        sensitivity="$(sb_detect_backend)"
    fi

    run_mode="${KL_RUN_MODE:-auto}"
    if [ "$run_mode" = "auto" ]; then
        if [ -t 0 ]; then run_mode="interactive"; else run_mode="unassisted"; fi
    fi

    # -------------------------------------------------------------------
    # keepassxc backend
    # -------------------------------------------------------------------
    if [ "$sensitivity" = "keepassxc" ]; then
        if sb_keepass_available 2>/dev/null; then
            cached_val="$(sb_keepass_read "$key" 2>/dev/null || true)"
            if [ -n "$cached_val" ]; then
                if [ "$run_mode" = "interactive" ]; then
                    _kl_read_input input "$sensitivity" "$prompt [Enter = reuse from KeePass]\n> "
                    if [ -z "$input" ]; then
                        eval "$var_name=\"$cached_val\""
                        return 0
                    fi
                    sb_keepass_write "$key" "$input"
                    eval "$var_name=\"$input\""
                    return 0
                else
                    printf 'KeePass: reusing "%s"\n' "$key" >&2
                    eval "$var_name=\"$cached_val\""
                    return 0
                fi
            fi
            # Not in KeePass yet
            _kl_read_input input "$sensitivity" "$prompt [will be saved to KeePass]\n> "
            value="${input:-$default_value}"
            if [ -n "$value" ]; then sb_keepass_write "$key" "$value"; fi
            eval "$var_name=\"$value\""
            return 0
        else
            printf '[KeePassXC not available - falling back to gpg]\n' >&2
            sensitivity="gpg"
        fi
    fi

    # -------------------------------------------------------------------
    # gpg / plain backend (file-based cache)
    # -------------------------------------------------------------------
    dir="$(kl_cache_dir)"
    case "$sensitivity" in
        gpg)   file="$dir/${key}.gpg" ;;
        plain) file="$dir/${key}.txt" ;;
        *)     file="$dir/${key}" ;;
    esac
    # Ensure parent directory for nested keys (e.g. forge/admin_pass)
    mkdir -p "$(dirname "$file")"

    value=""

    if [ -f "$file" ]; then
        if [ "$run_mode" = "interactive" ]; then
            _kl_read_input input "$sensitivity" "$prompt [Enter = reuse cached]\n> "
            if [ -z "$input" ]; then
                value="$(sb_read "$sensitivity" "$file")"
            else
                value="$input"
                sb_write "$sensitivity" "$file" "$value"
            fi
        else
            printf '%s\n' "$prompt" >&2
            kl_unassisted_wait "cached value for $key" 2
            value="$(sb_read "$sensitivity" "$file")"
        fi
    else
        if [ "$run_mode" = "interactive" ]; then
            if [ -n "$default_value" ]; then
                _kl_read_input input "$sensitivity" "$prompt [default: $default_value]\n> "
            else
                _kl_read_input input "$sensitivity" "$prompt\n> "
            fi
            value="${input:-$default_value}"
            if [ -n "$value" ]; then sb_write "$sensitivity" "$file" "$value"; fi
        else
            if [ -n "$default_value" ]; then
                printf '%s\n[no cache, using default "%s"]\n' "$prompt" "$default_value" >&2
                kl_unassisted_wait "default for $key" 3
                value="$default_value"
                sb_write "$sensitivity" "$file" "$value"
            else
                printf '%s\n[no cache and no default for "%s" - waiting for input]\n> ' \
                    "$prompt" "$key" >&2
                _kl_read_input input "$sensitivity" ""
                value="$input"
                if [ -n "$value" ]; then sb_write "$sensitivity" "$file" "$value"; fi
            fi
        fi
    fi

    eval "$var_name=\"$value\""
}

# ---------------------------------------------------------------------------
# kl_purge_cache_for_repo
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
