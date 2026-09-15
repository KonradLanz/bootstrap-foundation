# Vaultwarden QNAP operations

This directory contains conservative operational scripts for the existing QNAP Vaultwarden container.

## Important

- The current production container is named `vaultwarden`.
- Its persistent data directory is `/share/homes/DOMAIN=AD/koni/vaultwarden-data` and must remain mounted to `/data`.
- Do not commit `config.json`, database files, RSA keys, age private keys, recipient files, generated backup manifests, or backups.
- Do not update while the Web Vault/API is the only confirmed-good client path unless you first make and verify a backup.
- The application clients are currently the symptom domain: Web/API reports all entries. Diagnose endpoint configuration and local client session/cache before changing server state.

## Scripts

- `healthcheck-vaultwarden.sh`: read-only container, data-volume, capacity, and recent-log checks.
- `backup-vaultwarden.sh`: invokes Vaultwarden's built-in consistent backup, packages data and keys, encrypts it using `age`, writes a checksum, and tests decryption/archive integrity.
- `update-vaultwarden.sh`: intentionally dry-run by default. It requires a pinned tag and refuses `:latest`; it creates a verified backup then pulls the target. It deliberately does not recreate the existing manually-managed container.

## Required local setup

Install `age` on the QNAP by a trusted package/source, then create a recipient/key pair. Keep the identity private and off the NAS where possible.

```sh
mkdir -p /share/homes/DOMAIN=AD/koni/.config/vaultwarden-backup
chmod 700 /share/homes/DOMAIN=AD/koni/.config/vaultwarden-backup

# Generate the identity on an admin workstation if possible.
age-keygen -o vaultwarden-backup.agekey
# Store vaultwarden-backup.agekey outside the NAS and outside this repository.

# Copy only the public age1... recipient line to QNAP:
install -m 600 /dev/null /share/homes/DOMAIN=AD/koni/.config/vaultwarden-backup/age-recipient.txt
```

The backup script performs a local decryptability test. Therefore a corresponding age identity must be available to the user executing it, normally via `AGE_IDENTITY`:

```sh
export AGE_IDENTITY=/secure/path/vaultwarden-backup.agekey
```

For unattended backups, use a protected identity location readable only by the dedicated backup user, or use a separate backup machine to pull and encrypt archives. Do not put private keys in Git or ordinary shell history.

## Initial run

```sh
cd /share/CE_CACHEDEV4_DATA/homes/DOMAIN=AD/koni/git/repos/bootstrap-foundation/qnap/vaultwarden
chmod 700 healthcheck-vaultwarden.sh backup-vaultwarden.sh update-vaultwarden.sh
./healthcheck-vaultwarden.sh
export AGE_IDENTITY=/secure/path/vaultwarden-backup.agekey
./backup-vaultwarden.sh
```

After successful backup, validate a copy using the key stored off-device:

```sh
age -d -i /secure/path/vaultwarden-backup.agekey \
  -o /tmp/vaultwarden-restore.tar.gz \
  /share/NFSv=4/backup/vaultwarden/vaultwarden-YYYYMMDDTHHMMSSZ.tar.gz.age
tar -tzf /tmp/vaultwarden-restore.tar.gz
rm -f /tmp/vaultwarden-restore.tar.gz
```

## Client issue triage

Because the Web Vault/API has the full vault, do not modify the database. On each affected client, verify the exact self-hosted server URL, network path/DNS, certificate trust, and current client version; then log out and log back in only after the verified backup. Re-login rebuilds local vault cache from the healthy server.

## Update

Do not update from the update script until the current container configuration has been captured in a tracked Compose/Container-Station definition. It will not recreate an opaque live container.

```sh
./update-vaultwarden.sh --image vaultwarden/server:<chosen-release-tag>
./update-vaultwarden.sh --image vaultwarden/server:<chosen-release-tag> --apply
```
