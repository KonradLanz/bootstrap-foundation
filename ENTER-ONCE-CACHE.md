# Enter-Once Cache ("DurchEntern")

This repository provides a small POSIX-friendly helper for caching interactive inputs across runs so that you only have to type them once and can keep pressing Enter afterwards.

In German we call this pattern **"DurchEntern"** (enter through once) and **"WeiterEntern"** (keep pressing Enter to reuse previous answers).

Think of it as a little treasure chest for your prompts: the values are stored locally on your machine, never committed to git, and can be reused for future runs without retyping.

> A silly pirate analogy: instead of asking the captain for the same passphrase on every trip, we bury it once in a secret chest and then just shout "Enter ho!" while the script does the boring work. No more "Arrr, which token was that again?".

## Goals

- Work with plain POSIX shells (sh), with optional quality-of-life features when running under Bash.
- Keep all cached values **local and git-ignored**.
- Support both interactive runs and fully unattended runs.
- Avoid introducing hard dependencies on external config formats or heavy tooling.

## High-level design

- Cache root: `${XDG_CACHE_HOME:-$HOME/.cache}/kl-input-cache`.
- Each git repository gets its own namespace under that root, based on the canonical git top-level path.
- Within that per-repo directory, files are grouped by purpose (e.g. `auth/`, `paths/`) and their filenames act as keys.
- Sensitive values can be stored symmetrically encrypted via `gpg`; non-sensitive values can be stored as plain text.

The helper does **not** change any existing scripts by itself. Projects can opt into this pattern by sourcing `lib/input-cache.sh` and switching individual prompts to the helper API.

## Run modes

The helper distinguishes three run modes via the `KL_RUN_MODE` environment variable:

- `KL_RUN_MODE=interactive` – always behave interactively.
- `KL_RUN_MODE=unassisted` – never block for input; reuse cached values or fall back to defaults.
- `KL_RUN_MODE=auto` (default) – choose `interactive` when stdin is a TTY, otherwise `unassisted`.

This follows the usual split between interactive shells and non-interactive jobs (cron, CI, etc.).

## API overview

The main entry point is:

```sh
kl_read_cached VAR KEY PROMPT DEFAULT SENSITIVITY
```

- `VAR` – name of the shell variable that should receive the value.
- `KEY` – logical cache key (used to build the cache file path).
- `PROMPT` – human-readable prompt shown in interactive mode.
- `DEFAULT` – default value for this key; an empty string means "no sensible default".
- `SENSITIVITY` – either `gpg` (encrypted) or `plain`.

### Behaviour with cache present

- **interactive mode**
  - The user sees the prompt with a hint that Enter reuses the cached value.
  - Pressing Enter reuses the cached value.
  - Typing a new value replaces the cached value (after confirmation) and returns it.

- **unassisted mode**
  - If stdin is a TTY, the helper can optionally wait a short grace period before reusing the cached value, so a human has a chance to hit SPACE and extend the wait.
  - If stdin is not a TTY, the helper immediately reuses the cached value without waiting or prompting.

### Behaviour without cache

- **interactive mode**
  - If a non-empty default is provided, the prompt shows it.
  - Pressing Enter selects the default; any non-empty input overrides it.

- **unassisted mode**
  - With a non-empty default, the helper uses the default without blocking.
  - With an empty default, the helper treats the value as "no sensible default" and requires real user input (or fails in a strictly non-interactive environment).

This mirrors the intuition behind *DurchEntern* for the first setup and *WeiterEntern* for all subsequent runs.

## Using the helper from other repositories

Consumers are expected to locate `bootstrap-foundation` next to their own clone or under `~/github`, but an explicit override is also supported.

A typical pattern in a POSIX script looks like this:

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
  echo "Set KL_BOOTSTRAP_ROOT or clone bootstrap-foundation next to this repository." >&2
  exit 1
fi

. "$BOOTSTRAP_ROOT/lib/input-cache.sh"
```

Once sourced, a script can replace manual `read` prompts with the helper:

```sh
# Cache a GitHub token locally, encrypted via gpg
kl_read_cached GITHUB_TOKEN "auth/github_token" \
  "GitHub personal access token" "" gpg

# Cache an optional base path (plain text, with a default)
kl_read_cached STRUCTURED_PDFS_BASE_OVERRIDE "paths/structured_pdfs_base" \
  "Optional override for STRUCTURED_PDFS_BASE" "$STRUCTURED_PDFS_BASE" plain
```

This keeps all secrets and host-specific values out of git while still allowing fully unattended runs once the initial *DurchEntern* step is completed.
