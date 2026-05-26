#!/bin/sh
################################################################################
# pfsense/sync-certs-to-nas.sh
# Push *.own.dedyn.io TLS certificate from pfSense ACME to QNAP NAS,
# then reload Gitea (and optionally other services) via SSH.
#
# Install on pfSense:
#   cp sync-certs-to-nas.sh /root/scripts/sync-certs-to-nas.sh
#   chmod +x /root/scripts/sync-certs-to-nas.sh
#
# Add as ACME post-renewal hook:
#   Services > ACME > Certificates > [own.dedyn.io] > Actions List
#   Method: Shell Command
#   Command: /root/scripts/sync-certs-to-nas.sh
#
# SSH key setup (run once on pfSense):
#   ssh-keygen -t ed25519 -C "pfSense-acme-push" -f /root/.ssh/id_acme_push
#   ssh-copy-id -i /root/.ssh/id_acme_push.pub admin@192.168.0.215
################################################################################

# ── Configuration ─────────────────────────────────────────────────────────────────────────────
NAS_HOST="192.168.0.215"
NAS_USER="admin"
NAS_SSH_KEY="/root/.ssh/id_acme_push"
NAS_SSL_DIR="/share/ssl/own.dedyn.io"
ACME_DIR="/cf/conf/acme"
DOMAIN="own.dedyn.io"

# Space-separated list of container names to restart after cert update
RESTART_CONTAINERS="gitea"

# ── Logging ───────────────────────────────────────────────────────────────────────────────────
LOG="/var/log/sync-certs-to-nas.log"
log() { printf "[%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG"; }

log "=== cert sync start ==="

# ── Verify source files ───────────────────────────────────────────────────────────────────────────
FULLCHAIN="$ACME_DIR/${DOMAIN}.fullchain"
KEY="$ACME_DIR/${DOMAIN}.key"

[ -f "$FULLCHAIN" ] || { log "ERROR: $FULLCHAIN not found"; exit 1; }
[ -f "$KEY"       ] || { log "ERROR: $KEY not found";       exit 1; }

log "Certs: $FULLCHAIN ($(wc -c < "$FULLCHAIN") bytes), $KEY ($(wc -c < "$KEY") bytes)"

# ── Create target directory on NAS ───────────────────────────────────────────────────────────────
SSH_OPTS="-i $NAS_SSH_KEY -o StrictHostKeyChecking=no -o ConnectTimeout=10"

ssh $SSH_OPTS "${NAS_USER}@${NAS_HOST}" \
    "mkdir -p \"$NAS_SSL_DIR\" && chmod 700 \"$NAS_SSL_DIR\"" \
    && log "NAS: $NAS_SSL_DIR ready" \
    || { log "ERROR: Could not create $NAS_SSL_DIR on NAS"; exit 1; }

# ── Push cert files ──────────────────────────────────────────────────────────────────────────────────
scp -i "$NAS_SSH_KEY" -o StrictHostKeyChecking=no \
    "$FULLCHAIN" \
    "$KEY" \
    "${NAS_USER}@${NAS_HOST}:${NAS_SSL_DIR}/" \
    && log "Certs pushed to NAS:$NAS_SSL_DIR" \
    || { log "ERROR: scp failed"; exit 1; }

ssh $SSH_OPTS "${NAS_USER}@${NAS_HOST}" \
    "chmod 644 \"$NAS_SSL_DIR/${DOMAIN}.fullchain\" && chmod 600 \"$NAS_SSL_DIR/${DOMAIN}.key\"" \
    && log "NAS: permissions set (fullchain 644, key 600)" \
    || log "WARN: Could not set cert permissions on NAS"

# ── Reload containers ───────────────────────────────────────────────────────────────────────────────────
for _svc in $RESTART_CONTAINERS; do
    ssh $SSH_OPTS "${NAS_USER}@${NAS_HOST}" \
        "docker restart \"$_svc\" 2>&1" \
        && log "NAS: container '$_svc' restarted" \
        || log "WARN: could not restart '$_svc' — may not be running yet"
done

log "=== cert sync complete ==="
