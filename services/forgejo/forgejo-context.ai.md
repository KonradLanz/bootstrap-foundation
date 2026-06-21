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
| `bootstrap.sh` | ✅ exists — installs binary, systemd |
| `uninstall.sh` | ✅ exists |
| `01-create-os-user.sh` | ❌ missing |
| `02-configure-haproxy.sh` | ❌ missing |
| `03-create-forgejo-users.sh` | ❌ missing |
| `04-create-repo.sh` | ❌ missing |
| `README.md` | ❌ missing |

See [`forgejo-missing-compared-to-gitea.md`](./forgejo-missing-compared-to-gitea.md)
for the full gap analysis.

## Architecture Decision: TLS at pfSense HAProxy

Agreed in the bootstrap-foundation setup conversation (2026-05):

- TLS terminates at **pfSense HAProxy** on port 443.
- Forgejo listens on `http://127.0.0.1:3000` internally.
- Subdomain: `forgejo.own.dedyn.io`
- HAProxy must forward: `Host`, `X-Forwarded-Proto: https`,
  `X-Real-IP`, `X-Forwarded-For`.
- Host firewall restricts port 3000 to pfSense IP only.
- `ROOT_URL = https://forgejo.own.dedyn.io/` in `app.ini`.

## app.ini Hardening — Not Yet Applied

These settings were discussed but are not yet in `bootstrap.sh`:

```ini
[security]
COOKIE_SECURE                = true
COOKIE_SAMESITE              = lax
REVERSE_PROXY_LIMIT          = 1
REVERSE_PROXY_TRUSTED_PROXIES = 127.0.0.1/32,::1/128
INSTALL_LOCK                 = true   ; set AFTER initial wizard

[service]
DISABLE_REGISTRATION         = true   ; set AFTER first user created
SHOW_REGISTRATION_BUTTON     = false
```

## Relationship to Other Modules

| Module | Relationship |
|---|---|
| `services/gitea/` | Gitea equivalent — complete; use as template for missing scripts |
| `services/forge/` | API-based user/token scripts — platform-independent, works against this instance |
| `lib/secret-backends.sh` | KeePass lazy-init — should be sourced in `03-create-forgejo-users.sh` |

## email-analyser Integration

Forgejo (`forgejo.own.dedyn.io`) is the Git remote for the
`email-analyser` project. Repository lives under owner `structured-pdf`.
Deploy key and CI/CD token management is not yet scripted — tracked
in `services/forge/forge-context.ai.md`.

## Related AI Context Files

- [`forgejo-missing-compared-to-gitea.md`](./forgejo-missing-compared-to-gitea.md) — gap analysis
- [`services/forge/forge-context.ai.md`](../forge/forge-context.ai.md)
- [`services/gitea/README.md`](../gitea/README.md) — template for missing scripts
- [`services/vaultwarden/vaultwarden-context.ai.md`](../vaultwarden/vaultwarden-context.ai.md)
