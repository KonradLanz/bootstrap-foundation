#!/usr/bin/env bash
# services/forgejo/01-create-os-user.sh
# ---------------------------------------------------------------------------
# Legt den dedizierten Linux-Systemuser fuer den Forgejo-Dienst an.
#
# Muss als root ausgefuehrt werden.
# ---------------------------------------------------------------------------
set -euo pipefail

FORGEJO_USER="${1:-forgejo}"
FORGEJO_HOME="/var/lib/${FORGEJO_USER}"

if [[ $EUID -ne 0 ]]; then echo "Bitte als root ausfuehren."; exit 1; fi

if id "$FORGEJO_USER" >/dev/null 2>&1; then
  echo "User '${FORGEJO_USER}' existiert bereits – ueberspringe."
else
  useradd \
    --system \
    --create-home \
    --home-dir "${FORGEJO_HOME}" \
    --shell /bin/bash \
    "${FORGEJO_USER}"
  echo "User '${FORGEJO_USER}' angelegt."
fi

install -d -o "${FORGEJO_USER}" -g "${FORGEJO_USER}" -m 0750 /etc/forgejo
for d in custom data log repositories; do
  install -d -o "${FORGEJO_USER}" -g "${FORGEJO_USER}" -m 0750 "${FORGEJO_HOME}/${d}"
done
chmod 750 "${FORGEJO_HOME}"

echo
echo "=== OS-User fertig ==="
echo "  User  : ${FORGEJO_USER}"
echo "  Home  : ${FORGEJO_HOME}"
echo "  Conf  : /etc/forgejo/"
echo
echo "Naechster Schritt:"
echo "  bash services/forgejo/02-configure-haproxy.sh <subdomain> <forgejo-host-ip>"
