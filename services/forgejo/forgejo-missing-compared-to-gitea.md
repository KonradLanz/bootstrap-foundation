# Forgejo – Gap Analysis vs. Gitea

> **Status: RESOLVED** — All gaps closed on 2026-06-21.
> This file is kept for historical reference.
> See `forgejo-context.ai.md` for current state.

**Date:** 2026-06-21
**Repo:** [KonradLanz/bootstrap-foundation](https://github.com/KonradLanz/bootstrap-foundation)

---

## Resolution Summary

| Gap | Resolved | How |
|---|---|---|
| `01-create-os-user.sh` missing | ✅ 2026-06-21 | Created, mirrors gitea counterpart |
| `02-configure-haproxy.sh` missing | ✅ 2026-06-21 | Created with full HAProxy + app.ini hardening |
| `03-create-forgejo-users.sh` missing | ✅ 2026-06-21 | Created with `sb_write` KeePass integration |
| `04-create-repo.sh` missing | ✅ 2026-06-21 | Created |
| `README.md` missing | ✅ 2026-06-21 | Created with architecture + execution order |
| `COOKIE_SECURE` not set in `bootstrap.sh` | ✅ 2026-06-21 | Patched |
| `COOKIE_SAMESITE` not set | ✅ 2026-06-21 | Patched |
| `REVERSE_PROXY_LIMIT` not set | ✅ 2026-06-21 | Patched |
| `REVERSE_PROXY_TRUSTED_PROXIES` not set | ✅ 2026-06-21 | Patched |
| `PASSWORD_HASH_ALGO = pbkdf2` (weak) | ✅ 2026-06-21 | Changed to `argon2` |
| `lib/secret-backends.sh` not wired into user scripts | ✅ 2026-06-21 | `03-create-forgejo-users.sh` uses `sb_write` |
| `services/gitea/bootstrap.sh` same hardening gaps | ✅ 2026-06-21 | Patched identically |
| `services/forge/create-repo.sh` missing | ✅ 2026-06-21 | Created (REST API, idempotent) |
| `services/forge/create-token.sh` missing | ✅ 2026-06-21 | Created (REST API + KeePass storage) |

## Remaining Open Items

- [ ] `INSTALL_LOCK` flip: must be set to `true` **manually** after initial web wizard
- [ ] `DISABLE_REGISTRATION` flip: `03-create-forgejo-users.sh` checks but does not patch `app.ini` at runtime — done by `02-configure-haproxy.sh` at setup time
- [ ] `lib/secret-backends.sh` bitwarden backend: not yet implemented (tracked in `vaultwarden-context.ai.md`)
- [ ] `services/vaultwarden/uninstall.sh`: missing
- [ ] `services/forge/set-deploy-key.sh`: not yet created
