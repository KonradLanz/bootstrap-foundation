#!/bin/sh
# qnap/forgejo/bootstrap-on-nas.sh
# ---------------------------------------------------------------------------
# Einmaliges Setup-Skript fuer Forgejo auf dem QNAP NAS.
# Loest PATH-Probleme (git, docker-compose) und startet bootstrap-forgejo.sh.
#
# Aufruf (auf dem NAS als admin):
#   sh ~/git/bootstrap-foundation/qnap/forgejo/bootstrap-on-nas.sh
#
# Oder direkt per SSH vom Mac:
#   ssh admin@nas.ad.own.dedyn.io \
#     'sh ~/git/bootstrap-foundation/qnap/forgejo/bootstrap-on-nas.sh'
# ---------------------------------------------------------------------------
set -eu

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[1;36m'; RED='\033[0;31m'; NC='\033[0m'
info()  { printf "${BLUE}[INFO]${NC}  %s\n" "$*"; }
ok()    { printf "${GREEN}[OK]${NC}    %s\n" "$*"; }
warn()  { printf "${YELLOW}[WARN]${NC}  %s\n" "$*"; }
error() { printf "${RED}[ERROR]${NC} %s\n" "$*" >&2; exit 1; }

# ── Konfiguration ────────────────────────────────────────────────────────────
FORGEJO_DOMAIN="forgejo.own.dedyn.io"
HAPROXY_IP="192.168.111.40"
ADMIN_USER="forgejo-admin"
ADMIN_EMAIL="admin@own.dedyn.io"
REPO_DIR="/share/CE_CACHEDEV4_DATA/homes/DOMAIN=AD/koni/git/bootstrap-foundation"
ADMIN_PASS=""
READ_PASS_STDIN=0

# ── Args ─────────────────────────────────────────────────────────────────────
DRY_RUN_FLAG=""
REWRITE_FLAG=""
while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run)         DRY_RUN_FLAG="--dry-run";        shift ;;
        --rewrite-compose) REWRITE_FLAG="--rewrite-compose"; shift ;;
        --haproxy)         HAPROXY_IP="$2";                 shift 2 ;;
        --admin-user)      ADMIN_USER="$2";                 shift 2 ;;
        --admin-email)     ADMIN_EMAIL="$2";                shift 2 ;;
        --admin-pass)      ADMIN_PASS="$2";                 shift 2 ;;
        --read-pass-stdin) READ_PASS_STDIN=1;               shift ;;
        *)                 FORGEJO_DOMAIN="$1";             shift ;;
    esac
done

# Passwort aus stdin lesen (erste Zeile) wenn angefordert
if [ "$READ_PASS_STDIN" = "1" ] && [ -z "$ADMIN_PASS" ]; then
    read -r ADMIN_PASS || true
fi

# ── 1. PATH erweitern ────────────────────────────────────────────────────────
info "Setze PATH..."
CS_BIN="/share/CACHEDEV1_DATA/.qpkg/container-station/bin"
OPT_BIN="/opt/bin"
USR_LOCAL="/usr/local/bin"

export PATH="${CS_BIN}:${OPT_BIN}:${USR_LOCAL}:${PATH}"
ok "PATH: $PATH"

# ── 2. git finden ────────────────────────────────────────────────────────────
info "Suche git..."
if command -v git >/dev/null 2>&1; then
    ok "git gefunden: $(command -v git) ($(git --version))"
else
    # Entware-Fallback: opkg install git
    warn "git nicht im PATH. Versuche Installation via Entware (opkg)..."
    if command -v opkg >/dev/null 2>&1; then
        opkg install git || error "opkg install git fehlgeschlagen. Bitte git manuell installieren."
        ok "git via opkg installiert."
    else
        error "git nicht gefunden und opkg nicht verfuegbar.\n"\
              "Bitte im QNAP App Center 'Entware' oder 'Git' installieren,\n"\
              "oder git manuell nach /usr/local/bin kopieren."
    fi
fi

# ── 3. docker-compose pruefen ────────────────────────────────────────────────
info "Suche docker-compose..."
if command -v docker-compose >/dev/null 2>&1; then
    ok "docker-compose: $(command -v docker-compose)"
elif command -v docker >/dev/null 2>&1; then
    ok "docker (v2 compose plugin): $(command -v docker)"
else
    error "Weder docker-compose noch docker gefunden.\n"\
          "Bitte Container Station im QNAP App Center installieren."
fi

# ── 4. PATH dauerhaft in .profile speichern ───────────────────────────────────
PROFILE="${HOME}/.profile"
if ! grep -q 'container-station' "$PROFILE" 2>/dev/null; then
    info "Schreibe PATH in ${PROFILE}..."
    cat >> "$PROFILE" << 'EOF'

# bootstrap-foundation: QNAP Container Station + Entware PATH
export PATH="/share/CACHEDEV1_DATA/.qpkg/container-station/bin:/opt/bin:/usr/local/bin:$PATH"
EOF
    ok "${PROFILE} aktualisiert."
else
    info "${PROFILE} enthalt bereits container-station Eintrag — ueberspringe."
fi

# ── 5. git pull ───────────────────────────────────────────────────────────────
if [ ! -d "$REPO_DIR" ]; then
    error "Repo nicht gefunden: ${REPO_DIR}\n"\
          "Bitte zuerst: git clone https://github.com/KonradLanz/bootstrap-foundation.git ${REPO_DIR}"
fi

# safe.directory fuer AD-Domain-Pfade setzen (admin != repo-owner)
git config --global --add safe.directory "$REPO_DIR" 2>/dev/null || true

info "git pull in ${REPO_DIR}..."
cd "$REPO_DIR"
git pull origin main
ok "Repo aktuell: $(git log --oneline -1)"

# ── 6. bootstrap-forgejo.sh ausfuehren ───────────────────────────────────────
info "Starte Forgejo Bootstrap..."
printf '\n'
sh "${REPO_DIR}/qnap/forgejo/bootstrap-forgejo.sh" \
    ${DRY_RUN_FLAG} \
    ${REWRITE_FLAG} \
    --haproxy "$HAPROXY_IP" \
    --admin-user "$ADMIN_USER" \
    --admin-email "$ADMIN_EMAIL" \
    ${ADMIN_PASS:+--admin-pass "$ADMIN_PASS"} \
    "$FORGEJO_DOMAIN"
