#!/usr/bin/env bash
# macos/03-gh-token-keepass.sh  — idempotent
# GitHub PAT in KeePassXC speichern.
# Beliebig oft aufrufbar: prueft ob Eintrag bereits existiert.
set -euo pipefail

GITHUB_USER="${GITHUB_USER:-KonradLanz}"
GIT_BASE="${GIT_BASE:-$HOME/git}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

_ok()   { printf '  [OK]  %s\n' "$1"; }
_skip() { printf '  [--]  %s\n' "$1"; }
_run()  { printf '  [>>]  %s\n' "$1"; }

[[ -f /opt/homebrew/bin/brew ]] && eval "$(/opt/homebrew/bin/brew shellenv)"

if [[ -f "${BOOTSTRAP_ROOT}/lib/secret-backends.sh" ]]; then
  # shellcheck source=/dev/null
  . "${BOOTSTRAP_ROOT}/lib/secret-backends.sh"
else
  echo "ERROR: ${BOOTSTRAP_ROOT}/lib/secret-backends.sh nicht gefunden."
  exit 1
fi

echo
echo '=== GitHub PAT in KeePassXC speichern (idempotent) ==='

if ! sb_keepass_available 2>/dev/null; then
  echo '  [WARN] keepassxc-cli oder KeePass-DB nicht gefunden.'
  echo '         brew install --cask keepassxc'
  printf '         KL_KEEPASS_DB: %s\n' "${KL_KEEPASS_DB:-~/KeePassLatest.kdbx}"
  echo
  echo '  Datenbank anlegen:'
  echo "    bash ${BOOTSTRAP_ROOT}/services/forge/init-keepass-db.sh"
  exit 1
fi

KEY="github/${GITHUB_USER}_pat"

# Master-PW einmalig abfragen (fuer exists-Check und ggf. Write)
printf '  KeePass Master-Passwort: '
stty -echo 2>/dev/null || true
read -r KL_KEEPASS_PASS
stty echo 2>/dev/null || true
export KL_KEEPASS_PASS
printf '\n'

# Pruefen ob Eintrag bereits existiert
EXISTING=$(printf '%s\n' "$KL_KEEPASS_PASS" \
  | "${KEEPASSXC_CLI:-keepassxc-cli}" locate --no-password \
      "${KL_KEEPASS_DB:-$HOME/KeePassLatest.kdbx}" \
      "bootstrap-foundation/${KEY}" 2>/dev/null || true)

if [[ -n "$EXISTING" ]]; then
  _skip "Eintrag existiert bereits: bootstrap-foundation/${KEY}"
  read -r -p '  Eintrag aktualisieren? [y/N] ' UPDATE
  [[ "$UPDATE" =~ ^[Yy]$ ]] || { KL_KEEPASS_PASS=""; echo '  Uebersprungen.'; exit 0; }
fi

# Token aus gh lesen oder manuell eingeben
GH_TOKEN=""
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  GH_TOKEN=$(gh auth token 2>/dev/null || true)
fi

if [[ -n "$GH_TOKEN" ]]; then
  _skip "Token aus gh gelesen (${#GH_TOKEN} Zeichen)"
  read -r -p '  Diesen Token speichern? [Y/n] ' SAVE_FROM_GH
  [[ "${SAVE_FROM_GH:-Y}" =~ ^[Nn]$ ]] && GH_TOKEN=""
fi

if [[ -z "$GH_TOKEN" ]]; then
  echo
  echo '  PAT eingeben (https://github.com/settings/tokens/new  Scopes: repo read:org workflow):'
  printf '  PAT: '
  stty -echo 2>/dev/null || true
  read -r GH_TOKEN
  stty echo 2>/dev/null || true
  printf '\n'
fi

[[ -z "$GH_TOKEN" ]] && { echo '  Kein Token. Abbruch.'; KL_KEEPASS_PASS=""; exit 1; }

# Gruppen anlegen (idempotent)
for group in 'bootstrap-foundation' 'bootstrap-foundation/github'; do
  result=$(printf '%s\n' "$KL_KEEPASS_PASS" \
    | "${KEEPASSXC_CLI:-keepassxc-cli}" mkdir --no-password \
        "${KL_KEEPASS_DB:-$HOME/KeePassLatest.kdbx}" "$group" 2>&1 || true)
  printf '%s' "$result" | grep -qi 'exists\|bereits\|already' \
    && _skip "Gruppe vorhanden: ${group}" \
    || _ok  "Gruppe erstellt:  ${group}"
done

sb_keepass_write "${KEY}" "${GH_TOKEN}" "${GITHUB_USER}"
GH_TOKEN=""
KL_KEEPASS_PASS=""

echo
echo '=== Fertig ==='
printf '  KeePass-Eintrag: bootstrap-foundation/%s\n' "$KEY"
echo
echo 'Naechster Schritt:'
echo "  bash ${GIT_BASE}/bootstrap-foundation/macos/04-ssh-key-github.sh"
