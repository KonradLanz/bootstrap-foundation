#!/usr/bin/env bash
# services/forge/create-user.sh
#
# Legt einen Forgejo-User an:
#   1. Generiert ein sicheres Passwort (32 Zeichen)
#   2. Speichert es im konfigurierten Credential-Backend
#      (keepassxc -> gpg -> plain, auto-detected)
#   3. Legt den User ueber die Forgejo-API an
#   4. Optional: erstellt einen API-Token und speichert ihn ebenfalls
#
# Aufruf:
#   bash services/forge/create-user.sh [--admin] <username>
#
# Optionen:
#   --admin             User erhaelt Forgejo-Admin-Rechte
#   --no-token          Kein API-Token erstellen
#   --url <url>         Forgejo-Basis-URL (default: http://localhost:3000)
#   --admin-user <u>    Forgejo-Admin fuer API-Calls (default: forgejo-admin)
#
# Credential-Backend-Overrides (Umgebungsvariablen):
#   CREDENTIAL_BACKEND  plain | gpg | keepassxc | auto
#   KL_KEEPASS_DB       Pfad zur .kdbx
#   KL_KEEPASS_GROUP    Root-Gruppe (default: bootstrap-foundation)
#   KEEPASSXC_CLI       Pfad zu keepassxc-cli
################################################################################
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# ── Credential-Library laden ──────────────────────────────────────────────────
# shellcheck source=../../lib/secret-backends.sh
. "${REPO_ROOT}/lib/secret-backends.sh"

# ── Farben ────────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;36m'
RED='\033[0;31m'
NC='\033[0m'

info()    { printf "${BLUE}[INFO]${NC}    %s\n" "$*"; }
ok()      { printf "${GREEN}[OK]${NC}      %s\n" "$*"; }
warn()    { printf "${YELLOW}[WARN]${NC}    %s\n" "$*"; }
error()   { printf "${RED}[ERROR]${NC}   %s\n" "$*" >&2; exit 1; }

# ── Argumente parsen ──────────────────────────────────────────────────────────
IS_ADMIN=0
CREATE_TOKEN=1
FORGEJO_URL="${FORGEJO_URL:-http://localhost:3000}"
ADMIN_USER="${FORGEJO_ADMIN_USER:-forgejo-admin}"
USERNAME=""

while [ $# -gt 0 ]; do
    case "$1" in
        --admin)        IS_ADMIN=1 ;;
        --no-token)     CREATE_TOKEN=0 ;;
        --url)          FORGEJO_URL="$2"; shift ;;
        --admin-user)   ADMIN_USER="$2"; shift ;;
        --*)            error "Unbekannte Option: $1" ;;
        *)              USERNAME="$1" ;;
    esac
    shift
done

[ -z "$USERNAME" ] && error "Usage: $0 [--admin] [--no-token] [--url <url>] <username>"

# ── Backend erkennen ──────────────────────────────────────────────────────────
BACKEND=$(sb_detect_backend)
info "Credential-Backend: $BACKEND"

# ── Cache-Pfade fuer gpg/plain ────────────────────────────────────────────────
# Fuer keepassxc sind diese keys, fuer gpg/plain Dateipfade.
CACHE_DIR="${HOME}/.cache/kl-input-cache/forge"
mkdir -p "$CACHE_DIR"
PW_KEY="forge/${USERNAME}_pass"
PW_FILE="${CACHE_DIR}/${USERNAME}_pass"
TOKEN_KEY="forge/${USERNAME}_token"
TOKEN_FILE="${CACHE_DIR}/${USERNAME}_token"
ADMIN_PW_KEY="forge/${ADMIN_USER}_pass"
ADMIN_PW_FILE="${CACHE_DIR}/${ADMIN_USER}_pass"

_target() {
    if [ "$BACKEND" = "keepassxc" ]; then printf '%s' "$1"
    else printf '%s' "$2"; fi
}

# ── Passwort generieren ───────────────────────────────────────────────────────
# 32 druckbare ASCII-Zeichen (kein Backslash, kein Anführungszeichen)
# um Shell- und JSON-Escaping zu vermeiden.
_gen_password() {
    # openssl ist auf QNAP, macOS und Linux verfuegbar
    if command -v openssl >/dev/null 2>&1; then
        openssl rand -base64 48 \
            | tr -d '/+\n' \
            | tr -dc 'A-Za-z0-9!@#%^&*()-_=+[]{}|;:,.<>?' \
            | head -c 32
    else
        # Fallback: /dev/urandom
        tr -dc 'A-Za-z0-9!@#%^&*()-_=+[]{}|;:,.<>?' < /dev/urandom \
            | head -c 32
    fi
}

# ── Admin-Passwort aus Backend lesen (fuer API-Calls) ─────────────────────────
_get_admin_password() {
    _adm_target=$(_target "$ADMIN_PW_KEY" "$ADMIN_PW_FILE")
    _adm_pw=$(sb_read "$BACKEND" "$_adm_target" 2>/dev/null || true)
    if [ -z "$_adm_pw" ]; then
        printf "${YELLOW}[INPUT]${NC}   Forgejo-Passwort fuer Admin '%s': " "$ADMIN_USER" >&2
        stty -echo 2>/dev/null || true
        read -r _adm_pw
        stty echo  2>/dev/null || true
        printf '\n' >&2
        # In Backend speichern damit nachfolgende Aufrufe es haben
        sb_write "$BACKEND" "$(_target "$ADMIN_PW_KEY" "$ADMIN_PW_FILE")" \
                 "$_adm_pw" "$ADMIN_USER" 2>/dev/null || true
    fi
    printf '%s' "$_adm_pw"
}

# ── Neues Passwort generieren und speichern ───────────────────────────────────
PW_TARGET=$(_target "$PW_KEY" "$PW_FILE")

# Bestehendes Passwort pruefen
EXISTING=$(sb_read "$BACKEND" "$PW_TARGET" 2>/dev/null || true)
if [ -n "$EXISTING" ]; then
    warn "Passwort fuer '$USERNAME' bereits im Backend vorhanden."
    printf "${YELLOW}[INPUT]${NC}   Ueberschreiben? [j/N] " >&2
    read -r _overwrite
    case "$_overwrite" in
        [jJyY]*) info "Generiere neues Passwort..." ;;
        *) NEW_PASS="$EXISTING"; info "Bestehendes Passwort wird verwendet."; SKIP_GEN=1 ;;
    esac
fi

SKIP_GEN="${SKIP_GEN:-0}"
if [ "$SKIP_GEN" = "0" ]; then
    NEW_PASS=$(_gen_password)
    sb_write "$BACKEND" "$PW_TARGET" "$NEW_PASS" "$USERNAME"
    ok "Passwort generiert und in '$BACKEND' gespeichert."
fi

# Kurze Anzeige im Terminal (einmalig)
printf '\n'
info "Generiertes Passwort fuer '%s':" "$USERNAME"
printf '  %s\n\n' "$NEW_PASS"
info "(Passwort steht dauerhaft im Backend '$BACKEND' — nicht notieren.)"
printf '\n'

# ── Forgejo-API: User anlegen ─────────────────────────────────────────────────
info "Lege Forgejo-User '$USERNAME' an via API..."

ADMIN_PASS=$(_get_admin_password)

# JSON sicher zusammenbauen
IS_ADMIN_BOOL="false"
[ "$IS_ADMIN" = "1" ] && IS_ADMIN_BOOL="true"

API_PAYLOAD=$(printf '{"username":"%s","password":"%s","email":"%s@localhost","must_change_password":false,"source_id":0,"login_name":"%s","send_notify":false}' \
    "$USERNAME" "$NEW_PASS" "$USERNAME" "$USERNAME")

HTTP_CODE=$(curl -s -o /tmp/forge_create_out.json -w '%{http_code}' \
    -X POST "${FORGEJO_URL}/api/v1/admin/users" \
    -u "${ADMIN_USER}:${ADMIN_PASS}" \
    -H 'Content-Type: application/json' \
    -d "$API_PAYLOAD") || true

if [ "$HTTP_CODE" = "201" ]; then
    ok "User '$USERNAME' in Forgejo angelegt (HTTP 201)."
elif [ "$HTTP_CODE" = "422" ]; then
    warn "User '$USERNAME' existiert moeglicherweise bereits (HTTP 422)."
    cat /tmp/forge_create_out.json 2>/dev/null | grep -o '"message":"[^"]*"' || true
    printf '\n'
else
    warn "Unerwarteter HTTP-Status: $HTTP_CODE"
    cat /tmp/forge_create_out.json 2>/dev/null || true
    printf '\n'
fi
rm -f /tmp/forge_create_out.json

# ── Admin-Rechte setzen (falls --admin) ───────────────────────────────────────
if [ "$IS_ADMIN" = "1" ]; then
    info "Setze Admin-Flag fuer '$USERNAME'..."
    HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' \
        -X PATCH "${FORGEJO_URL}/api/v1/admin/users/${USERNAME}" \
        -u "${ADMIN_USER}:${ADMIN_PASS}" \
        -H 'Content-Type: application/json' \
        -d '{"admin":true,"source_id":0,"login_name":"'"$USERNAME"'"}') || true
    [ "$HTTP_CODE" = "200" ] && ok "Admin-Flag gesetzt." \
        || warn "Admin-Flag: HTTP $HTTP_CODE (evtl. bereits gesetzt)"
fi

# ── API-Token erstellen ───────────────────────────────────────────────────────
if [ "$CREATE_TOKEN" = "1" ]; then
    info "Erstelle API-Token fuer '$USERNAME'..."
    TOKEN_PAYLOAD=$(printf '{"name":"bootstrap-token","scopes":["write:repository","write:issue","read:user"]}' )

    TOKEN_RESPONSE=$(curl -s \
        -X POST "${FORGEJO_URL}/api/v1/users/${USERNAME}/tokens" \
        -u "${USERNAME}:${NEW_PASS}" \
        -H 'Content-Type: application/json' \
        -d "$TOKEN_PAYLOAD") || true

    TOKEN_VALUE=$(printf '%s' "$TOKEN_RESPONSE" | grep -o '"sha1":"[^"]*"' | cut -d'"' -f4 || true)

    if [ -n "$TOKEN_VALUE" ]; then
        TOKEN_TARGET=$(_target "$TOKEN_KEY" "$TOKEN_FILE")
        sb_write "$BACKEND" "$TOKEN_TARGET" "$TOKEN_VALUE" "$USERNAME"
        ok "API-Token erstellt und in '$BACKEND' gespeichert."
    else
        warn "Token-Erstellung fehlgeschlagen oder Token bereits vorhanden."
        printf '%s\n' "$TOKEN_RESPONSE" | grep -o '"message":"[^"]*"' || true
    fi
fi

# ── Abschluss ─────────────────────────────────────────────────────────────────
printf '\n'
ok  "Fertig: User '$USERNAME' (admin=$IS_ADMIN_BOOL, backend=$BACKEND)"
info "Passwort abrufen: sb_read $BACKEND '${PW_TARGET}'"
if [ "$CREATE_TOKEN" = "1" ]; then
    TOKEN_TARGET=$(_target "$TOKEN_KEY" "$TOKEN_FILE")
    info "Token abrufen:   sb_read $BACKEND '${TOKEN_TARGET}'"
fi
printf '\n'
