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
<<<<<<< HEAD
# Requires: keepassxc-cli in PATH
# Install on QNAP x86_64: see CREDENTIAL-BACKENDS.md
#
# Usage:
#   bash services/forge/init-keepass-db.sh
#   KL_KEEPASS_DB=/share/homes/DOMAIN=AD/koni/Database2.kdbx \
#     bash services/forge/init-keepass-db.sh
=======
# Usage:
#   bash services/forge/init-keepass-db.sh
#   KL_KEEPASS_DB=/path/to/vault.kdbx bash services/forge/init-keepass-db.sh
>>>>>>> ac4e492 (feat(lib/input-cache): add keepassxc backend alongside gpg + plain)

: "${KEEPASSXC_CLI:=keepassxc-cli}"
: "${KL_KEEPASS_DB:=${HOME}/KeePassLatest.kdbx}"

if ! command -v "$KEEPASSXC_CLI" >/dev/null 2>&1; then
  echo "ERROR: keepassxc-cli not found."
<<<<<<< HEAD
  echo "Siehe CREDENTIAL-BACKENDS.md fuer Installationsanleitung."
=======
  echo "Install: https://keepassxc.org/download/"
  echo "QNAP x86_64 AppImage:"
  echo "  wget https://github.com/keepassxreboot/keepassxc/releases/latest/download/KeePassXC-*-x86_64.AppImage"
>>>>>>> ac4e492 (feat(lib/input-cache): add keepassxc backend alongside gpg + plain)
  exit 1
fi

echo
echo '=== KeePass DB initialisieren ==='
<<<<<<< HEAD
printf '  Zieldatei: %s\n' "$KL_KEEPASS_DB"
echo

if [ -f "$KL_KEEPASS_DB" ]; then
  echo "  Datenbank existiert bereits: ${KL_KEEPASS_DB}"
  echo "  Ueberspringe Erstellung - nur Gruppen werden sichergestellt."
=======
printf 'Zieldatei: %s\n' "$KL_KEEPASS_DB"
echo

if [ -f "$KL_KEEPASS_DB" ]; then
  echo "Datenbank existiert bereits: ${KL_KEEPASS_DB}"
  echo "Überspringe Erstellung – nur Gruppen werden sichergestellt."
>>>>>>> ac4e492 (feat(lib/input-cache): add keepassxc backend alongside gpg + plain)
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
<<<<<<< HEAD
    echo 'ERROR: Passwoerter stimmen nicht ueberein.'
=======
    echo 'ERROR: Passwörter stimmen nicht überein.'
>>>>>>> ac4e492 (feat(lib/input-cache): add keepassxc backend alongside gpg + plain)
    exit 1
  fi

  printf '%s\n' "$DB_PASS" \
    | "$KEEPASSXC_CLI" db-create \
        --set-password \
        --no-password \
        "$KL_KEEPASS_DB"
<<<<<<< HEAD
  echo "  Datenbank erstellt: ${KL_KEEPASS_DB}"
  DB_PASS="" DB_PASS2=""
fi

echo
echo '  Gruppen anlegen (falls nicht vorhanden) ...'

printf 'Master-Passwort zum Oeffnen: '
=======
  echo "Datenbank erstellt: ${KL_KEEPASS_DB}"
  DB_PASS=""
fi

echo
echo 'Gruppen anlegen (falls nicht vorhanden) …'

printf 'Master-Passwort zum Öffnen: '
>>>>>>> ac4e492 (feat(lib/input-cache): add keepassxc backend alongside gpg + plain)
stty -echo 2>/dev/null || true
read -r DB_OPEN_PASS
stty echo 2>/dev/null || true
printf '\n'

<<<<<<< HEAD
for group in 'bootstrap-foundation' 'bootstrap-foundation/forge'; do
  result=$(printf '%s\n' "$DB_OPEN_PASS" \
    | "$KEEPASSXC_CLI" mkdir --no-password "$KL_KEEPASS_DB" "$group" 2>&1 || true)
  if printf '%s' "$result" | grep -qi 'exists\|bereits\|already'; then
=======
# keepassxc-cli mkdir erstellt ggf. übergeordnete Gruppen automatisch
for group in 'bootstrap-foundation' 'bootstrap-foundation/forge'; do
  result=$(printf '%s\n' "$DB_OPEN_PASS" \
    | "$KEEPASSXC_CLI" mkdir --no-password "$KL_KEEPASS_DB" "$group" 2>&1 || true)
  if echo "$result" | grep -qi 'exists\|bereits'; then
>>>>>>> ac4e492 (feat(lib/input-cache): add keepassxc backend alongside gpg + plain)
    printf '  Gruppe vorhanden: %s\n' "$group"
  else
    printf '  Gruppe erstellt:  %s\n' "$group"
  fi
done
<<<<<<< HEAD
DB_OPEN_PASS=""
=======
>>>>>>> ac4e492 (feat(lib/input-cache): add keepassxc backend alongside gpg + plain)

echo
echo '=== Fertig ==='
printf '  Datenbank : %s\n' "$KL_KEEPASS_DB"
<<<<<<< HEAD
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
echo '  Gruppe    : bootstrap-foundation/forge'
echo
echo 'Nächste Schritte:'
echo '  1. Symlink anlegen (falls gewünscht):'
printf "     ln -sf '%s' ~/KeePassLatest.kdbx\n" "$KL_KEEPASS_DB"
echo '  2. User anlegen:'
echo '     bash services/forge/create-user.sh'
echo '  3. KL_KEEPASS_DB in deine Shell-Config eintragen:'
printf "     export KL_KEEPASS_DB='%s'\n" "$KL_KEEPASS_DB"
echo
echo 'Token werden automatisch unter bootstrap-foundation/forge/<user>_token gespeichert.'
>>>>>>> ac4e492 (feat(lib/input-cache): add keepassxc backend alongside gpg + plain)
