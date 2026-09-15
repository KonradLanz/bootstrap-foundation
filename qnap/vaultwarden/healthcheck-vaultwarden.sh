#!/usr/bin/env bash
# qnap/vaultwarden/healthcheck-vaultwarden.sh
# Read-only checks for the Vaultwarden container and persistent data directory.
set -Eeuo pipefail

VW_CONTAINER="${VW_CONTAINER:-vaultwarden}"
VW_DATA_DIR="${VW_DATA_DIR:-/share/homes/DOMAIN=AD/koni/vaultwarden-data}"

command -v docker >/dev/null || { echo 'ERROR: docker is required' >&2; exit 1; }
[[ -d "$VW_DATA_DIR" ]] || { echo "ERROR: data directory not found: $VW_DATA_DIR" >&2; exit 1; }

docker inspect "$VW_CONTAINER" >/dev/null 2>&1 || { echo "ERROR: container not found: $VW_CONTAINER" >&2; exit 1; }

echo '== Container =='
docker ps --filter "name=^/${VW_CONTAINER}$" --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}'
echo
echo '== Image and mounts =='
docker inspect "$VW_CONTAINER" --format 'Image={{.Config.Image}}{{println}}ImageID={{.Image}}{{println}}{{range .Mounts}}{{println .Source " -> " .Destination}}{{end}}'
echo
echo '== Data files =='
ls -lah "$VW_DATA_DIR"
ls -lah "$VW_DATA_DIR"/db.sqlite3* 2>/dev/null || true
echo
echo '== Data size =='
du -sh "$VW_DATA_DIR"
echo
echo '== Filesystem capacity =='
df -h "$VW_DATA_DIR"
df -i "$VW_DATA_DIR"
echo
echo '== Recent Vaultwarden logs =='
docker logs --since 24h --tail 250 "$VW_CONTAINER" 2>&1 || true
