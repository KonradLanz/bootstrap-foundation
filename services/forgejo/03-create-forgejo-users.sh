#!/usr/bin/env bash
# services/forgejo/03-create-forgejo-users.sh
# ---------------------------------------------------------------------------
# Legt den Forgejo-Admin und einen optionalen Projekt-User per CLI an.
# Passwort wird wahlweise interaktiv abgefragt ODER aus KeePass gelesen
# (via lib/secret-backends.sh, lazy-init).
#
# Muss als root oder als 'forgejo'-Systemuser ausgefuehrt werden.
#
# Credential-Backend:
#   SB_BACKEND=keepassxc  (Standard) -> KeePass via lib/secret-backends.sh
#   SB_BACKEND=plain                 -> interaktive Passwort-Eingabe
# ---------------------------------------------------------------------------
set -euo pipefail

FORGEJO_BIN="${FORGEJO_BIN:-/usr/local/bin/forgejo}"
FORGEJO_CFG="${FORGEJO_CFG:-/etc/forgejo/app.ini}"
FORGEJO_SYS_USER="${FORGEJO_SYS_USER:-forgejo}"
SB_BACKEND="${SB_BACKEND:-keepassxc}"

# Pfad zu secret-backends.sh (relativ zum Repo-Root)
_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_LIB="${_SCRIPT_DIR}/../../lib/secret-backends.sh"

if [[ ! -x "${FORGEJO_BIN}" ]]; then
  echo "ERROR: Forgejo-Binary nicht gefunden: ${FORGEJO_BIN}"
  echo "       Setze FORGEJO_BIN=/pfad/zu/forgejo"
  exit 1
fi

# Hilfsfunktion: Forgejo-CLI als Systemuser ausfuehren
forgejo_cli() {
  if [[ $EUID -eq 0 ]]; then
    sudo -u "${FORGEJO_SYS_USER}" "${FORGEJO_BIN}" --config "${FORGEJO_CFG}" "$@"
  else
    "${FORGEJO_BIN}" --config "${FORGEJO_CFG}" "$@"
  fi
}

# ---------------------------------------------------------------------------
# Passwort-Hilfsfunktionen
# ---------------------------------------------------------------------------
_read_pass_interactive() {
  local label="$1" pass pass2
  printf 'Passwort fuer "%s": ' "${label}"
  stty -echo 2>/dev/null || true
  read -r pass
  stty echo 2>/dev/null || true
  printf '\n'
  printf 'Passwort (wiederholen): '
  stty -echo 2>/dev/null || true
  read -r pass2
  stty echo 2>/dev/null || true
  printf '\n'
  if [[ "${pass}" != "${pass2}" ]]; then
    echo "ERROR: Passwoerter stimmen nicht ueberein."
    exit 1
  fi
  printf '%s' "${pass}"
}

_get_password() {
  local key="$1" label="$2"
  if [[ "${SB_BACKEND}" == "keepassxc" ]] && [[ -f "${_LIB}" ]]; then
    # shellcheck source=../../lib/secret-backends.sh
    . "${_LIB}"
    local stored
    stored="$(sb_read keepassxc "${key}" 2>/dev/null || true)"
    if [[ -n "${stored}" ]]; then
      echo "[sb] Passwort fuer '${key}' aus KeePass gelesen." >&2
      printf '%s' "${stored}"
      return
    fi
    # Nicht in KeePass -> interaktiv abfragen und speichern
    local pass
    pass="$(_read_pass_interactive "${label}")"
    sb_write keepassxc "${key}" "${pass}" "forgejo"
    echo "[sb] Passwort fuer '${key}' in KeePass gespeichert." >&2
    printf '%s' "${pass}"
  else
    _read_pass_interactive "${label}"
  fi
}

# ---------------------------------------------------------------------------
# 1. Admin-User anlegen
# ---------------------------------------------------------------------------
ADMIN_USER="forgejo-admin"
ADMIN_MAIL="forgejo-admin@example.lan"
ADMIN_KP_KEY="forgejo/admin_pass"

ADMIN_PASS="$(_get_password "${ADMIN_KP_KEY}" "${ADMIN_USER}")"

if forgejo_cli admin user create \
    --admin \
    --username "${ADMIN_USER}" \
    --password "${ADMIN_PASS}" \
    --email "${ADMIN_MAIL}" 2>&1; then
  echo "Admin-User '${ADMIN_USER}' angelegt."
else
  echo "[WARN] Admin-User '${ADMIN_USER}' existiert moeglicherweise bereits."
fi
ADMIN_PASS=""

# ---------------------------------------------------------------------------
# 2. Optionaler Projekt-User
# ---------------------------------------------------------------------------
if [[ "${CREATE_PROJ_USER:-1}" == "1" ]]; then
  PROJ_USER="${PROJ_USER:-forge-bot}"
  PROJ_MAIL="${PROJ_USER}@example.lan"
  PROJ_KP_KEY="forgejo/proj_${PROJ_USER}_pass"

  PROJ_PASS="$(_get_password "${PROJ_KP_KEY}" "${PROJ_USER}")"

  if forgejo_cli admin user create \
      --username "${PROJ_USER}" \
      --password "${PROJ_PASS}" \
      --email "${PROJ_MAIL}" 2>&1; then
    echo "Projekt-User '${PROJ_USER}' angelegt."
  else
    echo "[WARN] Projekt-User '${PROJ_USER}' existiert moeglicherweise bereits."
  fi
  PROJ_PASS=""
fi

# ---------------------------------------------------------------------------
# 3. Absicherung: DISABLE_REGISTRATION pruefen
# ---------------------------------------------------------------------------
if grep -q 'DISABLE_REGISTRATION.*=.*true' "${FORGEJO_CFG}" 2>/dev/null; then
  echo "app.ini: DISABLE_REGISTRATION=true bereits gesetzt."
else
  echo "[WARN] DISABLE_REGISTRATION nicht in app.ini gefunden."
  echo "       Bitte manuell sicherstellen:"
  echo "       DISABLE_REGISTRATION = true in [service]-Sektion."
fi

echo
echo "=== Forgejo-User-Einrichtung abgeschlossen ==="
echo "  Admin       : ${ADMIN_USER} (${ADMIN_MAIL})"
[[ "${CREATE_PROJ_USER:-1}" == "1" ]] && echo "  Projekt-User: ${PROJ_USER} (${PROJ_MAIL})"
echo "  Registrierung: deaktiviert"
echo
echo "Naechster Schritt:"
echo "  bash services/forgejo/04-create-repo.sh"
