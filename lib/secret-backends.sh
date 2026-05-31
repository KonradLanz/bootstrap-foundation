#!/bin/sh
# lib/secret-backends.sh
#
# Credential backend library for bootstrap-foundation.
#
# Provides read/write helpers for three backends:
#   plain      - plain text (non-sensitive convenience values)
#   gpg        - symmetric AES-256 via GnuPG
#   keepassxc  - keepassxc-cli against a .kdbx database
#
# This file is designed to be sourced. It defines functions only;
# it does not execute anything on source.
#
# Environment variables (all optional, have defaults):
#   KEEPASSXC_CLI        path/name of keepassxc-cli  (default: keepassxc-cli)
#   KL_KEEPASS_DB        path to .kdbx file          (default: ~/KeePassLatest.kdbx)
#   KL_KEEPASS_GROUP     root group inside .kdbx      (default: bootstrap-foundation)
#   KL_KEEPASS_PASS      master password (env, skips prompt)
#   CREDENTIAL_BACKEND   plain | gpg | keepassxc | auto
#
# Auto-detection order (when CREDENTIAL_BACKEND=auto or unset):
#   keepassxc  -> gpg  -> plain

: "${KEEPASSXC_CLI:=keepassxc-cli}"
: "${KL_KEEPASS_DB:=${HOME}/KeePassLatest.kdbx}"
: "${KL_KEEPASS_GROUP:=bootstrap-foundation}"

# Session-level master password (populated once per process, never written to disk)
KL_KEEPASS_PASS_SESSION=""

# ---------------------------------------------------------------------------
# sb_detect_backend
# Prints the effective backend name to stdout.
# ---------------------------------------------------------------------------
sb_detect_backend() {
    case "${CREDENTIAL_BACKEND:-auto}" in
        plain|gpg|keepassxc) printf '%s' "${CREDENTIAL_BACKEND}" ; return ;;
    esac
    # auto
    if command -v "$KEEPASSXC_CLI" >/dev/null 2>&1 && [ -f "$KL_KEEPASS_DB" ]; then
        printf 'keepassxc'
    elif command -v gpg >/dev/null 2>&1; then
        printf 'gpg'
    else
        printf 'plain'
    fi
}

# ---------------------------------------------------------------------------
# KeePassXC helpers
# ---------------------------------------------------------------------------

_sb_kp_unlock() {
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

_sb_kp_entry() {
    printf '%s/%s' "$KL_KEEPASS_GROUP" "$1"
}

# sb_keepass_available
# Returns 0 if keepassxc-cli is usable and DB file exists.
sb_keepass_available() {
    command -v "$KEEPASSXC_CLI" >/dev/null 2>&1 || return 1
    [ -f "$KL_KEEPASS_DB" ] || return 1
}

# sb_keepass_read KEY
# Prints the stored password for KEY to stdout (empty if not found).
sb_keepass_read() {
    _sb_kp_unlock
    entry="$(_sb_kp_entry "$1")"
    printf '%s\n' "$KL_KEEPASS_PASS_SESSION" \
        | "$KEEPASSXC_CLI" show -a password --no-password \
            "$KL_KEEPASS_DB" "$entry" 2>/dev/null || true
}

# sb_keepass_write KEY VALUE [USERNAME]
# Creates or updates the entry for KEY with VALUE.
sb_keepass_write() {
    key="$1"; value="$2"; username="${3:-bootstrap}"
    _sb_kp_unlock
    entry="$(_sb_kp_entry "$key")"
    exists=$(printf '%s\n' "$KL_KEEPASS_PASS_SESSION" \
        | "$KEEPASSXC_CLI" locate --no-password \
            "$KL_KEEPASS_DB" "$entry" 2>/dev/null || true)
    if [ -n "$exists" ]; then
        printf '%s\n' "$KL_KEEPASS_PASS_SESSION" \
            | "$KEEPASSXC_CLI" edit --no-password \
                --username "$username" --password "$value" \
                "$KL_KEEPASS_DB" "$entry" >/dev/null 2>&1 || true
    else
        printf '%s\n' "$KL_KEEPASS_PASS_SESSION" \
            | "$KEEPASSXC_CLI" add --no-password \
                --username "$username" --password "$value" \
                "$KL_KEEPASS_DB" "$entry" >/dev/null 2>&1 || true
    fi
}

# ---------------------------------------------------------------------------
# GPG helpers
# ---------------------------------------------------------------------------

# sb_gpg_read FILE
# Decrypts FILE and prints value to stdout.
sb_gpg_read() {
    gpg --batch --quiet --decrypt "$1" 2>/dev/null
}

# sb_gpg_write FILE VALUE
# Symmetrically encrypts VALUE into FILE.
sb_gpg_write() {
    printf '%s' "$2" | gpg --batch --yes --symmetric --cipher-algo AES256 -o "$1"
}

# ---------------------------------------------------------------------------
# Plain helpers
# ---------------------------------------------------------------------------

sb_plain_read() { cat "$1"; }
sb_plain_write() { printf '%s\n' "$2" > "$1"; }

# ---------------------------------------------------------------------------
# sb_read  BACKEND CACHE_FILE_OR_KEY  ->  stdout
# sb_write BACKEND CACHE_FILE_OR_KEY VALUE [kp_username]
#
# Unified read/write that dispatches to the right backend.
# For keepassxc: CACHE_FILE_OR_KEY is the logical key (e.g. forge/admin_pass).
# For gpg/plain: CACHE_FILE_OR_KEY is a filesystem path.
# ---------------------------------------------------------------------------
sb_read() {
    backend="$1"; target="$2"
    case "$backend" in
        keepassxc) sb_keepass_read "$target" ;;
        gpg)       sb_gpg_read "$target" ;;
        *)         sb_plain_read "$target" ;;
    esac
}

sb_write() {
    backend="$1"; target="$2"; value="$3"; extra="${4:-bootstrap}"
    case "$backend" in
        keepassxc) sb_keepass_write "$target" "$value" "$extra" ;;
        gpg)       sb_gpg_write "$target" "$value" ;;
        *)         sb_plain_write "$target" "$value" ;;
    esac
}
