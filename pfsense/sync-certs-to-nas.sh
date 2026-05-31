#!/bin/sh
################################################################################
# pfsense/sync-certs-to-nas.sh
# Push *.own.dedyn.io TLS certificate from pfSense ACME to QNAP NAS,
# then reload git services (Gitea, Forgejo) via SSH.
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
#   ssh-copy-id -i /root/.ssh/id_acme_push.pub admin@192.168.1.201
#
# NOTE: pfSense has no 'docker' binary — all container ops run on the NAS via SSH.
################################################################################

# ── Configuration ─────────────────────────────────────────────────────────────
NAS_HOST="192.168.1.201"
NAS_USER="admin"
NAS_SSH_KEY="/root/.ssh/id_acme_push"
NAS_SSL_DIR="/share/ssl/own.dedyn.io"
ACME_DIR="/cf/conf/acme"
DOMAIN="own.dedyn.io"

# Space-separated list of Docker container names to restart on the NAS after cert update.
# Add or remove names here — each is checked for existence and running state before restart.
RESTART_CONTAINERS="gitea forgejo"

# ── Logging ───────────────────────────────────────────────────────────────────
LOG="/var/log/sync-certs-to-nas.log"
log()  { printf "[%s] %s\n"      "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG"; }
warn() { printf "[%s] WARN: %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG"; }

log "=== cert sync start ==="

# ── Verify source cert files ───────────────────────────────────────────────────
FULLCHAIN="$ACME_DIR/${DOMAIN}.fullchain"
KEY="$ACME_DIR/${DOMAIN}.key"

if [ ! -f "$FULLCHAIN" ]; then
    log "ERROR: $FULLCHAIN not found — run ACME renewal first"
    log "       pfSense: Services > ACME Certificates > Renew"
    exit 1
fi
if [ ! -f "$KEY" ]; then
    log "ERROR: $KEY not found — run ACME renewal first"
    exit 1
fi

log "Certs: $FULLCHAIN ($(wc -c < "$FULLCHAIN") bytes), $KEY ($(wc -c < "$KEY") bytes)"

SSH_OPTS="-i $NAS_SSH_KEY -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes"

# ── Verify SSH connectivity ────────────────────────────────────────────────────
if ! ssh $SSH_OPTS "${NAS_USER}@${NAS_HOST}" "true" 2>/dev/null; then
    log "ERROR: Cannot SSH to ${NAS_USER}@${NAS_HOST}"
    log "       Run once: ssh-copy-id -i ${NAS_SSH_KEY}.pub ${NAS_USER}@${NAS_HOST}"
    exit 1
fi

# ── Create target directory on NAS ────────────────────────────────────────────
ssh $SSH_OPTS "${NAS_USER}@${NAS_HOST}" \
    "mkdir -p \"$NAS_SSL_DIR\" && chmod 700 \"$NAS_SSL_DIR\"" \
    && log "NAS: $NAS_SSL_DIR ready" \
    || { log "ERROR: Could not create $NAS_SSL_DIR on NAS"; exit 1; }

# ── Push cert files ────────────────────────────────────────────────────────────
scp -i "$NAS_SSH_KEY" -o StrictHostKeyChecking=no \
    "$FULLCHAIN" \
    "$KEY" \
    "${NAS_USER}@${NAS_HOST}:${NAS_SSL_DIR}/" \
    && log "Certs pushed to NAS:$NAS_SSL_DIR" \
    || { log "ERROR: scp failed"; exit 1; }

ssh $SSH_OPTS "${NAS_USER}@${NAS_HOST}" \
    "chmod 644 \"$NAS_SSL_DIR/${DOMAIN}.fullchain\" && chmod 600 \"$NAS_SSL_DIR/${DOMAIN}.key\"" \
    && log "NAS: permissions set (fullchain 644, key 600)" \
    || warn "Could not set cert permissions on NAS"

# ── Restart containers on NAS via SSH ─────────────────────────────────────────
# pfSense has no docker binary — all docker commands run on the NAS over SSH.
for _svc in $RESTART_CONTAINERS; do

    # Check if container exists at all (running or stopped)
    _exists=$(ssh $SSH_OPTS "${NAS_USER}@${NAS_HOST}" \
        "docker ps -a --filter name='^${_svc}$' --format '{{.Names}}' 2>/dev/null" || true)

    if [ -z "$_exists" ]; then
        warn "Container '${_svc}' not found on NAS — not installed yet, skipping"
        continue
    fi

    # Check if container is currently running
    _running=$(ssh $SSH_OPTS "${NAS_USER}@${NAS_HOST}" \
        "docker ps --filter name='^${_svc}$' --filter status=running --format '{{.Names}}' 2>/dev/null" || true)

    if [ -z "$_running" ]; then
        _status=$(ssh $SSH_OPTS "${NAS_USER}@${NAS_HOST}" \
            "docker inspect --format '{{.State.Status}}' '${_svc}' 2>/dev/null" || echo "unknown")
        warn "Container '${_svc}' exists but is not running (status: ${_status})"
        warn "Cert was updated on disk — '${_svc}' will pick it up on next start"
        continue
    fi

    # Restart
    if ssh $SSH_OPTS "${NAS_USER}@${NAS_HOST}" \
        "docker restart '${_svc}'" >/dev/null 2>&1; then
        log "NAS: container '${_svc}' restarted"
    else
        warn "NAS: docker restart '${_svc}' failed — check NAS logs"
    fi

done

log "=== cert sync complete ==="
