#!/usr/bin/env bash
# services/gitea/03-create-gitea-users.sh
# ---------------------------------------------------------------------------
# Legt den Gitea-Admin und den Projekt-User 'structured-pdf' per CLI an.
# Danach wird die oeffentliche Registrierung deaktiviert (DISABLE_REGISTRATION).
#
# Muss als root oder als 'gitea'-Systemuser ausgefuehrt werden.
# ---------------------------------------------------------------------------
set -euo pipefail

GITEA_BIN="${GITEA_BIN:-/opt/gitea/gitea}"
GITEA_CFG="${GITEA_CFG:-/etc/gitea/app.ini}"
GITEA_SYS_USER="${GITEA_SYS_USER:-gitea}"

if [[ ! -x "${GITEA_BIN}" ]]; then
  echo "ERROR: Gitea-Binary nicht gefunden: ${GITEA_BIN}"
  echo "       Setze GITEA_BIN=/pfad/zu/gitea"
  exit 1
fi

# Hilfsfunktion: Gitea-CLI als Systemuser ausfuehren
gitea_cli() {
  sudo -u "${GITEA_SYS_USER}" "${GITEA_BIN}" --config "${GITEA_CFG}" "$@"
}

# ---------------------------------------------------------------------------
# 1. Admin-User anlegen
# ---------------------------------------------------------------------------
ADMIN_USER="gitea-admin"
ADMIN_MAIL="gitea-admin@example.lan"

printf 'Admin-Passwort fuer "%s": ' "${ADMIN_USER}"
stty -echo 2>/dev/null || true
read -r ADMIN_PASS
stty echo 2>/dev/null || true
printf '\n'

printf 'Admin-Passwort (wiederholen): '
stty -echo 2>/dev/null || true
read -r ADMIN_PASS2
stty echo 2>/dev/null || true
printf '\n'

if [[ "${ADMIN_PASS}" != "${ADMIN_PASS2}" ]]; then
  echo "ERROR: Passwoerter stimmen nicht ueberein."
  exit 1
fi
ADMIN_PASS2=""

if gitea_cli admin user create \
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
# 2. Projekt-User anlegen
# ---------------------------------------------------------------------------
PROJ_USER="structured-pdf"
PROJ_MAIL="structured-pdf@example.lan"

printf 'Passwort fuer Projekt-User "%s": ' "${PROJ_USER}"
stty -echo 2>/dev/null || true
read -r PROJ_PASS
stty echo 2>/dev/null || true
printf '\n'

printf 'Passwort (wiederholen): '
stty -echo 2>/dev/null || true
read -r PROJ_PASS2
stty echo 2>/dev/null || true
printf '\n'

if [[ "${PROJ_PASS}" != "${PROJ_PASS2}" ]]; then
  echo "ERROR: Passwoerter stimmen nicht ueberein."
  exit 1
fi
PROJ_PASS2=""

if gitea_cli admin user create \
    --username "${PROJ_USER}" \
    --password "${PROJ_PASS}" \
    --email "${PROJ_MAIL}" 2>&1; then
  echo "Projekt-User '${PROJ_USER}' angelegt."
else
  echo "[WARN] Projekt-User '${PROJ_USER}' existiert moeglicherweise bereits."
fi
PROJ_PASS=""

# ---------------------------------------------------------------------------
# 3. Registrierung deaktivieren (app.ini patch)
# ---------------------------------------------------------------------------
# DISABLE_REGISTRATION ist in 02-configure-haproxy.sh bereits gesetzt.
# Hier Absicherung per grep:
if grep -q 'DISABLE_REGISTRATION.*=.*true' "${GITEA_CFG}" 2>/dev/null; then
  echo "app.ini: DISABLE_REGISTRATION=true bereits gesetzt."
else
  echo "[WARN] DISABLE_REGISTRATION nicht in app.ini gefunden."
  echo "       Bitte manuell sicherstellen:"
  echo "       DISABLE_REGISTRATION = true in [service]-Sektion."
fi

echo
echo "=== Gitea-User-Einrichtung abgeschlossen ==="
echo "  Admin       : ${ADMIN_USER} (${ADMIN_MAIL})"
echo "  Projekt-User: ${PROJ_USER} (${PROJ_MAIL})"
echo "  Registrierung: deaktiviert"
echo
echo "Naechster Schritt:"
echo "  bash services/gitea/04-create-repo.sh"
