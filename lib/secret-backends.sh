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

# Script directory — used to locate init-keepass-db.sh
_SB_LIB_DIR=$(cd "$(dirname "$0")" 2>/dev/null && pwd || printf '%s' "${HOME}")

# Session-level master password (populated once per process, never written to disk)
KL_KEEPASS_PASS_SESSION=""

# ---------------------------------------------------------------------------
# sb_detect_backend
# Prints the effective backend name to stdout.
# ---------------------------------------------------------------------------
sb_detect_backend() {
    case "${CREDENTIAL_BACKEND:-auto}" in
        plain|gpg|keepassxc|vaultwarden) printf '%s' "${CREDENTIAL_BACKEND}" ; return ;;
    esac
    # auto -- Prioritaet: vaultwarden > keepassxc > gpg > plain
    # Vaultwarden nur wenn BW_SESSION aktiv und unlocked (kein Prompt hier)
    if [ -n "${BW_SESSION:-}" ] && command -v bw >/dev/null 2>&1; then
        _bw_st=$(bw status --session "$BW_SESSION" 2>/dev/null \
            | python3 -c "import sys,json; print(json.load(sys.stdin).get('status',''))" \
            2>/dev/null || true)
        if [ "$_bw_st" = "unlocked" ]; then
            printf 'vaultwarden'; return
        fi
    fi
    if command -v "$KEEPASSXC_CLI" >/dev/null 2>&1 && [ -f "$KL_KEEPASS_DB" ]; then
        printf 'keepassxc'
    elif command -v gpg >/dev/null 2>&1; then
        printf 'gpg'
    else
        printf 'plain'
    fi
}

# ---------------------------------------------------------------------------
# sb_ensure_keepass_db
# Called automatically before the first keepassxc write.
# If KL_KEEPASS_DB does not exist yet, locates init-keepass-db.sh and runs it.
# ---------------------------------------------------------------------------
sb_ensure_keepass_db() {
    [ -f "$KL_KEEPASS_DB" ] && return 0

    # Locate init-keepass-db.sh relative to this library file.
    # Callers source this lib from various directories, so we search upward.
    _init_script=""
    _search_dir="$_SB_LIB_DIR"
    _depth=0
    while [ "$_depth" -lt 5 ]; do
        _candidate="${_search_dir}/services/forge/init-keepass-db.sh"
        if [ -f "$_candidate" ]; then
            _init_script="$_candidate"
            break
        fi
        _parent=$(dirname "$_search_dir")
        [ "$_parent" = "$_search_dir" ] && break
        _search_dir="$_parent"
        _depth=$((_depth + 1))
    done

    if [ -z "$_init_script" ]; then
        printf '[WARN]  KeePass-DB nicht gefunden und init-keepass-db.sh nicht lokalisierbar.\n' >&2
        printf '[WARN]  Bitte manuell ausfuehren: bash services/forge/init-keepass-db.sh\n' >&2
        return 1
    fi

    printf '\n[INFO]  KeePass-Datenbank existiert noch nicht.\n' >&2
    printf '[INFO]  Ersteinrichtung wird gestartet...\n\n' >&2
    # Export relevant env vars so init script picks them up
    export KL_KEEPASS_DB KL_KEEPASS_GROUP KEEPASSXC_CLI
    bash "$_init_script"
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
# Auto-initialises the DB if it does not exist yet.
sb_keepass_write() {
    key="$1"; value="$2"; username="${3:-bootstrap}"
    # Lazy init: create DB on first write if it does not exist
    sb_ensure_keepass_db || return 1
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
# Vaultwarden helpers (bw CLI)
#
# Delegiert an lib/bw-session.sh wenn vorhanden.
# KEY ist der logische Cache-Key (z.B. "nas/ssh_pass").
# Item-Name in Vaultwarden: "kl: nas/ssh_pass"
# ---------------------------------------------------------------------------

_sb_bw_session_lib() {
    # Lokalisiert bw-session.sh relativ zu diesem File
    # BASH_SOURCE[0] funktioniert auch bei 'source', $0 nicht
    _self="${BASH_SOURCE[0]:-${(%):-%x}}"
    _dir=$(cd "$(dirname "$_self")" 2>/dev/null && pwd || printf '%s/lib' "${KL_BOOTSTRAP_ROOT:-$HOME}")
    for _candidate in \
        "${KL_BOOTSTRAP_ROOT:-}/lib/bw-session.sh" \
        "${_dir}/bw-session.sh" \
        "${_dir}/../lib/bw-session.sh"
    do
        [ -f "$_candidate" ] && printf '%s' "$_candidate" && return
    done
}

_sb_bw_sourced=0
_sb_ensure_bw() {
    [ "$_sb_bw_sourced" = "1" ] && return 0
    _lib=$(_sb_bw_session_lib)
    [ -z "$_lib" ] && return 1
    # shellcheck source=/dev/null
    . "$_lib"
    _sb_bw_sourced=1
}

sb_vaultwarden_available() {
    _sb_ensure_bw || return 1
    command -v bw >/dev/null 2>&1 || return 1
    bw status 2>/dev/null | python3 -c \
        "import sys,json; s=json.load(sys.stdin); exit(0 if s.get('status')=='unlocked' else 1)" \
        2>/dev/null
}

# KEY -> stdout (leer wenn nicht gefunden)
sb_vaultwarden_read() {
    _sb_ensure_bw || return 0
    kl_bw_get "$1"
}

# KEY VALUE
sb_vaultwarden_write() {
    _sb_ensure_bw || return 0
    kl_bw_set "$1" "$2"
}

# KEY
sb_vaultwarden_delete() {
    _sb_ensure_bw || return 0
    kl_bw_delete "$1"
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
        vaultwarden) sb_vaultwarden_read "$target" ;;
        keepassxc)   sb_keepass_read "$target" ;;
        gpg)         sb_gpg_read "$target" ;;
        *)           sb_plain_read "$target" ;;
    esac
}

sb_write() {
    backend="$1"; target="$2"; value="$3"; extra="${4:-bootstrap}"
    case "$backend" in
        vaultwarden) sb_vaultwarden_write "$target" "$value" ;;
        keepassxc)   sb_keepass_write "$target" "$value" "$extra" ;;
        gpg)         sb_gpg_write "$target" "$value" ;;
        *)           sb_plain_write "$target" "$value" ;;
    esac
}
