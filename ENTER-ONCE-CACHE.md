# Enter-Once Cache ("DurchEntern")

This repository provides a small POSIX-friendly helper for caching interactive
inputs across runs so that you only have to type them once and can keep
pressing Enter afterwards.

In German we call this pattern **"DurchEntern"** (enter through once) and
**"WeiterEntern"** (keep pressing Enter to reuse previous answers).

> A silly pirate analogy: instead of asking the captain for the same passphrase
> on every trip, we bury it once in a secret chest and then just shout
> "Enter ho!" while the script does the boring work.

## Goals

- Work with plain POSIX shells (sh), with optional quality-of-life features
  when running under Bash.
- Keep all cached values **local and git-ignored**.
- Support both interactive runs and fully unattended runs.
- Avoid introducing hard dependencies on external config formats or heavy tooling.
- Support **multiple secure backends** for sensitive values.

## Credential Backends

The helper supports three storage backends for sensitive values, selected via
the `CREDENTIAL_BACKEND` environment variable or auto-detected at runtime:

| Backend | Auto-detect condition | Storage | Notes |
|---|---|---|---|
| `keepassxc` | `keepassxc-cli` in PATH + `KL_KEEPASS_DB` exists | `.kdbx` database | **Preferred** – GUI + CLI, cross-platform |
| `gpg` | `gpg` in PATH | `~/.cache/kl-input-cache/<repo>/<key>.gpg` | Good fallback, terminal-only |
| `plain` | always available | `~/.cache/kl-input-cache/<repo>/<key>.txt` | Non-sensitive values only |

### Backend priority (auto mode)

```
keepassxc  →  gpg  →  plain
```

### KeePassXC backend

Requires:
- `keepassxc-cli` in PATH (or `KEEPASSXC_CLI` env var)
- `KL_KEEPASS_DB` pointing to a `.kdbx` file (default: `~/KeePassLatest.kdbx`)
- Master password entered **once per shell session** (stored in
  `KL_KEEPASS_PASS_SESSION` in memory, never on disk)

Create a new database:
```sh
bash services/forge/init-keepass-db.sh
```

KeePass groups used by this project:
```
bookstrap-foundation/
  forge/
    <username>_token    ← API tokens (write:repository)
    admin_pass          ← Forge admin password
    <username>_pass     ← Application user passwords
```

#### License

KeePassXC is licensed under **GPL-2.0 or later**.
`keepassxc-cli` is part of KeePassXC and carries the same license.
Using `keepassxc-cli` as an external binary (subprocess) from shell scripts
does **not** make your scripts subject to the GPL – only distribution of
linked/combined works triggers copyleft. Shell scripts that merely invoke
`keepassxc-cli` via `exec`/subprocess are free to use any license.

See: https://keepassxc.org/docs/ and https://www.gnu.org/licenses/gpl-faq.html

### GPG backend

Values are symmetrically encrypted with AES-256 via GnuPG.
No key management needed; the passphrase is requested on first use and
cached by the gpg-agent for the session duration.

GPG is pre-installed on most Linux distributions and macOS (via Homebrew).
On QNAP Entware: `opkg install gnupg2`.

#### License

GnuPG is licensed under **GPL-3.0 or later** (same subprocess note applies).

## High-level design

- Cache root: `${XDG_CACHE_HOME:-$HOME/.cache}/kl-input-cache`
- Each git repository gets its own namespace based on the canonical
  `git rev-parse --show-toplevel` path.
- Within that per-repo directory, files are grouped by purpose
  (`auth/`, `paths/`) and filenames act as keys.
- Sensitive values use the configured backend (`keepassxc`, `gpg`);
  non-sensitive values use `plain`.

## Run modes

The helper distinguishes three run modes via the `KL_RUN_MODE` environment
variable:

| Mode | Behaviour |
|---|---|
| `interactive` | Always prompt; Enter reuses cached value |
| `unassisted` | Never block; reuse cache or default silently |
| `auto` (default) | `interactive` when stdin is a TTY, else `unassisted` |

## API overview

The main entry point is:

```sh
kl_read_cached VAR KEY PROMPT DEFAULT SENSITIVITY
```

| Parameter | Values | Notes |
|---|---|---|
| `VAR` | shell variable name | receives the value |
| `KEY` | logical cache key | builds file path or KeePass entry |
| `PROMPT` | human-readable string | shown in interactive mode |
| `DEFAULT` | any string / `""` | empty = no sensible default |
| `SENSITIVITY` | `plain` \| `gpg` \| `keepassxc` | storage backend |

### Example

```sh
. "$BOOTSTRAP_ROOT/lib/input-cache.sh"

# Non-sensitive: plain text cache
kl_read_cached FORGE_HOST 'forge/host' 'Forgejo base URL' 'http://localhost:3000' plain

# Sensitive password: auto backend (keepassxc > gpg > plain)
kl_read_cached FORGE_ADMIN_PASS 'forge/admin_pass' 'Forge admin password' '' "${CREDENTIAL_BACKEND:-gpg}"

# GitHub token: always keepassxc
kl_read_cached GITHUB_TOKEN 'auth/github_token' 'GitHub personal access token' '' keepassxc
```

## Using the helper from other repositories

```sh
SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd || echo .)"

if [ -n "${KL_BOOTSTRAP_ROOT:-}" ]; then
  BOOTSTRAP_ROOT="$KL_BOOTSTRAP_ROOT"
elif [ -d "$HOME/github/bootstrap-foundation" ]; then
  BOOTSTRAP_ROOT="$HOME/github/bootstrap-foundation"
elif [ -d "$SCRIPT_DIR/../bootstrap-foundation" ]; then
  BOOTSTRAP_ROOT="$SCRIPT_DIR/../bootstrap-foundation"
else
  echo "Error: bootstrap-foundation not found." >&2
  exit 1
fi

. "$BOOTSTRAP_ROOT/lib/input-cache.sh"
```

## QNAP Entware: install keepassxc-cli

```bash
# x86_64 QNAP (AppImage – kein ARM-Support)
mkdir -p ~/bin
wget -q -O ~/bin/KeePassXC.AppImage \
  "https://github.com/keepassxreboot/keepassxc/releases/latest/download/KeePassXC-2.7.9-x86_64.AppImage"
chmod +x ~/bin/KeePassXC.AppImage

# Wrapper fuer keepassxc-cli
cat > ~/bin/keepassxc-cli << 'EOF'
#!/bin/sh
exec ~/bin/KeePassXC.AppImage cli "$@"
EOF
chmod +x ~/bin/keepassxc-cli

# PATH sicherstellen
export PATH="$HOME/bin:$PATH"
```

## Roadmap

- [ ] `keepassxc` als erstes Backend vollständig integriert ✅
- [ ] `gpg` Backend ✅
- [ ] `plain` Backend ✅
- [ ] Vaultwarden/Bitwarden CLI (`bw`) als optionales viertes Backend
- [ ] Windows: `keepassxc-cli` via Chocolatey/winget
- [ ] macOS: `keepassxc-cli` via Homebrew
- [ ] `init-keepass-db.sh` für alle Plattformen ✅
