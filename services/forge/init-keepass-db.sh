#!/usr/bin/env bash
set -euo pipefail

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

: "${KEEPASSXC_CLI:=keepassxc-cli}"
: "${KL_KEEPASS_DB:=${HOME}/KeePassLatest.kdbx}"

if ! command -v "$KEEPASSXC_CLI" >/dev/null 2>&1; then
  echo "ERROR: keepassxc-cli not found."
  echo "Install: https://keepassxc.org/download/"
  echo "QNAP x86_64 AppImage:"
  echo "  wget https://github.com/keepassxreboot/keepassxc/releases/latest/download/KeePassXC-*-x86_64.AppImage"
  exit 1
fi

echo
echo '=== KeePass DB initialisieren ==='
printf 'Zieldatei: %s\n' "$KL_KEEPASS_DB"
echo

if [ -f "$KL_KEEPASS_DB" ]; then
  echo "Datenbank existiert bereits: ${KL_KEEPASS_DB}"
  echo "Ueberspringe Erstellung - nur Gruppen werden sichergestellt."
else
  printf 'Master-Passwort (neu): '
  stty -echo 2>/dev/null || true
  read -r DB_PASS
  stty echo 2>/dev/null || true
  printf '\n'

  printf 'Master-Passwort (wiederholen): '
  stty -echo 2>/dev/null || true
  read -r DB_PASS2
  stty echo 2>/dev/null || true
  printf '\n'

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
fi

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
done
DB_OPEN_PASS=""

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
