#!/usr/bin/env bash
# services/forge/set-ssh-key.sh
# ---------------------------------------------------------------------------
# Fuegt einen SSH-Key zu Forgejo/Gitea hinzu -- ohne Web UI, ohne Signature.
#
# Zwei Modi:
#   --user-key   Key wird dem User zugeordnet (gilt fuer alle Repos)
#                -> POST /api/v1/user/keys
#   --deploy-key Key wird einem einzelnen Repo zugeordnet (CI/CD)
#                -> POST /api/v1/repos/<owner>/<repo>/keys
#
# Idempotent: existierender Key mit gleichem Titel wird nicht doppelt
# angelegt (prueft per GET vor POST).
#
# Aufruf (User Key):
#   bash services/forge/set-ssh-key.sh <username> \
#     [--url <url>] [--key-file <path>] [--key-title <title>]
#
# Aufruf (Deploy Key):
#   bash services/forge/set-ssh-key.sh <username> \
#     --deploy-key --repo <reponame> \
#     [--url <url>] [--key-file <path>] [--key-title <title>] [--read-only]
#
# Optionen:
#   --url <url>          Forgejo-Basis-URL      (default: https://forgejo.own.dedyn.io)
#   --admin-user <u>     Admin fuer API-Auth    (default: forgejo-admin)
#   --key-file <path>    Pfad zum Public Key    (default: ~/.ssh/id_ed25519.pub)
#   --key-title <title>  Titel des Keys         (default: hostname des lokalen Rechners)
#   --deploy-key         Deploy-Key-Modus (Repo-spezifisch)
#   --repo <name>        Repo-Name (required bei --deploy-key)
#   --read-only          Deploy Key nur lesend  (default: read-write)
# ---------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
. "${REPO_ROOT}/lib/secret-backends.sh"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[1;36m'; RED='\033[0;31m'; NC='\033[0m'
info()  { printf "${BLUE}[INFO]${NC}    %s\n" "$*"; }
ok()    { printf "${GREEN}[OK]${NC}      %s\n" "$*"; }
warn()  { printf "${YELLOW}[WARN]${NC}    %s\n" "$*"; }
die()   { printf "${RED}[ERROR]${NC}   %s\n" "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
FORGE_URL="https://forgejo.own.dedyn.io"
ADMIN_USER="forgejo-admin"
KEY_FILE="${HOME}/.ssh/id_ed25519.pub"
KEY_TITLE="$(hostname -s 2>/dev/null || echo 'mac')"
MODE="user"          # user | deploy
REPO_NAME=""
READ_ONLY="false"
USERNAME=""

# ---------------------------------------------------------------------------
# Args
# ---------------------------------------------------------------------------
[ $# -lt 1 ] && die "Aufruf: $0 <username> [optionen]  (--help fuer Details)"
USERNAME="$1"; shift

while [ $# -gt 0 ]; do
    case "$1" in
        --url)         FORGE_URL="$2";   shift 2 ;;
        --admin-user)  ADMIN_USER="$2";  shift 2 ;;
        --key-file)    KEY_FILE="$2";    shift 2 ;;
        --key-title)   KEY_TITLE="$2";   shift 2 ;;
        --deploy-key)  MODE="deploy";    shift   ;;
        --repo)        REPO_NAME="$2";   shift 2 ;;
        --read-only)   READ_ONLY="true"; shift   ;;
        --help|-h)
            sed -n '2,35p' "$0" | grep '^#' | sed 's/^# \?//'
            exit 0 ;;
        *) die "Unbekannte Option: $1" ;;
    esac
done

[ "$MODE" = "deploy" ] && [ -z "$REPO_NAME" ] && \
    die "--deploy-key benoetigt --repo <reponame>"
[ -f "$KEY_FILE" ] || die "Key-Datei nicht gefunden: $KEY_FILE"

# ---------------------------------------------------------------------------
# Token aus Credential-Backend lesen
# ---------------------------------------------------------------------------
BACKEND=$(sb_detect_backend)
TOKEN_KEY="forge/${ADMIN_USER}_token_bootstrap"
ADMIN_TOKEN=$(sb_read "$BACKEND" "$TOKEN_KEY")

if [ -z "$ADMIN_TOKEN" ]; then
    # Fallback: User-eigenen Token versuchen
    TOKEN_KEY="forge/${USERNAME}_token_bootstrap"
    ADMIN_TOKEN=$(sb_read "$BACKEND" "$TOKEN_KEY")
fi

if [ -z "$ADMIN_TOKEN" ]; then
    warn "Kein Token im Backend ($BACKEND) unter '$TOKEN_KEY'"
    printf "API-Token fuer %s@%s: " "$ADMIN_USER" "$FORGE_URL" >&2
    read -rs ADMIN_TOKEN
    printf '\n' >&2
    [ -z "$ADMIN_TOKEN" ] && die "Kein Token angegeben."
fi

PUB_KEY=$(cat "$KEY_FILE")

# ---------------------------------------------------------------------------
# API-Hilfsfunktionen
# ---------------------------------------------------------------------------
api_get() {
    curl -sf \
        -H "Authorization: token ${ADMIN_TOKEN}" \
        -H "Content-Type: application/json" \
        "${FORGE_URL}/api/v1${1}"
}

api_post() {
    curl -sf \
        -X POST \
        -H "Authorization: token ${ADMIN_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "$2" \
        "${FORGE_URL}/api/v1${1}"
}

# ---------------------------------------------------------------------------
# Instanz pruefen
# ---------------------------------------------------------------------------
info "Pruefe Verbindung zu ${FORGE_URL}..."
VERSION=$(api_get "/version" | python3 -c "import sys,json; print(json.load(sys.stdin).get('version','?'))" 2>/dev/null) \
    || die "Forgejo/Gitea nicht erreichbar: ${FORGE_URL}"
ok "Verbunden: ${FORGE_URL} (${VERSION})"

# ---------------------------------------------------------------------------
# User Key Modus
# ---------------------------------------------------------------------------
if [ "$MODE" = "user" ]; then
    info "Modus: User Key fuer '${USERNAME}'"

    # Als Admin: Key fuer anderen User setzen -> /api/v1/admin/users/<user>/keys
    # Als User selbst: /api/v1/user/keys
    # Wir pruefen zuerst ob wir Admin-Rechte haben
    IS_ADMIN=$(api_get "/users/${USERNAME}" \
        | python3 -c "import sys,json; u=json.load(sys.stdin); print('yes' if u.get('is_admin') else 'no')" \
        2>/dev/null || echo 'no')

    # Bestehende Keys pruefen (immer als der authentifizierte User)
    EXISTING=$(api_get "/user/keys" 2>/dev/null \
        | python3 -c "
import sys, json
keys = json.load(sys.stdin)
for k in keys:
    if k.get('title') == '${KEY_TITLE}':
        print(k['id'])
        break
" 2>/dev/null || true)

    if [ -n "$EXISTING" ]; then
        ok "User Key '${KEY_TITLE}' bereits vorhanden (id=${EXISTING}) -- uebersprungen."
        exit 0
    fi

    # Key hochladen
    PAYLOAD=$(python3 -c "
import json, sys
print(json.dumps({
    'key':       sys.argv[1],
    'read_only': False,
    'title':     sys.argv[2]
}))
" "$PUB_KEY" "$KEY_TITLE")

    RESULT=$(api_post "/user/keys" "$PAYLOAD") \
        || die "Key-Upload fehlgeschlagen. Token-Rechte pruefen (benoetigt: write:user_key)"

    KEY_ID=$(printf '%s' "$RESULT" \
        | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])" 2>/dev/null || echo '?')
    ok "User Key hinzugefuegt: '${KEY_TITLE}' (id=${KEY_ID})"
    info "Gilt fuer alle Repos von '${USERNAME}' auf ${FORGE_URL}"
fi

# ---------------------------------------------------------------------------
# Deploy Key Modus
# ---------------------------------------------------------------------------
if [ "$MODE" = "deploy" ]; then
    info "Modus: Deploy Key fuer '${USERNAME}/${REPO_NAME}' (read-only=${READ_ONLY})"

    # Bestehende Deploy Keys pruefen
    EXISTING=$(api_get "/repos/${USERNAME}/${REPO_NAME}/keys" 2>/dev/null \
        | python3 -c "
import sys, json
keys = json.load(sys.stdin)
for k in keys:
    if k.get('title') == '${KEY_TITLE}':
        print(k['id'])
        break
" 2>/dev/null || true)

    if [ -n "$EXISTING" ]; then
        ok "Deploy Key '${KEY_TITLE}' bereits vorhanden fuer ${USERNAME}/${REPO_NAME} (id=${EXISTING}) -- uebersprungen."
        exit 0
    fi

    PAYLOAD=$(python3 -c "
import json, sys
print(json.dumps({
    'key':       sys.argv[1],
    'read_only': sys.argv[2] == 'true',
    'title':     sys.argv[3]
}))
" "$PUB_KEY" "$READ_ONLY" "$KEY_TITLE")

    RESULT=$(api_post "/repos/${USERNAME}/${REPO_NAME}/keys" "$PAYLOAD") \
        || die "Deploy Key Upload fehlgeschlagen. Repo existiert? Token-Rechte ok?"

    KEY_ID=$(printf '%s' "$RESULT" \
        | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])" 2>/dev/null || echo '?')
    ok "Deploy Key hinzugefuegt: '${KEY_TITLE}' -> ${USERNAME}/${REPO_NAME} (id=${KEY_ID}, read-only=${READ_ONLY})"
fi

# ---------------------------------------------------------------------------
# SSH-Verbindung testen
# ---------------------------------------------------------------------------
FORGE_HOST=$(printf '%s' "$FORGE_URL" | sed 's|https\?://||' | cut -d/ -f1)
info "Teste SSH-Verbindung zu ${FORGE_HOST}..."
SSH_RESULT=$(ssh -i "${KEY_FILE%.pub}" \
    -o IdentitiesOnly=yes \
    -o StrictHostKeyChecking=no \
    -o BatchMode=yes \
    -o ConnectTimeout=5 \
    "git@${FORGE_HOST}" 2>&1 || true)

if printf '%s' "$SSH_RESULT" | grep -qi 'hi\|welcome\|successfully'; then
    ok "SSH-Verbindung erfolgreich: git@${FORGE_HOST}"
else
    warn "SSH-Test nicht eindeutig. Output: ${SSH_RESULT}"
    warn "Manuell testen: ssh -T git@${FORGE_HOST}"
fi

printf '\n'
ok "Fertig. Key '${KEY_TITLE}' ist auf ${FORGE_URL} aktiv."
if [ "$MODE" = "user" ]; then
    printf '\nNaechste Schritte:\n'
    printf '  ssh -T git@%s\n' "$FORGE_HOST"
    printf '  git remote add forgejo git@%s:%s/<repo>.git\n' "$FORGE_HOST" "$USERNAME"
fi
