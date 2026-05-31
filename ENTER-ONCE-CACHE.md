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

## Credential Backends

Die Credential-Speicherung ist in `lib/secret-backends.sh` ausgelagert
(lebt in `main`).

Drei Backends werden unterstuetzt, automatisch erkannt oder per
`CREDENTIAL_BACKEND` erzwungen:

| Backend | Wann aktiv (auto) |
|---|---|
| `keepassxc` | `keepassxc-cli` in PATH + `KL_KEEPASS_DB` existiert |
| `gpg` | `gpg` in PATH |
| `plain` | immer (Fallback) |

Details, Installationsanleitungen und Lizenzhinweise: **`CREDENTIAL-BACKENDS.md`**

## High-level design

- Cache root: `${XDG_CACHE_HOME:-$HOME/.cache}/kl-input-cache`
- Each git repository gets its own namespace based on
  `git rev-parse --show-toplevel`.
- Within the per-repo directory, files are grouped by purpose
  (`forge/`, `auth/`, `paths/`) and filenames act as keys.
- Sensitive values use the configured backend; non-sensitive values use `plain`.
- `lib/input-cache.sh` auto-sources `lib/secret-backends.sh` from the
  bootstrap-foundation root.

## Run modes

| Mode | Behaviour |
|---|---|
| `interactive` | Always prompt; Enter reuses cached value |
| `unassisted` | Never block; reuse cache or default silently |
| `auto` (default) | `interactive` when stdin is TTY, else `unassisted` |

Set via `KL_RUN_MODE` environment variable.

## API

```sh
kl_read_cached VAR KEY PROMPT DEFAULT SENSITIVITY
```

| Parameter | Values |
|---|---|
| `VAR` | shell variable name to assign |
| `KEY` | logical cache key (also used as KeePass entry path) |
| `PROMPT` | human-readable prompt |
| `DEFAULT` | default value, `""` = no sensible default |
| `SENSITIVITY` | `plain` \| `gpg` \| `keepassxc` \| `auto` |

### Example

```sh
. "$BOOTSTRAP_ROOT/lib/input-cache.sh"

# Non-sensitive: plain
kl_read_cached FORGE_HOST 'forge/host' 'Forgejo base URL' 'http://localhost:3000' plain

# Sensitive: auto backend
kl_read_cached FORGE_ADMIN_PASS 'forge/admin_pass' 'Forge admin password' '' auto

# Always keepassxc
kl_read_cached GITHUB_TOKEN 'auth/github_token' 'GitHub personal access token' '' keepassxc
```

## Using from other repositories

```sh
if [ -n "${KL_BOOTSTRAP_ROOT:-}" ]; then
  BOOTSTRAP_ROOT="$KL_BOOTSTRAP_ROOT"
elif [ -d "$HOME/github/bootstrap-foundation" ]; then
  BOOTSTRAP_ROOT="$HOME/github/bootstrap-foundation"
elif [ -d "$HOME/repos/bootstrap-foundation" ]; then
  BOOTSTRAP_ROOT="$HOME/repos/bootstrap-foundation"
else
  echo "Error: bootstrap-foundation not found. Set KL_BOOTSTRAP_ROOT." >&2
  exit 1
fi
. "$BOOTSTRAP_ROOT/lib/input-cache.sh"
```

## Roadmap

- [x] `keepassxc` Backend (in `lib/secret-backends.sh` auf `main`)
- [x] `gpg` Backend
- [x] `plain` Backend
- [x] `lib/input-cache.sh` sourct `secret-backends.sh` automatisch
- [ ] Vaultwarden/Bitwarden CLI (`bw`) als viertes Backend
- [ ] Windows: `keepassxc-cli` via winget
- [ ] macOS: `keepassxc-cli` via Homebrew (brew install keepassxc)
