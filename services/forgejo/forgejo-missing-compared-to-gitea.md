# Forgejo – Missing Scripts Compared to Gitea

Gap analysis between `services/forgejo` and `services/gitea` in the
`bootstrap-foundation` repository, including security hardening items
identified during this conversation.

**Date:** 2026-06-21  
**Repo:** [KonradLanz/bootstrap-foundation](https://github.com/KonradLanz/bootstrap-foundation)

---

## Current State

### `services/gitea` — complete

| File | Purpose |
|---|---|
| `bootstrap.sh` | Install binary, systemd service, Caddy reverse proxy |
| `01-create-os-user.sh` | Linux system user for Gitea daemon |
| `02-configure-haproxy.sh` | HAProxy/pfSense TLS termination + subdomain routing |
| `03-create-gitea-users.sh` | Admin + project user via Gitea CLI |
| `04-create-repo.sh` | Create repository, owner-only permissions |
| `uninstall.sh` | Full removal |
| `README.md` | Step-by-step documentation |

### `services/forgejo` — incomplete

| File | Status |
|---|---|
| `bootstrap.sh` | ✅ exists |
| `uninstall.sh` | ✅ exists |
| `01-create-os-user.sh` | ❌ missing |
| `02-configure-haproxy.sh` | ❌ missing |
| `03-create-forgejo-users.sh` | ❌ missing |
| `04-create-repo.sh` | ❌ missing |
| `README.md` | ❌ missing |

---

## Missing Scripts

### `01-create-os-user.sh`

Create a dedicated Linux system user under which the Forgejo daemon runs.
Equivalent to the gitea counterpart; directories needed:

- `/var/lib/forgejo/{custom,data,log,repositories}`
- `/etc/forgejo/` — owned by `forgejo:forgejo`, mode `0750`

### `02-configure-haproxy.sh`

Discussed and agreed in this chat: TLS should be terminated at the
**pfSense HAProxy**, not on the host. Key points to implement:

- Subdomain: `git.example.lan` (or `forgejo.own.dedyn.io`)
- HAProxy frontend listens on port 443, backend forwards to
  `http://<forgejo-host>:3000`
- Required headers forwarded by HAProxy:
  - `Host` → real hostname
  - `X-Forwarded-Proto` → `https`
  - `X-Real-IP` and `X-Forwarded-For`
- Forgejo host firewall: restrict port 3000 to pfSense IP only

### `03-create-forgejo-users.sh`

Create Admin + project user via Forgejo CLI (`forgejo admin user create`).
Equivalent to `services/gitea/03-create-gitea-users.sh` but adapted for:

- Forgejo binary path (typically `/usr/local/bin/forgejo`)
- Forgejo config path (`/etc/forgejo/app.ini`)
- Same pattern: interactive password prompt with confirmation, no
  plaintext on disk
- Disable public registration after user creation

### `04-create-repo.sh`

Create the project repository via Forgejo CLI
(`forgejo admin repo create`).  
Owner-only permissions by default — no additional collaborators added.

### `README.md`

Step-by-step guide covering:

1. Run `01-create-os-user.sh`
2. Configure HAProxy on pfSense (see `02-configure-haproxy.sh`)
3. Run `bootstrap.sh` with correct `FORGEJO_DOMAIN`
4. Run `03-create-forgejo-users.sh`
5. Run `04-create-repo.sh`

---

## Security Hardening Gaps (Both Services)

The following items were discussed in this chat but are **not yet reflected**
in either `services/gitea/bootstrap.sh` or `services/forgejo/bootstrap.sh`:

| Setting | Section in `app.ini` | Required Value | Status |
|---|---|---|---|
| `COOKIE_SECURE` | `[security]` | `true` | ❌ not set |
| `COOKIE_SAMESITE` | `[security]` | `lax` | ❌ not set |
| `REVERSE_PROXY_LIMIT` | `[security]` | `1` | ❌ not set |
| `REVERSE_PROXY_TRUSTED_PROXIES` | `[security]` | `127.0.0.1/32,::1/128` | ❌ not set |
| `INSTALL_LOCK` | `[security]` | `true` (after setup) | ⚠️ set to `false` in gitea bootstrap |
| `DISABLE_REGISTRATION` | `[service]` | `true` | ⚠️ set to `false` in gitea bootstrap |
| `SHOW_REGISTRATION_BUTTON` | `[service]` | `false` | ❌ not set |

> **Note:** `INSTALL_LOCK` and `DISABLE_REGISTRATION` should be `false`
> during the initial web wizard, then flipped to `true` immediately after.
> The bootstrap scripts should either set them post-install or at least
> document this as a required manual step.

---

## `lib/secret-backends.sh` Integration

The current `03-create-gitea-users.sh` prompts for passwords via plain
`read -r` and holds them in shell variables. The `lib/secret-backends.sh`
library (with lazy KeePass DB initialisation via `sb_ensure_keepass_db`)
was built in this conversation but is **not yet wired into the gitea or
forgejo user-creation scripts**.

Recommended: source `lib/secret-backends.sh` in `03-create-*-users.sh`
and use `sb_write` to persist generated or entered passwords to KeePass
instead of leaving them in shell variables.

---

## Duplication: `services/forge/` vs. `services/gitea/`

`services/forge/create-user.sh` and `services/gitea/03-create-gitea-users.sh`
both create Gitea/Forgejo application users. Consider consolidating:

- Keep `services/forge/create-user.sh` as the **generic, API-based** script
  (uses Forgejo REST API + token)
- Keep `services/gitea/03-` and `services/forgejo/03-` as **CLI-based**
  scripts (use local binary, suitable for first-run before API token exists)
- Document which to use when in each README

---

## Recommended Next Steps

1. **Create the 4 missing Forgejo scripts** (`01` – `04`) + `README.md`
   mirroring the gitea structure, adapted for Forgejo binary/paths and
   HAProxy TLS termination.
2. **Fix `app.ini` hardening** in both `bootstrap.sh` files: add
   `COOKIE_SECURE`, `COOKIE_SAMESITE`, `REVERSE_PROXY_LIMIT`,
   `REVERSE_PROXY_TRUSTED_PROXIES`; note `INSTALL_LOCK` flip.
3. **Wire `lib/secret-backends.sh`** into `03-create-*-users.sh` to
   eliminate plaintext password handling.
4. **Add a post-install step** in both bootstrap scripts that sets
   `INSTALL_LOCK = true` and `DISABLE_REGISTRATION = true` after the
   initial wizard completes.
