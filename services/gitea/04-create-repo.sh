#!/usr/bin/env bash
# services/gitea/04-create-repo.sh
# ---------------------------------------------------------------------------
# Legt das Repo 'structured-pdf-pipeline' als privates Repo des
# Projekt-Users 'structured-pdf' an.
#
# Nur der Owner (structured-pdf) hat Vollzugriff.
# ---------------------------------------------------------------------------
set -euo pipefail

GITEA_BIN="${GITEA_BIN:-/opt/gitea/gitea}"
GITEA_CFG="${GITEA_CFG:-/etc/gitea/app.ini}"
GITEA_SYS_USER="${GITEA_SYS_USER:-gitea}"
OWNER="${REPO_OWNER:-structured-pdf}"
REPO="${REPO_NAME:-structured-pdf-pipeline}"

if [[ ! -x "${GITEA_BIN}" ]]; then
  echo "ERROR: Gitea-Binary nicht gefunden: ${GITEA_BIN}"
  exit 1
fi

if sudo -u "${GITEA_SYS_USER}" "${GITEA_BIN}" --config "${GITEA_CFG}" \
    admin repo create \
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
echo "Weitere Berechtigungen koennen ueber die Gitea-Web-UI vergeben werden."
