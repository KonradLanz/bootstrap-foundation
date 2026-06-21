#!/usr/bin/env bash
# services/forge/create-repo.sh
# ---------------------------------------------------------------------------
# Legt ein privates Repository ueber die Forgejo/Gitea REST-API an.
# Idempotent: existierendes Repo wird nicht ueberschrieben.
#
# Aufruf:
#   bash services/forge/create-repo.sh <owner> <repo-name>
#   bash services/forge/create-repo.sh --org myorg myrepo
#
# Optionen:
#   --url <url>         Forgejo-Basis-URL   (default: https://forgejo.own.dedyn.io)
#   --admin-user <u>    Admin fuer API-Auth (default: forgejo-admin)
#   --org               Owner ist eine Organisation (statt User)
#   --public            Repo oeffentlich anlegen (default: privat)
#   --description <d>   Repo-Beschreibung
#   --init              README.md initial anlegen
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
IS_ORG=0
IS_PUBLIC=0
DESCRIPTION=""
INIT_README=0
OWNER=""
REPO_NAME=""

while [ $# -gt 0 ]; do
    case "$1" in
        --url)          FORGEJO_URL="$2"; shift ;;
        --admin-user)   ADMIN_USER="$2"; shift ;;
        --org)          IS_ORG=1 ;;
        --public)       IS_PUBLIC=1 ;;
        --description)  DESCRIPTION="$2"; shift ;;
        --init)         INIT_README=1 ;;
        --*)            error "Unbekannte Option: $1" ;;
        *)  [ -z "$OWNER" ] && { OWNER="$1"; } || { REPO_NAME="$1"; } ;;
    esac
    shift
done

[ -z "$OWNER" ]     && error "Usage: $0 [options] <owner> <repo-name>"
[ -z "$REPO_NAME" ] && error "Usage: $0 [options] <owner> <repo-name>"

# ── Admin-Passwort lesen ──────────────────────────────────────────────────────
BACKEND=$(sb_detect_backend)
CACHE_DIR="${HOME}/.cache/kl-input-cache/forge"; mkdir -p "$CACHE_DIR"
ADMIN_PW_KEY="forge/${ADMIN_USER}_pass"
ADMIN_PW_FILE="${CACHE_DIR}/${ADMIN_USER}_pass"
_target() { [ "$BACKEND" = "keepassxc" ] && printf '%s' "$1" || printf '%s' "$2"; }

ADMIN_PASS=$(sb_read "$BACKEND" "$(_target "$ADMIN_PW_KEY" "$ADMIN_PW_FILE")" 2>/dev/null || true)
if [ -z "$ADMIN_PASS" ]; then
    printf "${YELLOW}[INPUT]${NC}   Forgejo-Passwort fuer Admin '%s': " "$ADMIN_USER" >&2
    stty -echo 2>/dev/null || true; read -r ADMIN_PASS; stty echo 2>/dev/null || true; printf '\n' >&2
    sb_write "$BACKEND" "$(_target "$ADMIN_PW_KEY" "$ADMIN_PW_FILE")" "$ADMIN_PASS" "$ADMIN_USER" 2>/dev/null || true
fi

# ── Idempotenz-Check: Repo existiert? ─────────────────────────────────────────
info "Pruefe ob Repo '${OWNER}/${REPO_NAME}' existiert..."
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    -u "${ADMIN_USER}:${ADMIN_PASS}" \
    "${FORGEJO_URL}/api/v1/repos/${OWNER}/${REPO_NAME}")

if [ "$HTTP_STATUS" = "200" ]; then
    ok "Repo '${OWNER}/${REPO_NAME}' existiert bereits — ueberspringe."
    printf '\n  URL: %s/%s/%s\n\n' "$FORGEJO_URL" "$OWNER" "$REPO_NAME"
    exit 0
fi

# ── Repo anlegen ─────────────────────────────────────────────────────────────
if [ "$IS_ORG" = "1" ]; then
    API_PATH="/api/v1/orgs/${OWNER}/repos"
else
    API_PATH="/api/v1/user/repos"  # als Admin, setzt owner explizit
fi

PRIVATE=$([ "$IS_PUBLIC" = "1" ] && echo false || echo true)
AUTO_INIT=$([ "$INIT_README" = "1" ] && echo true || echo false)

info "Lege Repo '${OWNER}/${REPO_NAME}' an (privat=${PRIVATE})..."
RESPONSE=$(curl -s -w "\n%{http_code}" \
    -X POST \
    -H "Content-Type: application/json" \
    -u "${ADMIN_USER}:${ADMIN_PASS}" \
    "${FORGEJO_URL}${API_PATH}" \
    -d "$(printf '{"name":"%s","description":"%s","private":%s,"auto_init":%s,"owner":"%s"}' \
        "$REPO_NAME" "$DESCRIPTION" "$PRIVATE" "$AUTO_INIT" "$OWNER")")

HTTP_CODE=$(printf '%s' "$RESPONSE" | tail -1)
BODY=$(printf '%s' "$RESPONSE" | head -n -1)

if [ "$HTTP_CODE" = "201" ]; then
    ok "Repo '${OWNER}/${REPO_NAME}' angelegt."
    printf '\n  URL: %s/%s/%s\n\n' "$FORGEJO_URL" "$OWNER" "$REPO_NAME"
elif [ "$HTTP_CODE" = "409" ]; then
    warn "Repo existiert bereits (409) — OK."
else
    error "API-Fehler ${HTTP_CODE}: ${BODY}"
fi
