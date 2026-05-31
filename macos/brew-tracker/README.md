# brew-tracker

etckeeper-Style Tracking fuer Homebrew auf macOS.
Jedes `brew install`, `brew uninstall`, `brew upgrade` etc. wird automatisch als Git-Commit gespeichert.

## Einrichten (einmalig)

```sh
# Setup: lokales tracker-Repo + erster Snapshot
bash ~/git/bootstrap-foundation/macos/brew-tracker/setup.sh

# Optional: Remote-Repo fuer Backup/Sync
BREW_TRACKER_REMOTE=git@github.com:KonradLanz/brew-tracker.git \
  bash ~/git/bootstrap-foundation/macos/brew-tracker/setup.sh
```

Dann den Hook in `.zshrc` eintragen (einmalig):

```sh
echo 'source ~/git/bootstrap-foundation/macos/brew-tracker/brew-hook.sh' >> ~/.zshrc
source ~/.zshrc
```

## Verwendung

Ab jetzt passiert alles automatisch:

```sh
brew install ripgrep      # -> automatischer Commit: "brew install ripgrep [2026-05-31 17:30]"
brew uninstall wget       # -> automatischer Commit: "brew uninstall wget [2026-05-31 17:31]"
brew upgrade              # -> automatischer Commit: "brew upgrade  [2026-05-31 17:32]"
```

### Verlauf ansehen

```sh
git -C ~/git/brew-tracker log --oneline
```

### Was hat sich veraendert?

```sh
# Seit letztem Commit:
bash ~/git/bootstrap-foundation/macos/brew-tracker/brew-diff.sh

# Seit einem bestimmten Commit:
bash ~/git/bootstrap-foundation/macos/brew-tracker/brew-diff.sh abc1234
```

### Manueller Snapshot (ohne brew-Befehl)

```sh
brew bundle dump --force --file=~/git/brew-tracker/Brewfile
git -C ~/git/brew-tracker add -A && git -C ~/git/brew-tracker commit -m "manuell [$(date '+%Y-%m-%d %H:%M')]"
```

## Umgebungsvariablen

| Variable | Default | Beschreibung |
|---|---|---|
| `BREW_TRACKER_DIR` | `~/git/brew-tracker` | Lokales Verzeichnis fuer das tracker-Repo |
| `BREW_TRACKER_REMOTE` | (leer) | Optionale Git-Remote-URL fuer Sync/Backup |

## Aufbau

```
macos/brew-tracker/
├── setup.sh        # Einmaliges Setup: Repo + erster Snapshot
├── brew-hook.sh    # Shell-Wrapper (in .zshrc sourcen)
├── brew-diff.sh    # Zeigt Aenderungen seit letztem Commit
└── README.md       # Diese Datei
```

## Verwandt

- `macos/bootstrap.sh` — macOS Grundsetup
- `macos/02-gh-auth.sh` — GitHub CLI Authentifizierung
- [etckeeper](https://etckeeper.branchable.com/) — Inspiration (Linux /etc Tracking)
