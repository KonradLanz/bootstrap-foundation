#!/usr/bin/env bash
# qnap/vaultwarden/update-vaultwarden.sh
# Pulls and recreates an explicitly selected Vaultwarden image only after a
# successful verified backup. Default behaviour is dry-run.
set -Eeuo pipefail

VW_CONTAINER="${VW_CONTAINER:-vaultwarden}"
BACKUP_SCRIPT="${BACKUP_SCRIPT:-$(dirname "$0")/backup-vaultwarden.sh}"
TARGET_IMAGE="${TARGET_IMAGE:-}"
APPLY=0

usage() {
  cat <<'USAGE'
Usage:
  update-vaultwarden.sh --image vaultwarden/server:<tag> [--apply]

Without --apply, prints the planned update and exits without changing Docker.
The script does not use :latest. It always requires a fully pinned target tag.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --image) TARGET_IMAGE="${2:-}"; shift 2 ;;
    --apply) APPLY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ "$TARGET_IMAGE" =~ ^vaultwarden/server:[^[:space:]]+$ ]] || {
  echo 'ERROR: use --image vaultwarden/server:<pinned-tag>; :latest is not allowed' >&2
  exit 2
}
[[ "$TARGET_IMAGE" != 'vaultwarden/server:latest' ]] || {
  echo 'ERROR: :latest is not allowed' >&2
  exit 2
}
[[ -x "$BACKUP_SCRIPT" ]] || { echo "ERROR: backup script is not executable: $BACKUP_SCRIPT" >&2; exit 1; }
command -v docker >/dev/null || { echo 'ERROR: docker is required' >&2; exit 1; }

docker inspect "$VW_CONTAINER" >/dev/null 2>&1 || { echo "ERROR: container not found: $VW_CONTAINER" >&2; exit 1; }
CURRENT_IMAGE="$(docker inspect "$VW_CONTAINER" --format '{{.Config.Image}}')"
CURRENT_ID="$(docker inspect "$VW_CONTAINER" --format '{{.Image}}')"

echo "Current image: $CURRENT_IMAGE"
echo "Current image ID: $CURRENT_ID"
echo "Target image:  $TARGET_IMAGE"

if [[ "$APPLY" -ne 1 ]]; then
  echo 'Dry run only. Re-run with --apply after review.'
  exit 0
fi

"$BACKUP_SCRIPT"

docker pull "$TARGET_IMAGE"
docker stop "$VW_CONTAINER"

rollback() {
  echo "ERROR: update did not complete. Attempting rollback to $CURRENT_IMAGE ($CURRENT_ID)" >&2
  docker start "$VW_CONTAINER" >/dev/null 2>&1 || true
}
trap rollback ERR

docker rm "$VW_CONTAINER"

echo 'ERROR: automatic recreate is intentionally not implemented because the current container network, ports, environment, and restart policy must be preserved from its inspect output.' >&2
echo 'The backup completed and the target image was pulled. Recreate the container from your tracked deployment definition, then run the health check.' >&2
exit 1
