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

## Current Files

| File | Purpose | Status |
|---|---|---|
| `create-user.sh` | Create Forgejo/Gitea user + API token (idempotent) | ✅ exists |
| `init-keepass-db.sh` | Initialise KeePass DB for credential storage | ✅ exists |
| `README.md` | Usage documentation | ✅ exists |

## Design Decisions

- **API-based, not CLI-based.** Uses `POST /api/v1/admin/users` and
  `POST /api/v1/users/{user}/tokens`. This makes it portable across
  all deployment targets without needing local binary access.
- **KeePass lazy-init.** `init-keepass-db.sh` is called automatically
  on first credential write via `lib/secret-backends.sh:sb_ensure_keepass_db()`.
  No manual init step required.
- **Idempotent.** Running `create-user.sh` twice for the same username
  does not fail — it detects the existing user and skips creation.
- **Cache file** at `~/.config/structured-pdf-pipeline/env` stores
  non-secret defaults (username, email, Forge URL) across runs.
  Tokens are never written to the cache — KeePass only.

## Relationship to Other Modules

| Module | Relationship |
|---|---|
| `services/gitea/03-create-gitea-users.sh` | CLI-based equivalent; use for first-run before API token exists |
| `services/forgejo/03-create-forgejo-users.sh` | CLI-based equivalent for Forgejo (missing — see forgejo gap doc) |
| `lib/secret-backends.sh` | Credential backend library sourced by `create-user.sh` |
| `services/vaultwarden/` | Alternative secret backend; `setup-bw-backend.sh` configures Bitwarden CLI as credential store |

## Known Gaps / TODO

- [ ] **`create-repo.sh`** — API-based repo creation script missing.
  Should mirror `services/gitea/04-create-repo.sh` but via API.
- [ ] **`lib/secret-backends.sh` wiring** — `create-user.sh` prompts
  for passwords interactively; should use `sb_write` to persist to
  KeePass automatically.
- [ ] **Vaultwarden backend** — `services/vaultwarden/setup-bw-backend.sh`
  exists but is not yet wired as an alternative to KeePass in
  `lib/secret-backends.sh`.
- [ ] **email-analyser integration** — `create-user.sh` does not yet
  create the `email-analyser` project user or its API token.
  See `services/forge/forge-context.ai.md` → email-analyser section.

## email-analyser Integration Status

The `email-analyser` project uses Forgejo as its Git remote.
The following was done in a previous session:

- Repository `email-analyser` created under owner `structured-pdf`
  (or equivalent project user) in the running Forgejo instance.
- `create-user.sh` was adapted to optionally create the project user
  `structured-pdf` with restricted permissions.

What is **not yet** in this repo:
- A dedicated `create-email-analyser-project.sh` script that creates
  the repo, sets branch protection, and stores the deploy key.
- Documentation of the deploy key used by the email-analyser CI/CD.

## How to Use

```bash
# Admin user (first run)
bash services/forge/create-user.sh --admin forgejo-admin \
  --url https://forgejo.own.dedyn.io

# Project user
bash services/forge/create-user.sh structured-pdf \
  --url https://forgejo.own.dedyn.io

# Explicit Gitea target
FORGE_TYPE=gitea bash services/forge/create-user.sh myuser
```

## Related AI Context Files

- [`services/forgejo/forgejo-missing-compared-to-gitea.md`](../forgejo/forgejo-missing-compared-to-gitea.md)
- [`services/forgejo/forgejo-context.ai.md`](../forgejo/forgejo-context.ai.md)
- [`services/vaultwarden/vaultwarden-context.ai.md`](../vaultwarden/vaultwarden-context.ai.md)
