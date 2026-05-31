#!/usr/bin/env bash
set -euo pipefail

# services/forge/create-user.sh
# Creates a user (or reuses an existing one) on Forgejo *or* Gitea and
# generates a Personal Access Token.
#
# Credential backends (in priority order):
#   1. KeePassXC  (if keepassxc-cli is available and KL_KEEPASS_DB exists)
#   2. GPG        (symmetric AES-256, from kl-input-cache)
#   3. Plain text (for non-sensitive values like URLs and usernames)
#   4. Interactive prompt with DurchEntern/WeiterEntern caching
#
# Set CREDENTIAL_BACKEND=plain|gpg|keepassxc to force a specific backend.
# Default: auto-detect (keepassxc > gpg > plain)
#
# Idempotent: safe to re-run.
# Forgejo >= 1.20 and Gitea >= 1.19 both expose the same REST API.
#
# Usage:
#   bash services/forge/create-user.sh
#   FORGE_TYPE=gitea bash services/forge/create-user.sh
#   CREDENTIAL_BACKEND=keepassxc bash services/forge/create-user.sh

# ---------------------------------------------------------------------------
# Locate bootstrap-foundation and source input-cache.sh
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BOOTSTRAP_ROOT="$SCRIPT_DIR"

if [ -n "${KL_BOOTSTRAP_ROOT:-}" ]; then
    BOOTSTRAP_ROOT="$KL_BOOTSTRAP_ROOT"
elif [ -d "$HOME/github/bootstrap-foundation" ]; then
    BOOTSTRAP_ROOT="$HOME/github/bootstrap-foundation"
fi

INPUT_CACHE="$BOOTSTRAP_ROOT/lib/input-cache.sh"
if [ -f "$INPUT_CACHE" ]; then
    # shellcheck source=/dev/null
    . "$INPUT_CACHE"
    HAS_CACHE=1
else
    HAS_CACHE=0
fi

# ---------------------------------------------------------------------------
# Credential backend detection
# ---------------------------------------------------------------------------
: "${KEEPASSXC_CLI:=keepassxc-cli}"
: "${KL_KEEPASS_DB:=${HOME}/KeePassLatest.kdbx}"
: "${KL_KEEPASS_GROUP:=bootstrap-foundation/forge}"

if [ -z "${CREDENTIAL_BACKEND:-}" ]; then
    if command -v "$KEEPASSXC_CLI" >/dev/null 2>&1 && [ -f "$KL_KEEPASS_DB" ]; then
        CREDENTIAL_BACKEND="keepassxc"
    elif command -v gpg >/dev/null 2>&1; then
        CREDENTIAL_BACKEND="gpg"
    else
        CREDENTIAL_BACKEND="plain"
    fi
fi

echo "  Credential backend: ${CREDENTIAL_BACKEND}"

# ---------------------------------------------------------------------------
# ask() wrapper: uses input-cache when available, else plain read
# ---------------------------------------------------------------------------
ask() {
    local var_name="$1" prompt="$2" default="$3" sensitivity="${4:-plain}"
    if [ "$HAS_CACHE" = "1" ]; then
        kl_read_cached "$var_name" "forge/${var_name}" "$prompt" "$default" "$sensitivity"
    else
        printf '%s [%s]: ' "$prompt" "$default" >&2
        read -r REPLY
        printf -v "$var_name" '%s' "${REPLY:-$default}"
    fi
}

# ---------------------------------------------------------------------------
# Prompts
# ---------------------------------------------------------------------------
: "${FORGE_TYPE:=forgejo}"
FORGE_TYPE_UPPER="$(printf '%s' "$FORGE_TYPE" | tr '[:lower:]' '[:upper:]')"

echo
echo "=== ${FORGE_TYPE_UPPER} bootstrap: create user + API token ==="
echo "  Backend: ${CREDENTIAL_BACKEND}"
echo '  Press Enter to accept the cached/default value shown in brackets.'
echo

ask FORGE_HOST        "${FORGE_TYPE_UPPER} base URL (no trailing slash)" 'http://localhost:3000' plain
ask FORGE_ADMIN_USER  "${FORGE_TYPE_UPPER} admin username"               'admin'                 plain
ask FORGE_ADMIN_PASS  "${FORGE_TYPE_UPPER} admin password"               'changeme'              "$CREDENTIAL_BACKEND"

echo
echo '--- New application user ---'
ask NEW_USER   'Username'      'structured-pdf'           plain
ask NEW_EMAIL  'User email'    "${NEW_USER}@localhost"     plain
ask NEW_PASS   'User password' 'changeme123'               "$CREDENTIAL_BACKEND"
ask TOKEN_NAME 'Token name'    'structured-pdf-pipeline'   plain

export FORGE_ADMIN_USER FORGE_ADMIN_PASS FORGE_HOST

# ---------------------------------------------------------------------------
# 1. Create user (idempotent)
# ---------------------------------------------------------------------------
echo
echo "--- User '${NEW_USER}' ---"

HTTP_STATUS=$(curl -s \
  -o /tmp/_forge_create_user.json \
  -w '%{http_code}' \
  -X POST "${FORGE_HOST}/api/v1/admin/users" \
  -u "${FORGE_ADMIN_USER}:${FORGE_ADMIN_PASS}" \
  -H 'Content-Type: application/json' \
  -d "{
    \"email\": \"${NEW_EMAIL}\",
    \"login_name\": \"${NEW_USER}\",
    \"must_change_password\": false,
    \"password\": \"${NEW_PASS}\",
    \"send_notify\": false,
    \"source_id\": 0,
    \"username\": \"${NEW_USER}\"
  }")

case "$HTTP_STATUS" in
  201) echo "  Created '${NEW_USER}'." ;;
  422)
    echo "  User '${NEW_USER}' already exists - verifying password..."
    PROBE=$(curl -s -o /dev/null -w '%{http_code}' \
      "${FORGE_HOST}/api/v1/users/${NEW_USER}/tokens" \
      -u "${NEW_USER}:${NEW_PASS}")
    if [ "$PROBE" = '401' ]; then
      echo "  ERROR: password incorrect for existing user '${NEW_USER}'."
      exit 1
    fi
    echo "  Password OK (probe: ${PROBE})."
    ;;
  *)
    echo "  WARNING: unexpected HTTP ${HTTP_STATUS}:"
    cat /tmp/_forge_create_user.json; echo
    ;;
esac
rm -f /tmp/_forge_create_user.json

# ---------------------------------------------------------------------------
# 2. Create token (idempotent)
# ---------------------------------------------------------------------------
echo
echo "--- Token '${TOKEN_NAME}' ---"

_do_token() {
  curl -s \
    -o /tmp/_forge_token.json \
    -w '%{http_code}' \
    -X POST "${FORGE_HOST}/api/v1/users/${NEW_USER}/tokens" \
    -u "${NEW_USER}:${NEW_PASS}" \
    -H 'Content-Type: application/json' \
    -d "{\"name\": \"${1}\", \"scopes\": [\"read:repository\",\"write:repository\",\"read:user\"]}"
}

HTTP_STATUS=$(_do_token "$TOKEN_NAME")
if [ "$HTTP_STATUS" = '422' ]; then
  TOKEN_NAME="${TOKEN_NAME}-$(date +%Y%m%d%H%M%S)"
  echo "  Name exists - retrying as '${TOKEN_NAME}'..."
  HTTP_STATUS=$(_do_token "$TOKEN_NAME")
fi

if [ "$HTTP_STATUS" = '201' ]; then
  FORGE_NEW_TOKEN=$(grep -o '"sha1":"[^"]*"' /tmp/_forge_token.json | cut -d'"' -f4)
  [ -z "${FORGE_NEW_TOKEN:-}" ] && \
    FORGE_NEW_TOKEN=$(grep -o '"token":"[^"]*"' /tmp/_forge_token.json | cut -d'"' -f4)
  rm -f /tmp/_forge_token.json
else
  echo "  ERROR: token creation failed (HTTP ${HTTP_STATUS}):"
  cat /tmp/_forge_token.json; echo
  rm -f /tmp/_forge_token.json
  exit 1
fi

# ---------------------------------------------------------------------------
# 3. Save token to KeePass / cache
# ---------------------------------------------------------------------------
echo
if [ "$CREDENTIAL_BACKEND" = "keepassxc" ] && command -v "$KEEPASSXC_CLI" >/dev/null 2>&1; then
  kl_keepass_write "forge/${NEW_USER}_token" "$FORGE_NEW_TOKEN" "$NEW_USER"
  echo "  Token saved to KeePass: ${KL_KEEPASS_GROUP}/${NEW_USER}_token"
fi

# ---------------------------------------------------------------------------
# 4. Output
# ---------------------------------------------------------------------------
echo '=== SUCCESS ==='
echo
printf '  %-14s %s\n' "${FORGE_TYPE_UPPER} URL:" "$FORGE_HOST"
printf '  %-14s %s\n' 'Username:'     "$NEW_USER"
printf '  %-14s %s\n' 'Token name:'   "$TOKEN_NAME"
printf '  %-14s %s\n' 'Token:'        "$FORGE_NEW_TOKEN"
echo
if [ "$CREDENTIAL_BACKEND" = "keepassxc" ]; then
  echo "  Token saved to KeePass DB: ${KL_KEEPASS_DB}"
  echo "  Entry: ${KL_KEEPASS_GROUP}/${NEW_USER}_token"
else
  echo '  Store the token in your password manager (KeePass) now.'
  echo '  It will NOT be shown again.'
fi
