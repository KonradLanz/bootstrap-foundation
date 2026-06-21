# services/vaultwarden — AI Context & Status

> **Purpose of this file:** Machine-readable context for AI assistants
> working in this repository. Describes current state, design decisions,
> known gaps, and integration status with other modules.

**Last updated:** 2026-06-21  
**Repo:** [KonradLanz/bootstrap-foundation](https://github.com/KonradLanz/bootstrap-foundation)

---

## What `services/vaultwarden/` Is

Deployment and setup scripts for **Vaultwarden** (self-hosted
Bitwarden-compatible password manager) on QNAP Container Station
and local Docker. Also provides a **Bitwarden CLI credential backend**
that can replace or complement the KeePass backend in
`lib/secret-backends.sh`.

## Current Files

| File | Purpose | Status |
|---|---|---|
| `bootstrap-vaultwarden.sh` | Deploy Vaultwarden container | ✅ exists |
| `docker-compose.local.yml` | Local Docker Compose | ✅ exists |
| `docker-compose.qnap.yml` | QNAP Container Station Compose | ✅ exists |
| `setup-bw-backend.sh` | Configure Bitwarden CLI as credential backend | ✅ exists |
| `setup-recovery-qr.sh` | Generate recovery QR codes | ✅ exists |
| `README.md` | Documentation | ✅ exists |

## Credential Backend Integration Status

Vaultwarden / Bitwarden CLI is a **potential alternative backend** to
KeePass in `lib/secret-backends.sh`. Current state:

- `setup-bw-backend.sh` ✅ configures `bw` CLI with server URL and
  initial login.
- `lib/secret-backends.sh` ❌ does **not** yet have a `bitwarden`
  backend case — only `keepassxc`, `gpg`, `plain`.
- `CREDENTIAL_BACKEND=bitwarden` is **not** a valid value yet.

### What needs to be added to `lib/secret-backends.sh`

```sh
# sb_bw_read KEY
sb_bw_read() {
    bw get password "$1" 2>/dev/null
}

# sb_bw_write KEY VALUE [USERNAME]
sb_bw_write() {
    # bw CLI does not support direct item creation cleanly;
    # use bw create item with JSON template.
    # Tracked as TODO.
    :
}
```

Auto-detection order should become:
`keepassxc → bitwarden → gpg → plain`

## QNAP Deployment Notes

- Container runs on QNAP Container Station via `docker-compose.qnap.yml`.
- Persistent data volume: mapped to QNAP share.
- TLS: handled by pfSense HAProxy (same pattern as Forgejo);
  Vaultwarden listens on internal HTTP port only.
- Admin token: stored in KeePass (not in compose file).

## Known Gaps / TODO

- [ ] **`lib/secret-backends.sh` bitwarden backend** — read works via
  `bw get password`, write is not yet implemented cleanly.
- [ ] **Auto-unlock / session management** — `bw unlock` requires
  interactive input or `BW_SESSION` env var; session handling not
  yet scripted.
- [ ] **`setup-bw-backend.sh` ↔ `lib/secret-backends.sh` wiring** —
  `setup-bw-backend.sh` configures the CLI but does not set
  `CREDENTIAL_BACKEND=bitwarden` persistently.
- [ ] **No `uninstall.sh`** for Vaultwarden.

## Relationship to Other Modules

| Module | Relationship |
|---|---|
| `lib/secret-backends.sh` | Vaultwarden/Bitwarden CLI is a planned 4th backend |
| `services/forge/create-user.sh` | Uses `lib/secret-backends.sh`; will benefit from bitwarden backend |
| `services/forgejo/03-create-forgejo-users.sh` | (planned) will also use `lib/secret-backends.sh` |

## Related AI Context Files

- [`services/forge/forge-context.ai.md`](../forge/forge-context.ai.md)
- [`services/forgejo/forgejo-context.ai.md`](../forgejo/forgejo-context.ai.md)
- [`lib/secret-backends.sh`](../../lib/secret-backends.sh)
