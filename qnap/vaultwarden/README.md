# qnap/vaultwarden

Bootstrap Vaultwarden as a Docker container on QNAP NAS.

Vaultwarden is an unofficial Bitwarden-compatible server written in Rust,
designed for self-hosting with minimal resource usage.

## Two-Step Pattern

Analog to `qnap/forgejo/`:

| Step | Script | Purpose |
|------|--------|---------|
| 1    | `bootstrap-vaultwarden.sh` | Pull image, write compose, start container |
| 2    | `setup-vaultwarden.sh`     | Wait for readiness, lock signups, install backup cron |

## Quick Start

```sh
# 1. Deploy (generates admin token, starts container)
sh qnap/vaultwarden/bootstrap-vaultwarden.sh --haproxy vault.own.dedyn.io

# 2. Create your account in the browser
#    http://<QNAP-IP>:8080

# 3. Post-deploy: disable signups + install backup cron
sh qnap/vaultwarden/setup-vaultwarden.sh --disable-signups --setup-backup
```

## Options (bootstrap)

| Flag | Default | Description |
|------|---------|-------------|
| `--http-port PORT` | 8080 | HTTP port |
| `--ws-port PORT` | 3012 | WebSocket port |
| `--admin-token TOKEN` | generated | Admin token (argon2id or plain) |
| `--data-dir PATH` | `/share/vaultwarden` | Persistent data |
| `--haproxy [IP]` | — | TLS at HAProxy/pfSense (recommended) |
| `--disable-signups` | off | Lock registration immediately |
| `--rewrite-compose` | off | Overwrite existing compose file |
| `--dry-run` | off | Show what would be done |

## Options (setup)

| Flag | Default | Description |
|------|---------|-------------|
| `--disable-signups` | off | Set `SIGNUPS_ALLOWED=false` + restart |
| `--setup-backup` | off | Install daily cron to `/share/backup/` |
| `--backup-dir PATH` | `/share/backup` | Backup target directory |
| `--port PORT` | 8080 | Vaultwarden HTTP port |
| `--dry-run` | off | Show what would be done |

## Bitwarden CLI Integration

After setup, use `bw` to inject secrets into pipeline scripts without `.env` files:

```sh
export BW_SESSION=$(bw unlock --raw)
export IMAP_PASSWORD=$(bw get password "email-analyser-imap")
export SMTP_PASSWORD=$(bw get password "email-analyser-smtp")
bw lock
```

This is the intended hoKI-Secrets-Integration pattern for `email-analyser` and other services.

## Network

Joins the shared `nas-services` Docker network (same as Forgejo/Gitea/Postgres).
The bootstrap script creates the network if it does not exist.

## Backup

Installed by `setup-vaultwarden.sh --setup-backup`:
```
0 3 * * * tar czf /share/backup/vaultwarden-$(date +%F).tar.gz /share/vaultwarden/data/
```
Written to `/etc/config/crontab` (QNAP's persistent crontab location).
