#!/usr/bin/env bash
# services/forge/create-token.sh
# ---------------------------------------------------------------------------
# Erstellt einen API-Token fuer einen Forgejo/Gitea-User und speichert
# ihn im konfigurierten Credential-Backend (KeePass / GPG / plain).
# Idempotent: existierender Token unter gleichem Namen wird zurueckgegeben
# (falls noch im Backend vorhanden) oder neu erstellt.
#
# Aufruf:
#   bash services/forge/create-token.sh <username> [--token-name <name>]
#
# Optionen:
#   --url <url>         Forgejo-Basis-URL    (default: https://forgejo.own.dedyn.io)
#   --admin-user <u>    Admin fuer API-Auth  (default: forgejo-admin)
#   --token-name <n>    Name des API-Tokens  (default: bootstrap-token)
#   --scopes <s>        Token-Scopes         (default: write:repository,read:user)
# ---------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
. "${REPO_ROOT}/lib/secret-backends.sh"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[1;36m'; RED='\033[0;31m'; NC='\033[0m'
info()  { printf "${BLUE}[INFO]${NC}    %s\n" "$*"; }
ok()    { printf "${GREEN}[OK]${NC}      %s\n" "$*"; }
warn()  { printf "${YELLOW}[WARN]${NC}    %s\n" "$*"; }
error() { printf "${RED}[ERROR]${NC}   %s\n" "$*" >&2; exit 1; }

# ── Argumente ────────────────────────────────────────────────────────────────
FORGEJO_URL="${FORGEJO_URL:-https://forgejo.own.dedyn.io}"
ADMIN_USER="${FORGEJO_ADMIN_USER:-forgejo-admin}"
TOKEN_NAME="bootstrap-token"
SCOPES="write:repository,read:user"
USERNAME=""

while [ $# -gt 0 ]; do
    case "$1" in
        --url)          FORGEJO_URL="$2"; shift ;;
        --admin-user)   ADMIN_USER="$2"; shift ;;
        --token-name)   TOKEN_NAME="$2"; shift ;;
        --scopes)       SCOPES="$2"; shift ;;
        --*)            error "Unbekannte Option: $1" ;;
        *)              USERNAME="$1" ;;
    esac
    shift
done

[ -z "$USERNAME" ] && error "Usage: $0 [options] <username>"

# ── Backend + Cache-Pfade ──────────────────────────────────────────────────
BACKEND=$(sb_detect_backend)
CACHE_DIR="${HOME}/.cache/kl-input-cache/forge"; mkdir -p "$CACHE_DIR"
_target() { [ "$BACKEND" = "keepassxc" ] && printf '%s' "$1" || printf '%s' "$2"; }

ADMIN_PW_KEY="forge/${ADMIN_USER}_pass"
ADMIN_PW_FILE="${CACHE_DIR}/${ADMIN_USER}_pass"
TOKEN_KEY="forge/${USERNAME}_token_${TOKEN_NAME}"
TOKEN_FILE="${CACHE_DIR}/${USERNAME}_token_${TOKEN_NAME}"

# ── Admin-Passwort lesen ──────────────────────────────────────────────────────
ADMIN_PASS=$(sb_read "$BACKEND" "$(_target "$ADMIN_PW_KEY" "$ADMIN_PW_FILE")" 2>/dev/null || true)
if [ -z "$ADMIN_PASS" ]; then
    printf "${YELLOW}[INPUT]${NC}   Forgejo-Passwort fuer Admin '%s': " "$ADMIN_USER" >&2
    stty -echo 2>/dev/null || true; read -r ADMIN_PASS; stty echo 2>/dev/null || true; printf '\n' >&2
    sb_write "$BACKEND" "$(_target "$ADMIN_PW_KEY" "$ADMIN_PW_FILE")" "$ADMIN_PASS" "$ADMIN_USER" 2>/dev/null || true
fi

# ── Token aus Backend lesen (Idempotenz) ──────────────────────────────────────
EXISTING_TOKEN=$(sb_read "$BACKEND" "$(_target "$TOKEN_KEY" "$TOKEN_FILE")" 2>/dev/null || true)
if [ -n "$EXISTING_TOKEN" ]; then
    ok "Token '${TOKEN_NAME}' fuer '${USERNAME}' bereits im Backend — gebe zurueck."
    printf '\n  TOKEN: %s\n\n' "$EXISTING_TOKEN"
    exit 0
fi

# ── Alten Token mit gleichem Namen loeschen (API erlaubt keine Duplikate) ────
info "Loesche ggf. vorhandenen Token '${TOKEN_NAME}' fuer '${USERNAME}' per API..."
TOKEN_ID=$(curl -s \
    -u "${ADMIN_USER}:${ADMIN_PASS}" \
    "${FORGEJO_URL}/api/v1/users/${USERNAME}/tokens" \
    | grep -o '"id":[0-9]*' | grep -o '[0-9]*' | head -1 || true)
# Einfacher: alle Token listen und nach Name filtern
TOKEN_LIST=$(curl -s -u "${ADMIN_USER}:${ADMIN_PASS}" \
    "${FORGEJO_URL}/api/v1/users/${USERNAME}/tokens" 2>/dev/null || echo '[]')
TOKEN_ID=$(printf '%s' "$TOKEN_LIST" \
    | grep -o '{[^}]*"name":"'"${TOKEN_NAME}"'"[^}]*}' \
    | grep -o '"id":[0-9]*' | grep -o '[0-9]*' | head -1 || true)

if [ -n "$TOKEN_ID" ]; then
    curl -s -X DELETE \
        -u "${ADMIN_USER}:${ADMIN_PASS}" \
        "${FORGEJO_URL}/api/v1/users/${USERNAME}/tokens/${TOKEN_ID}" >/dev/null
    info "Alter Token '${TOKEN_NAME}' (id=${TOKEN_ID}) geloescht."
fi

# ── Neuen Token erstellen ──────────────────────────────────────────────────────────
info "Erstelle Token '${TOKEN_NAME}' fuer '${USERNAME}' (scopes: ${SCOPES})..."
RESPONSE=$(curl -s -w "\n%{http_code}" \
    -X POST \
    -H "Content-Type: application/json" \
    -u "${ADMIN_USER}:${ADMIN_PASS}" \
    "${FORGEJO_URL}/api/v1/users/${USERNAME}/tokens" \
    -d "$(printf '{"name":"%s","scopes":["%s"]}' \
        "$TOKEN_NAME" "$(printf '%s' "$SCOPES" | sed 's/,/","/g')")"
)
HTTP_CODE=$(printf '%s' "$RESPONSE" | tail -1)
BODY=$(printf '%s' "$RESPONSE" | head -n -1)

if [ "$HTTP_CODE" = "201" ]; then
    NEW_TOKEN=$(printf '%s' "$BODY" | grep -o '"sha1":"[^"]*"' | cut -d'"' -f4)
    if [ -z "$NEW_TOKEN" ]; then
        error "Token erstellt aber sha1 nicht in Response gefunden: ${BODY}"
    fi
    # In Backend speichern
    sb_write "$BACKEND" "$(_target "$TOKEN_KEY" "$TOKEN_FILE")" "$NEW_TOKEN" "$USERNAME" 2>/dev/null || true
    ok "Token '${TOKEN_NAME}' fuer '${USERNAME}' erstellt und gespeichert."
    printf '\n  TOKEN: %s\n\n' "$NEW_TOKEN"
else
    error "API-Fehler ${HTTP_CODE}: ${BODY}"
fi
