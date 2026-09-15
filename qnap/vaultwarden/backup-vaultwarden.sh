#!/usr/bin/env bash
# qnap/vaultwarden/backup-vaultwarden.sh
# Creates a consistent Vaultwarden backup, encrypts it with age, and verifies
# the encrypted artifact. No secret material belongs in this repository.
set -Eeuo pipefail
umask 077

VW_CONTAINER="${VW_CONTAINER:-vaultwarden}"
VW_DATA_DIR="${VW_DATA_DIR:-/share/homes/DOMAIN=AD/koni/vaultwarden-data}"
VW_BACKUP_DIR="${VW_BACKUP_DIR:-/share/NFSv=4/backup/vaultwarden}"
AGE_RECIPIENT_FILE="${AGE_RECIPIENT_FILE:-/share/homes/DOMAIN=AD/koni/.config/vaultwarden-backup/age-recipient.txt}"
RETENTION_DAYS="${RETENTION_DAYS:-30}"

command -v docker >/dev/null || { echo 'ERROR: docker is required' >&2; exit 1; }
command -v tar >/dev/null || { echo 'ERROR: tar is required' >&2; exit 1; }
command -v sha256sum >/dev/null || { echo 'ERROR: sha256sum is required' >&2; exit 1; }
command -v age >/dev/null || { echo 'ERROR: age is required; install age before running this script' >&2; exit 1; }

[[ -d "$VW_DATA_DIR" ]] || { echo "ERROR: data directory not found: $VW_DATA_DIR" >&2; exit 1; }
[[ -s "$AGE_RECIPIENT_FILE" ]] || { echo "ERROR: age recipient file missing or empty: $AGE_RECIPIENT_FILE" >&2; exit 1; }

mkdir -p "$VW_BACKUP_DIR"
test -w "$VW_BACKUP_DIR" || { echo "ERROR: backup directory is not writable: $VW_BACKUP_DIR" >&2; exit 1; }

docker inspect "$VW_CONTAINER" >/dev/null 2>&1 || { echo "ERROR: container not found: $VW_CONTAINER" >&2; exit 1; }

docker inspect "$VW_CONTAINER" --format '{{range .Mounts}}{{println .Source " -> " .Destination}}{{end}}' \
  | grep -F -- "$VW_DATA_DIR -> /data" >/dev/null || {
    echo "ERROR: expected mount not found: $VW_DATA_DIR -> /data" >&2
    exit 1
  }

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
WORK_DIR="$(mktemp -d "$VW_BACKUP_DIR/.vaultwarden-${STAMP}.XXXXXX")"
ARCHIVE="$VW_BACKUP_DIR/vaultwarden-${STAMP}.tar.gz"
ENCRYPTED="${ARCHIVE}.age"
MANIFEST="$VW_BACKUP_DIR/vaultwarden-${STAMP}.manifest.txt"

cleanup() {
  rm -rf "$WORK_DIR"
  rm -f "$ARCHIVE"
}
trap cleanup EXIT

# /vaultwarden backup creates a consistent SQLite database copy in /data.
docker exec "$VW_CONTAINER" /vaultwarden backup
DB_BACKUP="$VW_DATA_DIR/db.sqlite3.backup"
[[ -s "$DB_BACKUP" ]] || { echo "ERROR: Vaultwarden did not create $DB_BACKUP" >&2; exit 1; }

install -m 0600 "$DB_BACKUP" "$WORK_DIR/db.sqlite3"
for path in config.json rsa_key.pem rsa_key.pub.pem attachments sends; do
  [[ -e "$VW_DATA_DIR/$path" ]] && cp -a "$VW_DATA_DIR/$path" "$WORK_DIR/"
done

(
  cd "$WORK_DIR"
  find . -type f -printf '%P\n' | LC_ALL=C sort > "$MANIFEST"
  tar -czf "$ARCHIVE" .
)
age -R "$AGE_RECIPIENT_FILE" -o "$ENCRYPTED" "$ARCHIVE"
sha256sum "$ENCRYPTED" > "${ENCRYPTED}.sha256"

# Decrypt to a temporary stream and verify archive integrity. This proves that
# the local recipient key can decrypt the new encrypted artifact.
age -d -o - "$ENCRYPTED" | tar -tzf - >/dev/null

rm -f "$DB_BACKUP"
find "$VW_BACKUP_DIR" -maxdepth 1 -type f -name 'vaultwarden-*.tar.gz.age' -mtime "+$RETENTION_DAYS" -delete
find "$VW_BACKUP_DIR" -maxdepth 1 -type f -name 'vaultwarden-*.tar.gz.age.sha256' -mtime "+$RETENTION_DAYS" -delete
find "$VW_BACKUP_DIR" -maxdepth 1 -type f -name 'vaultwarden-*.manifest.txt' -mtime "+$RETENTION_DAYS" -delete

echo "Backup verified: $ENCRYPTED"
