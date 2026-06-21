#!/usr/bin/env bash
# services/forge/test.sh
# ---------------------------------------------------------------------------
# Regression-Tests fuer Forgejo/Gitea-Instanzen.
#
# Laeuft gegen EINE Instanz pro Aufruf.
# Fuer beide Instanzen ausfuehren:
#   bash services/forge/test.sh --url https://forgejo.own.dedyn.io
#   bash services/forge/test.sh --url https://gitea.own.dedyn.io
#
# Oder mit dem Wrapper:
#   bash services/forge/test.sh --all
#
# Tests:
#   1. api_reachable    GET /version -> HTTP 200
#   2. token_valid      GET /user -> 200 + Username stimmt
#   3. ssh_key_present  GET /user/keys -> id_ed25519 drin?
#   4. ssh_connection   ssh -T git@<host> -> "Hi" / "welcome"
#   5. push_to_create   temp-repo erstellen, pushen, loeschen (optional, --full)
#
# Exit-Code: 0 = alle Tests OK, 1 = mindestens ein FAIL
# ---------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
. "${REPO_ROOT}/lib/secret-backends.sh"

# ---------------------------------------------------------------------------
# Farben & Output
# ---------------------------------------------------------------------------
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'
BLUE='\033[1;36m'; BOLD='\033[1m'; NC='\033[0m'

PASS=0; FAIL=0; SKIP=0
_results=""

pass() { PASS=$((PASS+1)); _results="${_results}  ${GREEN}PASS${NC}  $1\n"; }
fail() { FAIL=$((FAIL+1)); _results="${_results}  ${RED}FAIL${NC}  $1\n"; }
skip() { SKIP=$((SKIP+1)); _results="${_results}  ${YELLOW}SKIP${NC}  $1\n"; }

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
FORGE_URL="https://forgejo.own.dedyn.io"
FORGE_URLS="https://forgejo.own.dedyn.io https://gitea.own.dedyn.io"
ADMIN_USER="forgejo-admin"
KEY_FILE="${HOME}/.ssh/id_ed25519.pub"
RUN_ALL=false
RUN_FULL=false   # push_to_create Test (destruktiv: erstellt + loescht temp-repo)
USERNAME=""

# ---------------------------------------------------------------------------
# Args
# ---------------------------------------------------------------------------
while [ $# -gt 0 ]; do
    case "$1" in
        --url)        FORGE_URL="$2";   shift 2 ;;
        --admin-user) ADMIN_USER="$2";  shift 2 ;;
        --user)       USERNAME="$2";    shift 2 ;;
        --key-file)   KEY_FILE="$2";    shift 2 ;;
        --all)        RUN_ALL=true;     shift   ;;
        --full)       RUN_FULL=true;    shift   ;;
        --help|-h)
            sed -n '2,30p' "$0" | grep '^#' | sed 's/^# \?//'
            exit 0 ;;
        *) printf 'Unbekannte Option: %s\n' "$1" >&2; exit 1 ;;
    esac
done

# --all: rekursiv fuer jede URL aufrufen
if [ "$RUN_ALL" = "true" ]; then
    OVERALL=0
    for url in $FORGE_URLS; do
        printf '\n%b=== %s ===%b\n' "$BOLD" "$url" "$NC"
        bash "$0" --url "$url" ${RUN_FULL:+--full} ${USERNAME:+--user "$USERNAME"} \
            || OVERALL=1
    done
    exit "$OVERALL"
fi

# ---------------------------------------------------------------------------
# Token laden
# ---------------------------------------------------------------------------
BACKEND=$(sb_detect_backend)
TOKEN_KEY="forge/${ADMIN_USER}_token_bootstrap"
ADMIN_TOKEN=$(sb_read "$BACKEND" "$TOKEN_KEY" 2>/dev/null || true)

if [ -z "$ADMIN_TOKEN" ] && [ -n "$USERNAME" ]; then
    TOKEN_KEY="forge/${USERNAME}_token_bootstrap"
    ADMIN_TOKEN=$(sb_read "$BACKEND" "$TOKEN_KEY" 2>/dev/null || true)
fi

if [ -z "$ADMIN_TOKEN" ]; then
    printf 'API-Token fuer %s (fuer Tests): ' "$FORGE_URL" >&2
    read -rs ADMIN_TOKEN; printf '\n' >&2
fi

FORGE_HOST=$(printf '%s' "$FORGE_URL" | sed 's|https\?://||' | cut -d/ -f1)

# ---------------------------------------------------------------------------
# API-Hilfsfunktion
# ---------------------------------------------------------------------------
api_get() {
    curl -sf --max-time 5 \
        -H "Authorization: token ${ADMIN_TOKEN}" \
        -H "Content-Type: application/json" \
        "${FORGE_URL}/api/v1${1}" 2>/dev/null
}

api_post() {
    curl -sf --max-time 10 \
        -X POST \
        -H "Authorization: token ${ADMIN_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "$2" \
        "${FORGE_URL}/api/v1${1}" 2>/dev/null
}

api_delete() {
    curl -sf --max-time 10 \
        -X DELETE \
        -H "Authorization: token ${ADMIN_TOKEN}" \
        "${FORGE_URL}/api/v1${1}" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Header
# ---------------------------------------------------------------------------
printf '\n%b%s%b\n' "$BOLD" "forge/test.sh" "$NC"
printf 'Target:  %s\n' "$FORGE_URL"
printf 'Backend: %s\n' "$BACKEND"
printf 'Key:     %s\n' "$KEY_FILE"
printf '%s\n' "$(printf '%0.s-' {1..50})"

# ---------------------------------------------------------------------------
# TEST 1: API erreichbar
# ---------------------------------------------------------------------------
VERSION=$(api_get "/version" \
    | python3 -c "import sys,json; print(json.load(sys.stdin).get('version','?'))" \
    2>/dev/null || true)

if [ -n "$VERSION" ] && [ "$VERSION" != "?" ]; then
    pass "api_reachable       ${FORGE_URL} (${VERSION})"
else
    fail "api_reachable       ${FORGE_URL} nicht erreichbar"
fi

# ---------------------------------------------------------------------------
# TEST 2: Token gueltig
# ---------------------------------------------------------------------------
AUTH_USER=$(api_get "/user" \
    | python3 -c "import sys,json; print(json.load(sys.stdin).get('login',''))" \
    2>/dev/null || true)

if [ -n "$AUTH_USER" ]; then
    pass "token_valid         eingeloggt als: ${AUTH_USER}"
    # USERNAME aus Token ableiten wenn nicht gesetzt
    [ -z "$USERNAME" ] && USERNAME="$AUTH_USER"
else
    fail "token_valid         Token ungueltig oder abgelaufen"
    # Restliche Tests koennen nicht laufen
    skip "ssh_key_present     (Token ungueltig -- uebersprungen)"
    skip "ssh_connection      (Token ungueltig -- uebersprungen)"
    [ "$RUN_FULL" = "true" ] && skip "push_to_create      (Token ungueltig -- uebersprungen)"
fi

# ---------------------------------------------------------------------------
# TEST 3: SSH Key vorhanden
# ---------------------------------------------------------------------------
if [ -n "$AUTH_USER" ]; then
    if [ -f "$KEY_FILE" ]; then
        KEY_FINGERPRINT=$(ssh-keygen -lf "$KEY_FILE" 2>/dev/null | awk '{print $2}' || true)
        KEYS_JSON=$(api_get "/user/keys" 2>/dev/null || true)
        KEY_FOUND=$(printf '%s' "$KEYS_JSON" \
            | python3 -c "
import sys, json
keys = json.load(sys.stdin)
print(len(keys))
" 2>/dev/null || echo '0')

        if [ "$KEY_FOUND" -gt 0 ] 2>/dev/null; then
            pass "ssh_key_present     ${KEY_FOUND} Key(s) registriert fuer ${AUTH_USER}"
        else
            fail "ssh_key_present     Kein SSH Key fuer ${AUTH_USER} -- set-ssh-key.sh ausfuehren"
        fi
    else
        skip "ssh_key_present     Key-Datei nicht gefunden: ${KEY_FILE}"
    fi
fi

# ---------------------------------------------------------------------------
# TEST 4: SSH Verbindung
# ---------------------------------------------------------------------------
if [ -n "$AUTH_USER" ] && [ -f "${KEY_FILE%.pub}" ]; then
    SSH_OUT=$(ssh \
        -i "${KEY_FILE%.pub}" \
        -o IdentitiesOnly=yes \
        -o StrictHostKeyChecking=no \
        -o BatchMode=yes \
        -o ConnectTimeout=5 \
        "git@${FORGE_HOST}" 2>&1 || true)

    if printf '%s' "$SSH_OUT" | grep -qi 'hi\|welcome\|successfully authenticated'; then
        pass "ssh_connection      git@${FORGE_HOST} antwortet korrekt"
    elif printf '%s' "$SSH_OUT" | grep -qi 'permission denied\|publickey'; then
        fail "ssh_connection      Permission denied -- Key nicht akzeptiert"
    else
        fail "ssh_connection      Unerwartete Antwort: ${SSH_OUT}"
    fi
else
    skip "ssh_connection      Privater Key nicht gefunden: ${KEY_FILE%.pub}"
fi

# ---------------------------------------------------------------------------
# TEST 5: push_to_create (nur mit --full)
# ---------------------------------------------------------------------------
if [ "$RUN_FULL" = "true" ] && [ -n "$AUTH_USER" ]; then
    TEMP_REPO="forge-test-$(date +%s)"
    TEMP_DIR=$(mktemp -d)

    # Repo erstellen
    CREATE_RESULT=$(api_post "/user/repos" \
        "{\"name\": \"${TEMP_REPO}\", \"private\": true, \"auto_init\": true}" \
        2>/dev/null || true)
    REPO_CREATED=$(printf '%s' "$CREATE_RESULT" \
        | python3 -c "import sys,json; print(json.load(sys.stdin).get('full_name',''))" \
        2>/dev/null || true)

    if [ -n "$REPO_CREATED" ]; then
        # Klonen + Push
        git clone --quiet \
            "git@${FORGE_HOST}:${AUTH_USER}/${TEMP_REPO}.git" \
            "$TEMP_DIR" 2>/dev/null \
        && printf 'forge-test\n' > "${TEMP_DIR}/test.txt" \
        && git -C "$TEMP_DIR" add test.txt \
        && git -C "$TEMP_DIR" -c user.email='test@test' -c user.name='test' \
            commit -qm 'forge regression test' \
        && git -C "$TEMP_DIR" push -q origin main 2>/dev/null \
        && pass "push_to_create      ${REPO_CREATED} erstellt + gepusht" \
        || fail "push_to_create      Klon/Push fehlgeschlagen"

        # Aufraumen
        api_delete "/repos/${AUTH_USER}/${TEMP_REPO}" >/dev/null 2>&1 || true
    else
        fail "push_to_create      Repo konnte nicht erstellt werden"
    fi

    rm -rf "$TEMP_DIR"
else
    [ "$RUN_FULL" = "false" ] && \
        skip "push_to_create      (--full nicht angegeben -- uebersprungen)"
fi

# ---------------------------------------------------------------------------
# Ergebnis
# ---------------------------------------------------------------------------
printf '%s\n' "$(printf '%0.s-' {1..50})"
printf '%b' "$_results"
printf '%s\n' "$(printf '%0.s-' {1..50})"
printf '%bPASS: %d  FAIL: %d  SKIP: %d%b\n' "$BOLD" "$PASS" "$FAIL" "$SKIP" "$NC"
printf '%s\n' "$(printf '%0.s-' {1..50})"

[ "$FAIL" -eq 0 ]
