#!/usr/bin/env bash
# services/forgejo/04-create-repo.sh
# ---------------------------------------------------------------------------
# Legt ein privates Repo per Forgejo-CLI an.
#
# Standardwerte:
#   Owner : forge-bot
#   Repo  : bootstrap-foundation (oder per REPO_NAME ueberschreiben)
#
# Aufruf:
#   bash services/forgejo/04-create-repo.sh
#   REPO_OWNER=myuser REPO_NAME=myrepo bash services/forgejo/04-create-repo.sh
# ---------------------------------------------------------------------------
set -euo pipefail

FORGEJO_BIN="${FORGEJO_BIN:-/usr/local/bin/forgejo}"
FORGEJO_CFG="${FORGEJO_CFG:-/etc/forgejo/app.ini}"
FORGEJO_SYS_USER="${FORGEJO_SYS_USER:-forgejo}"
OWNER="${REPO_OWNER:-forge-bot}"
REPO="${REPO_NAME:-bootstrap-foundation}"

if [[ ! -x "${FORGEJO_BIN}" ]]; then
  echo "ERROR: Forgejo-Binary nicht gefunden: ${FORGEJO_BIN}"
  exit 1
fi

if [[ $EUID -eq 0 ]]; then
  RUN="sudo -u ${FORGEJO_SYS_USER} ${FORGEJO_BIN} --config ${FORGEJO_CFG}"
else
  RUN="${FORGEJO_BIN} --config ${FORGEJO_CFG}"
fi

if ${RUN} admin repo create \
    --owner "${OWNER}" \
    --name "${REPO}" \
    --private 2>&1; then
  echo "Repo '${OWNER}/${REPO}' angelegt (privat)."
else
  echo "[WARN] Repo '${OWNER}/${REPO}' existiert moeglicherweise bereits."
fi

echo
echo "=== Repo-Einrichtung abgeschlossen ==="
echo "  Owner: ${OWNER}"
echo "  Repo : ${REPO}"
echo "  URL  : https://<deine-subdomain>/${OWNER}/${REPO}"
echo
echo "Nur der Owner '${OWNER}' hat Vollzugriff."
echo "Weitere Berechtigungen koennen ueber die Forgejo-Web-UI vergeben werden."
