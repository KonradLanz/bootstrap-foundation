#!/usr/bin/env bash
# qnap/postgres/run-bootstrap-postgres.sh
# ---------------------------------------------------------------------------
# Mac-seitiger Wrapper: holt PostgreSQL-Superuser-Passwort aus Vaultwarden
# und ruft bootstrap-postgres.sh headless per SSH auf dem QNAP auf.
#
# Aufruf (vom Mac, im Repo-Root):
#   bash qnap/postgres/run-bootstrap-postgres.sh [--dry-run] [--yes]
#
# Passwort-Logik:
#   1. Aus Vaultwarden: postgres/nasuser_pass
#   2. Falls nicht vorhanden: zufaellig generieren + in Vaultwarden speichern
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

NAS_HOST="nas"
REMOTE_REPO_PATH="/share/CE_CACHEDEV4_DATA/homes/DOMAIN=AD/koni/git/bootstrap-foundation"
POSTGRES_USER="nasuser"
PASS_KEY="postgres/nasuser_pass"
DRY_RUN_FLAG=""
YES_FLAG=""

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) DRY_RUN_FLAG="--dry-run"; shift ;;
        --yes)     YES_FLAG="--yes";         shift ;;
        --user)    POSTGRES_USER="$2";       shift 2 ;;
        --remote-path) REMOTE_REPO_PATH="$2"; shift 2 ;;
        --help|-h) grep '^#' "$0" | sed 's/^# \?//'; exit 0 ;;
        *) die "Unbekannte Option: $1" ;;
    esac
done

# ── Passwort aus Vaultwarden holen (oder neu generieren) ───────────────────
BACKEND=$(sb_detect_backend)
info "Credential-Backend: ${BACKEND}"

if [ "$BACKEND" = "vaultwarden" ] && [ -n "${BW_SESSION:-}" ]; then
    bw sync --session "$BW_SESSION" >/dev/null 2>&1 || true
fi

POSTGRES_PASS=$(sb_read "$BACKEND" "$PASS_KEY" 2>/dev/null || true)

if [ -z "$POSTGRES_PASS" ]; then
    warn "Kein Passwort im Backend unter '${PASS_KEY}' -- generiere neues."
    POSTGRES_PASS=$(LC_ALL=C tr -dc 'A-Za-z0-9!@#%^&*' < /dev/urandom | head -c 32 || true)
    ok "Zufaelliges Passwort generiert (${#POSTGRES_PASS} Zeichen)"
    sb_write "$BACKEND" "$PASS_KEY" "$POSTGRES_PASS" "$POSTGRES_USER"
    ok "Passwort in Vaultwarden gespeichert: ${PASS_KEY}"
else
    ok "Passwort aus Vaultwarden geladen: ${PASS_KEY}"
fi

# ── git pull auf NAS ────────────────────────────────────────────────────────────────
info "Aktualisiere Repo auf ${NAS_HOST}:${REMOTE_REPO_PATH}..."
ssh "$NAS_HOST" \
    "export PATH=/share/CACHEDEV1_DATA/.qpkg/container-station/bin:/opt/bin:\$PATH && \
     git config --global --add safe.directory '${REMOTE_REPO_PATH}' 2>/dev/null; \
     cd '${REMOTE_REPO_PATH}' && git pull --ff-only" \
    && ok "git pull OK" \
    || warn "git pull fehlgeschlagen -- fahre mit lokalem Stand fort"

# ── bootstrap-postgres.sh auf NAS ausfuehren ───────────────────────────────────
info "Starte bootstrap-postgres.sh auf ${NAS_HOST}..."
printf '%s\n' "$POSTGRES_PASS" | ssh "$NAS_HOST" \
    "ALWAYS_CONFIRM=${YES_FLAG:+1}${YES_FLAG:-0} \
     export PATH=/share/CACHEDEV1_DATA/.qpkg/container-station/bin:/opt/bin:\$PATH && \
     sh '${REMOTE_REPO_PATH}/qnap/postgres/bootstrap-postgres.sh' \
         ${DRY_RUN_FLAG} \
         ${YES_FLAG} \
         --user '${POSTGRES_USER}'"

ok "bootstrap-postgres.sh abgeschlossen."
printf '\nNaechste Schritte:\n'
printf '  1. Forgejo Bootstrap:  bash qnap/forgejo/run-bootstrap.sh --yes\n'
printf '  2. Gitea Bootstrap:    bash qnap/gitea/run-bootstrap.sh --yes  (falls genutzt)\n'
