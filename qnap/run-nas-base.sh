#!/usr/bin/env bash
# qnap/run-nas-base.sh
# ---------------------------------------------------------------------------
# Mac-seitiger Wrapper: schickt bootstrap-nas-base.sh per SSH ans NAS.
#
# Aufruf:
#   bash qnap/run-nas-base.sh
#
# Idempotent. Einmalig ausfuehren, dann ist docker/git auf dem NAS
# in jeder SSH-Session (auch non-interactive) im PATH.
# ---------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NAS_HOST="${1:-nas}"

printf '[INFO]  Setze NAS-Basis auf %s ...\n' "$NAS_HOST"
ssh "$NAS_HOST" 'sh -s' < "${SCRIPT_DIR}/bootstrap-nas-base.sh"
printf '[OK]    NAS-Basis abgeschlossen.\n'
printf '\nTest:\n  ssh nas docker ps\n'
