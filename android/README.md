# Android / Termux Bootstrap

Bootstraps a minimal but complete development environment on Android via [Termux](https://f-droid.org/packages/com.termux/).

## Prerequisites (manual steps before running)

1. **Install Termux** from [F-Droid](https://f-droid.org/packages/com.termux/) — **not** from the Play Store (outdated there)
2. **Install Acode** from [Play Store](https://play.google.com/store/apps/details?id=com.foxdebug.acodefree) or F-Droid
3. Open Termux and run the one-liner below

## One-liner

```sh
curl -fsSL https://raw.githubusercontent.com/KonradLanz/bootstrap-foundation/main/android/bootstrap.sh | sh
```

## What it does

| Step | Action |
|---|---|
| 1 | `termux-setup-storage` — SD card / shared storage access |
| 2 | `pkg update && pkg upgrade` |
| 3 | Install `git openssh curl wget python nodejs vim termux-api` |
| 4 | Write shell aliases to `~/.bashrc` (`gs`, `gl`, `gp`, `gpl`, `ga`, `gc`, `gcp`) |
| 5 | Generate `~/.ssh/id_ed25519` if missing, print public key |
| 6 | Set `git config` (name, email, defaultBranch, pull.rebase) |
| 7 | Clone `bootstrap-foundation` and `bw-minimal` into `~/projects/` |

## Optional env vars

| Variable | Default | Description |
|---|---|---|
| `KL_GITHUB_USER` | `KonradLanz` | GitHub username for cloning |
| `KL_FORGEJO_HOST` | _(empty)_ | Internal Forgejo hostname — adds `forgejo-home` SSH alias |
| `KL_FORGEJO_PORT` | `2222` | SSH port for Forgejo |
| `KL_GIT_EMAIL` | prompted | Git author email |
| `KL_GIT_NAME` | `Konrad` | Git author name |
| `KL_SKIP_ACODE` | `0` | Set `1` to suppress Acode install hint |
| `KL_RUN_MODE` | `auto` | `interactive` / `unassisted` / `auto` |

### Example with Forgejo

```sh
export KL_FORGEJO_HOST=forgejo.own.dedyn.io
curl -fsSL https://raw.githubusercontent.com/KonradLanz/bootstrap-foundation/main/android/bootstrap.sh | sh
```

## Three-liner to send to someone

```
1. Install Termux from F-Droid (not Play Store)
2. Open Termux
3. curl -fsSL https://raw.githubusercontent.com/KonradLanz/bootstrap-foundation/main/android/bootstrap.sh | sh
```

## Daily workflow

```sh
# Pull latest
gpl                          # alias for: git pull

# Edit in Acode, then push
gcp "feat: my change"        # alias for: git add -A && git commit -m "..." && git push

# Or step by step
gs                           # git status
ga                           # git add -A
gc "feat: my change"         # git commit -m
gp                           # git push
```

## Acode + Termux integration

1. Open Acode
2. **Settings → Terminal → Termux** — enable
3. Now the built-in terminal in Acode opens directly into Termux
4. Navigate to your project: `cd ~/projects/bootstrap-foundation`
5. Edit files in Acode, commit/push from the embedded terminal

## SSH key: add to GitHub

After the bootstrap, copy your public key:

```sh
cat ~/.ssh/id_ed25519.pub
```

Add it at: <https://github.com/settings/keys>

Test:
```sh
ssh -T git@github.com
```
