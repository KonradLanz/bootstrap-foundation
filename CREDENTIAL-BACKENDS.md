# Credential Backends

`lib/secret-backends.sh` stellt eine einheitliche Schnittstelle fuer drei
Passwort-Backends bereit. Skripte sourced die Library und rufen `sb_read` /
`sb_write` auf – welches Backend tatsaechlich genutzt wird, entscheidet
`sb_detect_backend` automatisch oder wird per `CREDENTIAL_BACKEND` erzwungen.

## Backend-Uebersicht

| Backend | Voraussetzung | Speicherort | Empfehlung |
|---|---|---|---|
| `keepassxc` | `keepassxc-cli` + `.kdbx`-Datei | `.kdbx`-Datenbank | **Bevorzugt** – GUI + CLI, cross-platform |
| `gpg` | `gpg` in PATH | `~/.cache/kl-input-cache/<repo>/<key>.gpg` | Guter Fallback, kein GUI noetig |
| `plain` | nichts | `~/.cache/kl-input-cache/<repo>/<key>.txt` | Nur fuer nicht-sensible Werte |

### Auto-Detection (Standard)

```
keepassxc  -->  gpg  -->  plain
```

Umgebungsvariable `CREDENTIAL_BACKEND` erzwingt ein bestimmtes Backend:

```bash
CREDENTIAL_BACKEND=gpg bash services/forge/create-user.sh
```

## KeePassXC Backend

### Umgebungsvariablen

| Variable | Default | Beschreibung |
|---|---|---|
| `KEEPASSXC_CLI` | `keepassxc-cli` | Pfad/Name des CLI-Binaries |
| `KL_KEEPASS_DB` | `~/KeePassLatest.kdbx` | Pfad zur `.kdbx`-Datei |
| `KL_KEEPASS_GROUP` | `bootstrap-foundation` | Root-Gruppe in der DB |
| `KL_KEEPASS_PASS` | _(leer)_ | Master-PW als Env-Var (optional, fuer CI) |

### Datenbank anlegen

```bash
bash services/forge/init-keepass-db.sh

# Mit eigener DB-Datei (z.B. bestehende QNAP-DB):
KL_KEEPASS_DB=/share/homes/DOMAIN=AD/koni/Database2.kdbx \
  bash services/forge/init-keepass-db.sh
```

### Gruppen-Struktur in der DB

```
bookstrap-foundation/
  forge/
    admin_pass           <- Forge Admin-Passwort
    <username>_pass      <- Applikations-User-Passwort
    <username>_token     <- API-Token (write:repository)
```

### Installation auf verschiedenen Plattformen

#### QNAP NAS (x86_64) – AppImage

```bash
mkdir -p ~/bin
wget -q -O ~/bin/KeePassXC.AppImage \
  "https://github.com/keepassxreboot/keepassxc/releases/latest/download/KeePassXC-2.7.9-x86_64.AppImage"
chmod +x ~/bin/KeePassXC.AppImage

cat > ~/bin/keepassxc-cli << 'EOF'
#!/bin/sh
exec ~/bin/KeePassXC.AppImage cli "$@"
EOF
chmod +x ~/bin/keepassxc-cli
export PATH="$HOME/bin:$PATH"  # in ~/.profile eintragen
```

> **QNAP ARM** (TS-x31, x28 etc.): Kein AppImage verfuegbar.
> Fallback: `CREDENTIAL_BACKEND=gpg`

#### macOS

```bash
brew install keepassxc
# keepassxc-cli ist automatisch im PATH
```

#### Ubuntu/Debian

```bash
sudo apt install keepassxc
```

#### Windows (PowerShell)

```powershell
winget install KeePassXCTeam.KeePassXC
# keepassxc-cli.exe liegt in C:\Program Files\KeePassXC\
```

### Symlink auf bestehende DB

Falls du eine bestehende KeePass-Datei nutzen willst:

```bash
ln -sf /share/homes/DOMAIN=AD/koni/Database2.kdbx ~/KeePassLatest.kdbx
export KL_KEEPASS_DB="$HOME/KeePassLatest.kdbx"
```

**Concurrent Access:** KeePass nutzt nur einen Advisory Lock (`.lock`-Datei).
CLI-Writes waehrend kein GUI-Client offen ist: sicher.
Gleichzeitiges Schreiben aus GUI + CLI: letzter Schreibvorgang gewinnt.

## GPG Backend

Werte werden symmetrisch mit AES-256 verschluesselt. Kein Key-Management
noetig – das Passphrase wird beim ersten Zugriff abgefragt und vom
`gpg-agent` fuer die Session gecacht.

### Installation

```bash
# QNAP Entware
opkg install gnupg2

# macOS
brew install gnupg

# Ubuntu/Debian
sudo apt install gnupg2
```

## Lizenzen

| Tool | Lizenz | Auswirkung auf deine Skripte |
|---|---|---|
| KeePassXC / keepassxc-cli | GPL-2.0+ | Subprocess-Aufruf loest keine GPL-Pflicht aus |
| GnuPG | GPL-3.0+ | Gleiche Subprocess-Ausnahme (GPL-FAQ) |
| bootstrap-foundation | MIT | Unveraendert – keine Infektion durch externe Binaries |

Subprocess-Aufrufe via `exec`, `$()` oder Pipes gelten laut GPL-FAQ nicht
als Linking oder Combining. Shell-Skripte die `keepassxc-cli` oder `gpg`
nur aufrufen bleiben unter ihrer eigenen Lizenz (hier: MIT).

Referenzen:
- https://www.gnu.org/licenses/gpl-faq.html#MereAggregation
- https://keepassxc.org/docs/
