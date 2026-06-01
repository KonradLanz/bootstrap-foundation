#!/usr/bin/env bash
# services/forge/init-keepass-db.sh
#
# Legt eine neue KeePass-Datenbank an (oder prueft eine bestehende)
# und erstellt die Gruppenstruktur fuer bootstrap-foundation.
#
# Aufruf:
#   bash services/forge/init-keepass-db.sh
#
# Optionen (als Umgebungsvariablen):
#   KL_KEEPASS_DB      Pfad zur .kdbx-Datei    (default: ~/KeePassLatest.kdbx)
#   KL_KEEPASS_GROUP   Root-Gruppe             (default: bootstrap-foundation)
#   KEEPASSXC_CLI      Pfad zu keepassxc-cli   (default: keepassxc-cli)
#
# Voraussetzung:  keepassxc-cli im PATH
# Fallback:       Wenn keepassxc-cli fehlt, bricht das Skript ab und
#                 verweist auf CREDENTIAL-BACKENDS.md fuer GPG-Alternative.
#
# Nach dem Aufruf:
#   .gitignore wird um *.kdbx ergaenzt (falls noch nicht vorhanden)
################################################################################
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

: "${KEEPASSXC_CLI:=keepassxc-cli}"
: "${KL_KEEPASS_DB:=${HOME}/KeePassLatest.kdbx}"
: "${KL_KEEPASS_GROUP:=bootstrap-foundation}"

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
input()   { printf "${YELLOW}[INPUT]${NC}   %s" "$*" >&2; }

# ── Voraussetzungen pruefen ───────────────────────────────────────────────────
if ! command -v "$KEEPASSXC_CLI" >/dev/null 2>&1; then
    error "keepassxc-cli nicht gefunden.\n" \
          "       Siehe CREDENTIAL-BACKENDS.md fuer Installationshinweise.\n" \
          "       GPG-Fallback: CREDENTIAL_BACKEND=gpg bash services/forge/create-user.sh"
fi

KEEPASSXC_VERSION=$("$KEEPASSXC_CLI" --version 2>&1 | head -1)
info "keepassxc-cli: $KEEPASSXC_VERSION"
info "Datenbank:     $KL_KEEPASS_DB"
info "Root-Gruppe:   $KL_KEEPASS_GROUP"

# ── Masterpasswort abfragen ───────────────────────────────────────────────────
_ask_master_password() {
    _pw1=""
    _pw2=""
    while true; do
        input "Neues KeePass-Masterpasswort: "
        stty -echo 2>/dev/null || true
        read -r _pw1
        stty echo  2>/dev/null || true
        printf '\n' >&2

        if [ ${#_pw1} -lt 12 ]; then
            warn "Passwort zu kurz (mind. 12 Zeichen). Bitte nochmals."
            continue
        fi

        input "Masterpasswort bestaetigen:  "
        stty -echo 2>/dev/null || true
        read -r _pw2
        stty echo  2>/dev/null || true
        printf '\n' >&2

        if [ "$_pw1" = "$_pw2" ]; then
            break
        fi
        warn "Passwoerter stimmen nicht ueberein. Bitte nochmals."
    done
    # Ergebnis in globale Variable schreiben (kein Subshell-Trap)
    KL_KEEPASS_MASTER="$_pw1"
}

# ── Datenbank anlegen oder pruefen ────────────────────────────────────────────
if [ -f "$KL_KEEPASS_DB" ]; then
    warn "Datenbank existiert bereits: $KL_KEEPASS_DB"
    info "Ueberspringe Erstellung — pruefe Zugaenglichkeit..."

    input "Masterpasswort fuer bestehende DB: "
    stty -echo 2>/dev/null || true
    read -r KL_KEEPASS_MASTER
    stty echo  2>/dev/null || true
    printf '\n' >&2

    if ! printf '%s\n' "$KL_KEEPASS_MASTER" \
            | "$KEEPASSXC_CLI" ls --no-password "$KL_KEEPASS_DB" >/dev/null 2>&1; then
        error "Masterpasswort falsch oder Datenbank beschaedigt."
    fi
    ok "Bestehende Datenbank ist zugaenglich."
else
    _ask_master_password

    DB_DIR=$(dirname "$KL_KEEPASS_DB")
    mkdir -p "$DB_DIR"

    info "Erstelle neue Datenbank..."
    printf '%s\n' "$KL_KEEPASS_MASTER" \
        | "$KEEPASSXC_CLI" db-create --no-password \
            --set-password \
            "$KL_KEEPASS_DB" >/dev/null
    ok "Datenbank erstellt: $KL_KEEPASS_DB"
fi

# ── Gruppenstruktur anlegen ───────────────────────────────────────────────────
# keepassxc-cli mkdir legt Gruppen an; ist idempotent wenn Gruppe existiert.
for _grp in \
    "${KL_KEEPASS_GROUP}" \
    "${KL_KEEPASS_GROUP}/forge"
do
    _exists=$(printf '%s\n' "$KL_KEEPASS_MASTER" \
        | "$KEEPASSXC_CLI" ls --no-password \
            "$KL_KEEPASS_DB" "$_grp" 2>/dev/null || true)
    if [ -z "$_exists" ]; then
        printf '%s\n' "$KL_KEEPASS_MASTER" \
            | "$KEEPASSXC_CLI" mkdir --no-password \
                "$KL_KEEPASS_DB" "$_grp" >/dev/null 2>&1 || true
        ok "Gruppe erstellt: $_grp"
    else
        info "Gruppe existiert: $_grp"
    fi
done

# ── .gitignore ergaenzen ──────────────────────────────────────────────────────
GITIGNORE="${REPO_ROOT}/.gitignore"
if ! grep -qF '*.kdbx' "$GITIGNORE" 2>/dev/null; then
    printf '\n# KeePass-Datenbank — NIEMALS committen\n*.kdbx\n' >> "$GITIGNORE"
    ok ".gitignore: *.kdbx ergaenzt"
else
    info ".gitignore: *.kdbx bereits eingetragen"
fi

# ── Abschluss ─────────────────────────────────────────────────────────────────
printf '\n'
ok  "KeePass-Datenbank bereit."
info "Naechster Schritt:"
info "  bash services/forge/create-user.sh --admin forgejo-admin"
info "  bash services/forge/create-user.sh structured-pdf"
printf '\n'
info "Pfad-Override fuer eigene DB:"
info "  KL_KEEPASS_DB=/share/homes/.../Database2.kdbx \\"
info "    bash services/forge/init-keepass-db.sh"
printf '\n'
