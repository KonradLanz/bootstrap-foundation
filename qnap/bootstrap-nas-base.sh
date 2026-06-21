#!/usr/bin/env bash
# qnap/bootstrap-nas-base.sh
# ---------------------------------------------------------------------------
# Einmaliges NAS-Fundament-Script: PATH + SSH-Environment dauerhaft setzen.
#
# Loest das strukturelle Problem dass non-interactive SSH-Sessions kein
# .profile sourcen -- docker, git etc. sind dann nicht im PATH.
#
# Aufruf (vom Mac):
#   ssh nas 'sh -s' < qnap/bootstrap-nas-base.sh
#   # oder via Wrapper:
#   bash qnap/run-nas-base.sh
#
# Idempotent: kann beliebig oft ausgefuehrt werden.
# ---------------------------------------------------------------------------
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[1;36m'; NC='\033[0m'
info() { printf "${BLUE}[INFO]${NC}  %s\n" "$*"; }
ok()   { printf "${GREEN}[OK]${NC}    %s\n" "$*"; }
warn() { printf "${YELLOW}[WARN]${NC}  %s\n" "$*"; }

NAS_PATH="/share/CACHEDEV1_DATA/.qpkg/container-station/bin:/opt/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

# ── 1. ~/.ssh/environment ───────────────────────────────────────────────────────────
# Wird von sshd fuer JEDE SSH-Session geladen -- auch non-interactive.
# Voraussetzung: PermitUserEnvironment yes in sshd_config (Schritt 2).
info "Setze ~/.ssh/environment ..."
mkdir -p "${HOME}/.ssh"
SSH_ENV="${HOME}/.ssh/environment"

if grep -q 'container-station' "${SSH_ENV}" 2>/dev/null; then
    ok "~/.ssh/environment bereits gesetzt -- ueberspringe."
else
    # Bestehende PATH-Zeile entfernen falls vorhanden, neu schreiben
    if [ -f "${SSH_ENV}" ]; then
        grep -v '^PATH=' "${SSH_ENV}" > "${SSH_ENV}.tmp" && mv "${SSH_ENV}.tmp" "${SSH_ENV}"
    fi
    printf 'PATH=%s\n' "${NAS_PATH}" >> "${SSH_ENV}"
    ok "~/.ssh/environment: PATH gesetzt."
fi

# ── 2. PermitUserEnvironment in sshd_config aktivieren ─────────────────────────
SSHD_CONF="/etc/ssh/sshd_config"
info "Pruefe PermitUserEnvironment in ${SSHD_CONF} ..."

if grep -q '^PermitUserEnvironment yes' "${SSHD_CONF}" 2>/dev/null; then
    ok "PermitUserEnvironment bereits aktiv."
elif grep -q 'PermitUserEnvironment' "${SSHD_CONF}" 2>/dev/null; then
    sed -i 's/^#\?PermitUserEnvironment.*/PermitUserEnvironment yes/' "${SSHD_CONF}"
    ok "PermitUserEnvironment aktiviert."
else
    printf '\nPermitUserEnvironment yes\n' >> "${SSHD_CONF}"
    ok "PermitUserEnvironment hinzugefuegt."
fi

# ── 3. .profile sicherstellen (Fallback fuer interaktive Login-Shells) ────────
PROFILE="${HOME}/.profile"
if grep -q 'container-station' "${PROFILE}" 2>/dev/null; then
    ok ".profile bereits gesetzt -- ueberspringe."
else
    cat >> "${PROFILE}" << 'EOF'

# bootstrap-foundation: QNAP Container Station + Entware PATH
export PATH="/share/CACHEDEV1_DATA/.qpkg/container-station/bin:/opt/bin:/usr/local/bin:$PATH"
EOF
    ok ".profile: PATH Eintrag hinzugefuegt."
fi

# ── 4. Sofort-Test ───────────────────────────────────────────────────────────────────
export PATH="${NAS_PATH}"
if command -v docker >/dev/null 2>&1; then
    ok "docker: $(docker --version 2>/dev/null | head -1)"
else
    warn "docker nicht gefunden -- Container Station installiert?"
fi
command -v git >/dev/null 2>&1 && ok "git: $(git --version)"

# ── 5. SSHD neu laden ─────────────────────────────────────────────────────────────────
info "Lade sshd Konfiguration neu ..."
if kill -HUP "$(cat /var/run/sshd.pid 2>/dev/null || pgrep sshd | head -1)" 2>/dev/null; then
    ok "sshd neu geladen -- ~/.ssh/environment ab sofort aktiv."
else
    warn "sshd HUP fehlgeschlagen -- ab naechster SSH-Session aktiv."
fi

printf '\n'
ok "NAS-Basis gesetzt. Ab naechster SSH-Session: docker/git ohne PATH-Prefix."
printf "  Test: ssh nas 'docker ps'\n"
