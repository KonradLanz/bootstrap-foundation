# macos/

macOS Bootstrap-Skripte — alle **idempotent** (beliebig oft aufrufbar).

## Quickstart (frisches MacBook)

```bash
curl -fsSL https://raw.githubusercontent.com/KonradLanz/bootstrap-foundation/main/macos/bootstrap.sh | sh
```

Bootstrap erledigt automatisch:
- Xcode CLT → Homebrew → git + gh + keepassxc
- `bootstrap-foundation` nach `~/git` klonen
- brew-tracker + dotfiles-tracker initialisieren
- brew-hook in `~/.zshrc` eintragen

Danach manuell:

```bash
cd ~/git/bootstrap-foundation

bash macos/02-gh-auth.sh          # gh anmelden + git identity
bash macos/03-gh-token-keepass.sh # PAT in KeePassXC sichern
bash macos/04-ssh-key-github.sh   # SSH-Key erzeugen + bei GitHub registrieren
```

## Idempotenz-Garantien

Jeder Schritt prüft vor der Ausführung ob er bereits erledigt wurde:

| Symbol | Bedeutung |
|---|---|
| `[--]` | Bereits erledigt, übersprungen |
| `[>>]` | Wird jetzt ausgeführt |
| `[OK]` | Erfolgreich abgeschlossen |

Beispiellauf auf bestehendem Mac:
```
[--]  Xcode CLT bereits installiert
[--]  Homebrew bereits installiert
[--]  git + gh bereits installiert
[--]  keepassxc bereits installiert
[--]  Repo aktuell
[--]  brew-tracker bereits eingerichtet
[--]  dotfiles-tracker bereits eingerichtet
[--]  brew-hook bereits in .zshrc
```

## Skripte

| Skript | Was |
|---|---|
| `bootstrap.sh` | Alles-in-einem: CLT, Homebrew, git, gh, keepassxc, Repo klonen, Tracker starten |
| `02-gh-auth.sh` | gh auth login, git credential helper, git identity + defaults |
| `03-gh-token-keepass.sh` | PAT aus gh lesen oder manuell, in KeePassXC speichern |
| `04-ssh-key-github.sh` | Ed25519 Key, macOS Keychain, ~/.ssh/config, bei GitHub registrieren, Remote auf SSH umstellen |
| `brew-tracker/setup.sh` | brew-tracker Repo initialisieren + ersten Brewfile-Snapshot |
| `dotfiles-tracker/setup.sh` | dotfiles-tracker Repo initialisieren + initiale Dotfiles erfassen |

## Umgebungsvariablen

| Variable | Default | Beschreibung |
|---|---|---|
| `GITHUB_USER` | `KonradLanz` | GitHub-Username |
| `GIT_BASE` | `~/git` | lokales Repo-Verzeichnis |
| `KL_KEEPASS_DB` | `~/KeePassLatest.kdbx` | Pfad zur KeePass-Datenbank |
| `SSH_KEY` | `~/.ssh/id_ed25519` | Pfad zum SSH-Key |
| `SSH_KEY_TITLE` | `hostname-YYYYMMDD` | Bezeichnung bei GitHub |
| `BREW_TRACKER_DIR` | `~/git/brew-tracker` | brew-tracker Repo |
| `DOTFILES_TRACKER_DIR` | `~/git/dotfiles-tracker` | dotfiles-tracker Repo |

## Rebase-Workflow

Nach Bootstrap ist das Repo per SSH erreichbar:

```bash
cd ~/git/bootstrap-foundation
git fetch origin
git checkout feature/enter-once-cache
git rebase origin/main
git push --force-with-lease origin feature/enter-once-cache
```
