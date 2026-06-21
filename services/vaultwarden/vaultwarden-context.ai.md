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
| `uninstall.sh` | Full removal | ❌ missing |

## Deployment Target

- **QNAP NAS:** `nas.ad.own.dedyn.io` / `192.168.111.42`
- **TLS:** pfSense HAProxy (same pattern as Forgejo) — internal port only
- **URL:** `https://vault.own.dedyn.io`
- **Admin token:** stored in KeePass (`vaultwarden/admin_token`)

> ⚠️ Port-Binding: check `docker-compose.qnap.yml` — was bound to old IP
> `192.168.1.201`. After IP migration to `192.168.111.42` container must be
> restarted. See `.ai/context.md` for migration status.

## Credential Backend Integration Status

Vaultwarden / Bitwarden CLI is a **planned 4th backend** in `lib/secret-backends.sh`.

| Backend | Status in `lib/secret-backends.sh` |
|---|---|
| `keepassxc` | ✅ fully implemented (read + write + lazy-init) |
| `gpg` | ✅ fully implemented |
| `plain` | ✅ implemented |
| `bitwarden` | ❌ NOT YET implemented |

### What needs to be added to `lib/secret-backends.sh`

```sh
# sb_bw_read KEY
sb_bw_read() {
    bw get password "$1" 2>/dev/null
}

# sb_bw_write KEY VALUE [USERNAME]
# bw CLI: create item with JSON template
sb_bw_write() {
    _bw_item=$(printf '{"type":1,"name":"%s","login":{"username":"%s","password":"%s"}}' \
        "$1" "${3:-bootstrap}" "$2")
    printf '%s' "$_bw_item" | bw encode | bw create item >/dev/null
}
```

Auto-detection order (target): `keepassxc → bitwarden → gpg → plain`

### Session Management (TODO)

```sh
# Before bw calls: ensure session is active
_sb_bw_unlock() {
    if [ -z "${BW_SESSION:-}" ]; then
        BW_SESSION=$(bw unlock --raw)
        export BW_SESSION
    fi
}
```

## Known Gaps / TODO

- [ ] **`lib/secret-backends.sh` bitwarden backend** — `sb_bw_read` + `sb_bw_write` + `_sb_bw_unlock`
- [ ] **Auto-detection** — add `bitwarden` case to `sb_detect_backend()`
- [ ] **`setup-bw-backend.sh` ↔ `lib/secret-backends.sh` wiring** — `setup-bw-backend.sh` configures CLI but does not export `CREDENTIAL_BACKEND=bitwarden` persistently
- [ ] **`uninstall.sh`** — not yet created
- [ ] **`email-analyser` migration** — IMAP/SMTP credentials from `.env` → `bw get`
- [ ] **`local-ai-stack` migration** — API keys → Vaultwarden

## Relationship to Other Modules

| Module | Relationship |
|---|---|
| `lib/secret-backends.sh` | Bitwarden is planned 4th backend |
| `services/forge/` scripts | Use `lib/secret-backends.sh`; will benefit from bitwarden backend |
| `services/forgejo/03-create-forgejo-users.sh` | Uses `lib/secret-backends.sh`; will benefit from bitwarden backend |

## Related AI Context Files

- [`services/forge/forge-context.ai.md`](../forge/forge-context.ai.md)
- [`services/forgejo/forgejo-context.ai.md`](../forgejo/forgejo-context.ai.md)
- [`.ai/context.md`](../../.ai/context.md) — Repo-weiter Kontext (IPs, NAS, pfSense)
