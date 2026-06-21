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

<<<<<<< HEAD
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
||||||| 12074a8
# services/forge/init-keepass-db.sh
# Creates a new KeePass database for bootstrap-foundation secrets.
#
# Creates:
#   ~/KeePassLatest.kdbx          (new or existing)
#   Group: bootstrap-foundation
#   Group: bootstrap-foundation/forge
#
# Requires: keepassxc-cli in PATH
# Install on QNAP x86_64: see CREDENTIAL-BACKENDS.md
#
# Usage:
#   bash services/forge/init-keepass-db.sh
#   KL_KEEPASS_DB=/share/homes/DOMAIN=AD/koni/Database2.kdbx \
#     bash services/forge/init-keepass-db.sh
=======
# services/forge/init-keepass-db.sh
# Creates a new KeePass database for bootstrap-foundation secrets.
#
# Creates:
#   ~/KeePassLatest.kdbx          (new or existing)
#   Group: bootstrap-foundation
#   Group: bootstrap-foundation/forge
#
# Usage:
#   bash services/forge/init-keepass-db.sh
#   KL_KEEPASS_DB=/path/to/vault.kdbx bash services/forge/init-keepass-db.sh
>>>>>>> origin/feature/enter-once-cache

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
<<<<<<< HEAD
    error "keepassxc-cli nicht gefunden.\n" \
          "       Siehe CREDENTIAL-BACKENDS.md fuer Installationshinweise.\n" \
          "       GPG-Fallback: CREDENTIAL_BACKEND=gpg bash services/forge/create-user.sh"
||||||| 12074a8
  echo "ERROR: keepassxc-cli not found."
  echo "Siehe CREDENTIAL-BACKENDS.md fuer Installationsanleitung."
  exit 1
=======
  echo "ERROR: keepassxc-cli not found."
  echo "Install: https://keepassxc.org/download/"
  echo "QNAP x86_64 AppImage:"
  echo "  wget https://github.com/keepassxreboot/keepassxc/releases/latest/download/KeePassXC-*-x86_64.AppImage"
  exit 1
>>>>>>> origin/feature/enter-once-cache
fi

<<<<<<< HEAD
KEEPASSXC_VERSION=$("$KEEPASSXC_CLI" --version 2>&1 | head -1)
info "keepassxc-cli: $KEEPASSXC_VERSION"
info "Datenbank:     $KL_KEEPASS_DB"
info "Root-Gruppe:   $KL_KEEPASS_GROUP"
||||||| 12074a8
echo
echo '=== KeePass DB initialisieren ==='
printf '  Zieldatei: %s\n' "$KL_KEEPASS_DB"
echo
=======
echo
echo '=== KeePass DB initialisieren ==='
printf 'Zieldatei: %s\n' "$KL_KEEPASS_DB"
echo
>>>>>>> origin/feature/enter-once-cache

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
<<<<<<< HEAD
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
||||||| 12074a8
  echo "  Datenbank existiert bereits: ${KL_KEEPASS_DB}"
  echo "  Ueberspringe Erstellung - nur Gruppen werden sichergestellt."
=======
  echo "Datenbank existiert bereits: ${KL_KEEPASS_DB}"
  echo "Ueberspringe Erstellung - nur Gruppen werden sichergestellt."
>>>>>>> origin/feature/enter-once-cache
else
    _ask_master_password

    DB_DIR=$(dirname "$KL_KEEPASS_DB")
    mkdir -p "$DB_DIR"

<<<<<<< HEAD
    info "Erstelle neue Datenbank..."
    printf '%s\n' "$KL_KEEPASS_MASTER" \
        | "$KEEPASSXC_CLI" db-create --no-password \
            --set-password \
            "$KL_KEEPASS_DB" >/dev/null
    ok "Datenbank erstellt: $KL_KEEPASS_DB"
||||||| 12074a8
  if [ "$DB_PASS" != "$DB_PASS2" ]; then
    echo 'ERROR: Passwoerter stimmen nicht ueberein.'
    exit 1
  fi

  printf '%s\n' "$DB_PASS" \
    | "$KEEPASSXC_CLI" db-create \
        --set-password \
        --no-password \
        "$KL_KEEPASS_DB"
  echo "  Datenbank erstellt: ${KL_KEEPASS_DB}"
  DB_PASS="" DB_PASS2=""
=======
  if [ "$DB_PASS" != "$DB_PASS2" ]; then
    echo 'ERROR: Passwoerter stimmen nicht ueberein.'
    exit 1
  fi

  printf '%s\n' "$DB_PASS" \
    | "$KEEPASSXC_CLI" db-create \
        --set-password \
        --no-password \
        "$KL_KEEPASS_DB"
  echo "Datenbank erstellt: ${KL_KEEPASS_DB}"
  DB_PASS=""
>>>>>>> origin/feature/enter-once-cache
fi

<<<<<<< HEAD
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
||||||| 12074a8
echo
echo '  Gruppen anlegen (falls nicht vorhanden) ...'

printf 'Master-Passwort zum Oeffnen: '
stty -echo 2>/dev/null || true
read -r DB_OPEN_PASS
stty echo 2>/dev/null || true
printf '\n'

for group in 'bootstrap-foundation' 'bootstrap-foundation/forge'; do
  result=$(printf '%s\n' "$DB_OPEN_PASS" \
    | "$KEEPASSXC_CLI" mkdir --no-password "$KL_KEEPASS_DB" "$group" 2>&1 || true)
  if printf '%s' "$result" | grep -qi 'exists\|bereits\|already'; then
    printf '  Gruppe vorhanden: %s\n' "$group"
  else
    printf '  Gruppe erstellt:  %s\n' "$group"
  fi
=======
echo
echo 'Gruppen anlegen (falls nicht vorhanden) ...'

printf 'Master-Passwort zum Oeffnen: '
stty -echo 2>/dev/null || true
read -r DB_OPEN_PASS
stty echo 2>/dev/null || true
printf '\n'

# keepassxc-cli mkdir erstellt ggf. uebergeordnete Gruppen automatisch
for group in 'bootstrap-foundation' 'bootstrap-foundation/forge'; do
  result=$(printf '%s\n' "$DB_OPEN_PASS" \
    | "$KEEPASSXC_CLI" mkdir --no-password "$KL_KEEPASS_DB" "$group" 2>&1 || true)
  if echo "$result" | grep -qi 'exists\|bereits'; then
    printf '  Gruppe vorhanden: %s\n' "$group"
  else
    printf '  Gruppe erstellt:  %s\n' "$group"
  fi
>>>>>>> origin/feature/enter-once-cache
done

<<<<<<< HEAD
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
||||||| 12074a8
echo
echo '=== Fertig ==='
printf '  Datenbank : %s\n' "$KL_KEEPASS_DB"
echo '  Gruppen   : bootstrap-foundation, bootstrap-foundation/forge'
echo
echo 'Naechste Schritte:'
echo '  1. Symlink setzen (optional, fuer ~/KeePassLatest.kdbx):'
printf "     ln -sf '%s' ~/KeePassLatest.kdbx\n" "$KL_KEEPASS_DB"
echo '  2. Shell-Config (z.B. ~/.profile):'
printf "     export KL_KEEPASS_DB='%s'\n" "$KL_KEEPASS_DB"
echo '  3. User + Token anlegen:'
echo '     bash services/forge/create-user.sh'
=======
echo
echo '=== Fertig ==='
printf '  Datenbank : %s\n' "$KL_KEEPASS_DB"
echo '  Gruppe    : bootstrap-foundation/forge'
echo
echo 'Naechste Schritte:'
echo '  1. Symlink anlegen (falls gewuenscht):'
printf "     ln -sf '%s' ~/KeePassLatest.kdbx\n" "$KL_KEEPASS_DB"
echo '  2. User anlegen:'
echo '     bash services/forge/create-user.sh'
echo '  3. KL_KEEPASS_DB in deine Shell-Config eintragen:'
printf "     export KL_KEEPASS_DB='%s'\n" "$KL_KEEPASS_DB"
echo
echo 'Token werden automatisch unter bootstrap-foundation/forge/<user>_token gespeichert.'
>>>>>>> origin/feature/enter-once-cache
