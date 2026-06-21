# services/forge — AI Context & Status

> **Purpose of this file:** Machine-readable context for AI assistants
> working in this repository. Describes current state, design decisions,
> known gaps, and links to related modules.

**Last updated:** 2026-06-21
**Repo:** [KonradLanz/bootstrap-foundation](https://github.com/KonradLanz/bootstrap-foundation)

---

## What `services/forge/` Is

Platform-independent helper scripts for **Forgejo and Gitea**.
They work against any running instance — QNAP Container Station,
Ubuntu systemd, Docker — via the Forgejo/Gitea **REST API**.
No SSH or local binary access required.

**This is the shared API layer for both Gitea and Forgejo.**
It complements (not replaces) the CLI-based `01–04` scripts in
`services/gitea/` and `services/forgejo/`.

## Layer Model

```
services/gitea/01-04    ← CLI, first-run, local binary required
services/forgejo/01-04  ← CLI, first-run, local binary required
services/forge/         ← API, any time after instance is running
```

## Current Files

| File | Purpose | Status |
|---|---|---|
| `create-user.sh` | Create Forgejo/Gitea user + API token | ✅ exists |
| `create-repo.sh` | Create private/public repo via REST API | ✅ created 2026-06-21 |
| `create-token.sh` | Create + store API token in KeePass | ✅ created 2026-06-21 |
| `init-keepass-db.sh` | Initialise KeePass DB + group structure | ✅ exists |
| `README.md` | Documentation | ✅ exists (needs update) |
| `set-deploy-key.sh` | Add SSH deploy key to repo | ❌ missing |

## Default Target Instance

```bash
FORGEJO_URL=https://forgejo.own.dedyn.io
FORGEJO_ADMIN_USER=forgejo-admin
```

All scripts accept `--url` and `--admin-user` to override.

## Credential Backend

All scripts source `lib/secret-backends.sh` and use `sb_detect_backend()`.
Auto-detection order: `keepassxc → gpg → plain`.

KeePass key paths used by `services/forge/`:
- `forge/<admin-user>_pass` — Admin password for API auth
- `forge/<username>_pass` — User password
- `forge/<username>_token_<name>` — API token

## Usage Examples

```bash
# Create a user + token (create-user.sh, existing)
bash services/forge/create-user.sh structured-pdf --url https://forgejo.own.dedyn.io

# Create a private repo
bash services/forge/create-repo.sh structured-pdf email-analyser \
  --url https://forgejo.own.dedyn.io \
  --description "email-analyser pipeline"

# Create an API token for CI/CD
bash services/forge/create-token.sh structured-pdf \
  --token-name ci-token \
  --scopes write:repository,read:user

# Create token for admin (for API calls from other scripts)
bash services/forge/create-token.sh forgejo-admin \
  --token-name admin-api \
  --scopes issue,repository,user
```

## Relationship to Other Modules

| Module | Relationship |
|---|---|
| `services/forgejo/` | Forgejo install — run `01-04` first, then use `forge/` for ongoing management |
| `services/gitea/` | Gitea install — same pattern |
| `lib/secret-backends.sh` | Credential backend — sourced by all scripts here |
| `services/vaultwarden/` | Planned Bitwarden backend (not yet in `lib/secret-backends.sh`) |

## Known Gaps / TODO

- [ ] `set-deploy-key.sh` — add SSH deploy key to repo via API
- [ ] `README.md` — update to reflect `create-repo.sh` + `create-token.sh`
- [ ] Bitwarden backend support — tracked in `vaultwarden-context.ai.md`

## Related AI Context Files

- [`services/forgejo/forgejo-context.ai.md`](../forgejo/forgejo-context.ai.md)
- [`services/forgejo/forgejo-missing-compared-to-gitea.md`](../forgejo/forgejo-missing-compared-to-gitea.md) — resolved gaps
- [`services/vaultwarden/vaultwarden-context.ai.md`](../vaultwarden/vaultwarden-context.ai.md)
- [`.ai/context.md`](../../.ai/context.md) — Repo-weiter Kontext (IPs, NAS, pfSense)
