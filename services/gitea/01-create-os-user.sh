#!/usr/bin/env bash
# services/gitea/01-create-os-user.sh
# ---------------------------------------------------------------------------
# Legt den dedizierten Linux-Systemuser fuer den Gitea-Dienst an.
#
# Muss als root ausgefuehrt werden.
# ---------------------------------------------------------------------------
set -euo pipefail

GITEA_USER="${1:-gitea}"
GITEA_HOME="/var/lib/${GITEA_USER}"

if [[ $EUID -ne 0 ]]; then echo "Bitte als root ausfuehren."; exit 1; fi

if id "$GITEA_USER" >/dev/null 2>&1; then
  echo "User '${GITEA_USER}' existiert bereits – ueberspringe."
else
  useradd \
    --system \
    --create-home \
    --home-dir "${GITEA_HOME}" \
    --shell /bin/bash \
    "${GITEA_USER}"
  echo "User '${GITEA_USER}' angelegt."
fi

install -d -o "${GITEA_USER}" -g "${GITEA_USER}" -m 0750 /etc/gitea
for d in custom data log repositories; do
  install -d -o "${GITEA_USER}" -g "${GITEA_USER}" -m 0750 "${GITEA_HOME}/${d}"
done
chmod 750 "${GITEA_HOME}"

echo
echo "=== OS-User fertig ==="
echo "  User  : ${GITEA_USER}"
echo "  Home  : ${GITEA_HOME}"
echo "  Conf  : /etc/gitea/"
echo
echo "Naechster Schritt:"
echo "  bash services/gitea/02-configure-haproxy.sh <subdomain> <gitea-host-ip>"
