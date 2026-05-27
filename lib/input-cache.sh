#!/bin/sh
# lib/input-cache.sh
#
# Enter-Once Cache ("DurchEntern") helper for POSIX shells.
#
# - Caches interactive inputs per git repository in XDG cache.
# - Supports interactive and unassisted runs via KL_RUN_MODE.
# - Stores sensitive values encrypted with gpg (optional) or as plain text.
#
# This file is designed to be sourced from other scripts.

set -eu

# Determine cache root
: "${XDG_CACHE_HOME:=$HOME/.cache}"
KL_INPUT_CACHE_ROOT="$XDG_CACHE_HOME/kl-input-cache"

# Determine a stable per-repo ID (prefer git top-level, fall back to pwd)
kl_repo_id() {
    if command -v git >/dev/null 2>&1; then
        top=$(git rev-parse --show-toplevel 2>/dev/null || printf '')
    else
        top=
    fi

    if [ -n "$top" ]; then
        # Use sha1sum of the canonical top-level path
        # shellcheck disable=SC200 echo is fine here
        printf '%s' "$top" | sha1sum | awk '{print $1}'
    else
        # Fallback: current directory
        pwd | sha1sum | awk '{print $1}'
    fi
}

kl_cache_dir() {
    repo_id="$(kl_repo_id)"
    dir="$KL_INPUT_CACHE_ROOT/$repo_id"
    mkdir -p "$dir"
    printf '%s\n' "$dir"
}

# Load a cached value from file (gpg or plain)
kl_load_from_file() {
    file="$1"
    sensitivity="$2"

    if [ "$sensitivity" = "gpg" ]; then
        # shellcheck disable=SC2005
        printf '%s' "$(gpg --batch --quiet --decrypt "$file")"
    else
        # shellcheck disable=SC2002
        cat "$file"
    fi
}

# Write a value to cache file (gpg or plain)
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

# Unassisted wait helper: only meaningful when stdin is a TTY.
# In strictly non-interactive environments this returns quickly.
kl_unassisted_wait() {
    what="$1"
    delay="$2"

    # No TTY: nothing to do, do not delay automated jobs unnecessarily.
    if ! [ -t 0 ]; then
        return 0
    fi

    # Only use Bash's timed single-char read when running under Bash.
    if [ -z "${BASH_VERSION:-}" ]; then
        sleep "$delay"
        return 0
    fi

    printf 'Using %s in %s seconds. Press SPACE for +30s… ' "$what" "$delay" >&2

    # shellcheck disable=SC2162
    if read -r -t "$delay" -n 1 key 2>/dev/null; then
        case "$key" in
            " ")
                printf '\nExtending wait by 30 seconds…\n' >&2
                sleep 30
                ;;
            *)
                printf '\n' >&2
                ;;
        esac
    else
        printf '\n' >&2
    fi
}

# Main helper: read a value with optional caching.
#
# Usage:
#   kl_read_cached VAR KEY PROMPT DEFAULT SENSITIVITY
#
# VAR        - shell variable name to assign.
# KEY        - logical cache key (used to build cache path).
# PROMPT     - human-readable prompt for interactive mode.
# DEFAULT    - default value ("" means "no sensible default").
# SENSITIVITY- "gpg" or "plain".

kl_read_cached() {
    var_name="$1"
    key="$2"
    prompt="$3"
    default_value="${4-}"
    sensitivity="${5-gpg}"

    run_mode="${KL_RUN_MODE:-auto}"

    # Auto mode: interactive when stdin is a TTY, unassisted otherwise
    if [ "$run_mode" = "auto" ]; then
        if [ -t 0 ]; then
            run_mode="interactive"
        else
            run_mode="unassisted"
        fi
    fi

    dir="$(kl_cache_dir)"
    case "$sensitivity" in
        gpg)   file="$dir/$key.gpg" ;;
        plain) file="$dir/$key.txt" ;;
        *)     file="$dir/$key" ;;
    esac

    value=""

    if [ -f "$file" ]; then
        # Cache present
        if [ "$run_mode" = "interactive" ]; then
            printf '%s [Enter = reuse cached]\n' "$prompt" >&2
            printf '> ' >&2
            # shellcheck disable=SC2162
            read input || input=""
            if [ -z "$input" ]; then
                value="$(kl_load_from_file "$file" "$sensitivity")"
            else
                value="$input"
                kl_write_to_file "$file" "$value" "$sensitivity"
            fi
        else
            # unassisted: reuse cached value; optional small grace period
            printf '%s\n' "$prompt" >&2
            kl_unassisted_wait "cached value for $key" 2
            value="$(kl_load_from_file "$file" "$sensitivity")"
        fi
    else
        # No cache yet
        if [ "$run_mode" = "interactive" ]; then
            if [ -n "$default_value" ]; then
                printf '%s [default: %s]\n' "$prompt" "$default_value" >&2
            else
                printf '%s\n' "$prompt" >&2
            fi
            printf '> ' >&2
            # shellcheck disable=SC2162
            read input || input=""
            if [ -z "$input" ] && [ -n "$default_value" ]; then
                value="$default_value"
            else
                value="$input"
            fi
            if [ -n "$value" ]; then
                kl_write_to_file "$file" "$value" "$sensitivity"
            fi
        else
            # unassisted mode
            if [ -n "$default_value" ]; then
                printf '%s\n' "$prompt" >&2
                printf '[no cache, will use default "%s"]\n' "$default_value" >&2
                kl_unassisted_wait "default for $key" 3
                value="$default_value"
                kl_write_to_file "$file" "$value" "$sensitivity"
            else
                # No cache and no default: cannot proceed silently
                printf '%s\n' "$prompt" >&2
                printf '[no cache and no default for "%s" – waiting for manual input]\n' "$key" >&2
                printf '> ' >&2
                # shellcheck disable=SC2162
                read input || input=""
                value="$input"
                if [ -n "$value" ]; then
                    kl_write_to_file "$file" "$value" "$sensitivity"
                fi
            fi
        fi
    fi

    # Export value into the requested variable name
    # shellcheck disable=SC2086
    eval "$var_name=\"\$value\""
}

# Optional helper to purge all cached inputs for the current repo.
kl_purge_cache_for_repo() {
    dir="$(kl_cache_dir)"
    printf 'Delete all cached inputs for this repository in "%s"? [y/N] ' "$dir" >&2
    # shellcheck disable=SC2162
    read answer || answer=""
    case "$answer" in
        y|Y)
            rm -rf -- "$dir"
            printf 'Cache deleted.\n' >&2
            ;;
        *)
            printf 'Keeping cache.\n' >&2
            ;;
    esac
}
