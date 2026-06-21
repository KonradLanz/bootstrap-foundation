#!/usr/bin/env bash
# qnap/forgejo/run-bootstrap.sh
# ---------------------------------------------------------------------------
# Wrapper: holt Forgejo-Admin-Passwort aus dem Credential-Backend (Mac)
# und ruft bootstrap-forgejo.sh headless per SSH auf dem QNAP auf.
#
# Aufruf (vom Mac, im Repo-Root):
#   bash qnap/forgejo/run-bootstrap.sh [--dry-run] [--rewrite-compose]
#
# Voraussetzungen:
#   - SSH-Zugang zum QNAP via 'nas' (ssh-alias)
#   - Repo auf dem QNAP unter REMOTE_REPO_PATH
#   - Credential-Backend (vaultwarden/keepassxc/plain) konfiguriert
# ---------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
export KL_BOOTSTRAP_ROOT="$REPO_ROOT"
. "${REPO_ROOT}/lib/secret-backends.sh"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[1;36m'; RED='\033[0;31m'; NC='\033[0m'
info() { printf "${BLUE}[INFO]${NC}  %s\n" "$*"; }
ok()   { printf "${GREEN}[OK]${NC}    %s\n" "$*"; }
warn() { printf "${YELLOW}[WARN]${NC}  %s\n" "$*"; }
die()  { printf "${RED}[ERROR]${NC} %s\n" "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Konfiguration
# ---------------------------------------------------------------------------
NAS_HOST="nas"
REMOTE_REPO_PATH="/share/CE_CACHEDEV4_DATA/homes/DOMAIN=AD/koni/git/bootstrap-foundation"
FORGEJO_DOMAIN="forgejo.own.dedyn.io"
HAPROXY_IP="192.168.111.40"
LOCAL_IP="192.168.111.42"
ADMIN_USER="forgejo-admin"
ADMIN_EMAIL="admin@${FORGEJO_DOMAIN}"
DRY_RUN_FLAG=""
REWRITE_FLAG=""
YES_FLAG=""

# ---------------------------------------------------------------------------
# Args
# ---------------------------------------------------------------------------
while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run)        DRY_RUN_FLAG="--dry-run";       shift ;;
        --rewrite-compose) REWRITE_FLAG="--rewrite-compose"; shift ;;
        --yes)            YES_FLAG="--yes";                shift ;;
        --domain)         FORGEJO_DOMAIN="$2";            shift 2 ;;
        --admin-user)     ADMIN_USER="$2";                shift 2 ;;
        --admin-email)    ADMIN_EMAIL="$2";               shift 2 ;;
        --haproxy-ip)     HAPROXY_IP="$2";               shift 2 ;;
        --local-ip)       LOCAL_IP="$2";                 shift 2 ;;
        --remote-path)    REMOTE_REPO_PATH="$2";          shift 2 ;;
        --help|-h)
            grep '^#' "$0" | sed 's/^# \?//'; exit 0 ;;
        *) die "Unbekannte Option: $1" ;;
    esac
done

# ---------------------------------------------------------------------------
# Passwort aus Backend holen
# ---------------------------------------------------------------------------
BACKEND=$(sb_detect_backend)
info "Credential-Backend: ${BACKEND}"

PASS_KEY="forgejo/${ADMIN_USER}_pass"
# Sicherstellen dass lokaler bw-Cache aktuell ist
if [ "$BACKEND" = "vaultwarden" ] && [ -n "${BW_SESSION:-}" ]; then
    bw sync --session "$BW_SESSION" >/dev/null 2>&1 || true
fi
ADMIN_PASS=$(sb_read "$BACKEND" "$PASS_KEY" 2>/dev/null || true)

if [ -z "$ADMIN_PASS" ]; then
    warn "Kein Passwort im Backend unter '${PASS_KEY}'"

    # Default-Passwort vorschlagen (zufaellig, 32 Zeichen)
    DEFAULT_PASS=$(LC_ALL=C tr -dc 'A-Za-z0-9!@#%^&*' < /dev/urandom | head -c 32 || true)
    printf "Neues Passwort fuer '%s'\n" "$ADMIN_USER" >&2
    printf "  [Enter]  = zufaelliges Passwort verwenden (%d Zeichen, versteckt)\n" "${#DEFAULT_PASS}" >&2
    printf "  Eingabe  = eigenes Passwort (versteckt, Laenge wird angezeigt)\n" >&2
    printf "Passwort: " >&2
    read -rs ADMIN_PASS; printf '\n' >&2

    if [ -z "$ADMIN_PASS" ]; then
        ADMIN_PASS="$DEFAULT_PASS"
        ok "Zufaelliges Passwort generiert (${#ADMIN_PASS} Zeichen)"
    else
        ok "Passwort eingegeben (${#ADMIN_PASS} Zeichen)"
    fi

    printf "Passwort in Backend speichern? [Y/n] " >&2
    read -r SAVE_PASS
    if [ "${SAVE_PASS:-y}" != "n" ] && [ "${SAVE_PASS:-y}" != "N" ]; then
        sb_write "$BACKEND" "$PASS_KEY" "$ADMIN_PASS" "$ADMIN_USER"
        ok "Passwort gespeichert: ${PASS_KEY}"
    fi
else
    ok "Passwort aus Backend geladen: ${PASS_KEY}"
fi

# ---------------------------------------------------------------------------
# Repo auf NAS aktuell halten (git pull)
# ---------------------------------------------------------------------------
info "Aktualisiere Repo auf ${NAS_HOST}:${REMOTE_REPO_PATH}..."
ssh "$NAS_HOST" "export PATH=/opt/bin:/share/CACHEDEV1_DATA/.qpkg/container-station/bin:\$PATH && git config --global --add safe.directory '${REMOTE_REPO_PATH}' 2>/dev/null; cd '${REMOTE_REPO_PATH}' && git pull --ff-only" \
    && ok "git pull OK" \
    || warn "git pull fehlgeschlagen -- fahre mit lokalem Stand fort"

# ---------------------------------------------------------------------------
# bootstrap-forgejo.sh headless auf NAS ausfuehren
# ---------------------------------------------------------------------------
info "Starte bootstrap-forgejo.sh auf ${NAS_HOST}..."
info "  Domain:     ${FORGEJO_DOMAIN}"
info "  HAProxy IP: ${HAPROXY_IP}"
info "  Admin:      ${ADMIN_USER} <${ADMIN_EMAIL}>"
info "  Dry-run:    ${DRY_RUN_FLAG:-nein}"
printf '\n'

# Passwort wird per stdin uebergeben -- nie als CLI-Argument oder Env in der
# SSH-Commandline (wäre sichtbar in 'ps aux' auf dem NAS).
# bootstrap-on-nas.sh liest ADMIN_PASS aus erster stdin-Zeile.
printf '%s\n' "$ADMIN_PASS" | ssh "$NAS_HOST" \
    "ALWAYS_CONFIRM=${YES_FLAG:+1}${YES_FLAG:-0} sh '${REMOTE_REPO_PATH}/qnap/forgejo/bootstrap-on-nas.sh' \
        ${DRY_RUN_FLAG} \
        ${REWRITE_FLAG} \
        ${YES_FLAG} \
        --haproxy '${HAPROXY_IP}' \
        --local-ip '${LOCAL_IP}' \
        --admin-user '${ADMIN_USER}' \
        --admin-email '${ADMIN_EMAIL}' \
        --read-pass-stdin \
        '${FORGEJO_DOMAIN}'"

ok "bootstrap-forgejo.sh abgeschlossen."

# ---------------------------------------------------------------------------
# Phase 2: Primary User anlegen
# ---------------------------------------------------------------------------
PRIMARY_USER="$(kl_read_cached 'forgejo/primary_user' 'Forgejo Primary Username' 2>/dev/null || whoami)"
PRIMARY_EMAIL="$(kl_read_cached 'forgejo/primary_email' 'Forgejo Primary Email' 2>/dev/null || echo "${PRIMARY_USER}@${FORGEJO_DOMAIN}")"
PRIMARY_PASS_KEY="forgejo/${PRIMARY_USER}_pass"

info "Phase 2: Primary User '${PRIMARY_USER}' anlegen..."

PRIMARY_PASS=$(sb_read "$BACKEND" "$PRIMARY_PASS_KEY" 2>/dev/null || true)

if [ -z "$PRIMARY_PASS" ]; then
    PRIMARY_PASS=$(LC_ALL=C tr -dc 'A-Za-z0-9!@#%^&*' < /dev/urandom | head -c 32)
    sb_write "$BACKEND" "$PRIMARY_PASS_KEY" "$PRIMARY_PASS" "$PRIMARY_USER"
    ok "Passwort generiert + gespeichert: ${PRIMARY_PASS_KEY}"
else
    ok "Passwort aus Backend geladen: ${PRIMARY_PASS_KEY}"
fi

HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' \
    -X POST "https://${FORGEJO_DOMAIN}/api/v1/admin/users" \
    -u "${ADMIN_USER}:${ADMIN_PASS}" \
    -H "Content-Type: application/json" \
    -d "{
        \"username\": \"${PRIMARY_USER}\",
        \"email\": \"${PRIMARY_EMAIL}\",
        \"password\": \"${PRIMARY_PASS}\",
        \"must_change_password\": false,
        \"send_notify\": false
    }")

case "$HTTP_CODE" in
    201) ok "User '${PRIMARY_USER}' angelegt" ;;
    422) warn "User '${PRIMARY_USER}' existiert bereits — ueberspringe" ;;
    *)   die "User-Anlage fehlgeschlagen (HTTP ${HTTP_CODE})" ;;
esac

# ---------------------------------------------------------------------------
# Phase 3: SSH-Key fuer Primary User hinterlegen
# ---------------------------------------------------------------------------
SSH_KEY_PATH="${HOME}/.ssh/id_ed25519.pub"
[ -f "$SSH_KEY_PATH" ] || SSH_KEY_PATH="${HOME}/.ssh/id_rsa.pub"

if [ -f "$SSH_KEY_PATH" ]; then
    SSH_KEY_TITLE="$(hostname -s)"
    HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' \
        -X POST "https://${FORGEJO_DOMAIN}/api/v1/user/keys" \
        -u "${PRIMARY_USER}:${PRIMARY_PASS}" \
        -H "Content-Type: application/json" \
        -d "{
            \"key\": \"$(cat "$SSH_KEY_PATH")\",
            \"read_only\": false,
            \"title\": \"${SSH_KEY_TITLE}\"
        }")
    case "$HTTP_CODE" in
        201) ok "SSH-Key '${SSH_KEY_TITLE}' hinterlegt" ;;
        422) warn "SSH-Key bereits vorhanden — ueberspringe" ;;
        *)   warn "SSH-Key Upload fehlgeschlagen (HTTP ${HTTP_CODE})" ;;
    esac
else
    warn "Kein SSH Public Key gefunden (~/.ssh/id_ed25519.pub)"
fi

printf '\n'
printf 'Naechste Schritte:\n'
printf '  1. SSH testen:         ssh -T git@%s\n' "$FORGEJO_DOMAIN"
printf '  2. dotAI pushen:       cd ~/git/dotAI && git push forgejo main\n'
printf '  3. Regression:         bash services/forge/test.sh --url https://%s\n' "$FORGEJO_DOMAIN"
