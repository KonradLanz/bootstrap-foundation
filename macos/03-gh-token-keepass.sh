#!/usr/bin/env bash
# macos/03-gh-token-keepass.sh
# ---------------------------------------------------------------------------
# GitHub PAT in KeePassXC speichern.
#
# Liest den aktuell von gh gespeicherten Token (falls vorhanden) und
# legt ihn in der KeePass-Datenbank unter
#   bootstrap-foundation/github/<GITHUB_USER>_pat
# ab.
#
# Alternativ kann ein Token manuell eingegeben werden.
#
# Voraussetzung:
#   - keepassxc-cli in PATH (brew install keepassxc)
#   - KeePass-DB existiert unter KL_KEEPASS_DB (default: ~/KeePassLatest.kdbx)
#   - lib/secret-backends.sh erreichbar
# ---------------------------------------------------------------------------
set -euo pipefail

GITHUB_USER="${GITHUB_USER:-KonradLanz}"
GIT_BASE="${GIT_BASE:-$HOME/git}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Homebrew PATH
[[ -f /opt/homebrew/bin/brew ]] && eval "$(/opt/homebrew/bin/brew shellenv)"

# secret-backends.sh laden
if [[ -f "${BOOTSTRAP_ROOT}/lib/secret-backends.sh" ]]; then
  # shellcheck source=/dev/null
  . "${BOOTSTRAP_ROOT}/lib/secret-backends.sh"
else
  echo "ERROR: ${BOOTSTRAP_ROOT}/lib/secret-backends.sh nicht gefunden."
  echo "       Bitte bootstrap-foundation klonen:"
  echo "       git clone https://github.com/KonradLanz/bootstrap-foundation.git ${GIT_BASE}/bootstrap-foundation"
  exit 1
fi

echo
echo '=== GitHub PAT in KeePassXC speichern ==='

# Pruefen ob keepassxc verfuegbar
if ! sb_keepass_available 2>/dev/null; then
  echo '[WARN] keepassxc-cli oder KeePass-DB nicht gefunden.'
  echo '       Installieren: brew install keepassxc'
  printf '       KL_KEEPASS_DB: %s\n' "${KL_KEEPASS_DB:-~/KeePassLatest.kdbx}"
  echo
  echo 'Datenbank anlegen:'
  echo "  bash ${BOOTSTRAP_ROOT}/services/forge/init-keepass-db.sh"
  exit 1
fi

# Gruppe sicherstellen
KEY="github/${GITHUB_USER}_pat"
KP_GROUP="bootstrap-foundation/github"

# Versuche Token aus gh zu lesen
GH_TOKEN=""
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  GH_TOKEN=$(gh auth token 2>/dev/null || true)
fi

if [[ -n "$GH_TOKEN" ]]; then
  echo "Token aus gh gelesen (${#GH_TOKEN} Zeichen)."
  read -r -p 'Diesen Token in KeePass speichern? [Y/n] ' SAVE_FROM_GH
  SAVE_FROM_GH="${SAVE_FROM_GH:-Y}"
  [[ "$SAVE_FROM_GH" =~ ^[Nn]$ ]] && GH_TOKEN=""
fi

if [[ -z "$GH_TOKEN" ]]; then
  echo
  echo 'PAT manuell eingeben (oder erzeugen unter https://github.com/settings/tokens/new):'
  echo '  Benoetigt: repo, read:org, workflow'
  printf 'PAT: '
  stty -echo 2>/dev/null || true
  read -r GH_TOKEN
  stty echo 2>/dev/null || true
  printf '\n'
fi

[[ -z "$GH_TOKEN" ]] && { echo 'Kein Token eingegeben. Abbruch.'; exit 1; }

# Gruppe anlegen falls noetig
printf 'KeePass Master-Passwort: '
stty -echo 2>/dev/null || true
read -r KL_KEEPASS_PASS
stty echo 2>/dev/null || true
export KL_KEEPASS_PASS
printf '\n'

for group in 'bootstrap-foundation' 'bootstrap-foundation/github'; do
  result=$(printf '%s\n' "$KL_KEEPASS_PASS" \
    | "${KEEPASSXC_CLI:-keepassxc-cli}" mkdir --no-password \
        "${KL_KEEPASS_DB:-$HOME/KeePassLatest.kdbx}" "$group" 2>&1 || true)
  printf '%s' "$result" | grep -qi 'exists\|bereits\|already' \
    && printf '  Gruppe vorhanden: %s\n' "$group" \
    || printf '  Gruppe erstellt:  %s\n' "$group"
done

# Token speichern
sb_keepass_write "${KEY}" "${GH_TOKEN}" "${GITHUB_USER}"
GH_TOKEN=""
KL_KEEPASS_PASS=""

echo
echo '=== Fertig ==='
printf '  KeePass-Eintrag: bootstrap-foundation/%s\n' "$KEY"
echo
echo 'Token lesen (Kontrolle):'
printf '  keepassxc-cli show -a password %s bootstrap-foundation/%s\n' \
  "${KL_KEEPASS_DB:-~/KeePassLatest.kdbx}" "$KEY"
echo
echo 'Naechster Schritt:'
echo "  bash ${GIT_BASE}/bootstrap-foundation/macos/04-ssh-key-github.sh"
