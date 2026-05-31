# dotfiles-tracker

etckeeper-Style Tracking fuer macOS Dotfiles und Systemkonfigurationen.
Aenderungen an Shell-Konfiguration, Git-Config, SSH-Config und /etc/hosts
werden in einem lokalen Git-Repo nachverfolgt.

## Getrackte Dateien

| Quelldatei | Im Repo | Symlink? |
|---|---|---|
| `~/.zshrc` | `zshrc` | ✓ automatisch |
| `~/.zprofile` | `zprofile` | ✓ automatisch |
| `~/.gitconfig` | `gitconfig` | ✓ automatisch |
| `~/.ssh/config` | `ssh/config` | ✓ automatisch |
| `/etc/hosts` | `etc/hosts` | ✗ manuell sync (braucht sudo) |

> **SSH Private Keys werden nie getrackt** – `.gitignore` schliesst `ssh/id_*`, `*.pem`, `*.key` aus.

## Einrichten (einmalig)

```sh
bash ~/git/bootstrap-foundation/macos/dotfiles-tracker/setup.sh
```

Nach dem Setup sind `~/.zshrc`, `~/.gitconfig` etc. Symlinks ins Repo –
Aenderungen sind sofort sichtbar mit `git -C ~/git/dotfiles diff`.

## Verwendung

### Aenderungen committen

Home-Dateien (Symlinks) werden automatisch gesehen:
```sh
git -C ~/git/dotfiles add -A
git -C ~/git/dotfiles commit -m "zshrc: ripgrep alias hinzugefuegt"
```

Oder fuer alle (inkl. /etc/hosts sync):
```sh
bash ~/git/bootstrap-foundation/macos/dotfiles-tracker/dotfiles-sync.sh
# Mit Kommentar:
bash ~/git/bootstrap-foundation/macos/dotfiles-tracker/dotfiles-sync.sh "hosts: dev.local hinzugefuegt"
```

### Was hat sich geaendert?

```sh
# Seit letztem Commit:
bash ~/git/bootstrap-foundation/macos/dotfiles-tracker/dotfiles-diff.sh

# Seit einem bestimmten Commit:
bash ~/git/bootstrap-foundation/macos/dotfiles-tracker/dotfiles-diff.sh abc1234

# Aktuell uncommittete Aenderungen:
git -C ~/git/dotfiles diff
```

### Verlauf

```sh
git -C ~/git/dotfiles log --oneline
```

## Weitere Dateien hinzufuegen

In `setup.sh` die `FILES`-Variable erweitern:
```sh
$HOME/.config/starship.toml|config/starship.toml
$HOME/.vimrc|vimrc
```

Dann `setup.sh` erneut ausfuehren oder manuell kopieren + Symlink setzen.

## Aufbau

```
macos/dotfiles-tracker/
├── setup.sh           # Einmaliges Setup: Repo + Dateien + Symlinks
├── dotfiles-sync.sh   # Manueller Sync + Commit (vor allem fuer /etc/hosts)
├── dotfiles-diff.sh   # Zeigt Aenderungen seit letztem Commit
└── README.md          # Diese Datei
```

## Verwandt

- `macos/brew-tracker/` — Tracking von Homebrew-Paketen
- `macos/bootstrap.sh` — macOS Grundsetup
- [etckeeper](https://etckeeper.branchable.com/) — Inspiration
