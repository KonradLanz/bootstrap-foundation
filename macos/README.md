# macos/

macOS Bootstrap-Skripte fuer ein neues MacBook.

## Ablauf

```
curl -fsSL https://raw.githubusercontent.com/KonradLanz/bootstrap-foundation/main/macos/bootstrap.sh | sh
```

Danach:

```bash
cd ~/git/bootstrap-foundation

# GitHub CLI anmelden
bash macos/02-gh-auth.sh

# PAT in KeePassXC speichern
bash macos/03-gh-token-keepass.sh

# SSH-Key erzeugen + bei GitHub registrieren
bash macos/04-ssh-key-github.sh
```

## Skripte

| Skript | Was | Als |
|---|---|---|
| `bootstrap.sh` | Xcode CLT, Homebrew, git, gh, Repos klonen | normaler User |
| `02-gh-auth.sh` | gh auth login, git credential helper, git identity | normaler User |
| `03-gh-token-keepass.sh` | PAT aus gh lesen oder manuell eingeben, in KeePassXC speichern | normaler User |
| `04-ssh-key-github.sh` | Ed25519 Key erzeugen, macOS Keychain, ~/.ssh/config, bei GitHub registrieren | normaler User |

## Umgebungsvariablen

| Variable | Default | Beschreibung |
|---|---|---|
| `GITHUB_USER` | `KonradLanz` | GitHub-Username |
| `GIT_BASE` | `~/git` | lokales Repo-Verzeichnis |
| `KL_KEEPASS_DB` | `~/KeePassLatest.kdbx` | Pfad zur KeePass-Datenbank |
| `SSH_KEY` | `~/.ssh/id_ed25519` | Pfad zum SSH-Key |
| `SSH_KEY_TITLE` | `hostname-YYYYMMDD` | Bezeichnung bei GitHub |

## Hinweise

- `~/github` und `~/git` koennen parallel existieren (Skripte nutzen `GIT_BASE`).
- `03-gh-token-keepass.sh` benoetigt `lib/secret-backends.sh` (im Repo enthalten).
- `UseKeychain yes` in `~/.ssh/config` speichert die SSH-Passphrase im macOS Keychain;
  nach Neustart einmal `ssh-add --apple-use-keychain ~/.ssh/id_ed25519` reicht.
- Bestehende Repos von HTTPS auf SSH umstellen:
  ```bash
  git -C ~/git/bootstrap-foundation remote set-url origin \
    git@github.com:KonradLanz/bootstrap-foundation.git
  ```
