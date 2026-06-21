# services/forgejo — AI Context & Status

> **Purpose of this file:** Machine-readable context for AI assistants
> working in this repository. Describes current state, design decisions,
> known gaps, and back-references to related modules.

**Last updated:** 2026-06-21
**Repo:** [KonradLanz/bootstrap-foundation](https://github.com/KonradLanz/bootstrap-foundation)

---

## What `services/forgejo/` Is

Installation and lifecycle scripts for **Forgejo** (the Gitea fork)
on Ubuntu/Debian as a systemd service, behind a pfSense HAProxy
reverse proxy doing TLS termination.

## Current Files

| File | Status |
|---|---|
| `bootstrap.sh` | ✅ exists — installs binary, systemd; **hardened** |
| `uninstall.sh` | ✅ exists |
| `01-create-os-user.sh` | ✅ created 2026-06-21 |
| `02-configure-haproxy.sh` | ✅ created 2026-06-21 |
| `03-create-forgejo-users.sh` | ✅ created 2026-06-21 (sb_write integrated) |
| `04-create-repo.sh` | ✅ created 2026-06-21 |
| `README.md` | ✅ created 2026-06-21 |

## Architecture Decision: TLS at pfSense HAProxy

- TLS terminates at **pfSense HAProxy** on port 443.
- Forgejo listens on `http://127.0.0.1:3000` internally.
- Subdomain: `forgejo.own.dedyn.io`
- HAProxy must forward: `Host`, `X-Forwarded-Proto: https`, `X-Real-IP`, `X-Forwarded-For`.
- Host firewall restricts port 3000 to pfSense IP (`192.168.111.40`) only.
- `ROOT_URL = https://forgejo.own.dedyn.io/` in `app.ini`.
- `REVERSE_PROXY_TRUSTED_PROXIES = 127.0.0.1/32,::1/128` — adjust if pfSense IP differs.

## app.ini Hardening — Applied in bootstrap.sh + 02-configure-haproxy.sh

```ini
[security]
COOKIE_SECURE                = true
COOKIE_SAMESITE              = lax
REVERSE_PROXY_LIMIT          = 1
REVERSE_PROXY_TRUSTED_PROXIES = 127.0.0.1/32,::1/128
PASSWORD_HASH_ALGO           = argon2
INSTALL_LOCK                 = false   ; flip to true AFTER initial wizard

[session]
COOKIE_SECURE = true

[service]
DISABLE_REGISTRATION         = false   ; flip to true AFTER first user created
SHOW_REGISTRATION_BUTTON     = false
```

> **Post-install manual steps:**
> 1. Run web wizard at `https://forgejo.own.dedyn.io`
> 2. Set `INSTALL_LOCK = true` in `app.ini`
> 3. Run `03-create-forgejo-users.sh` → sets `DISABLE_REGISTRATION = true`

## Credential Backend: KeePass (lazy-init)

`03-create-forgejo-users.sh` sources `lib/secret-backends.sh` and uses
`sb_write keepassxc` to persist passwords on first entry.

KeePass key paths:
- `forgejo/admin_pass` — Admin-User Passwort
- `forgejo/proj_<user>_pass` — Projekt-User Passwort

## Relationship to Other Modules

| Module | Relationship |
|---|---|
| `services/gitea/` | Gitea equivalent — complete; same structure |
| `services/forge/` | **API-based** user/token/repo scripts — plattformunabhängig, works against this instance |
| `lib/secret-backends.sh` | KeePass lazy-init — sourced in `03-create-forgejo-users.sh` |
| `services/vaultwarden/` | Planned 4th credential backend (Bitwarden CLI) |

## email-analyser Integration

Forgejo (`forgejo.own.dedyn.io`) is the Git remote for the `email-analyser` project.
Repository lives under owner `structured-pdf`.
Deploy key and CI/CD token management: use `services/forge/create-token.sh`.

## Execution Order (out-of-the-box setup)

```bash
# 1. OS user + directories
sudo bash services/forgejo/01-create-os-user.sh

# 2. app.ini + HAProxy reference config
sudo bash services/forgejo/02-configure-haproxy.sh forgejo.own.dedyn.io 192.168.111.42

# 3. pfSense: configure HAProxy frontend/backend per output above
# 4. pfSense Firewall: restrict port 3000 to 192.168.111.40
# 5. DNS: A-record forgejo.own.dedyn.io -> 192.168.111.40

# 6. Install + start Forgejo
FORGEJO_DOMAIN=forgejo.own.dedyn.io bash services/forgejo/bootstrap.sh

# 7. Run web wizard at https://forgejo.own.dedyn.io -> flip INSTALL_LOCK manually

# 8. Create users (pulls from KeePass or prompts + saves)
sudo bash services/forgejo/03-create-forgejo-users.sh

# 9. Create initial repo
FORGEJO_BIN=/usr/local/bin/forgejo bash services/forgejo/04-create-repo.sh

# 10. Create API token for CI/CD
bash services/forge/create-token.sh forgejo-admin --token-name ci-token
```

## Related AI Context Files

- [`forgejo-missing-compared-to-gitea.md`](./forgejo-missing-compared-to-gitea.md) — gap analysis (historical)
- [`services/forge/forge-context.ai.md`](../forge/forge-context.ai.md)
- [`services/gitea/README.md`](../gitea/README.md)
- [`services/vaultwarden/vaultwarden-context.ai.md`](../vaultwarden/vaultwarden-context.ai.md)
- [`.ai/context.md`](../../.ai/context.md) — Repo-weiter Kontext (IPs, NAS, pfSense)
